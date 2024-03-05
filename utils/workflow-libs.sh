#!/bin/bash

# These are utility bash functions intended to make workflow building easier. They can
# be imported by any bash workflow using source /swift-pw-bin/utils/workflow-libs.sh
# All these functions run as part of the workflow inside the user workspace.


cluster_rsync_exec() {
    # DESCRIPTION:
    # 1. Looks for every script named cluster_rsync_exec.sh under the ./resources directory
    # 1. Copies the ./resources/<resource-label>/ directory to the job directory in the remote resource
    # 2. Executes the script ./resources/<resource-label>/cluster_rsync_exec.sh in the remote resource
    # PREREQUISITES:
    # Run python3 /swift-pw-bin/utils/input_form_resource_wrapper.py before this function
    for path_to_rsync_exec_sh in $(find resources -name cluster_rsync_exec.sh); do
        chmod +x ${path_to_rsync_exec_sh}
        resource_dir=$(dirname ${path_to_rsync_exec_sh})
        resource_label=$(basename ${resource_dir})

        # Load resource inputs
        echo "export PW_RESOURCE_DIR=${PWD}/${resource_dir}" >> ${resource_dir}/inputs.sh
        source ${resource_dir}/inputs.sh

        echo; echo "Running ${path_to_rsync_exec_sh} in ${resource_publicIp}"

        # Copy the file containing this function to the resource directory
        cp ${BASH_SOURCE[0]} ${resource_dir}
        
        # Rsync resource directory in user space to job directory in the resource
        origin=${resource_dir}/
        destination=${resource_publicIp}:${resource_jobdir}/${resource_label}/
        echo "rsync -avzq --rsync-path="mkdir -p ${resource_jobdir} && rsync " ${origin} ${destination}"
        rsync -avzq --rsync-path="mkdir -p ${resource_jobdir} && rsync " ${origin} ${destination}

        # Execute the script
        echo "ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/cluster_rsync_exec.sh"
        ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/cluster_rsync_exec.sh
    done
}

cancel_jobs_by_name() {
    # Cancels the jobs submitted by the cluster_rsync_exec function using the job's name
    for resource_inputs_sh in $(find resources -name inputs.sh); do
        resource_dir=$(dirname ${resource_inputs_sh})
        resource_label=$(basename ${resource_dir})

        source ${resource_inputs_sh}
        
        if [ "${jobschedulertype}" != "PBS" ] && [ "${jobschedulertype}" != "SLURM" ]; then
            continue
        fi

        echo; echo "Canceling jobs in ${resource_name} - ${resource_publicIp}"

        # Prepare cancel script
        if [[ ${jobschedulertype} == "SLURM" ]]; then
            # FIXME: Add job_name to input_form_resource_wrapper
            job_name=$(cat ${resource_dir}/batch_header.sh | grep -e '--job-name' | cut -d'=' -f2)
            job_ids=$(ssh -o StrictHostKeyChecking=no ${resource_publicIp} squeue -h -o "%i" -n ${job_name})
            if [ -z "${job_ids}" ]; then
                echo "No jobs found in ${resource_name} - ${resource_publicIp}"
                continue
            fi
        elif [[ ${jobschedulertype} == "PBS" ]]; then
            # FIXME: Add job_name to input_form_resource_wrapper
            job_name=$(cat ${resource_dir}/batch_header.sh | grep -e '#PBS -N' | cut -d'=' -f2)
            job_ids=$(ssh -o StrictHostKeyChecking=no ${resource_publicIp} qselect -N ${job_name})
            if [ -z "${job_ids}" ]; then
                echo "No jobs found in ${resource_name} - ${resource_publicIp}"
                continue
            fi
        fi

        echo "${cancel_cmd} ${job_ids}" | tr '\n' ' ' >> ${resource_dir}/cancel_job.sh
        echo "${resource_dir}/cancel_job.sh:"
        cat ${resource_dir}/cancel_job.sh
        
        # Run cancel script
        echo "ssh -o StrictHostKeyChecking=no ${resource_publicIp} 'bash -s' < ${resource_dir}/cancel_job.sh"
        ssh -o StrictHostKeyChecking=no ${resource_publicIp} 'bash -s' < ${resource_dir}/cancel_job.sh

    done

}

cancel_jobs_by_script() {
    # Runs every cancel.sh script located on the remote resource directory
    for resource_inputs_sh in $(find resources -name inputs.sh); do
        resource_dir=$(dirname ${resource_inputs_sh})
        resource_label=$(basename ${resource_dir})

        source ${resource_inputs_sh}

        cancel_script="${resource_jobdir}/${resource_label}/cancel.sh"
        cancel_script_exists=$(ssh ${resource_publicIp} "[ -f \"${cancel_script}\" ]" && echo "True" || echo "False")

        if [[ ${cancel_script_exists} == "True" ]]; then
            echo; echo "Running Canceling script ${cancel_script} in ${resource_name} - ${resource_publicIp}"
            ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${cancel_script}
        fi
    done

}

