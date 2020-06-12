#!/bin/bash

GT_USER=$1
sched_ip=$2

exec_work_dir=/var/opt/gtsuite/gtdistd
chmod 777 ${exec_work_dir} -R
GTIHOME=/home/GTI
GT_VERSION_HOME=${GTIHOME}/v2019
GT_CONF=${exec_work_dir}/gtdistd-exec.properties
webapp_xml=${exec_work_dir}/webapp.xml
log_file=/tmp/wti.out
gtdistd=/etc/init.d/gtdistd

# Check if properties file already exists and copy it if not present
if ! [ -f "${GT_CONF}" ]; then
    echo Copying file /tmp/gtdistd-exec.properties to ${GT_CONF} >> ${log_file}
    cp /tmp/gtdistd-exec.properties ${GT_CONF}
fi

# Check if gtdistd daemon file already exists and make it if not present
if ! [ -f "${gtdistd}" ]; then
    echo "Copying file ${GTIHOME}/v2019/distributed/bin/gtdistd-init.d to ${gtdistd}" >> ${log_file}
    cp ${GTIHOME}/v2019/distributed/bin/gtdistd-init.d ${gtdistd}
    echo Editing ${gtdistd} with:
    echo GT_USER=${GT_USER} >> ${log_file}
    echo GT_CONF=${GT_CONF} >> ${log_file}
    echo GT_VERSION_HOME=${GT_VERSION_HOME} >> ${log_file}
    sed -i "s|^GT_VERSION_HOME.*|GT_VERSION_HOME=${GT_VERSION_HOME}|g" ${gtdistd}
    sed -i "s|^GT_USER.*|GT_USER=${GT_USER}|g" ${gtdistd}
    sed -i "s|^GT_CONF.*|GT_CONF=${GT_CONF}|g" ${gtdistd}
    sed -i 's/\r//' ${gtdistd}
fi

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

# Watcher period: Watcher checks for sim files every wp seconds
wp=60

# FIXME: Cannot use Python script to read it because it has wrong format and says unauthorized
#        Using grep instead...
while true; do
    sleep ${wp}
    curl http://${sched_ip}:8979/jobs/?xml > ${webapp_xml}_tmp ${HOSTNAME} && mv ${webapp_xml}_tmp ${webapp_xml}
    date >> ${log_file}
    executors=$(cat ${webapp_xml} | tr " " "\n" | grep hostname | cut -d'=' -f2 | sed "s/\"//g")
    for executor in ${executors}; do
        if [[ ${executor} == ${HOSTNAME}* ]]; then
            echo ${HOSTNAME} is active >> ${log_file}
        else
            echo ${HOSTNAME} is not active. Exiting >> ${log_file}
            exit 0
        fi
    done
done
