#!/usr/bin/env bash
# ON DEMAND: inspect (and replay) events that failed after all Lambda retries.
# DRY_RUN=true  -> show what is in the queue, change nothing
# DRY_RUN=false -> re-send each failed Lambda event to the function's live alias, then delete it from the DLQ
source "$(dirname "$0")/lib.sh"
require aws jq
start_report replay-dlq
NOTIFY_ON_OK=true
DRY="${DRY_RUN:-true}"

url=$(aws sqs get-queue-url --queue-name "${PROJECT}-lambda-dlq" --query QueueUrl --output text)
out "queue: $url   mode: $([[ "$DRY" == "true" ]] && echo 'DRY RUN (inspect only)' || echo REPLAY)"

handled=0
for _ in 1 2 3 4 5; do   # up to 50 messages per run
  msgs=$(aws sqs receive-message --queue-url "$url" --max-number-of-messages 10 --wait-time-seconds 2 \
    --visibility-timeout 60 --output json)
  count=$(echo "$msgs" | jq '.Messages | length')
  (( count == 0 )) && break
  for i in $(seq 0 $(( count - 1 ))); do
    m=$(echo "$msgs" | jq ".Messages[$i]")
    body=$(echo "$m" | jq -r .Body)
    receipt=$(echo "$m" | jq -r .ReceiptHandle)
    # Lambda failure destinations wrap the original event: requestContext + requestPayload + responsePayload
    fn_arn=$(echo "$body" | jq -r '.requestContext.functionArn // empty' 2>/dev/null || true)
    if [[ -z "$fn_arn" ]]; then
      warn "message not from a Lambda destination (EventBridge Scheduler?): $(echo "$body" | cut -c1-200)"
      continue
    fi
    fn=$(echo "$fn_arn" | cut -d: -f7)
    reason=$(echo "$body" | jq -r '.responsePayload.errorMessage // .requestContext.condition')
    out "- $fn  reason: $reason"
    out "  event: $(echo "$body" | jq -c '.requestPayload' | cut -c1-200)"
    if [[ "$DRY" != "true" ]]; then
      echo "$body" | jq '.requestPayload' > /tmp/replay-payload.json
      aws lambda invoke --function-name "$fn" --qualifier live --invocation-type Event \
        --cli-binary-format raw-in-base64-out --payload file:///tmp/replay-payload.json /dev/null >/dev/null
      aws sqs delete-message --queue-url "$url" --receipt-handle "$receipt"
      ok "replayed to $fn:live and removed from DLQ"
    fi
    handled=$(( handled + 1 ))
  done
done

if (( handled == 0 )); then ok "DLQ is empty"; elif [[ "$DRY" == "true" ]]; then warn "$handled message(s) inspected - fix the cause, then run again with DRY_RUN unticked"; fi
finish "DLQ replay"
