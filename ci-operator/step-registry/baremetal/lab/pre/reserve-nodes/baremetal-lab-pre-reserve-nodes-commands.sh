#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

SSHOPTS=(-o 'ConnectTimeout=5'
  -o 'StrictHostKeyChecking=no'
  -o 'UserKnownHostsFile=/dev/null'
  -o 'ServerAliveInterval=90'
  -o LogLevel=ERROR
  -i "${CLUSTER_PROFILE_DIR}/ssh-key")

[ -z "${AUX_HOST}" ] && {  echo "\$AUX_HOST is not filled. Failing."; exit 1; }
[ -z "${masters}" ] && {  echo "\$masters is not filled. Failing."; exit 1; }
[ -z "${workers}" ] && {  echo "\$workers is not filled. Failing."; exit 1; }
[ -z "${architecture}" ] && {  echo "\$architecture is not filled. Failing."; exit 1; }

gnu_arch=$(echo "${architecture}" | sed 's/arm64/aarch64/;s/amd64/x86_64/')

# The hostname of nodes and the cluster names have limited length for BM.
# Other profiles add to the cluster_name the suffix "-${JOB_NAME_HASH}".
echo "${NAMESPACE}" > "${SHARED_DIR}/cluster_name"
CLUSTER_NAME="${NAMESPACE}"

echo "Reserving nodes for baremetal installation (${masters} masters, ${workers} workers) $([ "$RESERVE_BOOTSTRAP" == true ] && echo "+ 1 bootstrap physical node")..."
timeout -s 9 180m ssh "${SSHOPTS[@]}" "root@${AUX_HOST}" bash -s -- \
  "${CLUSTER_NAME}" "${masters}" "${workers}" "${RESERVE_BOOTSTRAP}" "${gnu_arch}" << 'EOF'
set -o nounset
set -o errexit
set -o pipefail
set -o allexport

BUILD_USER=ci-op
BUILD_ID="${1}"
N_MASTERS="${2}"
N_WORKERS="${3}"
# The IPI variable is to be deprecated in order to be more generic and better exploit the prow steps patterns for supporting
# multiple kind of installations
# However, for now, we need to keep it in the following as it is used by the baremetal lab scripts in the internal CI.
if [ "${4}" == "true" ]; then
  IPI=false
else
  IPI=true
fi
ARCH="${5}"
set +o allexport

# shellcheck disable=SC2174
mkdir -m 755 -p {/var/builds,/opt/tftpboot,/opt/html}/${BUILD_ID}
mkdir -m 777 -p /opt/nfs/${BUILD_ID}
touch /etc/{hosts_pool_reserved,vips_reserved}
# The current implementation of the following scripts is different based on the auxiliary host. Keeping the script in
# the remote aux servers temporarily.
bash /usr/local/bin/reserve_hosts.sh
bash /usr/local/bin/reserve_vips.sh
EOF

echo "Node reservation concluded successfully."
scp "${SSHOPTS[@]}" "root@${AUX_HOST}:/var/builds/${CLUSTER_NAME}/*.yaml" "${SHARED_DIR}/"
more "${SHARED_DIR}"/*.yaml |& sed 's/pass.*$/pass ** HIDDEN **/g'


# Example host element from the list in the hosts.yaml file:
# - mac: 34:73:5a:9d:eb:e1 # The mac address of the interface connected to the baremetal network
#  vendor: dell
#  ip: *****
#  host: openshift-qe-054
#  arch: x86_64
#  root_device: /dev/sdb
#  root_dev_hctl: ""
#  provisioning_mac: 34:73:5a:9d:eb:e2 # The mac address of the interface connected to the provisioning network (based on dynamic native-vlan)
#  switch_port: ""
#  switch_port_v2: ge-1/0/23@10.1.233.31:22 # Port in the managed switch (JunOS)
#  ipi_disabled_ifaces: eno1 # Interfaces to disable in the hosts
#  baremetal_iface: eno2 # The interface connected to the baremetal network
#  bmc_address: openshift-qe-054-drac.mgmt..... # The address of the BMC
#  bmc_scheme: ipmi
#  bmc_base_uri: /
#  bmc_user: ... # these are the ipmi credentials
#  bmc_pass: ...
#  console_kargs: tty1;ttyS0,115200n8 # The serial console kargs needed at boot time for allowing remote viewing of the console
#  transfer_protocol_type: http # VirtualMedia Transfer Protocol Type
#  redfish_user: ... # redfish credentials, ipmi and redfish credentials differ in some cases
#  redfish_password: ...
#  build_id: ci-op-testaget # not usually needed as it is the same as CLUSTER_NAME
#  build_user: ci-op
#  name: master-02 # This name must be either master or worker or bootstrap in order for the steps to set the role correctly
