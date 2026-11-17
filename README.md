# lab-ops
Operations automation: every repetitive daily, weekly and monthly task as a script, scheduled by Jenkins.

- `scripts/` - one script per task (shared helpers in `lib.sh`; exit 0=OK, 1=WARN, 2=FAIL)
- `pipelines/ops-task.Jenkinsfile` - generic runner used by every scheduled job
- `jobs/*.groovy` - Job DSL: creates the `ops/*` jobs and the `orders-api` pipeline (run by the `seed-jobs` job)
- `runbooks/` - what to do when an alert fires
- `chaos/break.sh` - 13 incident drills (Kubernetes, servers, drift, Lambda, S3)
- `cost/lab-stop.sh`, `cost/lab-start.sh` - stop/start the lab to save money
