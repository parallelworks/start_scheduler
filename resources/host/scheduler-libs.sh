
echod() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}


curl_wrapper () {
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


# Function to check partition names
check_partition_names() {
    # Get partition information using sinfo and filter out the header
    partition_info=$(sinfo -h -o "%P")

    # Flag to indicate if any partition name has more than 8 characters
    error_found=0

    # Loop through each partition name
    while read -r partition_name; do
        # Check if the length of the partition name is greater than 8 characters
        if [ ${#partition_name} -gt 8 ]; then
            echo "Partition name '$partition_name' has more than 8 characters."
            error_found=1
        fi
    done <<< "$partition_info"

    # Exit with status code 1 if an error was found
    if [ $error_found -eq 1 ]; then
        echo "Partition names cannot have more than 8 characters! Exiting job..."
        exit 1
    fi
}

list_sorted_partitions() {
    sinfo --noheader --format="%P"  | sed 's/*//g' > partitions.list
    rm -f partitions_with_cores.list
    while IFS= read -r partition; do
        # Number of cores in the partition
        local pcores=$(sinfo  --noheader -p ${partition} -o "%.8c" | tr -d ' ')
        echo "${partition} ${pcores}" >>  partitions_with_cores.list
    done < partitions.list
    sort -k2 -r -n partitions_with_cores.list | awk '{print $1}' > partitions.list
}

get_core_supply() {
    CORE_SUPPLY=0   
    while IFS= read -r partition; do
        # Number of cores in the partition
        local pcores=$(sinfo  --noheader -p ${partition} -o "%.8c" | tr -d ' ')
        # Number of jobs running in this partition
        local pjobs=$(squeue --long | grep "\b${partition}\b" | wc -l)
        export CORE_SUPPLY=$((CORE_SUPPLY+pcores*pjobs))
    done < partitions.list
}

submit_executor_job() {
    local partition=$1
    local job_name=$2
    local pcores=$3
    local exec_prop_file_template=${PWD}/properties_files/gtdistd-exec-${gt_version}.properties

    local slurm_job_dir="${PWD}/slurm-jobs/$(date +%Y-%m-%d)"
    mkdir -p ${slurm_job_dir}
    
    # Create SLURM script from executor
    sed -e "s|__PARTITION__|${partition}|g" \
        -e "s|__JOB_NAME__|${job_name}|g" \
        -e "s|__SLURM_JOB_DIR__|${slurm_job_dir}|g" \
        -e "s|__CORES_PER_NODE__|${pcores}|g" \
        -e "s|__RESOURCE_TYPE__|${resource_type}|g" \
        -e "s|__GT_VERSION__|${gt_version}|g" \
        -e "s|__SCHEDULER_INTERNAL_IP__|${resource_privateIp}|g" \
        -e "s|__LICENSE_HOSTNAME__|${gt_license_hostname}|g" \
        -e "s|__EXEC_PROP_FILE_TEMPLATE__|${exec_prop_file_template}|g" \
        "${APP_DIR}/executor-template.sh" > "${slurm_job_dir}/${job_name}.sh"

    # Submit job to queue
    jobid=$(sbatch ${slurm_job_dir}/${job_name}.sh | tail -1 | awk -F ' ' '{print $4}')
}


satisfy_core_overdemand() {
    core_overdemand=$1

    if [ "${core_overdemand}" -le 0 ]; then
        return
    fi

    # Minimize number of nodes by submitting jobs from large to small
    while IFS= read -r partition; do
        # Number of cores in the partition
        local pcores=$(sinfo  --noheader -p ${partition} -o "%.8c" | tr -d ' ')
        # Maximum number of nodes in the partition
        local max_nodes=$(sinfo  --noheader -p ${partition} -o "%D" | tr -d ' ')
        # Number of jobs running in this partition
        # - Jobs always request 1 node!
        local pjobs=$(squeue --long | grep "\b${partition}\b" | wc -l)
        # Available number of nodes in the partition 
        local available_nodes=$((max_nodes-pjobs))
        # Partition nodes needed to satisfy the overdemand
        local needed_nodes=$((core_overdemand/pcores))
        # Do not submit more jobs than available nodes
        if [ "${available_nodes}" -lt "${needed_nodes}" ]; then
            local njobs="${available_nodes}"
        else
            local njobs="${needed_nodes}"
        fi
        
        # Submit as many jobs as needed nodes. Each job requests 1 node!
        for i in $(seq 1 "${njobs}"); do
            job_name="${SECONDS}-${partition}-${i}"
            echod "Submitting job ${job_name} to partition ${partition} with ${pcores} cores"
            submit_executor_job ${partition} ${job_name}
            core_overdemand=$((core_overdemand-pcores))
        done
        sleep 1
    done < partitions.list
    
    if [ "$core_overdemand" -le 0 ]; then
        return
    fi

    # Distribute remaining packets to the single smallest possible node
    tac partitions.list | while IFS= read -r partition; do
        # Maximum number of nodes in the partition
        local max_nodes=$(sinfo  --noheader -p ${partition} -o "%D" | tr -d ' ')
        # Number of jobs running in this partition
        # - Jobs always request 1 node!
        local pjobs=$(squeue --long | grep "\b${partition}\b" | wc -l)
        # Do not submit additional jobs to this partition if the maximum number of running nodes is reached
        if [ "${pjobs}" -lt "${max_nodes}" ]; then
            job_name="${SECONDS}-${partition}-remainder"
            echod "Submitting job ${job_name} to partition ${partition} with ${pcores} cores"
            submit_executor_job ${partition} ${job_name}
            core_overdemand=$((core_overdemand-pcores))
            break
        fi
    done
}


start_gt_db() {
    # Start DB on node boot as USER
    # VERSION=$(echo ${gt_version} | sed "s/v//g")
    # ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
    # ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstop
    # ${GTIHOME}/bin/gtcollect -V ${VERSION} dbstart
    # FIXME: Wont work after 2029
    for gtv in $(ls -d ${GTIHOME}/v202*); do
        vn=$(basename ${gtv} | sed 's/v//g')
        echo "${GTIHOME}/bin/gtcollect -V ${vn} dbstart"
        ${GTIHOME}/bin/gtcollect -V ${vn} dbstart
    done
}

#$GTIHOME/v2020/distributed/bin/gtdistd.sh -c <config-file>
# USE LATEST VERSION!
configure_daemon_systemd() {
    local prop_file=$1

    # Make sure this user can write the gtdistd.out file
    touch /tmp/gtdistd.out
    chmod 777 /tmp/gtdistd.out

    # Get daemon version
    vn=$(echo ${gt_version} | sed 's/v//g')
    if [ ${vn} -lt 2020 ]; then
        dversion=v2020
    else
        dversion=${gt_version}
    fi

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
    sudo systemctl daemon-reload

    # Restart service:
    sudo systemctl start gtdistd.service
    sudo systemctl status gtdistd.service

    # Launch GUI Need X11 DISPLAY!
    # $GTIHOME/${dversion}/distributed/bin/gtdistdconfig.sh
}

write_balance() {
    ssh ${resource_ssh_usercontainer_options} usercontainer ${pw_job_dir}/utils/get_balance.py > balance.json
    
    ssh_exit_code=$?
    if [ $ssh_exit_code -ne 0 ]; then
        echod "ERROR: Could not obtain balance with command:"
        echod "ssh ${resource_ssh_usercontainer_options} usercontainer ${pw_job_dir}/utils/get_balance.py"
        echod "Exiting workflow"
        exit 1
    fi

    if [ ! -s "balance.json" ]; then
        echod "Error: File balance.json is missing or empty."
        exit 1
    fi
}