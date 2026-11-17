#!/usr/bin/env bash
# Run from your laptop at the end of each day. Stops everything that can be stopped.
# Still billed while stopped: EKS control plane, NAT gateway, EBS volumes, ALB, public IPv4 addresses.
# To stop ALL charges: terraform destroy (see the guide, Day 14).
set -euo pipefail
REGION="${AWS_REGION:-us-west-2}"
CLUSTER="${CLUSTER_NAME:-devops-lab}"
DB="${DB_INSTANCE:-devops-lab-orders-db}"

echo "==> Scaling EKS node groups to 0"
for ng in $(aws eks list-nodegroups --cluster-name "$CLUSTER" --region "$REGION" --query 'nodegroups[]' --output text); do
  aws eks update-nodegroup-config --cluster-name "$CLUSTER" --nodegroup-name "$ng" --region "$REGION" \
    --scaling-config minSize=0,maxSize=4,desiredSize=0 >/dev/null
  echo "    $ng -> 0"
done

echo "==> Stopping RDS ($DB) - AWS restarts it automatically after 7 days"
aws rds stop-db-instance --db-instance-identifier "$DB" --region "$REGION" >/dev/null 2>&1 \
  && echo "    stopping" || echo "    already stopped (or not available)"

echo "==> Stopping lab EC2 instances"
ids=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Project,Values=devops-lab" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [[ -n "$ids" ]]; then
  # shellcheck disable=SC2086
  aws ec2 stop-instances --instance-ids $ids --region "$REGION" >/dev/null
  echo "    stopping: $ids"
else
  echo "    none running"
fi
echo "Done. Start again with cost/lab-start.sh"
