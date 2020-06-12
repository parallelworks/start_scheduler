#!/bin/bash

GT_USER=$1

exec_work_dir=/var/opt/gtsuite/gtdistd
chmod 777 ${exec_work_dir} -R
GTIHOME=/home/GTI
GT_VERSION_HOME=${GTIHOME}/v2019
GT_CONF=${exec_work_dir}/gtdistd-exec.properties
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

# Wait for the sim file to appear (sim_found) and for ALL sim files to disappear
# before exiting the cog-job-submit
sim_found=false # True when a sim file is found
# Watcher period: Watcher checks for sim files every wp seconds
wp=10
# Timeout period: cog-job will exit even if no sim file was found after tp seconds
tp=60
accu=0
while true; do
    sleep ${wp}
    accu=$((accu + wp))
    sim_counter=$(find ${exec_work_dir} -name **.sim | wc -l)
    date >> ${log_file}
    echo Running simulations: ${sim_counter} >> ${log_file}
    if [ ${sim_counter} -eq 0 ]; then
        if ${sim_found}; then
	    ${gtdistd} stop
            exit 0
        fi
    else
        sim_found=true
        echo Simulation found >> ${log_file}
    fi
    if ! ${sim_found} && [ ${accu} -gt ${tp} ]; then
        echo "No simulation was found after ${accu}>${wp} seconds" >> ${log_file}
        exit 0
    fi
done
