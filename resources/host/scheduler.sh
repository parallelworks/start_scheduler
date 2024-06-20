#!/bin/bash
APP_DIR=$(dirname $0)
source inputs.sh
source ${APP_DIR}/scheduler-libs.sh

export GTIHOME=/software/gtsuite
GT_VERSION_HOME=${GTIHOME}/${gt_version}
export PATH=${GTIHOME}/bin/:${PATH}
export PATH=${GT_VERSION_HOME}/GTsuite/bin/linux_x86_64/:${PATH}

# Directories / Files:
# Persistent disk is mounted in the sched_work_dir!
export sched_work_dir=/var/opt/gtsuite/
export exec_work_dir=/var/opt/gtsuite/


sudo mkdir -p ${sched_work_dir} ${GTIHOME}

# Make sure user has permissions
sudo chown ${USER}: ${GTIHOME} -R
chmod u+w ${GTIHOME} -R
sudo chown ${USER}: ${sched_work_dir} -R
chmod u+w ${sched_work_dir} -R
mkdir -p ${sched_work_dir}/gtdistd ${sched_work_dir}/db ${sched_work_dir}/compounds

ulimit -u

# Create license tunnels
# FIXME: It assumes ~/.ssh/config is present and defines the usercontainer host!
#        Won't work in onprem resources!
ssh -J usercontainer ${resource_ssh_usercontainer_options} -fN \
    -L 0.0.0.0:${gt_license_port}:localhost:${gt_license_port} \
    -L 0.0.0.0:${gt_license_vendor_port}:localhost:${gt_license_vendor_port} \
    flexlm@${gt_license_ip} </dev/null &>/dev/null &

netstat -tuln |  grep "${gt_license_port}\|${gt_license_vendor_port}"


# CREATE PROPERTIES FILES
exec_prop_file=${sched_work_dir}/gtdistd/gtdistd-exec.properties
sched_prop_file=${sched_work_dir}/gtdistd/gtdistd-sched.properties

# Prepare executor properties file (except core-count and priority)
pf_dir=properties_files
# cp ${GT_VERSION_HOME}/distributed/config-samples/gtdistd-exec.properties ${exec_prop_file}
cp ${pf_dir}/gtdistd-exec-${gt_version}.properties ${exec_prop_file}
sed -i "s|^GTDistributed.work-dir.*|GTDistributed.work-dir = ${exec_work_dir}/gtdistd|g" ${exec_prop_file}
sed -i "s|^GTDistributed.license-file.*|GTDistributed.license-file = ${resource_privateIp}:${gt_license_port}|g" ${exec_prop_file}
sed -i "s|^GTDistributed.client.hostname.*|GTDistributed.client.hostname = ${resource_privateIp}|g" ${exec_prop_file}
sed -i 's/\r//' ${exec_prop_file}

# Prepare scheduler properties file
cp ${pf_dir}/gtdistd-sched-${gt_version}.properties ${sched_prop_file}
sed -i "s|^GTDistributed.work-dir.*|GTDistributed.work-dir = ${sched_work_dir}/gtdistd|g" ${sched_prop_file}
if [[ ${adv_gt_sum_serv} == "True" ]]; then
    echod Activating summary service
    sed -i "s|GTDistributed.job-summary-service-enable.*|GTDistributed.job-summary-service-enable = true|g" ${sched_prop_file}
fi

if [[ ${adv_gt_allow_ps} == "True" ]]; then
    echod "Enabling parallel solver"
    sed -i "s|GTDistributed.scheduler.max-parallel-cores-per-solver.*||g" ${sched_prop_file}
    sed -i "s|GTDistributed.scheduler.validation.max-parallel-cores-per-solver.*||g" ${sched_prop_file}
fi

# Start or restart gtdist daemon
date >> ${sched_work_dir}/dates.txt


# FIXME: Uncomment
start_gt_db
if ! start_gt_db; then
    echo "ERROR: Failed to start GT database" >&2
    exit 1
fi

# FIXME: Uncomment
configure_daemon_systemd ${sched_prop_file}
if ! configure_daemon_systemd ${sched_prop_file}; then
    echo "ERROR: Failed to configure and start daemon systemd with ${sched_prop_file}" >&2
    cat /tmp/gtdistd.out >&2
    exit 1
fi

while true; do
    sleep ${adv_pw_ds_cycle}
    echo; echo
    # REALOAD INPUTS AND LIBS
    # This facilitate debugging and quick fixes
    source inputs.sh
    source ${APP_DIR}/scheduler-libs.sh
    
    # Check every time in case new partitions are added
    check_partition_names
    
    # Writes balance to balance.json file
    # FIXME: Uncomment
    write_balance # Writes balance.json

    # Updates the sched_prop_file to inhibit jobs that checkout products without balance
    python3 ${APP_DIR}/enforce_balance_in_prop_file.py ${sched_prop_file}

    # CORE DEMAND
    # FIXME Uncomment
    curl_wrapper "curl -s http://${resource_privateIp}:8979/jobs/?xml" webapp.xml
    # FIXME Uncomment
    python3 get_core_demand.py \
        --webapp_xml webapp.xml \
        --balance_json balance.json \
        --allow_ps ${adv_gt_allow_ps} \
        --sched_work_dir ${sched_work_dir} > CORE_DEMAND

    export CORE_DEMAND=$(cat CORE_DEMAND)
    echod "CORE DEMAND: ${CORE_DEMAND}"

    # CORE SUPPLY
    list_sorted_partitions
    get_core_supply
    echod "CORE SUPPLY: ${CORE_SUPPLY}"

    core_overdemand=$((CORE_DEMAND-CORE_SUPPLY))
    
    if [ -f "INHIBIT_JOBS" ]; then
        echod "INHIBITING SUBMISSION OF ADDITIONAL JOBS"
        core_overdemand=0
    fi

    if [ "${core_overdemand}" -gt 0 ]; then
        echod "CORE OVERDEMAND: ${core_overdemand}"
        satisfy_core_overdemand ${core_overdemand}
    fi
    # The tail is to skip the date
    squeue --long | tail -n +2
done