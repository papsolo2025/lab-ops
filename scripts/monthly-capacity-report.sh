#!/usr/bin/env bash
# MONTHLY: capacity planning - how full is the cluster, which disks will fill, which HPAs are maxed out.
source "$(dirname "$0")/lib.sh"
require kubectl jq
start_report monthly-capacity-report
setup_kube
NOTIFY_ON_OK=true

pct() { awk -v v="${1:-0}" 'BEGIN{printf "%d", v * 100}'; }

section "Cluster requests vs allocatable"
cpu=$(prom_value 'sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"})')
mem=$(prom_value 'sum(kube_pod_container_resource_requests{resource="memory"}) / sum(kube_node_status_allocatable{resource="memory"})')
out "CPU requested: $(pct "$cpu")%   memory requested: $(pct "$mem")%"
if (( $(pct "$cpu") > 80 || $(pct "$mem") > 80 )); then warn "cluster above 80% of allocatable - raise node group max or rightsize requests"; else ok "cluster has headroom"; fi

section "Nodes right now"
kubectl top nodes 2>/dev/null | tee -a "$REPORT_FILE" || out "(metrics-server not available)"

section "EC2 disks predicted to fill within 30 days"
full=$(prom_query 'predict_linear(node_filesystem_avail_bytes{job="ec2-node-exporter",mountpoint="/"}[7d], 30*24*3600) < 0' \
  | jq -r '.data.result[].metric.name')
if [[ -z "$full" ]]; then ok "no disks predicted to fill"; else out "$full"; warn "disks predicted to fill within 30 days"; fi

section "Persistent volumes above 70%"
pvcs=$(prom_query 'kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.7' \
  | jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.persistentvolumeclaim) \(.value[1] | tonumber * 100 | floor)%"')
if [[ -z "$pvcs" ]]; then ok "all PVCs below 70%"; else out "$pvcs"; warn "PVCs filling up"; fi

section "HPAs at their maximum replicas"
maxed=$(prom_query 'kube_horizontalpodautoscaler_status_current_replicas >= on (namespace, horizontalpodautoscaler) kube_horizontalpodautoscaler_spec_max_replicas' \
  | jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.horizontalpodautoscaler)"')
if [[ -z "$maxed" ]]; then ok "no HPA at max"; else out "$maxed"; warn "HPAs at max - raise maxReplicas or optimise"; fi

finish "Monthly capacity report"
