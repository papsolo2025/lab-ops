#!/usr/bin/env bash
# DAILY: does the real AWS infrastructure still match the Terraform code?
# Needs: LAB_TERRAFORM_REPO, and TFVARS_FILE (Jenkins secret-file credential with terraform.tfvars)
source "$(dirname "$0")/lib.sh"
require git terraform
start_report daily-drift-check
: "${LAB_TERRAFORM_REPO:?}" "${TFVARS_FILE:?}"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 "$LAB_TERRAFORM_REPO" "$work/tf"

# Each stack has its own state; check them all. The extension stack is skipped if never applied.
for stack in ${TF_STACKS:-lab extension}; do
  section "Stack: envs/$stack"
  dir="$work/tf/envs/$stack"
  [[ -d "$dir" ]] || { warn "envs/$stack not in repo"; continue; }
  cp "$TFVARS_FILE" "$dir/terraform.tfvars"
  plan="$REPORT_DIR/terraform-plan-$stack.txt"
  if ! (cd "$dir" && terraform init -input=false -no-color >/dev/null 2>"$plan"); then
    out "$(tail -5 "$plan")"; fail "init failed for $stack"; continue
  fi
  set +e
  (cd "$dir" && terraform plan -input=false -no-color -lock-timeout=120s -detailed-exitcode) > "$plan" 2>&1
  rc=$?
  set -e
  case $rc in
    0) ok "no drift - matches the code" ;;
    2) if grep -q 'Plan: [1-9][0-9]* to add, 0 to change, 0 to destroy' "$plan" && [[ "$stack" != "lab" ]] \
          && ! grep -q 'must be replaced\|will be updated\|will be destroyed' "$plan"; then
         warn "$stack: only additions planned - stack probably not applied yet"
       else
         out "$(grep -E '^\s+# .* (will|must) be' "$plan" || true)"
         out "$(grep -E '^Plan:' "$plan" || true)"
         warn "$stack: DRIFT or unapplied changes - see terraform-plan-$stack.txt"
       fi ;;
    *) out "$(tail -20 "$plan")"; fail "$stack: terraform plan failed (exit $rc)" ;;
  esac
done

finish "Terraform drift check"
