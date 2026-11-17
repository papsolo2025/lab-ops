#!/usr/bin/env bash
# WEEKLY: rolling OS patching of web + tools servers (one at a time, reboot if needed, post-checks).
# Needs: LAB_ANSIBLE_REPO, SSH_KEY_FILE.  Set DRY_RUN=true for --check mode.
source "$(dirname "$0")/lib.sh"
require git ansible-playbook
start_report weekly-patching
: "${LAB_ANSIBLE_REPO:?}" "${SSH_KEY_FILE:?}"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 "$LAB_ANSIBLE_REPO" "$work/ansible"
cd "$work/ansible"

args=(-i inventories/private.aws_ec2.yml --private-key "$SSH_KEY_FILE" playbooks/patch.yml)
[[ "${DRY_RUN:-false}" == "true" ]] && args+=(--check) && out "DRY RUN (--check)"

export ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=0
if ansible-playbook "${args[@]}" 2>&1 | tee -a "$REPORT_FILE"; then
  ok "patching completed"
else
  fail "patching failed - check which host stopped the rollout"
fi

finish "Weekly patching"
