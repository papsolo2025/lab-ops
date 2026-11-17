#!/usr/bin/env bash
# Shared helpers for every automation script. Source it:  source "$(dirname "$0")/lib.sh"
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-west-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
CLUSTER_NAME="${CLUSTER_NAME:-devops-lab}"
PROJECT="${PROJECT:-devops-lab}"
DB_INSTANCE="${DB_INSTANCE:-devops-lab-orders-db}"
REPORT_DIR="${REPORT_DIR:-$(pwd)/reports}"
mkdir -p "$REPORT_DIR"

STATUS="OK"            # OK | WARN | FAIL  - the worst result seen so far
REPORT_FILE=""

log()  { printf '%s %s\n' "$(date '+%F %T')" "$*" >&2; }
die()  { log "ERROR: $*"; exit 2; }

# Start a report file named after the task, e.g. reports/daily-health-check-2026-11-17.txt
start_report() {
  REPORT_FILE="$REPORT_DIR/$1-$(date +%F).txt"
  : > "$REPORT_FILE"
  out "# $1 - $(date '+%F %T %Z')"
}
out()     { echo "$*" | tee -a "$REPORT_FILE"; }
section() { out ""; out "== $* =="; }
warn()    { out "WARN: $*"; [[ "$STATUS" == "FAIL" ]] || STATUS="WARN"; }
fail()    { out "FAIL: $*"; STATUS="FAIL"; }
ok()      { out "OK:   $*"; }

require() { for c in "$@"; do command -v "$c" >/dev/null || die "missing command: $c"; done; }

setup_kube() {
  export KUBECONFIG="${KUBECONFIG:-$REPORT_DIR/../.kubeconfig}"
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$KUBECONFIG" >/dev/null
}

# Query Prometheus through the Kubernetes API server proxy (no port-forward needed).
# Usage: prom_query 'up == 0'   -> prints raw JSON
prom_query() {
  local q
  q=$(jq -rn --arg q "$1" '$q|@uri')
  kubectl get --raw "/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy/api/v1/query?query=${q}"
}
# First value of an instant query as a number (empty if no data)
prom_value() { prom_query "$1" | jq -r '.data.result[0].value[1] // empty'; }

# Post the final status to Slack (if SLACK_WEBHOOK_URL is set and not "none") and set the exit code.
#   0 = OK, 1 = WARN (Jenkins marks the build UNSTABLE), 2 = FAIL
finish() {
  local title="$1" icon=":white_check_mark:" code=0
  [[ "$STATUS" == "WARN" ]] && icon=":warning:" && code=1
  [[ "$STATUS" == "FAIL" ]] && icon=":x:" && code=2
  out ""
  out "RESULT: $STATUS"
  if [[ -n "${SLACK_WEBHOOK_URL:-}" && "${SLACK_WEBHOOK_URL}" != "none" && ( "$STATUS" != "OK" || "${NOTIFY_ON_OK:-false}" == "true" ) ]]; then
    local body
    body=$(jq -n --arg t "$icon *$title*: $STATUS ${BUILD_URL:-}" --arg r "$(tail -c 2500 "$REPORT_FILE")" \
      '{text: ($t + "\n```" + $r + "```")}')
    curl -fsS -X POST -H 'Content-Type: application/json' --data "$body" "$SLACK_WEBHOOK_URL" >/dev/null \
      || log "Slack post failed"
  fi
  exit "$code"
}
