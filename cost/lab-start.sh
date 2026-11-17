#!/usr/bin/env bash
# Run from your laptop each morning. Starts the lab and prints the new URLs
# (public IPs change after a stop/start; private IPs stay the same).
set -euo pipefail
REGION="${AWS_REGION:-us-west-2}"
CLUSTER="${CLUSTER_NAME:-devops-lab}"
DB="${DB_INSTANCE:-devops-lab-orders-db}"

echo "==> Starting lab EC2 instances"
ids=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=devops-lab" "Name=instance-state-name,Values=stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [[ -n "$ids" ]]; then
  # shellcheck disable=SC2086
  aws ec2 start-instances --instance-ids $ids --region "$REGION" >/dev/null
fi

echo "==> Starting RDS"
aws rds start-db-instance --db-instance-identifier "$DB" --region "$REGION" >/dev/null 2>&1 || echo "    already running"

echo "==> Scaling EKS node groups back to 2"
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[]' --output text); do
  aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$ng" --region "$REGION" \
    --scaling-config minSize=1,maxSize=4,desiredSize=2 >/dev/null
done

if [[ -n "$ids" ]]; then
  # shellcheck disable=SC2086
  aws ec2 wait instance-running --instance-ids $ids --region "$REGION"
fi
echo
aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=devops-lab" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,PublicIpAddress,PrivateIpAddress]' --output table
echo "Jenkins: http://<jenkins public IP>:8080   Nexus: :8081   SonarQube: :9000 (on the tools server)"
echo "Nodes and RDS take ~5-10 minutes to be ready. If your home IP changed, update my_ip_cidr and terraform apply."
