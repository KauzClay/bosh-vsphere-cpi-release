#!/usr/bin/env bash

set -euo pipefail

export PS4='+\e[0;33m $(printf "%-8s %s\\t%-10s" $(date +%T) "$0:${LINENO}")\e[m\n+ '

# shellcheck disable=SC2154
trap 'exit_code=$?; echo "Failed at $0:${LINENO}: $BASH_COMMAND (exit: $exit_code)"; exit $exit_code' ERR

lock_id="${1}"
lock_dir=$(mktemp -d -t lock.sshuttle)

pushd "${lock_dir}"
  sheepctl lock get "${lock_id}" --json > lock.json

  cat lock.json | jq -r '.access' > metadata

  source metadata

  echo "use this password for the vcpi login: ${BOSH_VSPHERE_JUMPER_PASSWORD}"
  sshuttle -r vcpi@"${BOSH_VSPHERE_JUMPER_HOST}" 192.168.111.0/24
popd
