# Runbook: KubePodCrashLooping

**Impact:** A pod keeps restarting.

## Diagnose
```bash
kubectl -n <ns> get pods
kubectl -n <ns> describe pod <pod>     # Last State: reason + exit code
kubectl -n <ns> logs <pod> --previous
Exit code 137 = OOMKilled (memory limit), 1 = app error, 127 = command not found
```

## Fix
- Fix the cause in Git (values file or code), let the pipeline redeploy
- Emergency: helm -n <ns> rollback orders-api <revision>

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
