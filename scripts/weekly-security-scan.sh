#!/usr/bin/env bash
# WEEKLY: scan every image currently RUNNING in the cluster with Trivy (new CVEs appear every week).
source "$(dirname "$0")/lib.sh"
require kubectl trivy jq
start_report weekly-security-scan
setup_kube

images=$(kubectl get pods -A -o jsonpath='{..containers[*].image}' | tr ' ' '\n' | sort -u)
out "$(echo "$images" | wc -l) unique images running"

section "CRITICAL / HIGH vulnerabilities with a fix available"
total_crit=0
while read -r img; do
  [[ -z "$img" ]] && continue
  safe=$(echo "$img" | tr '/:@' '___')
  if ! trivy image --quiet --scanners vuln --ignore-unfixed --severity HIGH,CRITICAL \
        --format json -o "$REPORT_DIR/trivy-$safe.json" "$img" 2>/dev/null; then
    warn "could not scan $img"
    continue
  fi
  crit=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$REPORT_DIR/trivy-$safe.json")
  high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$REPORT_DIR/trivy-$safe.json")
  out "$(printf '%-4s CRITICAL %-4s HIGH  %s' "$crit" "$high" "$img")"
  total_crit=$(( total_crit + crit ))
done <<<"$images"

section "Summary"
if (( total_crit > 0 )); then
  warn "$total_crit CRITICAL vulnerabilities in running images - create tickets, prioritise prod"
else
  ok "no fixable CRITICAL vulnerabilities in running images"
fi

finish "Weekly security scan"
