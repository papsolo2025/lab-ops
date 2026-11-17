#!/usr/bin/env bash
# MONTHLY: SLO and error budget report for orders-api in prod.
#   Availability SLO: 99.9% of requests are not 5xx
#   Latency SLO:      99% of requests complete in under 500 ms
source "$(dirname "$0")/lib.sh"
require kubectl jq awk
start_report monthly-slo-report
setup_kube
NOTIFY_ON_OK=true

WINDOW="${SLO_WINDOW:-30d}"   # Prometheus keeps 15 days in the lab, so this covers what exists
AVAIL_SLO=0.999
LAT_SLO=0.99
sel='namespace="prod",route!~"/health.*"'

total=$(prom_value "sum(increase(http_requests_total{$sel}[$WINDOW]))")
errors=$(prom_value "sum(increase(http_requests_total{$sel,status=~\"5..\"}[$WINDOW]))")
fast=$(prom_value "sum(increase(http_request_duration_seconds_bucket{$sel,le=\"0.5\"}[$WINDOW]))")
count=$(prom_value "sum(increase(http_request_duration_seconds_count{$sel}[$WINDOW]))")

[[ -z "$total" ]] && { fail "no request data for prod - is the app deployed and loadgen running?"; finish "SLO report"; }
errors=${errors:-0}

section "Availability (window: $WINDOW)"
awk -v t="$total" -v e="$errors" -v slo="$AVAIL_SLO" 'BEGIN {
  avail = 1 - e / t; budget = (1 - slo) * t; used = (budget > 0) ? e / budget * 100 : 0
  printf "requests: %d   errors: %d   availability: %.4f%%   (SLO %.1f%%)\n", t, e, avail * 100, slo * 100
  printf "error budget: %d failed requests allowed, %d used = %.0f%% of budget\n", budget, e, used
}' | tee -a "$REPORT_FILE"
used_pct=$(awk -v t="$total" -v e="$errors" -v slo="$AVAIL_SLO" 'BEGIN{printf "%d", e / ((1 - slo) * t) * 100}')
if (( used_pct >= 100 )); then fail "error budget exhausted - freeze risky releases, prioritise reliability work"
elif (( used_pct >= 75 )); then warn "error budget ${used_pct}% used"
else ok "availability SLO met"; fi

section "Latency (share of requests under 500 ms)"
if [[ -n "$fast" && -n "$count" ]]; then
  ratio=$(awk -v f="$fast" -v c="$count" 'BEGIN{printf "%.4f", f / c}')
  out "fast requests: $(awk -v r="$ratio" 'BEGIN{printf "%.2f", r*100}')%   (SLO $(awk -v s=$LAT_SLO 'BEGIN{print s*100}')%)"
  if awk -v r="$ratio" -v s="$LAT_SLO" 'BEGIN{exit !(r < s)}'; then warn "latency SLO missed"; else ok "latency SLO met"; fi
fi

finish "Monthly SLO report"
