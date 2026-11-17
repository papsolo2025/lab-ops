#!/usr/bin/env bash
# MONTHLY: disaster recovery drill - restore the latest RDS snapshot into a temporary instance,
# prove the data is there, measure RTO/RPO, then delete the temporary instance.
source "$(dirname "$0")/lib.sh"
require aws jq psql
start_report monthly-dr-drill
NOTIFY_ON_OK=true

DR_ID="dr-drill-$(date +%Y%m%d%H%M)"
cleanup() {
  log "Deleting temporary instance $DR_ID"
  aws rds delete-db-instance --db-instance-identifier "$DR_ID" --skip-final-snapshot --delete-automated-backups >/dev/null 2>&1 || true
}
trap cleanup EXIT

src=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE" --query 'DBInstances[0]' --output json)
subnet_group=$(echo "$src" | jq -r '.DBSubnetGroup.DBSubnetGroupName')
sg_ids=$(echo "$src" | jq -r '[.VpcSecurityGroups[].VpcSecurityGroupId] | join(" ")')
secret_arn=$(echo "$src" | jq -r '.MasterUserSecret.SecretArn')

section "Pick the latest automated snapshot"
read -r snap snap_time <<<"$(aws rds describe-db-snapshots --db-instance-identifier "$DB_INSTANCE" --snapshot-type automated \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].[DBSnapshotIdentifier,SnapshotCreateTime]' --output text)"
[[ -z "$snap" || "$snap" == "None" ]] && { fail "no snapshot to restore"; finish "DR drill"; }
rpo_min=$(( ( $(date +%s) - $(date -d "$snap_time" +%s) ) / 60 ))
out "snapshot: $snap  taken: $snap_time  -> RPO if disaster happened now: ${rpo_min} minutes"

section "Restore (the clock is running)"
start=$(date +%s)
# shellcheck disable=SC2086
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$DR_ID" --db-snapshot-identifier "$snap" \
  --db-instance-class db.t4g.micro --db-subnet-group-name "$subnet_group" \
  --vpc-security-group-ids $sg_ids --no-multi-az --no-publicly-accessible \
  --tags Key=Purpose,Value=dr-drill Key=Project,Value="$PROJECT" >/dev/null
out "restore started: $DR_ID"
aws rds wait db-instance-available --db-instance-identifier "$DR_ID"
rto_min=$(( ( $(date +%s) - start ) / 60 ))
out "instance available after ${rto_min} minutes"

section "Validate the data"
endpoint=$(aws rds describe-db-instances --db-instance-identifier "$DR_ID" --query 'DBInstances[0].Endpoint.Address' --output text)
creds=$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --query SecretString --output text)
user=$(echo "$creds" | jq -r .username); pass=$(echo "$creds" | jq -r .password)
if counts=$(PGPASSWORD="$pass" psql "host=$endpoint dbname=orders_prod user=$user sslmode=require connect_timeout=10" \
      -tAc "SELECT count(*), max(created_at) FROM orders" 2>&1); then
  out "restored orders_prod: rows|latest = $counts"
  ok "data restored and readable"
else
  out "$counts"
  fail "could not read restored data (if authentication failed: the password rotated after the snapshot - back up secrets too!)"
fi

section "Results"
out "RTO measured: ${rto_min} min   RPO: ${rpo_min} min"
(( rto_min > ${RTO_TARGET_MIN:-60} )) && warn "RTO above target of ${RTO_TARGET_MIN:-60} minutes"

finish "Monthly DR drill"
