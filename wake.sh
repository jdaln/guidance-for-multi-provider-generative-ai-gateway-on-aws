#!/bin/bash
# Bring a hibernated gateway back with the same URL, master key, virtual keys, budgets and spend history.
# Usage: ./wake.sh [snapshot-identifier]   (default: the most recent litellm-stack-hibernate-* snapshot)
set -euo pipefail

if [ ! -f ".env" ]; then echo "Error: .env file missing, aborting."; exit 1; fi
source .env
MAIN_STACK_NAME="litellm-stack"
HIBERNATE_SECRET_NAME="${HIBERNATE_SECRET_NAME:-${MAIN_STACK_NAME}-hibernate}"

SNAPSHOT_ID="${1:-}"
if [ -z "$SNAPSHOT_ID" ]; then
    SNAPSHOT_ID=$(aws rds describe-db-snapshots --snapshot-type manual \
        --query "sort_by(DBSnapshots[?starts_with(DBSnapshotIdentifier, '${MAIN_STACK_NAME}-hibernate-')], &SnapshotCreateTime)[-1].DBSnapshotIdentifier" \
        --output text)
fi
if [ -z "$SNAPSHOT_ID" ] || [ "$SNAPSHOT_ID" = "None" ]; then
    echo "Error: no ${MAIN_STACK_NAME}-hibernate-* snapshot found. Run ./deploy.sh for a fresh deployment instead."
    exit 1
fi
aws secretsmanager describe-secret --secret-id "$HIBERNATE_SECRET_NAME" >/dev/null 2>&1 \
    || { echo "Error: secret ${HIBERNATE_SECRET_NAME} not found; without it the restored database cannot be decrypted."; exit 1; }

echo "Restoring from snapshot ${SNAPSHOT_ID} with secrets from ${HIBERNATE_SECRET_NAME}"
export RDS_SNAPSHOT_IDENTIFIER="$SNAPSHOT_ID"
export REUSE_SECRETS_FROM="$HIBERNATE_SECRET_NAME"
./deploy.sh

# From now on every deploy must keep reusing the saved keys, otherwise a later apply would generate new
# ones and orphan the restored database. Persist that in .env (idempotent).
if grep -q '^REUSE_SECRETS_FROM=' .env; then
    sed -i.bak -e "s|^REUSE_SECRETS_FROM=.*|REUSE_SECRETS_FROM=\"${HIBERNATE_SECRET_NAME}\"|" .env && rm -f .env.bak
else
    printf '\nREUSE_SECRETS_FROM="%s" # set by wake.sh: keep reusing the saved LiteLLM keys on every deploy\n' "$HIBERNATE_SECRET_NAME" >> .env
fi
echo "Awake. The snapshot ${SNAPSHOT_ID} is kept; delete it when you no longer need a restore point."
