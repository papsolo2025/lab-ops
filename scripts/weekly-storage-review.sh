#!/usr/bin/env bash
# WEEKLY: storage review - S3 security baseline and size, EFS usage/tiering, EBS type and snapshots, RDS space.
source "$(dirname "$0")/lib.sh"
require aws jq
start_report weekly-storage-review
NOTIFY_ON_OK=true

yesterday=$(date -u -d '-2 days' +%Y-%m-%dT00:00:00Z); now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

section "S3 buckets (${PROJECT}-*): security baseline"
for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${PROJECT}-')].Name" --output text); do
  issues=()
  pab=$(aws s3api get-public-access-block --bucket "$b" --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null || echo '{}')
  [[ "$(echo "$pab" | jq '[.[]] | all and length == 4')" == "true" ]] || issues+=("public access block incomplete")
  aws s3api get-bucket-encryption --bucket "$b" >/dev/null 2>&1 || issues+=("no default encryption")
  [[ "$(aws s3api get-bucket-versioning --bucket "$b" --query Status --output text)" == "Enabled" ]] || issues+=("versioning off")
  aws s3api get-bucket-lifecycle-configuration --bucket "$b" >/dev/null 2>&1 || issues+=("no lifecycle rules")
  aws s3api get-bucket-policy --bucket "$b" --query Policy --output text 2>/dev/null | grep -q 'aws:SecureTransport' \
    || issues+=("no TLS-only policy")
  bytes=$(aws cloudwatch get-metric-statistics --namespace AWS/S3 --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value="$b" Name=StorageType,Value=StandardStorage \
    --start-time "$yesterday" --end-time "$now" --period 86400 --statistics Average \
    --query 'sort_by(Datapoints, &Timestamp)[-1].Average' --output text)
  size=$(awk -v b="${bytes/None/0}" 'BEGIN{printf "%.1f MB", b/1048576}')
  if (( ${#issues[@]} == 0 )); then ok "$b ($size Standard)"
  else warn "$b ($size): $(printf "%s; " "${issues[@]}")"; fi
done
out "Note: the Terraform state bucket has no lifecycle rule on purpose (state history matters)."

section "EFS file systems"
aws efs describe-file-systems --query 'FileSystems[].[Name,FileSystemId,Encrypted,SizeInBytes.Value,SizeInBytes.ValueInIA]' \
  --output text | while IFS=$'\t' read -r name id enc total ia; do
    echo "$name $id encrypted=$enc total=$(( ${total:-0} / 1048576 ))MB in_IA=$(( ${ia:-0} / 1048576 ))MB"
  done | tee -a "$REPORT_FILE"
for id in $(aws efs describe-file-systems --query 'FileSystems[].FileSystemId' --output text); do
  status=$(aws efs describe-backup-policy --file-system-id "$id" --query 'BackupPolicy.Status' --output text 2>/dev/null || echo NONE)
  if [[ "$status" == "ENABLED" ]]; then ok "$id automatic backups enabled"; else warn "$id automatic backups: $status"; fi
done

section "EBS"
gp2=$(aws ec2 describe-volumes --filters Name=volume-type,Values=gp2 --query 'Volumes[].VolumeId' --output text)
if [[ -z "$gp2" ]]; then ok "no gp2 volumes (gp3 is ~20% cheaper)"; else warn "gp2 volumes to migrate to gp3: $gp2"; fi
old_snaps=$(aws ec2 describe-snapshots --owner-ids self \
  --query "length(Snapshots[?StartTime<='$(date -u -d '-90 days' +%F)'])" --output text)
if (( old_snaps > 0 )); then warn "$old_snaps EBS snapshots older than 90 days"; else ok "no EBS snapshots older than 90 days"; fi

section "RDS free storage"
free=$(aws cloudwatch get-metric-statistics --namespace AWS/RDS --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE" --start-time "$yesterday" --end-time "$now" \
  --period 86400 --statistics Minimum --query 'sort_by(Datapoints, &Timestamp)[-1].Minimum' --output text)
if [[ "$free" == "None" ]]; then warn "no FreeStorageSpace data (database stopped?)"
else
  gb=$(awk -v b="$free" 'BEGIN{printf "%.1f", b/1073741824}')
  if awk -v g="$gb" 'BEGIN{exit !(g < 4)}'; then warn "RDS free storage ${gb} GB - enable storage autoscaling or grow it"
  else ok "RDS free storage ${gb} GB"; fi
fi

finish "Weekly storage review"
