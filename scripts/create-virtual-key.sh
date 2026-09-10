#!/usr/bin/env bash
# Create a LiteLLM virtual key with stacked spend windows (6h / 24h / 7d).
#
# Stacked windows (budget_limits) cannot be set through the Admin UI or through
# default_key_generate_params, so keys are created with this script.
#
# Usage:
#   export GATEWAY_URL="https://gateway.example.org"
#   export LITELLM_MASTER_KEY="sk-..."      # from Secrets Manager (LiteLLMMasterSalt-*), never commit it
#   ./scripts/create-virtual-key.sh <key-alias> [comma-separated model names]
#
# Optional overrides (USD): BUDGET_6H (30), BUDGET_24H (75), BUDGET_7D (300)
set -euo pipefail

ALIAS="${1:?usage: $0 <key-alias> [models]}"
MODELS="${2:-claude-opus-4-6-eu,claude-opus-5-eu,claude-sonnet-5-eu,claude-haiku-4-5-eu,claude-fable-5-global,claude-fable-5-1-global,gpt-5.6-sol-global,gpt-5.6-terra-global,gpt-6-astra-global}"
: "${GATEWAY_URL:?set GATEWAY_URL}"
: "${LITELLM_MASTER_KEY:?set LITELLM_MASTER_KEY}"
BUDGET_6H="${BUDGET_6H:-30}"
BUDGET_24H="${BUDGET_24H:-75}"
BUDGET_7D="${BUDGET_7D:-300}"

MODELS_JSON=$(printf '%s' "$MODELS" | tr -d ' ' | awk -F, '{for(i=1;i<=NF;i++){printf "%s\"%s\"", (i>1?",":""), $i}}')

BODY=$(cat <<JSON
{
  "key_alias": "${ALIAS}",
  "models": [${MODELS_JSON}],
  "budget_limits": [
    {"budget_duration": "6h",  "max_budget": ${BUDGET_6H}},
    {"budget_duration": "24h", "max_budget": ${BUDGET_24H}},
    {"budget_duration": "7d",  "max_budget": ${BUDGET_7D}}
  ],
  "metadata": {"created_by": "scripts/create-virtual-key.sh"}
}
JSON
)

RESPONSE=$(curl -sS --fail-with-body "${GATEWAY_URL%/}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  --data "${BODY}")

echo "Key created for alias '${ALIAS}' (shown once, store it in a password manager):"
printf '%s\n' "$RESPONSE" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["key"])'
