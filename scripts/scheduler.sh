#!/bin/bash
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

exec_pools=$1
version=$2 # v2020
sum_serv=$3
ds_cycle=$4
od_frac=$5
api_key=$6 #4c1bb8ff47a0f42b96ebb670dcb09418 (not a real API key)
pf_dir=$7 # Properties files directory
log_dir=$8
cloud=${9}

apps_dir=$(dirname $0)
export GTIHOME=/opt/gtsuite
GT_VERSION_HOME=${GTIHOME}/${version}
export PATH=${GTIHOME}/bin/:${PATH}
export PATH=${GT_VERSION_HOME}/GTsuite/bin/linux_x86_64/:${PATH}
export PATH=/opt/swift-bin/bin/:${PATH}
export PATH=/opt/swift-pw-bin/swift-svn/bin/:${PATH}
export PATH=/opt/bin/:${PATH}

pw_http="beta2.parallel.works"

sched_ip_ext=$(curl -s ifconfig.me) # FIXME: Get internal IP
sched_ip_int=$(hostname -I  | cut -d' ' -f1 | sed "s/ //g")

echo "Scheduler External IP:   ${sched_ip_ext}"
echo "Scheduler Internal IP:   ${sched_ip_int}"

ulimit -u

# Open tunnel to license server through beta:
# FIXME: wont work with triple license!
# export GTISOFT_LICENSE_FILE=${lic_port}:localhost
sudo sed -i "s|.*GatewayPorts.*|GatewayPorts yes|g" /etc/ssh/sshd_config
sudo service sshd restart
sleep 10

tunnel=$(curl -s "https://${pw_http}/api/account?key=${api_key}" | grep tunnel | sed "s/\"//g" | cut -d':' -f2-)
lic_hostname=$(echo ${tunnel} | cut -d',' -f2)
license_port=$(echo ${tunnel} | cut -d',' -f3)
vendor_port=$(echo ${tunnel} | cut -d',' -f4)

# Scheduler security group needs these ports open!
open_tunnel_cmd="setsid ssh -L 0.0.0.0:${license_port}:localhost:${license_port} localhost -fNT"
echo Tunneling port ${license_port}:
echo ${open_tunnel_cmd}
${open_tunnel_cmd}

open_tunnel_cmd="setsid ssh -L 0.0.0.0:${vendor_port}:localhost:${vendor_port} localhost -fNT"
echo Tunneling port ${vendor_port}:
echo ${open_tunnel_cmd}
${open_tunnel_cmd}

# Add lic server's hostname to loopback address
cat /etc/hosts > hosts_mod
echo "127.0.0.1 ${lic_hostname}" >> hosts_mod
sudo cp hosts_mod /etc/hosts
echo
echo "/etc/hosts"
cat /etc/hosts
echo

lic_server="${license_port}@${sched_ip_int}"
echo License server as seen from executors: ${lic_server}

# Directories / Files:
sched_work_dir=/var/opt/gtsuite/
exec_work_dir=/var/opt/gtsuite/

# Attach and mount disk
# - The ${sched_work_dir} directory should be empty before mounting the persistent disk
sudo rm -rf ${sched_work_dir}
sudo mkdir -p ${sched_work_dir}

# FORMAT THE DISK BEFORE FIRST USE!
dname=$(lsblk | tail -n1 | awk '{print $1}' | tr -cd '[:alnum:]._-')
if [[ ${cloud} == "GCP" ]]; then
    did=$(ls -1l /dev/disk/by-id/google-* | grep ${dname} | awk '{print $9}')
    sudo mount -o discard,defaults ${did} ${sched_work_dir}
elif [[ ${cloud} == "AWS" ]]; then
    # ONLY FIRST TIME!
    # sudo yum install xfsprogs
    # sudo mkfs -t xfs /dev/xvdf
    #dname=$(lsblk |  awk '$4 == "1G" {print $1}') # --> xvdf (if disk size is correct and unique)
    sudo mount /dev/${dname} ${sched_work_dir}
elif [[ ${cloud} == "Azure" ]]; then
    dname=$(lsblk -o NAME,HCTL,SIZE,MOUNTPOINT | grep -i "sd" | awk '{print $1}' | tail -n1 |  tr -cd '[:alnum:]._-')
    # ONLY FIRST TIME!
    # sudo parted /dev/${dname} --script mklabel gpt mkpart xfspart xfs 0% 100%
    # sudo mkfs.xfs /dev/${dname}1
    # sudo partprobe /dev/${dname}1
    sudo mount /dev/${dname} ${sched_work_dir}
fi


# Make sure user has permissions
sudo chown ${USER}: ${GTIHOME} -R
chmod u+w ${GTIHOME} -R
sudo chown ${USER}: ${sched_work_dir} -R
chmod u+w ${sched_work_dir} -R
mkdir -p ${sched_work_dir}/gtdistd ${sched_work_dir}/db ${sched_work_dir}/compounds

exec_prop_file=${sched_work_dir}/gtdistd/gtdistd-exec.properties
sched_prop_file=${sched_work_dir}/gtdistd/gtdistd-sched.properties

