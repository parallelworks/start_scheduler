#!/bin/bash
export GTI_DB_CREATION_OPT=1
echo "INPUTS:"
echo $@

version=$1
GT_USER=$2
sched_ip=$3
cpe=$4 # Cores per executor
priority=$5 # Executor priority

exec_work_dir=/var/opt/gtsuite
exec_prop_file=${exec_work_dir}/gtdistd/gtdistd-exec.properties
GTIHOME=/opt/gtsuite
GT_VERSION_HOME=${GTIHOME}/${version}

# Directories / Files:
mkdir -p ${exec_work_dir}/gtdistd ${exec_work_dir}/db ${exec_work_dir}/compounds

# Start or restart gtdist daemon
# Make sure user home exists:
if ! [ -d /home/${GT_USER} ]; then
    echo "Creating user account for user: ${GT_USER}"
    adduser ${GT_USER}
fi


# Make sure user has permissions
sudo chown ${GT_USER}: ${GTIHOME} -R
chmod u+w ${GTIHOME} -R
sudo chown ${GT_USER}: ${exec_work_dir} -R
chmod u+w ${exec_work_dir} -R

# Start DB on node boot: Neehar: "Do not use the ds"
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstop
#${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
${GTIHOME}/bin/gtcollect dbstart

# Make sure this user can write the gtdistd.out file
touch /tmp/gtdistd.out
chmod 777 /tmp/gtdistd.out

echo Copying file /tmp/gtdistd-exec.properties to ${exec_prop_file}
cp /tmp/gtdistd-exec.properties ${exec_prop_file}
sed -i "s|.*GTDistributed.executor.core-count.*|GTDistributed.executor.core-count = ${cpe}|g" ${exec_prop_file}
sed -i "s|.*GTDistributed.executor.priority.*|GTDistributed.executor.priority = ${priority}|g" ${exec_prop_file}

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

configure_daemon_systemd ${exec_prop_file}


# Wait for the sim file to appear (sim_found) and for ALL sim files to disappear
# before exiting the cog-job-submit
# FIXME: Some jobs are so fast that we never catch the .sim files
# FIXME: If min slider = 1 and no inputs wti is going to shut down and boot repeatedly every 5 min
sim_found=false # True when a sim file is found
# Watcher period: Watcher checks for sim files every wp seconds
wp=10
# Timeout period: cog-job will exit even if no sim file was found after tp seconds
tp=300
accu=0
while true; do
    sleep ${wp}
    accu=$((accu + wp))
    date
    sim_counter=$(find ${exec_work_dir}/gtdistd -name **.sim | wc -l)
    echo Running simulations: ${sim_counter}
    if [ ${sim_counter} -eq 0 ]; then
        echo "No ongoing simulation was found"
        if ${sim_found}; then # There was a simulation
            echo "All simulation were completed"
            # Will exit after sim was not found 3 times
            exit_counter=$((exit_counter + 1))
            echo "Exit counter: ${exit_counter}"
            if [ ${exit_counter} -gt 3 ]; then
                sudo systemctl stop gtdistd.service
                exit 0
            fi
        fi
    else
        sim_found=true
        exit_counter=0
        echo "Ongoing simulations: ${sim_counter}"
    fi
    if ! ${sim_found} && [ ${accu} -gt ${tp} ]; then
        echo "Exiting. No simulation was found after ${accu}>${tp} seconds"
        sudo systemctl stop gtdistd.service
        exit 0
    fi
done

sudo systemctl stop gtdistd.service