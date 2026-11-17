#!/usr/bin/env bash
# DAILY: serverless health - Lambda errors/throttles/latency, dead-letter queue, export pipeline freshness.
source "$(dirname "$0")/lib.sh"
require aws jq
start_report daily-lambda-health

start=$(date -u -d '-24 hours' +%Y-%m-%dT%H:%M:%SZ); end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
metric() {  # $1 function, $2 metric, $3 statistic
  aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name "$2" \
    --dimensions Name=FunctionName,Value="$1" --start-time "$start" --end-time "$end" \
    --period 86400 --statistics "$3" --query "Datapoints[0].$3" --output text
}

section "Lambda functions (last 24h)"
functions=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '${PROJECT}-')].FunctionName" --output text)
[[ -z "$functions" ]] && warn "no ${PROJECT}-* functions found (extension stack not applied?)"
for fn in $functions; do
  inv=$(metric "$fn" Invocations Sum); err=$(metric "$fn" Errors Sum); thr=$(metric "$fn" Throttles Sum)
  p99=$(aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Duration \
    --dimensions Name=FunctionName,Value="$fn" --start-time "$start" --end-time "$end" --period 86400 \
    --extended-statistics p99 --query 'Datapoints[0].ExtendedStatistics.p99' --output text)
  live=$(aws lambda get-alias --function-name "$fn" --name live --query FunctionVersion --output text 2>/dev/null || echo "-")
  out "$(printf '%-34s live=v%-3s invocations=%-5s errors=%-4s throttles=%-4s p99=%sms' "$fn" "$live" "${inv/None/0}" "${err/None/0}" "${thr/None/0}" "${p99/None/-}")"
  [[ "$live" == "1" ]] && warn "$fn: live alias still on version 1 (placeholder) - run the lab-serverless pipeline"
  if [[ "${err/None/0}" != "0" && "${err/None/0}" != "0.0" ]]; then
    warn "$fn had errors - latest:"
    aws logs filter-log-events --log-group-name "/aws/lambda/$fn" --start-time $(( ($(date +%s) - 86400) * 1000 )) \
      --filter-pattern '{ $.level = "ERROR" }' --limit 3 --query 'events[].message' --output text 2>/dev/null \
      | cut -c1-300 | tee -a "$REPORT_FILE" || true
  fi
  if [[ "${thr/None/0}" != "0" && "${thr/None/0}" != "0.0" ]]; then warn "$fn was throttled"; fi
done

section "Dead-letter queue"
if url=$(aws sqs get-queue-url --queue-name "${PROJECT}-lambda-dlq" --query QueueUrl --output text 2>/dev/null); then
  depth=$(aws sqs get-queue-attributes --queue-url "$url" --attribute-names ApproximateNumberOfMessages \
    --query 'Attributes.ApproximateNumberOfMessages' --output text)
  if (( depth > 0 )); then warn "$depth failed event(s) waiting in the DLQ - run ops/replay-dlq (DRY_RUN first)"
  else ok "DLQ empty"; fi
fi

section "Export pipeline freshness (prod)"
bucket="${PROJECT}-orders-exports-$(aws sts get-caller-identity --query Account --output text)"
latest=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix exports/prod/ \
  --query 'sort_by(Contents, &LastModified)[-1].[Key,LastModified]' --output text 2>/dev/null || true)
if [[ -z "$latest" || "$latest" == "None" ]]; then
  warn "no prod export found yet (is export.enabled true in values-prod.yaml?)"
else
  read -r key modified <<<"$latest"
  age_h=$(( ( $(date +%s) - $(date -d "$modified" +%s) ) / 3600 ))
  out "latest export: $key (${age_h}h old)"
  if (( age_h > 26 )); then fail "prod export is ${age_h}h old - check the orders-api-export CronJob"; else ok "export is fresh"; fi
  summary="summaries/${key#exports/}"
  if aws s3api head-object --bucket "$bucket" --key "$summary" >/dev/null 2>&1; then ok "summary exists: $summary"
  else fail "no summary for $key - did the Lambda fail? (check the DLQ and logs)"; fi
fi

finish "Daily Lambda health"