# Prepare executor properties file (except core-count and priority)
# cp ${GT_VERSION_HOME}/distributed/config-samples/gtdistd-exec.properties ${exec_prop_file}
cp ${pf_dir}/gtdistd-exec-${version}.properties ${exec_prop_file}
sed -i "s|^GTDistributed.work-dir.*|GTDistributed.work-dir = ${exec_work_dir}/gtdistd|g" ${exec_prop_file}
sed -i "s|^GTDistributed.license-file.*|GTDistributed.license-file = ${lic_server}|g" ${exec_prop_file}
sed -i "s|^GTDistributed.client.hostname.*|GTDistributed.client.hostname = ${sched_ip_int}|g" ${exec_prop_file}
sed -i 's/\r//' ${exec_prop_file}

# Prepare scheduler properties file
cp ${pf_dir}/gtdistd-sched-${version}.properties ${sched_prop_file}
sed -i "s|^GTDistributed.work-dir.*|GTDistributed.work-dir = ${sched_work_dir}/gtdistd|g" ${sched_prop_file}
if [[ ${sum_serv} == "True" ]]; then
    echo Activating summary service
    sed -i "s|GTDistributed.job-summary-service-enable.*|GTDistributed.job-summary-service-enable = true|g" ${sched_prop_file}
fi

# Start or restart gtdist daemon
date >> ${sched_work_dir}/dates.txt

# Start DB on node boot as USER
# VERSION=$(echo ${version} | sed "s/v//g")
# ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
# ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstop
# ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
# FIXME: Wont work after 2029
for gtv in $(ls -d ${GTIHOME}/v202*); do
    vn=$(basename ${gtv} | sed 's/v//g')
    echo "${GTIHOME}/bin/gtcollect -V ${vn} dbstart"
    ${GTIHOME}/bin/gtcollect -V ${vn} dbstart
done


# Make sure this user can write the gtdistd.out file
touch /tmp/gtdistd.out
chmod 777 /tmp/gtdistd.out

# START GTDIST DAEMON
# Get daemon version
vn=$(echo ${version} | sed 's/v//g')
if [ ${vn} -lt 2020 ]; then
    dversion=v2020
else
    dversion=${version}
fi

#$GTIHOME/v2020/distributed/bin/gtdistd.sh -c <config-file>
# USE LATEST VERSION!
configure_daemon_systemd() {
    local prop_file=$1
    # Following instructions in section 5b of /opt/gtsuite/v2020/distributed/bin/README_Linux.md
    sudo cp ${GTIHOME}/${dversion}/distributed/bin/systemd-unit-files/gtdistd.service /etc/systemd/system/
    sudo cp -r ${GTIHOME}/${dversion}/distributed/bin/systemd-unit-files/gtdistd.service.d /etc/systemd/system/
    conf_file=/etc/systemd/system/gtdistd.service.d/override.conf
    sudo sed -i "s|User=.*|User=${USER}|g" ${conf_file}
    sudo sed -i "s|Environment=GTIHOME=.*|Environment=GTIHOME=${GTIHOME}|g" ${conf_file}
    sudo sed -i "s|Environment=GT_VERSION_HOME=.*|Environment=GT_VERSION_HOME=${GT_VERSION_HOME}|g" ${conf_file}
    sudo sed -i "s|Environment=GT_CONF=.*|Environment=GT_CONF=${prop_file}|g" ${conf_file}
    # Environment=JRE_HOME=/opt/gtsuite/${dversion}/GTsuite/jre/linux_x86_64
    # Environment=JAVA_OPTS=
    # Environment=DAEMON_OUT=/tmp/gtdistd.out

    # Verify the syntax of the `override.conf` file contains no syntax errors. A correct file
    # will generate no output.
    sudo systemd-analyze verify /etc/systemd/system/gtdistd.service

    # Restart service:
    sudo systemctl start gtdistd.service
    sudo systemctl status gtdistd.service

    # Launch GUI Need X11 DISPLAY!
    # $GTIHOME/${dversion}/distributed/bin/gtdistdconfig.sh
}

configure_daemon_systemd ${sched_prop_file}

# Create input for main.py script
create_ms_input () {
    echo "webapp_xml=webapp.xml" > ${ms_input}
    echo "sched_work_dir=${sched_work_dir}" >> ${ms_input}
    echo "exec_work_dir=${exec_work_dir}" >> ${ms_input}
    echo "version=${version}" >> ${ms_input}
    echo "pool_names=${exec_pools}" >> ${ms_input}
    echo "pool_info_json=pools_info.json" >> ${ms_input}
    echo "gtdist_exec_pfile=${exec_prop_file}" >> ${ms_input}
    echo "log_dir=${log_dir}" >> ${ms_input}
    echo "od_frac=${od_frac}" >> ${ms_input}
    echo "cloud=${cloud}" >> ${ms_input}
    echo "api_key=${api_key}" >> ${ms_input}
    echo "sched_ip_int=${sched_ip_int}" >> ${ms_input}
    echo "lic_hostname=${lic_hostname}" >> ${ms_input}
}

ms_input=main_input.txt
while true; do
    sleep ${ds_cycle}
    secure_curl "curl -s https://${pw_http}/api/resources?key=${api_key}" pools_info.json
    secure_curl "curl -s http://${sched_ip_int}:8979/jobs/?xml" webapp.xml
    echo; date
    create_ms_input
    python3 ${apps_dir}/sched/main.py ${ms_input}
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
