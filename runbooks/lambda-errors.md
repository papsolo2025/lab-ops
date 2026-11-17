# Runbook: Lambda errors / DLQ not empty

**Impact:** order exports are not being summarised (export-processor) or the lab is not being stopped (lab-scheduler).

## Diagnose
```bash
FN=devops-lab-export-processor
aws logs tail /aws/lambda/$FN --since 1h --filter-pattern '{ $.level = "ERROR" }'
aws lambda get-alias --function-name $FN --name live          # which version is live?
aws lambda list-versions-by-function --function-name $FN --query 'Versions[].[Version,Description]'
# X-Ray: CloudWatch console > X-Ray traces > filter by the function - which call failed and how long it took
# Jenkins: run ops/replay-dlq with DRY_RUN ticked to see the failed events and error messages
```

## Fix
- Bad deployment (errors started right after a release): roll back the alias
  `aws lambda update-alias --function-name $FN --name live --function-version <previous>`
- Permission error (AccessDenied in logs): compare the call with the role policy in envs/extension, fix in Terraform
- Throttling: check account concurrency (`aws lambda get-account-settings`); request an increase
- Then replay the failed events: ops/replay-dlq with DRY_RUN unticked

## Afterwards
- Confirm the CloudWatch alarm returned to OK and the DLQ is empty
- Postmortem if exports were missing for more than a day
