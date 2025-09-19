#!/usr/bin/env bash

set -euo pipefail

export PS4='+\e[0;33m $(printf "%-8s %s\\t%-10s" $(date +%T) "$0:${LINENO}")\e[m\n+ '

# shellcheck disable=SC2154
trap 'exit_code=$?; echo "Failed at $0:${LINENO}: $BASH_COMMAND (exit: $exit_code)"; exit $exit_code' ERR

update_hosts_entry() {
  local ip="$1"
  local hostname="$2"
  local hosts_file="/etc/hosts"

  if [ -z "$ip" ] || [ -z "$hostname" ]; then
    echo "Error: Both IP and hostname must be provided"
    return 1
  fi

  sudo cp "$hosts_file" "hosts.bak.$(date +%s)"

  if grep -q "[[:space:]]${hostname}\([[:space:]]*\)$" "$hosts_file"; then
    echo "Updating existing hosts entry for ${hostname}"
    sudo sed -i.tmp "s/^[^#]*[[:space:]]${hostname}\([[:space:]]*\)$/${ip} ${hostname}/" "$hosts_file"
    sudo rm -f "${hosts_file}.tmp"
  else

    echo "Adding new hosts entry: ${ip} ${hostname}"
    echo "${ip} ${hostname}" | sudo tee -a "$hosts_file" > /dev/null
  fi

  if grep -q "^${ip}[[:space:]]${hostname}" "$hosts_file"; then
    echo "Successfully updated /etc/hosts with ${ip} ${hostname}"
  else
    echo "Warning: Failed to verify hosts entry update"
    return 1
  fi
}

lock_id="${1}"
lock_dir=$(mktemp -d -t lock.sshuttle)

pushd "${lock_dir}"
  sheepctl lock get "${lock_id}" --json > lock.json

  cat lock.json | jq -r '.access' > metadata

  source metadata

  # Setup NSXT Hostname
  openssl s_client -showcerts -proxy "$BOSH_VSPHERE_JUMPER_HOST:80" -connect "${BOSH_VSPHERE_CPI_NSXT_HOST}":443 </dev/null 2>/dev/null | openssl x509 -outform PEM > "nsxt-manager-cert.pem"
  BOSH_NSXT_CERT_HOST_NAME="$(openssl x509 -noout -text -in nsxt-manager-cert.pem | awk '/X509v3 Subject Alternative Name/ {getline;gsub(/ /, "", $0); print}' | tr -d "DNS:" | sed 's/^\*\./nsx-mgr./')"
  update_hosts_entry "${BOSH_VSPHERE_CPI_NSXT_HOST}" "${BOSH_NSXT_CERT_HOST_NAME}"

  # Setup VC Hostname
  openssl s_client -showcerts -proxy "$BOSH_VSPHERE_JUMPER_HOST:80" -connect "${BOSH_VSPHERE_CPI_HOST}":443 </dev/null 2>/dev/null | openssl x509 -outform PEM > "vcenter-cert.pem"
  BOSH_VSPHERE_CERT_HOST_NAME="$(openssl x509 -noout -text -in vcenter-cert.pem | awk '/X509v3 Subject Alternative Name/ {getline;gsub(/ /, "", $0); print}' | tr -d "DNS:" | sed 's/^\*\./nsx-mgr./')"
  update_hosts_entry "${BOSH_VSPHERE_CPI_HOST}" "${BOSH_VSPHERE_CERT_HOST_NAME}"

  echo "use this password for the vcpi login: ${BOSH_VSPHERE_JUMPER_PASSWORD}"
  sshuttle -r vcpi@"${BOSH_VSPHERE_JUMPER_HOST}" 192.168.111.0/24
popd
