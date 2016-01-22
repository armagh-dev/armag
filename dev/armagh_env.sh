export ARMAGH_DEV_ROOT=$1
export ARMAGH_HOME=${ARMAGH_DEV_ROOT}/home/armagh
export ARMAGH_CONFIG=${ARMAGH_DEV_ROOT}/etc/armagh
export ARMAGH_DATA=${ARMAGH_DEV_ROOT}/var/armagh
export ARMAGH_REPO=${ARMAGH_DEV_ROOT}/home/armagh/repo
export ARMAGH_CLUSTER_SETUP=${ARMAGH_DEV_ROOT}/home/armagh/cluster_setup
export ARMAGH_CA=${ARMAGH_DEV_ROOT}/etc/armagh/ca
export ARMAGH_APP_LOG=${ARMAGH_DEV_ROOT}/var/log/armagh
export ARMAGH_PID=${ARMAGH_DEV_ROOT}/var/run/armagh

for x in ARMAGH_HOME ARMAGH_CONFIG ARMAGH_DATA ARMAGH_REPO ARMAGH_CLUSTER_SETUP ARMAGH_CA ARMAGH_APP_LOG ARMAGH_PID
do
  eval target_dir=\$${x}
  mkdir -p ${target_dir}
done

export ARMAGH_STRL=bW9uZ29kYjovLzEyNy4wLjAuMToyNzAxNy9hcm1hZ2gK
export ARMAGH_STRF=bW9uZ29kYjovLzEyNy4wLjAuMToyNzAxNy9hcm1hZ2hfYWRtaW4K