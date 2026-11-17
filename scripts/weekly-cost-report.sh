#!/usr/bin/env bash
# WEEKLY: cost this week vs last week, plus idle and untagged resources.
source "$(dirname "$0")/lib.sh"
require aws jq
start_report weekly-cost-report
NOTIFY_ON_OK=true

# Returns {"Service name": cost, ...} for the period [start, end)
cost_by_service() {
  aws ce get-cost-and-usage --time-period "Start=$1,End=$2" --granularity DAILY \
    --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE --output json \
    | jq '[.ResultsByTime[].Groups[] | {s: .Keys[0], c: (.Metrics.UnblendedCost.Amount | tonumber)}]
          | group_by(.s) | map({key: .[0].s, value: (map(.c) | add)}) | from_entries'
}

today=$(date +%F); week_ago=$(date -d '-7 days' +%F); two_weeks_ago=$(date -d '-14 days' +%F)
this_week=$(cost_by_service "$week_ago" "$today")
last_week=$(cost_by_service "$two_weeks_ago" "$week_ago")

section "Cost by service: last 7 days vs previous 7 days (USD)"
jq -rn --argjson a "$this_week" --argjson b "$last_week" '
  ([$a | keys[]] + [$b | keys[]]) | unique
  | map({s: ., a: ($a[.] // 0), b: ($b[.] // 0)}) | map(select(.a > 0.01 or .b > 0.01))
  | sort_by(-.a)[] | "\(.s)\t\(.a)\t\(.b)"' \
  | awk -F'\t' '{printf "%-45s %8.2f   (prev %8.2f)\n", $1, $2, $3}' | tee -a "$REPORT_FILE"
tw=$(echo "$this_week" | jq '[.[]] | add // 0 | . * 100 | round / 100')
lw=$(echo "$last_week" | jq '[.[]] | add // 0 | . * 100 | round / 100')
out "TOTAL this week: \$$tw   previous week: \$$lw"
if awk -v a="$tw" -v b="$lw" 'BEGIN{exit !(b > 0 && a > b * 1.25)}'; then warn "spend up more than 25% week over week"; fi

section "Unattached EBS volumes (paying for nothing)"
vols=$(aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output text)
if [[ -z "$vols" ]]; then ok "none"; else out "$vols"; warn "unattached volumes found"; fi

section "Unassociated Elastic IPs"
eips=$(aws ec2 describe-addresses --query 'Addresses[?AssociationId==null].PublicIp' --output text)
if [[ -z "$eips" ]]; then ok "none"; else out "$eips"; warn "idle Elastic IPs found"; fi

section "Stopped EC2 instances (EBS still billed)"
stopped=$(aws ec2 describe-instances --filters Name=instance-state-name,Values=stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key==`Name`]|[0].Value]' --output text)
if [[ -z "$stopped" ]]; then ok "none"; else out "$stopped"; fi

section "EC2 instances missing an Owner tag"
untagged=$(aws ec2 describe-instances --query 'Reservations[].Instances[?!not_null(Tags[?Key==`Owner`]|[0])].InstanceId' --output text)
if [[ -z "$untagged" ]]; then ok "all instances tagged"; else out "$untagged"; warn "untagged instances"; fi

finish "Weekly cost report"
