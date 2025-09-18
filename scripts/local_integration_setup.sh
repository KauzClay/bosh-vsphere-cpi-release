#!/usr/bin/env bash

set -eo pipefail

export PS4='+\e[0;33m $(printf "%-8s %s\\t%-10s" $(date +%T) "$0:${LINENO}")\e[m\n+ '

# shellcheck disable=SC2154
trap 'exit_code=$?; echo "Failed at $0:${LINENO}: $BASH_COMMAND (exit: $exit_code)"; exit $exit_code' ERR

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  local script="$(basename "${0:-${BASH_SOURCE[0]}}")"
  local margin="$(printf '%*s' ${#script})"
while IFS= read -r line; do echo "${line/  /}"; done <<EOF
  Usage: $script [TEST_ARGS]

  Launch a Nimbus testbed from a Vane recipe

  Options:

  Arguments:
    TEST_ARGS             Stuff you wanna pass to rspec, like the test file

  Environment Variables:
    LOCK_ID                           Shepherd v1 lock id
    BOSH_VSPHERE_STEMCELL_ID          Use a pre-deployed stemcell instead of uploading one for your test
EOF
  exit 1
}

lock_id="${LOCK_ID}"

[ -z "${lock_id}" ] && usage

lock_dir=$(mktemp -d -t lock)

pushd "${lock_dir}"
  sheepctl lock get "${lock_id}" --json > lock.json

  cat lock.json | jq -r '.access' > metadata

  source metadata

  export BOSH_NSXT_CA_CERT_FILE
  BOSH_NSXT_CA_CERT_FILE="${PWD}/nsxt-manager-cert.pem"
  # To get the cert from nsxt-manager, we run openssl on the jump box, and then pipe that result into a local openssl command that reformats it into PEM
  openssl s_client -showcerts -connect "${BOSH_VSPHERE_CPI_NSXT_HOST}":443 </dev/null 2>/dev/null | openssl x509 -outform PEM > $BOSH_NSXT_CA_CERT_FILE
  # The certificate's SAN contains the host name, so extract it because SSL validation fails when using the IP address
  # NOTE: Don't hard code the name as it is not guaranteed to be "nsxt-manager"
  BOSH_NSXT_CERT_HOST_NAME="$(openssl x509 -noout -text -in nsxt-manager-cert.pem | awk '/X509v3 Subject Alternative Name/ {getline;gsub(/ /, "", $0); print}' | tr -d "DNS:" | sed 's/^\*\./nsx-mgr./')"
  # TODO this shouldn't add a new entry every time you run
  #echo "${BOSH_VSPHERE_CPI_NSXT_HOST} ${BOSH_NSXT_CERT_HOST_NAME}" | sudo tee -a /etc/hosts
  export BOSH_VSPHERE_CPI_NSXT_HOST="https://${BOSH_NSXT_CERT_HOST_NAME}"

  BOSH_VSPHERE_STEMCELL="$(pwd)/stemcell/stemcell.tgz"
  export BOSH_VSPHERE_STEMCELL

popd


pushd "${SCRIPT_ROOT}/../src/vsphere_cpi"

bundle install


SKIP_STEMCELL_DELETION=true bundle exec rspec --require ./spec/support/verbose_formatter.rb --format VerboseFormatter "$@"

popd

