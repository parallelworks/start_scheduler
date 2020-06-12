#!/bin/bash
apps_dir=$(dirname $0)
export GTIHOME=/home/GTI
export GTISOFT_LICENSE_FILE=$1
export PATH=/home/GTI/bin/:${PATH}
export PATH=/opt/swift-pw-bin/swift-svn/bin/:${PATH}

pool_name=$2
GT_USER=$3
ds_freq=$4 # Demand sensing frequency
api_key=$5 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$6 # Properties files directory
sched_ip=$(curl ifconfig.me)

curl https://beta.parallel.works/api/resources?key=${api_key} > pools_info.json
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

# Packages per executor
ppe=${workercpu}

# Global completed packets counter:
count_rq(){
    curl http://${sched_ip}:8979/jobs/?xml > webapp.xml
    python3 ${apps_dir}/count_rq.py webapp.xml
}

# Old way of counting packets based on work subdirectories
count_rq_old() {
    rqc=0
    for jd in $(find ${sched_work_dir}/jobs -maxdepth 1 -mindepth 1 -type d); do
	    jrqc=-2 # Split and merge are not sent to executors
	    for pd in $(find ${jd} -maxdepth 1 -mindepth 1 -type d); do
	        gdx_file=$(find ${pd} -name *.gdx)
	        # Assuming that if no results file is present then job is running or queued
	        if [ -z "${gdx_file}" ]; then
		        jrqc=$((jrqc+1))
	        fi
	    done
	    # If job is not done
	    # jrqc = 0 ---> Just done
	    # jrqc = -1 --> Merged
	    if [ ${jrqc} -gt 0 ]; then
	        rqc=$((rqc + jrqc))
	    fi
    done
    echo ${rqc}
}

count_active_executors() {
    ls 2>/dev/null -Ubad1 -- /tmp/cjs.* | wc -l
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
            /bin/bash ${exec_work_dir}/wti.sh ${GT_USER}
    rm ${cjs_rf}
}

count_free_licenses() {
    license_info=$(perl ${apps_dir}/lmstatparse.pl -f GTsuite)
    used=$(echo ${license_info} | awk '{print $2}')
    total=$(echo ${license_info} | awk '{print $3}')
    echo $((total - used))
}

match_supply_to_demand() {
    # Packets running or queued
    rqc_demand=$(count_rq)
    echo Running or Queued Packets: ${rqc_demand}
    active_executors=$(count_active_executors)
    # Packets than can be executed
    pe_supply=$((active_executors * ppe))
    echo Packet Execution Supply: ${pe_supply}
    if [ ${rqc_demand} -gt ${pe_supply} ]; then
	    overdemand=$((rqc_demand - pe_supply))
        echo "Over Demand: ${overdemand}"
	    for i in $(seq 1 ${ppe} ${overdemand}); do
            if [ ${pe_supply} -lt ${max_pool_cap} ]; then
                if [ ${pe_supply} -lt ${free_licenses} ]; then
                    echo "Starting Executor (cjs)"
                    cjs &
                    sleep 0.01
                    pe_supply=$((pe_supply + ppe))
                else
                    echo "All licenses are in use!"
                    break
                fi
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
sed -i "s|.*GTDistributed.executor.core-count.*|GTDistributed.executor.core-count = ${workercpu}|g" ${exec_prop_file}
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

while true; do
    sleep ${ds_freq}
    # Try not to submit more cog-job-submit than the max_pool_capacity. Should not break anything
    # but will waste time (wti.sh has a timeout anyway)
    date
    max_pool_slider=$(curl ${CONTROLURL}/getAll | tr ',' '\n' | grep max | cut -d':' -f2)
    max_pool_cap=$((max_pool_slider * ppe))
    free_licenses=$(count_free_licenses) # Takes ~ 1 sec to run
    match_supply_to_demand
done
