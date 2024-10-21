#!/bin/bash
source inputs.sh
ssh-keygen -R ${pwrl_host_resource_publicIp}

if [ -z "${workflow_utils_branch}" ]; then
    # If empty, clone the main default branch
    git clone https://github.com/parallelworks/workflow-utils.git
else
    # If not empty, clone the specified branch
    git clone -b "$workflow_utils_branch" https://github.com/parallelworks/workflow-utils.git
fi

mv workflow-utils/* utils/
rm -rf workflow-utils

source utils/workflow-libs.sh

# Processing resource inputs
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh
source /pw/.miniconda3/etc/profile.d/conda.sh
conda activate

python utils/input_form_resource_wrapper.py

if ! [ -f "resources/host/inputs.sh" ]; then
    displayErrorMessage "ERROR - Missing file ./resources/host/inputs.sh. Resource wrapper failed"
fi

source resources/host/inputs.sh

# Create script to estblish tunnel form the controller node to the license server
bash create_license_tunnel_script.sh "resources/host/license_tunnel.sh"

# Create remote job directory
cluster_rsync

# Create license tunnel
echo; echo
# Need to forward agent to access license server from controller
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/pw_id_rsa
echo "ssh -A -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh"
ssh -A -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh
return_code=$?
if [ ${return_code} -ne 0 ]; then
    bash cancel.sh
    exit 1
fi

# Launch scheduler
echo; echo
echo "ssh -A -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/launch_scheduler.sh"
ssh -A -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/launch_scheduler.sh

echo "Start Scheduler Submitted"

# Preparing service.json to connect to webapp
#sed -i "s|.*PORT.*|    \"PORT\": \"${resource_ports}\",|" service.json


while true; do
    # Check if either of the ports are open and listening
    # Check if both ports are open and listening
    if ! ssh -o StrictHostKeyChecking=no ${resource_publicIp} "netstat -tuln | grep -q ${gt_license_port} && netstat -tuln | grep -q ${gt_license_vendor_port}"; then
        # Print a message if one or both ports are not listening
        echo "SSH tunnel is not fully established on remote host. One or both of the ports ${gt_license_port} or ${gt_license_vendor_port} are not listening."
        ssh -A -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh
    fi
    
    # Check if the screen session exists on the remote host
    if ssh "${resource_publicIp}" screen -list | grep gt-scheduler > /dev/null 2>&1; then
        echo "$(date) gt-scheduler session is running on ${resource_publicIp}" >> screen-session.log 2>&1
    else
        echo "$(date) gt-scheduler session is not running on ${resource_publicIp}" >> screen-session.log 2>&1
        break
    fi
    sleep 60
done


bash cancel.sh

