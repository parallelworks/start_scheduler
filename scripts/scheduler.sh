#!/bin/bash

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
version=$3
VERSION=$(echo ${version} | sed "s/v//g")
GT_USER=$4
sum_serv=$5
api_key=$6 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$7 # Properties files directory
log_dir=$8

apps_dir=$(dirname $0)
export GTIHOME=/opt/gtsuite
GT_VERSION_HOME=${GTIHOME}/${version}
export GTISOFT_LICENSE_FILE=$1
export PATH=${GTIHOME}/bin/:${PATH}
export PATH=${GT_VERSION_HOME}/GTsuite/bin/linux_x86_64/:${PATH}
export PATH=/opt/swift-pw-bin/swift-svn/bin/:${PATH}
pw_http="http://beta.parallel.works"

sched_ip=$(curl ifconfig.me)
echo "Scheduler IP:   ${sched_ip}"

# Directories / Files:
sched_work_dir=/var/opt/gtsuite/
exec_work_dir=/var/opt/gtsuite/
mkdir -p ${sched_work_dir}/gtdistd ${sched_work_dir}/db ${sched_work_dir}/compounds

# Make sure user has permissions
sudo chown ${GT_USER}: ${GTIHOME} -R
chmod u+w ${GTIHOME} -R
sudo chown ${GT_USER}: ${sched_work_dir} -R
chmod u+w ${sched_work_dir} -R

# Attach and mount disk
host_instance=`hostname`
disk_name=$(echo ${host_instance} | cut -d'-' -f2-3)
disk_zone=$(echo ${host_instance} | cut -d'-' -f6-)
gcloud compute instances attach-disk ${host_instance} --disk ${disk_name} --device-name ${disk_name} --zone ${disk_zone}
sudo mount /dev/disk/by-id/google-${disk_name} ${sched_work_dir}

exec_prop_file=${sched_work_dir}/gtdistd/gtdistd-exec.properties
sched_prop_file=${sched_work_dir}/gtdistd/gtdistd-sched.properties

# Prepare executor properties file (except core-count and priority)
# cp ${GT_VERSION_HOME}/distributed/config-samples/gtdistd-exec.properties ${exec_prop_file}
cp ${pf_dir}/gtdistd-exec-${version}.properties ${exec_prop_file}
sed -i "s|GTDistributed.work-dir.*|GTDistributed.work-dir = ${exec_work_dir}|g" ${exec_prop_file}
sed -i "s|GTDistributed.license-file.*|GTDistributed.license-file = ${GTISOFT_LICENSE_FILE}|g" ${exec_prop_file}
sed -i "s|GTDistributed.client.hostname.*|GTDistributed.client.hostname = ${sched_ip}|g" ${exec_prop_file}
sed -i 's/\r//' ${exec_prop_file}

# Prepare scheduler properties file
cp ${pf_dir}/gtdistd-sched-${version}.properties ${sched_prop_file}
sed -i "s|GTDistributed.work-dir.*|GTDistributed.work-dir = ${sched_work_dir}/gtdistd|g" ${sched_prop_file}
if [[ ${sum_serv} == "True" ]]; then
    echo Activating summary service
    sed -i "s|GTDistributed.job-summary-service-enable.*|GTDistributed.job-summary-service-enable = true|g" ${sched_prop_file}
fi

# Start or restart gtdist daemon
# Make sure user exists:
if ! [ -d /home/${GT_USER} ]; then
    echo "Creating user account for user: ${GT_USER}"
    adduser ${GT_USER}
fi

# Start DB on node boot as GT_USER
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstop
${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart

# Make sure this user can write the gtdistd.out file
touch /tmp/gtdistd.out
chmod 777 /tmp/gtdistd.out

# Start gtdist daemon

#$GTIHOME/v2020/distributed/bin/gtdistd.sh -c <config-file>
# USE LATEST VERSION!
configure_daemon_systemd() {
    local prop_file=$1
    # Following instructions in section 5b of /opt/gtsuite/v2020/distributed/bin/README_Linux.md
    sudo cp ${GTIHOME}/v2020/distributed/bin/systemd-unit-files/gtdistd.service /etc/systemd/system/
    sudo cp -r ${GTIHOME}/v2020/distributed/bin/systemd-unit-files/gtdistd.service.d /etc/systemd/system/
    conf_file=/etc/systemd/system/gtdistd.service.d/override.conf
    sudo sed -i "s|User=.*|User=${GT_USER}|g" ${conf_file}
    sudo sed -i "s|Environment=GTIHOME=.*|Environment=GTIHOME=${GTIHOME}|g" ${conf_file}
    sudo sed -i "s|Environment=GT_VERSION_HOME=.*|Environment=GT_VERSION_HOME=${GT_VERSION_HOME}|g" ${conf_file}
    sudo sed -i "s|Environment=GT_CONF=.*|Environment=GT_CONF=${prop_file}|g" ${conf_file}
    # Environment=JRE_HOME=/opt/gtsuite/v2020/GTsuite/jre/linux_x86_64
    # Environment=JAVA_OPTS=
    # Environment=DAEMON_OUT=/tmp/gtdistd.out

    # Verify the syntax of the `override.conf` file contains no syntax errors. A correct file
    # will generate no output.
    sudo systemd-analyze verify /etc/systemd/system/gtdistd.service

    # Restart service:
    sudo systemctl start gtdistd.service
    sudo systemctl status gtdistd.service

    # Launch GUI Need X11 DISPLAY!
    # $GTIHOME/v2020/distributed/bin/gtdistdconfig.sh
}

configure_daemon_systemd ${sched_prop_file}

# Create input for main.py script
create_ms_input () {
    echo "webapp_xml=webapp.xml" > ${ms_input}
    echo "sched_work_dir=${sched_work_dir}" >> ${ms_input}
    echo "exec_work_dir=${exec_work_dir}" >> ${ms_input}
    echo "gt_user=${GT_USER}" >> ${ms_input}
    echo "version=${version}" >> ${ms_input}
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
    # but will waste time (executor.sh has a timeout)
    echo; date
    create_ms_input
    python3 ${apps_dir}/sched/main.py ${ms_input}
done