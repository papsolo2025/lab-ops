#!/usr/bin/env bash
# WEEKLY: Nexus health and blob store size (cleanup policies themselves run inside Nexus as scheduled tasks).
# Needs: NEXUS_URL, NEXUS_USER, NEXUS_PASS (Jenkins credential nexus-admin)
source "$(dirname "$0")/lib.sh"
require curl jq
start_report weekly-nexus-health
: "${NEXUS_URL:?}" "${NEXUS_USER:?}" "${NEXUS_PASS:?}"
WARN_GB="${NEXUS_WARN_GB:-20}"

section "Status"
if curl -fsS "$NEXUS_URL/service/rest/v1/status/writable" >/dev/null; then ok "Nexus is up and writable"
else fail "Nexus is not writable"; finish "Nexus health"; fi

checks=$(curl -fsS -u "$NEXUS_USER:$NEXUS_PASS" "$NEXUS_URL/service/rest/v1/status/check")
echo "$checks" | jq -r 'to_entries[] | "\(if .value.healthy then "healthy  " else "UNHEALTHY" end)  \(.key)"' | tee -a "$REPORT_FILE"
unhealthy=$(echo "$checks" | jq '[to_entries[] | select(.value.healthy | not)] | length')
if (( unhealthy == 0 )); then ok "all health checks pass"; else warn "$unhealthy health check(s) failing"; fi

section "Blob stores"
while IFS=$'\t' read -r name bytes count; do
  [[ -z "$name" ]] && continue
  gb=$(awk -v b="$bytes" 'BEGIN{printf "%.2f", b/1024/1024/1024}')
  out "$name: ${gb} GB in $count blobs"
  if awk -v g="$gb" -v w="$WARN_GB" 'BEGIN{exit !(g > w)}'; then
    warn "$name above ${WARN_GB} GB - check cleanup policies and run 'Compact blob store'"
  fi
done < <(curl -fsS -u "$NEXUS_USER:$NEXUS_PASS" "$NEXUS_URL/service/rest/v1/blobstores" \
         | jq -r '.[] | "\(.name)\t\(.totalSizeInBytes)\t\(.blobCount)"')

finish "Nexus health"
