#!/usr/bin/env bash
# DAILY: run the Ansible cleanup playbook on every server (logs, journal, Docker images).
# Needs: LAB_ANSIBLE_REPO, SSH_KEY_FILE (Jenkins SSH credential)
source "$(dirname "$0")/lib.sh"
require git ansible-playbook
start_report daily-disk-cleanup
: "${LAB_ANSIBLE_REPO:?}" "${SSH_KEY_FILE:?}"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
git clone -q --depth 1 "$LAB_ANSIBLE_REPO" "$work/ansible"
cd "$work/ansible"

export ANSIBLE_HOST_KEY_CHECKING=False ANSIBLE_FORCE_COLOR=0
# Limit excludes Jenkins itself; it cleans its own Docker cache in the same way.
if ansible-playbook -i inventories/private.aws_ec2.yml --private-key "$SSH_KEY_FILE" playbooks/cleanup.yml \
     2>&1 | tee -a "$REPORT_FILE"; then
  ok "cleanup finished on all servers"
else
  fail "cleanup playbook failed"
fi

finish "Disk cleanup"
