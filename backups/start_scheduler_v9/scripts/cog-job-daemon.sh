#!/bin/bash
apps_dir=$(dirname $0)
export GTIHOME=/home/GTI
export GTISOFT_LICENSE_FILE=$1
export PATH=/home/GTI/bin/:${PATH}
export PATH=/home/GTI/v2019/GTsuite/bin/linux_x86_64/:${PATH}
export PATH=/opt/swift-pw-bin/swift-svn/bin/:${PATH}
pw_http="http://beta.parallel.works"


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

exec_pools=$2
GT_USER=$3
api_key=$4 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$5 # Properties files directory
log_dir=$6

sched_ip=$(curl ifconfig.me)
echo "Scheduler IP:   ${sched_ip}"

# Directories / Files:
gtdistd=/etc/init.d/gtdistd
sched_work_dir=/var/opt/gtsuite/gtdistd
exec_work_dir=/var/opt/gtsuite/gtdistd

# Return the scheduler to saved state
mkdir -p ${sched_work_dir}
host_instance=`hostname`
disk_name=$(echo ${host_instance} | cut -d'-' -f2-3)
disk_zone=$(echo ${host_instance} | cut -d'-' -f6-)
gcloud compute instances attach-disk ${host_instance} --disk ${disk_name} --device-name ${disk_name} --zone ${disk_zone}
mount /dev/disk/by-id/google-${disk_name} ${sched_work_dir}
chmod 777 ${sched_work_dir} -R

exec_prop_file=${sched_work_dir}/gtdistd-exec.properties
sched_prop_file=${sched_work_dir}/gtdistd-sched.properties
GT_VERSION_HOME=${GTIHOME}/v2019

# Clean jobs dir:
#rm -rf ${sched_work_dir}/jobs/*
rm -f /tmp/cjs.*

# Prepare executor properties file
cp ${pf_dir}/gtdistd-exec.properties ${exec_prop_file}
cp ${GTIHOME}/v2019/distributed/config-samples/gtdistd-exec.properties ${exec_prop_file}
sed -i "s|GTDistributed.work-dir.*|GTDistributed.work-dir = ${exec_work_dir}|g" ${exec_prop_file}
sed -i "s|GTDistributed.license-file.*|GTDistributed.license-file = ${GTISOFT_LICENSE_FILE}|g" ${exec_prop_file}
sed -i "s|GTDistributed.client.hostname.*|GTDistributed.client.hostname = ${sched_ip}|g" ${exec_prop_file}
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

# Start DB on node boot as GT_USER
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart ds
#<call_to_solver>
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstop ds
#${GTIHOME}/bin/gtcollect dbstart
su ${GT_USER} -c "${GTIHOME}/bin/gtcollect dbstart"


# Make sure this user can write the gtdistd.out file
touch /tmp/gtdistd.out
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

# Create input for main.py script
create_ms_input () {
    echo "webapp_xml=webapp.xml" > ${ms_input}
    echo "sched_work_dir=${sched_work_dir}" >> ${ms_input}
    echo "exec_work_dir=${exec_work_dir}" >> ${ms_input}
    echo "gt_user=${GT_USER}" >> ${ms_input}
    echo "sched_ip=${sched_ip}" >> ${ms_input}
    echo "pool_names=${exec_pools}" >> ${ms_input}
    echo "pool_info_json=pools_info.json" >> ${ms_input}
    echo "gtdist_exec_pfile=${exec_prop_file}" >> ${ms_input}
    echo "log_dir=${log_dir}" >> ${ms_input}
}

ms_input=main_input.txt
while true; do
    sleep 30
    secure_curl "curl https://beta.parallel.works/api/resources?key=${api_key}" pools_info.json
    secure_curl "curl http://${sched_ip}:8979/jobs/?xml" webapp.xml
    # Try not to submit more cog-job-submit than the max_pool_capacity. Should not break anything
    # but will waste time (wti.sh has a timeout)
    echo; date
    create_ms_input
    /bin/python3.6 ${apps_dir}/sched/main.py ${ms_input}
done