# Runbook: OrdersApiDown

**Impact:** No orders-api pod in prod can be scraped; customers likely see errors or timeouts.

## Diagnose
```bash
kubectl -n prod get deploy,rs,pods -l app.kubernetes.io/name=orders-api
kubectl -n prod describe pod <pod>   # read Events at the bottom
kubectl -n prod logs <pod> --previous
helm -n prod history orders-api       # was there a recent deploy?
kubectl get nodes                     # are nodes Ready?
```

## Fix
- Recent bad deploy: helm -n prod rollback orders-api <previous revision>
- Pods Pending: check node capacity (kubectl describe pod), scale node group
- Readiness failing: check the database (see high-error-rate.md)

## Afterwards
- Confirm the alert resolved and dashboards are normal
- Write a short postmortem if users were affected
- Improve this runbook if anything was missing
