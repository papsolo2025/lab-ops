#!/usr/bin/env bash
# DAILY: the "morning health check" - cluster, pods, alerts, servers, app golden signals.
source "$(dirname "$0")/lib.sh"
require kubectl jq aws
start_report daily-health-check
setup_kube

section "Kubernetes nodes"
kubectl get nodes -o wide | tee -a "$REPORT_FILE"
not_ready=$(kubectl get nodes --no-headers | awk '$2 != "Ready"' | wc -l)
if (( not_ready == 0 )); then ok "all nodes Ready"; else fail "$not_ready node(s) not Ready"; fi

section "Pods that are not Running/Completed"
bad_pods=$(kubectl get pods -A --no-headers | grep -Ev 'Running|Completed' || true)
if [[ -z "$bad_pods" ]]; then ok "no unhealthy pods"; else out "$bad_pods"; fail "unhealthy pods found"; fi

section "Pods with more than 5 restarts"
restarts=$(kubectl get pods -A -o json | jq -r '.items[]
  | {ns: .metadata.namespace, pod: .metadata.name, r: ([.status.containerStatuses[]?.restartCount] | add // 0)}
  | select(.r > 5) | "\(.ns)/\(.pod) restarts=\(.r)"')
if [[ -z "$restarts" ]]; then ok "no pods restarting repeatedly"; else out "$restarts"; warn "pods restarting"; fi

section "Firing alerts"
alerts=$(prom_query 'ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor"}' \
  | jq -r '.data.result[].metric | "\(.severity // "-")\t\(.alertname)\t\(.namespace // .name // .instance // "")"' | sort -u)
if [[ -z "$alerts" ]]; then ok "no alerts firing"; else out "$alerts"; warn "$(echo "$alerts" | wc -l) alert(s) firing"; fi

section "EC2 servers (node_exporter)"
prom_query 'up{job="ec2-node-exporter"}' | jq -r '.data.result[] | "\(.metric.name)\tup=\(.value[1])"' | tee -a "$REPORT_FILE"
while IFS=$'\t' read -r name pct; do
  [[ -z "$name" ]] && continue
  if (( pct >= 85 )); then warn "$name disk ${pct}% full"; else ok "$name disk ${pct}%"; fi
done < <(prom_query '100 * (1 - node_filesystem_avail_bytes{job="ec2-node-exporter",mountpoint="/"} / node_filesystem_size_bytes{job="ec2-node-exporter",mountpoint="/"})' \
         | jq -r '.data.result[] | "\(.metric.name)\t\(.value[1] | tonumber | floor)"')

section "orders-api in prod (last hour)"
rps=$(prom_value 'sum(rate(http_requests_total{namespace="prod",route!~"/health.*"}[1h]))')
err=$(prom_value 'sum(rate(http_requests_total{namespace="prod",route!~"/health.*",status=~"5.."}[1h])) / sum(rate(http_requests_total{namespace="prod",route!~"/health.*"}[1h]))')
p95=$(prom_value 'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="prod",route!~"/health.*"}[1h])))')
out "requests/sec: ${rps:-no data}   error ratio: ${err:-no data}   p95 seconds: ${p95:-no data}"
if [[ -z "$rps" ]]; then warn "no traffic data for prod orders-api"
elif awk -v e="${err:-0}" 'BEGIN{exit !(e > 0.01)}'; then warn "error ratio above 1%"
else ok "error ratio within target"; fi

section "TLS certificates (hosts in CERT_HOSTS, if set)"
for host in ${CERT_HOSTS:-}; do
  end=$(echo | openssl s_client -connect "$host:443" -servername "$host" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [[ -z "$end" ]]; then warn "$host: could not read certificate"; continue; fi
  days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
  if (( days < 30 )); then warn "$host certificate expires in $days days"; else ok "$host certificate: $days days left"; fi
done

finish "Daily health check"
