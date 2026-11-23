#!/usr/bin/env bash
# Chaos drills: break something on purpose, then find and fix it like a real incident.
# Each drill prints WHAT users would notice - not the fix. Diagnose with dashboards, alerts,
# kubectl, logs and the runbooks. Write a short postmortem afterwards.
#
# Usage: chaos/break.sh <drill>
#   crashloop     app in dev crashes on start                 (Kubernetes troubleshooting)
#   oom           app in dev is killed for memory             (exit code 137)
#   bad-image     dev deploys an image tag that doesn't exist (ImagePullBackOff)
#   errors        20% of prod requests fail                   (alerts, SLO burn)
#   slow          prod requests become slow                   (latency alert)
#   disk-full     fills the disk on web-1                     (needs SSH key at ~/.ssh/devops-lab)
#   nexus-down    stops Nexus on the tools server              (pipeline failures)
#   drift         two manual console changes                  (Terraform drift - and its blind spot)
#   node-loss     terminates one EKS worker node              (self-healing, PDBs)
#   poison-file   uploads an invalid export to S3             (quarantine pattern, SNS)
#   throttle      sets export-processor concurrency to 0      (throttling, async retries, DLQ)
#   public-bucket tries to make the exports bucket public     (guardrails: does it even work?)
set -euo pipefail
REGION="${AWS_REGION:-us-west-2}"
KEY="${SSH_KEY:-$HOME/.ssh/devops-lab}"

ip_of() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=devops-lab-$1" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
}

case "${1:-}" in
  crashloop)
    kubectl -n dev patch deploy orders-api --type=json \
      -p '[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["sh","-c","echo starting; exit 1"]}]'
    echo "SYMPTOM: dev orders-api is down. Developers report the dev environment is broken." ;;
  oom)
    kubectl -n dev set resources deploy/orders-api --limits=memory=20Mi --requests=memory=20Mi
    echo "SYMPTOM: dev orders-api keeps restarting." ;;
  bad-image)
    kubectl -n dev set image deploy/orders-api orders-api=public.ecr.aws/nginx/nginx:does-not-exist
    echo "SYMPTOM: a 'deployment' to dev never finishes." ;;
  errors)
    kubectl -n prod set env deploy/orders-api CHAOS_ERROR_RATE=0.2
    echo "SYMPTOM: customers report intermittent failures in prod. Watch Grafana and Alertmanager." ;;
  slow)
    kubectl -n prod set env deploy/orders-api CHAOS_LATENCY_MS=800
    echo "SYMPTOM: customers say the app is slow." ;;
  disk-full)
    host=$(ip_of web-1)
    ssh -i "$KEY" -o StrictHostKeyChecking=no "ubuntu@$host" \
      'avail=$(df --output=avail -B1 / | tail -1); sudo fallocate -l $((avail * 93 / 100)) /var/log/app-debug.log && df -h /'
    echo "SYMPTOM: web-1 alerts on disk space. Find what is using the space." ;;
  nexus-down)
    host=$(ip_of tools)
    ssh -i "$KEY" -o StrictHostKeyChecking=no "ubuntu@$host" 'docker stop nexus'
    echo "SYMPTOM: CI pipelines started failing in the unit test stage." ;;
  drift)
    # Two "console changes". Terraform plan catches one of them but not the other - find out which and why.
    aws rds modify-db-instance --region "$REGION" --db-instance-identifier devops-lab-orders-db \
      --backup-retention-period 1 --apply-immediately >/dev/null
    sg=$(aws ec2 describe-security-groups --region "$REGION" --filters Name=group-name,Values=devops-lab-servers \
      --query 'SecurityGroups[0].GroupId' --output text)
    aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$sg" \
      --ip-permissions 'IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges=[{CidrIp=0.0.0.0/0,Description=temp-debug}]' >/dev/null
    echo "SYMPTOM: someone made 'temporary' changes in the console (database backups and a firewall rule)."
    echo "Run the drift check. Does it catch BOTH changes? (Hint: look at how the security group rules are modelled.)" ;;
  node-loss)
    node=$(kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' | awk -F/ '{print $NF}')
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$node" >/dev/null
    echo "SYMPTOM: a worker node disappeared ($node). Did prod stay up? How long until a new node joined?" ;;
  poison-file)
    acct=$(aws sts get-caller-identity --query Account --output text)
    echo '{"orders": [{"id": 1, "item": "pen", "quantity": "lots"}]}' > /tmp/poison.json
    aws s3 cp /tmp/poison.json "s3://devops-lab-orders-exports-$acct/exports/dev/orders-poison-$(date +%s).json"
    echo "SYMPTOM: an upstream system produced a bad export. What happened to it? (S3, logs, email)" ;;
  throttle)
    aws lambda put-function-concurrency --function-name devops-lab-export-processor --reserved-concurrent-executions 0 >/dev/null
    echo "SYMPTOM: exports stopped being summarised. Upload a file (or wait for the CronJob) and investigate."
    echo "(Throttled async events are retried for up to 1 hour, then land in the DLQ.)" ;;
  public-bucket)
    acct=$(aws sts get-caller-identity --query Account --output text)
    aws s3api put-bucket-acl --bucket "devops-lab-orders-exports-$acct" --acl public-read \
      && echo "!! The bucket accepted a public ACL - investigate" \
      || echo "Blocked. Which setting stopped it? Now try a bucket policy granting s3:GetObject to Principal \"*\"."
    ;;
  *)
    sed -n '2,20p' "$0"; exit 1 ;;
esac
