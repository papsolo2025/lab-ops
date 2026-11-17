#!/usr/bin/env bash
# DAILY (and on demand): copy the RDS password from Secrets Manager into a Kubernetes Secret
# in each app namespace, create the per-environment database, and restart the app if the password changed.
#
# Why: RDS rotates its managed master password automatically (every 7 days by default).
# Without this job the app loses its database connection every week - a classic real-world incident.
source "$(dirname "$0")/lib.sh"
require aws jq kubectl psql sha256sum
start_report sync-db-secret
setup_kube

NAMESPACES="${NAMESPACES:-dev staging prod}"

db=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE" --query 'DBInstances[0]' --output json)
host=$(echo "$db" | jq -r '.Endpoint.Address')
secret_arn=$(echo "$db" | jq -r '.MasterUserSecret.SecretArn')
creds=$(aws secretsmanager get-secret-value --secret-id "$secret_arn" --query SecretString --output text)
user=$(echo "$creds" | jq -r .username)
pass=$(echo "$creds" | jq -r .password)
hash=$(printf '%s' "$pass" | sha256sum | cut -c1-12)

for ns in $NAMESPACES; do
  dbname="orders_${ns}"
  section "$ns -> database $dbname"

  # Create the database if it does not exist (one RDS instance, one database per environment)
  if ! PGPASSWORD="$pass" psql "host=$host dbname=postgres user=$user sslmode=require" -tAc \
      "SELECT 1 FROM pg_database WHERE datname='$dbname'" | grep -q 1; then
    PGPASSWORD="$pass" psql "host=$host dbname=postgres user=$user sslmode=require" -c "CREATE DATABASE $dbname"
    ok "created database $dbname"
  fi

  kubectl get ns "$ns" >/dev/null 2>&1 || kubectl create ns "$ns"
  old_hash=$(kubectl -n "$ns" get secret orders-db -o jsonpath='{.metadata.annotations.lab/password-hash}' 2>/dev/null || true)

  kubectl -n "$ns" create secret generic orders-db \
    --from-literal=DB_HOST="$host" --from-literal=DB_NAME="$dbname" \
    --from-literal=DB_USER="$user" --from-literal=DB_PASSWORD="$pass" \
    --dry-run=client -o yaml \
    | kubectl annotate -f - --local -o yaml "lab/password-hash=$hash" \
    | kubectl apply -f - >/dev/null

  if [[ "$old_hash" != "$hash" ]]; then
    if kubectl -n "$ns" get deploy orders-api >/dev/null 2>&1; then
      kubectl -n "$ns" rollout restart deploy/orders-api
      warn "$ns: password changed - secret updated and orders-api restarted"
    else
      ok "$ns: secret created (orders-api not deployed yet)"
    fi
  else
    ok "$ns: secret already current"
  fi
done

finish "DB secret sync"
