#!/usr/bin/env bash
# WEEKLY: which alerts fired most in the last 7 days? Noisy alerts get tuned or deleted.
source "$(dirname "$0")/lib.sh"
require kubectl jq
start_report weekly-alert-noise-report
setup_kube
NOTIFY_ON_OK=true

section "Top alerts by time spent firing (last 7 days)"
# ALERTS is evaluated every 30s, so samples * 30 / 3600 = hours firing.
prom_query 'topk(10, sum by (alertname, severity) (count_over_time(ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor"}[7d])))' \
  | jq -r '.data.result | sort_by(-(.value[1] | tonumber))[]
           | "\((.value[1] | tonumber) * 30 / 3600 | . * 10 | floor / 10)h\t\(.metric.severity // "-")\t\(.metric.alertname)"' \
  | tee -a "$REPORT_FILE"

out ""
out "For each alert above ask: did someone need to act? If not -> raise the threshold, add 'for:', or delete it."
out "Then: was there an incident this week that had NO alert? -> add one."

finish "Alert noise report"
