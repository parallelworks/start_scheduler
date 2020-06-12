#!/bin/bash
apps_dir=$(dirname $0)
export GTIHOME=/home/GTI
export GTISOFT_LICENSE_FILE=$1
export PATH=/home/GTI/bin/:${PATH}
export PATH=/home/GTI/v2019/GTsuite/bin/linux_x86_64/:${PATH}
export PATH=/opt/swift-pw-bin/swift-svn/bin/:${PATH}

secure_curl () {
    local curl_cmd=$1
    local out_file=$2
    while true; do
	    ${curl_cmd} > ${out_file}.tmp && mv ${out_file}.tmp ${out_file}
        if [ -f ${out_file} ]; then
            break
	    else
            echo "ERROR: File ${out_file} was not produced by command:"
            echo "       ${curl_cmd}"
	        sleep 10
	    fi
    done
}

pool_name=$2
GT_USER=$3
api_key=$4 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$5 # Properties files directory
cpe=$6 # Cores per executor
limits_file=$7

sched_ip=$(curl ifconfig.me)

secure_curl "curl https://beta.parallel.works/api/resources?key=${api_key}" pools_info.json

python3 ${apps_dir}/read_pool_info.py pools_info.json ${pool_name} pool_info.env
source pool_info.env
echo "Scheduler IP:   ${sched_ip}"
echo "Exec Pool Name: ${pool_name}"
echo "Worker CPUs:    ${workercpu}"
echo "Max Workers:    ${maxworkers}"
echo "Service Port:   ${serviceport}"
echo "Control Port:   ${controlport}"

pw_http="http://beta.parallel.works"
SERVICEURL="${pw_http}:${serviceport}"
CONTROLURL="${pw_http}:${controlport}"

# Directories / Files:
gtdistd=/etc/init.d/gtdistd
sched_work_dir=/var/opt/gtsuite/gtdistd
exec_work_dir=/var/opt/gtsuite/gtdistd
exec_prop_file=${sched_work_dir}/gtdistd-exec.properties
sched_prop_file=${sched_work_dir}/gtdistd-sched.properties
GT_VERSION_HOME=${GTIHOME}/v2019


# If the cores per executor is not defined (<1) use all cpus
# Will not use hyperthreaded cpus by default!
max_cpe=$((2* workercpu))
if [ ${cpe} -lt 1 ]; then
    cpe=${workercpu}
elif [ ${cpe} -gt ${max_cpe} ]; then
    echo "WARNING: More CPUs per executor (${cpe}) were selected than available vCPUs (${max_cpe})"
    echo "WARNING: Defaulting CPUs per executor to maximum available ${max_cpe}"
    cpe=${max_cpe}
fi
echo "Using ${cpe} cores per executor"

count_core_supply() {
    executor_count=$(ls 2>/dev/null -Ubad1 -- /tmp/cjs.* | wc -l)
    echo $((executor_count * cpe))
}

cjs() {
    # Every cjs runs writes and deletes a file to monitor executor supply
    cjs_rf=$(mktemp /tmp/cjs.XXXXXX)
    wait_till_iddle_map="${apps_dir}/wti.sh -> ${exec_work_dir}/wti.sh"
    prop_file_map="${exec_prop_file} -> /tmp/gtdistd-exec.properties"
    STAGEINS="${wait_till_iddle_map} : ${prop_file_map}"
    cog-job-submit -provider "coaster-persistent" \
	       -service-contact "$SERVICEURL" \
	       -stagein "${STAGEINS}" \
	       -directory "${exec_work_dir}" \
            /bin/bash ${exec_work_dir}/wti.sh ${GT_USER} ${sched_ip}
    rm ${cjs_rf}
}

