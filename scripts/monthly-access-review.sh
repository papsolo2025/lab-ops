#!/usr/bin/env bash
# MONTHLY: IAM access review from the credential report - MFA, old keys, unused users, root usage.
source "$(dirname "$0")/lib.sh"
require aws python3
start_report monthly-access-review
NOTIFY_ON_OK=true

until [[ "$(aws iam generate-credential-report --query State --output text)" == "COMPLETE" ]]; do sleep 3; done
aws iam get-credential-report --query Content --output text | base64 -d > "$REPORT_DIR/credential-report.csv"

section "Findings"
findings=$(python3 - "$REPORT_DIR/credential-report.csv" <<'PY'
import csv, sys
from datetime import datetime, timezone
now = datetime.now(timezone.utc)
def age(v):
    if v in ("N/A", "no_information", "not_supported", ""):
        return None
    return (now - datetime.fromisoformat(v.replace("Z", "+00:00"))).days
for r in csv.DictReader(open(sys.argv[1])):
    u = r["user"]
    if u == "<root_account>":
        used = age(r["password_last_used"])
        if used is not None and used < 30:
            print(f"FAIL root account was used {used} days ago - use IAM users/roles instead")
        if r["access_key_1_active"] == "true" or r["access_key_2_active"] == "true":
            print("FAIL root account has active access keys - delete them")
        if r["mfa_active"] != "true":
            print("FAIL root account has no MFA")
        continue
    if r["password_enabled"] == "true" and r["mfa_active"] != "true":
        print(f"WARN {u}: console password without MFA")
    for k in ("1", "2"):
        if r[f"access_key_{k}_active"] == "true":
            rot = age(r[f"access_key_{k}_last_rotated"])
            used = age(r[f"access_key_{k}_last_used_date"])
            if rot is not None and rot > 90:
                print(f"WARN {u}: access key {k} is {rot} days old - rotate it")
            if used is None or used > 90:
                print(f"WARN {u}: access key {k} unused for 90+ days - disable it")
    pw_used = age(r["password_last_used"])
    if r["password_enabled"] == "true" and (pw_used is None or pw_used > 90):
        print(f"WARN {u}: console login unused for 90+ days - disable it")
PY
)
if [[ -z "$findings" ]]; then ok "no findings"; fi
while read -r level msg; do
  [[ -z "$level" ]] && continue
  if [[ "$level" == "FAIL" ]]; then fail "$msg"; else warn "$msg"; fi
done <<<"$findings"

out ""
out "Also review by hand: Jenkins users, Nexus users, SonarQube users, Grafana users, GitHub collaborators."
out "Evidence saved: credential-report.csv (auditors ask for this)."

finish "Monthly access review"
