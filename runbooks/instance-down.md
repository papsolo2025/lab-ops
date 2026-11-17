# Runbook: Ec2InstanceDown

**Impact:** Prometheus cannot reach node_exporter on a lab server.

## Diagnose
```bash
aws ec2 describe-instance-status --include-all-instances --filters Name=tag:Name,Values=<name>
Was it stopped on purpose (nightly stop)?
ssh ubuntu@<ip> 'systemctl status node_exporter'
```

## Fix
- Instance stopped: start it (cost/lab-start.sh)
- node_exporter dead: sudo systemctl restart node_exporter; re-run Ansible site.yml to enforce config

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
