# Runbook: OrdersApiHighErrorRate / OrdersApiErrorBudgetFastBurn

**Impact:** More than 5% of prod requests return HTTP 5xx.

## Diagnose
```bash
Grafana: error ratio by route and pod - is it one pod or all?
kubectl -n prod logs deploy/orders-api --since=15m | grep -i error
kubectl -n prod get deploy orders-api -o yaml | grep -A1 CHAOS   # injected failures?
aws rds describe-db-instances --db-instance-identifier devops-lab-orders-db --query 'DBInstances[0].DBInstanceStatus'
kubectl -n prod get secret orders-db -o jsonpath='{.metadata.annotations}'   # password rotated?
```

## Fix
- Bad release: helm -n prod rollback orders-api <revision>
- Password rotated: run the ops/sync-db-secret job
- Chaos setting left on: kubectl -n prod set env deploy/orders-api CHAOS_ERROR_RATE=0

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
