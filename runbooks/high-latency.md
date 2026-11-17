# Runbook: OrdersApiHighLatency

**Impact:** p95 latency in prod is above 500 ms.

## Diagnose
```bash
Grafana: latency by route, CPU throttling, pod count (HPA)
kubectl -n prod top pods
kubectl -n prod get hpa
RDS: CPU and connections in CloudWatch
```

## Fix
- CPU throttled: raise CPU requests/limits or HPA max
- Database slow: check slow queries, instance size
- Chaos setting left on: kubectl -n prod set env deploy/orders-api CHAOS_LATENCY_MS=0

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
