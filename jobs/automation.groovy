// Job DSL: creates one scheduled Jenkins job per operational task.
// LAB_OPS_REPO comes from the Jenkins controller environment (/opt/jenkins/.env).
// Schedules avoid 23:00-08:00 because the lab servers are stopped overnight to save money.

def tasks = [
  // ---- Daily ----
  [name: 'sync-db-secret',            cron: 'H 8 * * *',  desc: 'Copy rotated RDS password into Kubernetes secrets; restart app if it changed'],
  [name: 'daily-health-check',        cron: 'H 8 * * *',  desc: 'Nodes, pods, firing alerts, EC2 disks, prod golden signals'],
  [name: 'daily-backup-verify',       cron: 'H 9 * * *',  desc: 'RDS snapshots and AWS Backup jobs from the last 24h'],
  [name: 'daily-drift-check',         cron: 'H 10 * * *', desc: 'terraform plan -detailed-exitcode against real AWS'],
  [name: 'daily-disk-cleanup',        cron: 'H 20 * * *', desc: 'Ansible cleanup: journal, old logs, Docker images'],
  [name: 'daily-lambda-health',       cron: 'H 9 * * *',  desc: 'Lambda errors/throttles/p99, DLQ depth, export pipeline freshness'],
  // ---- Weekly ----
  [name: 'weekly-security-scan',      cron: 'H 9 * * 1',  desc: 'Trivy scan of every image running in the cluster'],
  [name: 'weekly-cost-report',        cron: 'H 9 * * 1',  desc: 'Cost this week vs last, idle and untagged resources'],
  [name: 'weekly-nexus-health',       cron: 'H 9 * * 1',  desc: 'Nexus health checks and blob store size'],
  [name: 'weekly-alert-noise-report', cron: 'H 15 * * 5', desc: 'Which alerts fired most this week'],
  [name: 'weekly-patching',           cron: 'H 10 * * 6', desc: 'Rolling OS patching of web and tools servers'],
  [name: 'weekly-storage-review',     cron: 'H 9 * * 1',  desc: 'S3 security baseline and size, EFS tiering/backups, EBS gp2 and snapshots, RDS space'],
  // ---- Monthly (1st of the month; run them by hand during the 2-week lab) ----
  [name: 'monthly-dr-drill',          cron: 'H 11 1 * *', desc: 'Restore latest RDS snapshot, validate data, measure RTO/RPO, clean up'],
  [name: 'monthly-access-review',     cron: 'H 11 1 * *', desc: 'IAM credential report: MFA, old keys, unused users, root usage'],
  [name: 'monthly-slo-report',        cron: 'H 12 1 * *', desc: 'Availability/latency SLO and error budget for prod'],
  [name: 'monthly-capacity-report',   cron: 'H 12 1 * *', desc: 'Cluster headroom, disks/PVCs filling, HPAs at max'],
  [name: 'monthly-eks-version-check', cron: 'H 12 1 * *', desc: 'Kubernetes version support window, upgrade insights, deprecated APIs'],
  // ---- On demand (no schedule) ----
  [name: 'replay-dlq',                cron: null,         desc: 'Inspect (DRY_RUN) or replay failed Lambda events from the dead-letter queue'],
]

folder('ops') {
  description('Scheduled operations automation - every repetitive daily, weekly and monthly task')
}

tasks.each { t ->
  pipelineJob("ops/${t.name}") {
    description(t.desc)
    parameters {
      stringParam('TASK', t.name, 'Script in lab-ops/scripts to run')
      booleanParam('DRY_RUN', t.name == 'replay-dlq', 'Preview only (weekly-patching, replay-dlq)')
    }
    if (t.cron) {
      properties {
        pipelineTriggers {
          triggers {
            cron { spec(t.cron) }
          }
        }
      }
    }
    definition {
      cpsScm {
        scm {
          git {
            remote { url(LAB_OPS_REPO) }
            branch('*/main')
          }
        }
        scriptPath('pipelines/ops-task.Jenkinsfile')
        lightweight(true)
      }
    }
  }
}

// Dashboard view of all ops jobs
listView('Operations') {
  jobs { regex('ops/.*') }
  recurse(true)
  columns {
    status()
    weather()
    name()
    lastSuccess()
    lastFailure()
    lastDuration()
    buildButton()
  }
}
