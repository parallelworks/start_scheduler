#!/bin/bash
APP_DIR=$(dirname $0)
source inputs.sh
source ${APP_DIR}/scheduler-libs.sh

export GTIHOME=/opt/gtsuite
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
# start_gt_db

# FIXME: Uncomment
# configure_daemon_systemd ${sched_prop_file}

while true; do
    echo; echo
    # REALOAD INPUTS AND LIBS
    # This facilitate debugging and quick fixes
    source inputs.sh
    source ${APP_DIR}/scheduler-libs.sh
    
    # Check every time in case new partitions are added
    check_partition_names
    
    # Writes balance to balance.json file
    # FIXME: Uncomment
    #write_balance # Writes balance.json

    # Updates the sched_prop_file to inhibit jobs that checkout products without balance
    python3 ${APP_DIR}/enforce_balance_in_prop_file.py ${sched_prop_file}

    # CORE DEMAND
    # FIXME Uncomment
    #curl_wrapper "curl -s http://${resource_privateIp}:8979/jobs/?xml" webapp.xml
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
    squeue --long
    sleep ${adv_pw_ds_cycle}
done


exit 0

#!/bin/bash
sleep 


# FIXME: This should be in the image!
sudo pip3 install requests

sleep 3
secure_curl () {
    local curl_cmd=$1
    local out_file=$2
    while true; do
	    ${curl_cmd} > ${out_file}.tmp 2> /dev/null && mv ${out_file}.tmp ${out_file}
        if [ -f ${out_file} ]; then
            break
	    else
            echo "ERROR: File ${out_file} was not produced by command:"
            echo "       ${curl_cmd}"
	        sleep 10
	    fi
    done
}

echo; echo INPUTS:
echo $@; echo

exec_pools=$1
version=$2 # v2020
sum_serv=$3
ds_cycle=$4
od_pct=$5
api_key=$6 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$7 # Properties files directory
cloud=$8
stream_port=${9}
pw_dir=${10}
PARSL_CLIENT_HOST=${11}
allow_ps=${12}


apps_dir=$(dirname $0)


pw_url="https://${PARSL_CLIENT_HOST}"

sched_ip_ext=$(curl -s ifconfig.me) # FIXME: Get internal IP
sched_ip_int=$(hostname -I  | cut -d' ' -f1 | sed "s/ //g")


# Create input for main.py script
create_ms_input () {
    echo "webapp_xml=webapp.xml" > ${ms_input}
    echo "sched_work_dir=${sched_work_dir}" >> ${ms_input}
    echo "exec_work_dir=${exec_work_dir}" >> ${ms_input}
    echo "version=${version}" >> ${ms_input}
    echo "pool_names=${exec_pools}" >> ${ms_input}
    echo "pool_info_json=pools_info.json" >> ${ms_input}
    echo "gtdist_exec_pfile=${exec_prop_file}" >> ${ms_input}
    echo "od_pct=${od_pct}" >> ${ms_input}
    echo "cloud=${cloud}" >> ${ms_input}
    echo "api_key=${api_key}" >> ${ms_input}
    echo "sched_ip_int=${sched_ip_int}" >> ${ms_input}
    echo "lic_hostname=${lic_hostname}" >> ${ms_input}
    echo "pw_url=${pw_url}" >> ${ms_input}
    echo "allow_ps=${allow_ps}" >> ${ms_input}
}

ms_input=main_input.txt
while true; do
    sleep ${ds_cycle}
    secure_curl "curl -s ${pw_url}/api/resources?key=${api_key}" pools_info.json
    secure_curl "curl -s http://${sched_ip_int}:8979/jobs/?xml" webapp.xml
    echo; date
    create_ms_input
    python3 ${apps_dir}/sched/main.py ${ms_input}
    sudo sed -i "s|^v|#v|g" /usr/lib/tmpfiles.d/tmp.conf
done

# create the license node tunnel
# ssh -L 27005:localhost:27005 localhost -fNT
# netstat -tulpn
# create the executor pool tunnel(s)
#localport=64027
# setsid ssh -L $localport:localhost:$localport localhost -fNT

# To test:
# yum install glibc.i686
# yum install libgcc_s.so.1

# RUN FROM USER NODE:
# Only needs to run once per user node --> User nodes may have multiple user containers
# LICENSE_SERVER=35.224.78.64
# LICENSE_USER=flexlm
# LICENSE_PORT=27005 27777

# autossh -M 0 -f -N -L $LICENSE_PORT:localhost:$LICENSE_PORT $LICENSE_USER@$LICENSE_SERVER
# autossh -M 0 -f -N -L $LICENSE_PORT:localhost:$LICENSE_PORT $LICENSE_USER@$LICENSE_SERVER