get_slurm_job_status() {
    # Get the header line to determine the column index corresponding to the job status
    if [ -z "${SQUEUE_HEADER}" ]; then
        export SQUEUE_HEADER="$(eval "$sshcmd ${status_cmd}" | awk 'NR==1')"
    fi
    status_column=$(echo "${SQUEUE_HEADER}" | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^S/) { print i; exit } }')
    status_response=$(eval $sshcmd ${status_cmd} | grep "\<${jobid}\>")
    echo "${SQUEUE_HEADER}"
    echo "${status_response}"
    export job_status=$(echo ${status_response} | awk -v id="${jobid}" -v col="$status_column" '{print $col}')
}

get_pbs_job_status() {
    # Get the header line to determine the column index corresponding to the job status
    if [ -z "${QSTAT_HEADER}" ]; then
        export QSTAT_HEADER="$(eval "$sshcmd ${status_cmd}" | awk 'NR==1')"
    fi
    status_response=$(eval $sshcmd ${status_cmd} 2>/dev/null | grep "\<${jobid}\>")
    echo "${QSTAT_HEADER}"
    echo "${status_response}"
    export job_status="$(eval $sshcmd ${status_cmd} -f ${jobid} 2>/dev/null  | grep job_state | cut -d'=' -f2 | tr -d ' ')"

}

wait_job() {
    while true; do
        sleep 15
        # squeue won't give you status of jobs that are not running or waiting to run
        # qstat returns the status of all recent jobs
        if [[ ${jobschedulertype} == "SLURM" ]]; then
            get_slurm_job_status
            # If job status is empty job is no longer running
            if [ -z "${job_status}" ]; then
                job_status=$($sshcmd sacct -j ${jobid}  --format=state | tail -n1)
                break
            fi
        elif [[ ${jobschedulertype} == "PBS" ]]; then
            get_pbs_job_status
            if [[ "${job_status}" == "C" ]]; then
                break
            elif [ -z "${job_status}" ]; then
                break
            fi
        fi
    done
}

install_miniconda() {
    install_dir=$1
    echo "Installing Miniconda3-py39_4.9.2"
    conda_repo="https://repo.anaconda.com/miniconda/Miniconda3-py39_4.9.2-Linux-x86_64.sh"
    ID=$(date +%s)-${RANDOM} # This script may run at the same time!
    nohup wget ${conda_repo} -O /tmp/miniconda-${ID}.sh 2>&1 > /tmp/miniconda_wget-${ID}.out
    rm -rf ${install_dir}
    mkdir -p $(dirname ${install_dir})
    nohup bash /tmp/miniconda-${ID}.sh -b -p ${install_dir} 2>&1 > /tmp/miniconda_sh-${ID}.out
}

create_conda_env_from_yaml() {
    CONDA_DIR=$1
    CONDA_ENV=$2
    CONDA_YAML=$3
    CONDA_SH="${CONDA_DIR}/etc/profile.d/conda.sh"
    # conda env export
    # Remove line starting with name, prefix and remove empty lines
    sed -i -e 's/name.*$//' -e 's/prefix.*$//' -e '/^$/d' ${CONDA_YAML}    
    
    if [ ! -d "${CONDA_DIR}" ]; then
        echo "Conda directory <${CONDA_DIR}> not found. Installing conda..."
        install_miniconda ${CONDA_DIR}
    fi
    
    echo "Sourcing Conda SH <${CONDA_SH}>"
    source ${CONDA_SH}
    echo "Activating Conda Environment <${CONDA_ENV}>"
    {
        conda activate ${CONDA_ENV}
    } || {
        echo "Conda environment <${CONDA_ENV}> not found. Installing conda environment from YAML file <${CONDA_YAML}>"
        conda env update -n ${CONDA_ENV} -q -f ${CONDA_YAML} #--prune
        {
            echo "Activating Conda Environment <${CONDA_ENV}> again"
            conda activate ${CONDA_ENV}
        } || {
            echo "ERROR: Conda environment <${CONDA_ENV}> not found. Exiting workflow"
            exit 1
        }
    }
}

findAvailablePort() {
    # Find an available availablePort
    minPort=6000
    maxPort=9000
    for port in $(seq ${minPort} ${maxPort} | shuf); do
        out=$(netstat -aln | grep LISTEN | grep ${port})
        if [ -z "${out}" ]; then
            # To prevent multiple users from using the same available port --> Write file to reserve it
            portFile=/tmp/${port}.port.used
            if ! [ -f "${portFile}" ]; then
                touch ${portFile}
                availablePort=${port}
                echo ${port}
                break
            fi
        fi
    done
}