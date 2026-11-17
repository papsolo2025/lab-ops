# Runbook: Ec2DiskUsageHigh / Ec2DiskWillFillIn24h

**Impact:** A server's root disk is filling up.

## Diagnose
```bash
ssh ubuntu@<ip> 'df -h /'
sudo du -xh / --max-depth=2 2>/dev/null | sort -rh | head -20
sudo find / -xdev -type f -size +500M -exec ls -lh {} \; 2>/dev/null
docker system df   # on Docker hosts
```

## Fix
- Delete the large unneeded file (confirm with the owner first)
- Run the ops/daily-disk-cleanup job
- Long term: log rotation, alert earlier, or grow the volume in Terraform

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
