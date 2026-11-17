#!/usr/bin/env bash
# DAILY: confirm last night's backups exist and are recent.
source "$(dirname "$0")/lib.sh"
require aws jq
start_report daily-backup-verify

section "RDS automated snapshots ($DB_INSTANCE)"
latest=$(aws rds describe-db-snapshots --db-instance-identifier "$DB_INSTANCE" --snapshot-type automated \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' --output text)
if [[ -z "$latest" || "$latest" == "None" ]]; then
  fail "no automated snapshots found"
else
  read -r snap_id snap_time snap_status <<<"$latest"
  age_h=$(( ( $(date +%s) - $(date -d "$snap_time" +%s) ) / 3600 ))
  out "latest: $snap_id  created: $snap_time  status: $snap_status  age: ${age_h}h"
  if (( age_h > 26 )); then fail "latest RDS snapshot is ${age_h}h old (expected < 26h)"
  elif [[ "$snap_status" != "available" ]]; then warn "latest snapshot status is $snap_status"
  else ok "RDS snapshot is recent"; fi
fi

section "AWS Backup jobs in the last 24 hours"
since=$(date -u -d '-24 hours' +%Y-%m-%dT%H:%M:%SZ)
jobs=$(aws backup list-backup-jobs --by-created-after "$since" --output json)
echo "$jobs" | jq -r '.BackupJobs[] | "\(.State)\t\(.ResourceType)\t\(.ResourceArn | split(":") | last)"' | tee -a "$REPORT_FILE"
total=$(echo "$jobs" | jq '.BackupJobs | length')
failed=$(echo "$jobs" | jq '[.BackupJobs[] | select(.State == "FAILED" or .State == "ABORTED" or .State == "EXPIRED")] | length')
if (( total == 0 )); then warn "no AWS Backup jobs ran in the last 24h (were the servers stopped?)"
elif (( failed > 0 )); then fail "$failed of $total backup jobs failed"
else ok "$total backup job(s), none failed"; fi

finish "Daily backup verification"
