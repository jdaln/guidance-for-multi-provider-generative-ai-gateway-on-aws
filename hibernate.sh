#!/bin/bash
# Take the gateway completely offline while keeping everything needed to bring it back unchanged:
#   1. save the LiteLLM master key and salt key into a Secrets Manager secret that Terraform does not manage,
#   2. archive the request/response audit logs into a private bucket,
#   3. snapshot the database,
#   4. turn off RDS deletion protection and run undeploy.sh (removes every other resource).
# While hibernated only the snapshot (~USD 2/month for 20 GB), the DNS zone and the two small buckets remain.
# Bring it back with ./wake.sh (about 40 minutes: image rebuild plus a full deploy).
set -euo pipefail

if [ ! -f ".env" ]; then echo "Error: .env file missing, aborting."; exit 1; fi
source .env
TERRAFORM_BIN="${TERRAFORM_BIN:-terraform}"
MAIN_STACK_NAME="litellm-stack"
DB_ID="${MAIN_STACK_NAME}-litellm-db"
HIBERNATE_SECRET_NAME="${HIBERNATE_SECRET_NAME:-${MAIN_STACK_NAME}-hibernate}"
AUDIT_ARCHIVE_BUCKET="${AUDIT_ARCHIVE_BUCKET:-${TERRAFORM_S3_BUCKET_NAME}-audit-archive}"
SNAPSHOT_ID="${MAIN_STACK_NAME}-hibernate-$(date -u +%Y%m%d-%H%M)"
aws_region=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')

echo "This removes the whole gateway stack in ${aws_region} after saving its state."
echo "  database snapshot : ${SNAPSHOT_ID}"
echo "  saved secrets     : ${HIBERNATE_SECRET_NAME}"
echo "  audit log archive : s3://${AUDIT_ARCHIVE_BUCKET}/${SNAPSHOT_ID}/"
read -r -p "Type HIBERNATE to continue: " answer
[ "$answer" = "HIBERNATE" ] || { echo "Aborted."; exit 1; }

echo "1/5 Saving master and salt keys..."
LIVE_SECRET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?starts_with(Name,'LiteLLMMasterSalt-')].ARN" --output text)
[ -n "$LIVE_SECRET_ARN" ] || { echo "Error: live LiteLLMMasterSalt-* secret not found"; exit 1; }
LIVE_SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$LIVE_SECRET_ARN" --query SecretString --output text)
if aws secretsmanager describe-secret --secret-id "$HIBERNATE_SECRET_NAME" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id "$HIBERNATE_SECRET_NAME" --secret-string "$LIVE_SECRET_VALUE" >/dev/null
else
    aws secretsmanager create-secret --name "$HIBERNATE_SECRET_NAME" \
        --description "LiteLLM master/salt/UI secrets saved by hibernate.sh; read by wake.sh" \
        --secret-string "$LIVE_SECRET_VALUE" --tags Key=project,Value=llmgateway >/dev/null
fi
unset LIVE_SECRET_VALUE

echo "2/5 Archiving audit logs..."
LOG_BUCKET_NAME=$(cd litellm-s3-log-bucket-terraform && "$TERRAFORM_BIN" output -raw LogBucketName 2>/dev/null || true)
if [ -n "$LOG_BUCKET_NAME" ]; then
    if ! aws s3api head-bucket --bucket "$AUDIT_ARCHIVE_BUCKET" 2>/dev/null; then
        aws s3 mb "s3://${AUDIT_ARCHIVE_BUCKET}" --region "$aws_region"
        aws s3api put-public-access-block --bucket "$AUDIT_ARCHIVE_BUCKET" \
            --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        aws s3api put-bucket-versioning --bucket "$AUDIT_ARCHIVE_BUCKET" --versioning-configuration Status=Enabled
    fi
    aws s3 sync "s3://${LOG_BUCKET_NAME}" "s3://${AUDIT_ARCHIVE_BUCKET}/${SNAPSHOT_ID}/" --only-show-errors
else
    echo "  (log bucket stack has no local state here, skipping archive)"
fi

echo "3/5 Snapshotting the database (this takes several minutes)..."
aws rds create-db-snapshot --db-instance-identifier "$DB_ID" --db-snapshot-identifier "$SNAPSHOT_ID" \
    --tags Key=project,Value=llmgateway >/dev/null
aws rds wait db-snapshot-available --db-snapshot-identifier "$SNAPSHOT_ID"
echo "  snapshot ${SNAPSHOT_ID} available"

echo "4/5 Turning off deletion protection..."
aws rds modify-db-instance --db-instance-identifier "$DB_ID" --no-deletion-protection --apply-immediately >/dev/null
for _ in $(seq 1 30); do
    prot=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DeletionProtection' --output text)
    [ "$prot" = "False" ] && break
    sleep 10
done
# Terraform also takes a final snapshot named <db>-final; an older one with that name would make destroy fail
if aws rds describe-db-snapshots --db-snapshot-identifier "${DB_ID}-final" >/dev/null 2>&1; then
    aws rds delete-db-snapshot --db-snapshot-identifier "${DB_ID}-final" >/dev/null
    aws rds wait db-snapshot-deleted --db-snapshot-identifier "${DB_ID}-final"
fi

echo "5/5 Removing the stack..."
./undeploy.sh

# Keep a single copy of the data: drop Terraform's final snapshot now that ours exists
if aws rds describe-db-snapshots --db-snapshot-identifier "${DB_ID}-final" >/dev/null 2>&1; then
    aws rds delete-db-snapshot --db-snapshot-identifier "${DB_ID}-final" >/dev/null
fi

echo
echo "Hibernated. Kept: snapshot ${SNAPSHOT_ID}, secret ${HIBERNATE_SECRET_NAME}, s3://${AUDIT_ARCHIVE_BUCKET}, the DNS zone and the Terraform state bucket."
echo "Bring it back with: ./wake.sh   (uses the latest hibernate snapshot; pass a snapshot name to pick another)"
