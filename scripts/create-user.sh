#!/usr/bin/env bash
# Create a gateway user: a LiteLLM internal user (email + password for the Admin UI, where they see only
# their own keys and spend) plus one API key with the standard spend windows (6h / 24h / 7d).
#
# Usage:
#   export GATEWAY_URL="https://gateway.example.org"
#   export LITELLM_MASTER_KEY="sk-..."       # from Secrets Manager (LiteLLMMasterSalt-*), never commit it
#   ./scripts/create-user.sh <email> [comma-separated model names]
#   ./scripts/create-user.sh --list                 # users and their spend
#   ./scripts/create-user.sh --delete <user_id>     # removes the user and all their keys
#
# Optional overrides (USD): BUDGET_6H (30), BUDGET_24H (75), BUDGET_7D (300); USER_PASSWORD (random if unset)
set -euo pipefail
: "${GATEWAY_URL:?set GATEWAY_URL}"
: "${LITELLM_MASTER_KEY:?set LITELLM_MASTER_KEY}"
BASE="${GATEWAY_URL%/}"
auth=(-H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json")

case "${1:-}" in
  --list)
    curl -sS --fail-with-body "${BASE}/user/list?page_size=100" "${auth[@]}" \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f"{u.get(\"user_email\") or \"-\":40} {u[\"user_id\"]:40} role={u.get(\"user_role\")} spend=${u.get(\"spend\",0):.2f}") for u in d.get("users", d if isinstance(d,list) else [])]'
    exit 0 ;;
  --delete)
    USER_ID="${2:?usage: $0 --delete <user_id>}"
    curl -sS --fail-with-body "${BASE}/user/delete" "${auth[@]}" --data "{\"user_ids\":[\"${USER_ID}\"]}" >/dev/null
    echo "Deleted user ${USER_ID} and their keys."
    exit 0 ;;
esac

EMAIL="${1:?usage: $0 <email> [models] | --list | --delete <user_id>}"
MODELS="${2:-claude-opus-4-6-eu,claude-opus-5-eu,claude-sonnet-5-eu,claude-haiku-4-5-eu,claude-fable-5-global,claude-fable-5-1-global,gpt-5.6-sol-global,gpt-5.6-terra-global,gpt-6-astra-global}"
BUDGET_6H="${BUDGET_6H:-30}"; BUDGET_24H="${BUDGET_24H:-75}"; BUDGET_7D="${BUDGET_7D:-300}"
# (no pipeline here: under `set -o pipefail` a tr|head pipe reports SIGPIPE as a failure and the script would exit silently)
PASSWORD="${USER_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(15))')}"
MODELS_JSON=$(printf '%s' "$MODELS" | tr -d ' ' | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i}}')

# Call the API; on a non-2xx answer print the body (LiteLLM's error message) and stop
api() {
  local path="$1" body="$2" out
  if ! out=$(curl -sS --fail-with-body "${BASE}${path}" "${auth[@]}" --data "$body"); then
    echo "Error from ${path}:" >&2; printf '%s\n' "$out" >&2; exit 1
  fi
  printf '%s' "$out"
}

USER_RESPONSE=$(api /user/new "{
  \"user_email\": \"${EMAIL}\",
  \"user_alias\": \"${EMAIL%%@*}\",
  \"user_role\": \"internal_user\",
  \"auto_create_key\": false,
  \"models\": [${MODELS_JSON}],
  \"max_budget\": ${BUDGET_7D},
  \"budget_duration\": \"7d\"
}")
USER_ID=$(printf '%s' "$USER_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user_id"])')

# The UI password is a documented field of /user/update (not of /user/new), so set it in a second call
api /user/update "{\"user_id\": \"${USER_ID}\", \"password\": \"${PASSWORD}\"}" >/dev/null

KEY_RESPONSE=$(api /key/generate "{
  \"user_id\": \"${USER_ID}\",
  \"key_alias\": \"${EMAIL}\",
  \"models\": [${MODELS_JSON}],
  \"max_budget\": ${BUDGET_7D},
  \"budget_duration\": \"7d\",
  \"budget_limits\": [
    {\"budget_duration\": \"6h\",  \"max_budget\": ${BUDGET_6H}},
    {\"budget_duration\": \"24h\", \"max_budget\": ${BUDGET_24H}},
    {\"budget_duration\": \"7d\",  \"max_budget\": ${BUDGET_7D}}
  ],
  \"metadata\": {\"created_by\": \"scripts/create-user.sh\"}
}")
KEY=$(printf '%s' "$KEY_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')

cat <<EOF

User created (send these to the person through a secure channel; they are shown once):
  Admin UI : ${BASE}/ui/   login: ${EMAIL}   password: ${PASSWORD}
  API base : ${BASE}/v1
  API key  : ${KEY}
  Limits   : USD ${BUDGET_6H} / 6h, ${BUDGET_24H} / 24h, ${BUDGET_7D} / 7d, models: ${MODELS}
  user_id  : ${USER_ID}   (for --delete)
EOF