# Looking at core demand vs supply
# Fixme: Need to know how many packets to check if gt free_licenses
match_supply_to_demand() {
    # Core Demand:
    core_demand=$(cat ${sched_work_dir}/CORE_DEMAND)
    echo Core Demand: ${core_demand}
    # Core Supply
    core_supply=$(count_core_supply)
    echo Core Supply: ${core_supply}
    if [ ${core_demand} -gt ${core_supply} ]; then
	    overdemand=$((core_demand - core_supply))
        echo "Over Demand: ${overdemand}"
	    for i in $(seq 1 ${cpe} ${overdemand}); do
            if [ ${core_supply} -lt ${max_pool_cap} ]; then
                echo "Starting Executor (cjs)"
                cjs &
                sleep 0.01
                core_supply=$((core_supply + cpe))
            else
                echo "Supply ${pe_supply} reached maximum pool capacity ${max_pool_cap}"
                break
            fi
	    done
    fi
}

# Clean jobs dir:
#rm -rf ${sched_work_dir}/jobs/*
rm -f /tmp/cjs.*
chmod 777 ${sched_work_dir} -R

# Prepare executor properties file
cp ${pf_dir}/gtdistd-exec.properties ${exec_prop_file}
cp ${GTIHOME}/v2019/distributed/config-samples/gtdistd-exec.properties ${exec_prop_file}
sed -i "s|GTDistributed.work-dir.*|GTDistributed.work-dir = ${exec_work_dir}|g" ${exec_prop_file}
sed -i "s|GTDistributed.license-file.*|GTDistributed.license-file = ${GTISOFT_LICENSE_FILE}|g" ${exec_prop_file}
sed -i "s|GTDistributed.client.hostname.*|GTDistributed.client.hostname = ${sched_ip}|g" ${exec_prop_file}
sed -i "s|.*GTDistributed.executor.core-count.*|GTDistributed.executor.core-count = ${cpe}|g" ${exec_prop_file}
sed -i 's/\r//' ${exec_prop_file}

# Prepare scheduler properties file
cp ${pf_dir}/gtdistd-sched.properties ${sched_prop_file}

# Prepare if gtdistd daemon file
echo "Copying file ${GTIHOME}/v2019/distributed/bin/gtdistd-init.d to ${gtdistd}"
cp ${GTIHOME}/v2019/distributed/bin/gtdistd-init.d ${gtdistd}
echo Editing ${gtdistd} with:
echo GT_USER=${GT_USER}
echo GT_CONF=${sched_prop_file}
echo GT_VERSION_HOME=${GT_VERSION_HOME}
sed -i "s|^GT_VERSION_HOME.*|GT_VERSION_HOME=${GT_VERSION_HOME}|g" ${gtdistd}
sed -i "s|^GT_USER.*|GT_USER=${GT_USER}|g" ${gtdistd}
sed -i "s|^GT_CONF.*|GT_CONF=${sched_prop_file}|g" ${gtdistd}
sed -i 's/\r//' ${gtdistd}

# Start or restart gtdist daemon
# Make sure user exists:
if ! [ -d /home/${GT_USER} ]; then
    echo "Creating user account for user: ${GT_USER}"
    adduser ${GT_USER}
fi
# Make sure this user can write the gtdistd.out file
chmod 777 /tmp/gtdistd.out
# Start gtdist daemon
gtdistd_status=$(${gtdistd} status)
echo ${gtdistd_status}
if [[ ${gtdistd_status} == "GT-Distributed is not running" ]]; then
    echo Starting gtdistd
    sleep 10
    ${gtdistd} start
else
    echo Re-starting gtdistd
    sleep 10
    ${gtdistd} restart
fi
${gtdistd} status



mv ${limits_file} ${sched_work_dir}
while true; do
    sleep 30
    lmutil lmstat -a > lmstat.out
    secure_curl "curl http://${sched_ip}:8979/jobs/?xml" webapp.xml
    # Try not to submit more cog-job-submit than the max_pool_capacity. Should not break anything
    # but will waste time (wti.sh has a timeout anyway)
    date
    /bin/python3.6 ${apps_dir}/sched_info/update_sched_info.py webapp.xml ${sched_work_dir} lmstat.out
    max_pool_slider=$(curl ${CONTROLURL}/getAll | tr ',' '\n' | grep max | cut -d':' -f2)
    max_pool_cap=$((max_pool_slider * cpe))
    match_supply_to_demand
done