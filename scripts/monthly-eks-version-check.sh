#!/usr/bin/env bash
# MONTHLY: is the cluster on a supported Kubernetes version, and is it ready to upgrade?
source "$(dirname "$0")/lib.sh"
require aws jq kubectl
start_report monthly-eks-version-check
setup_kube
NOTIFY_ON_OK=true

current=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query cluster.version --output text)
info=$(aws eks describe-cluster-versions --cluster-versions "$current" --query 'clusterVersions[0]' --output json)
latest=$(aws eks describe-cluster-versions --version-status STANDARD_SUPPORT \
  --query 'clusterVersions[].clusterVersion' --output text | tr '\t' '\n' | sort -V | tail -1)

section "Version"
eos=$(echo "$info" | jq -r '.endOfStandardSupportDate // empty')
out "cluster: $current   newest in standard support: $latest   status: $(echo "$info" | jq -r .versionStatus)"
if [[ -n "$eos" ]]; then
  days=$(( ( $(date -d "$eos" +%s) - $(date +%s) ) / 86400 ))
  out "end of standard support: $eos ($days days)"
  if (( days < 60 )); then warn "less than 60 days of standard support left - schedule the upgrade (extended support costs 6x)"; fi
fi
[[ "$current" != "$latest" ]] && out "upgrade available: $current -> next minor version (one minor version at a time)"

section "EKS upgrade insights"
aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter '{"categories":["UPGRADE_READINESS"]}' --output json \
  | jq -r '.insights[] | "\(.insightStatus.status)\t\(.name)"' | tee -a "$REPORT_FILE"
bad=$(aws eks list-insights --cluster-name "$CLUSTER_NAME" --filter '{"categories":["UPGRADE_READINESS"],"statuses":["ERROR","WARNING"]}' \
  --query 'length(insights)' --output text)
if (( bad == 0 )); then ok "no upgrade blockers reported"; else warn "$bad upgrade insight(s) need attention"; fi

section "Deprecated APIs still being called (from API server metrics)"
dep=$(prom_query 'group by (group, version, resource, removed_release) (apiserver_requested_deprecated_apis)' \
  | jq -r '.data.result[].metric | "\(.group)/\(.version) \(.resource) removed in \(.removed_release)"')
if [[ -z "$dep" ]]; then ok "no deprecated API usage"; else out "$dep"; warn "deprecated APIs in use - fix before upgrading"; fi

finish "EKS version check"
