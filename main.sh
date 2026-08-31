#!/bin/bash
source inputs.sh
ssh-keygen -R ${pwrl_host_resource_ip}


if [ -z "${workflow_utils_branch}" ]; then
    # If empty, clone the main default branch
    git clone https://github.com/parallelworks/workflow-utils.git
else
    # If not empty, clone the specified branch
    git clone -b "$workflow_utils_branch" https://github.com/parallelworks/workflow-utils.git
fi

rm workflow-utils/stream.sh
# -n so the workflow-utils copies do not overwrite this repo's own utils (e.g. get_node_info.py)
mv -n workflow-utils/* utils/
rm -rf workflow-utils

source utils/workflow-libs.sh

# workflow-utils does not always define displayErrorMessage
if ! declare -F displayErrorMessage >/dev/null; then
    displayErrorMessage() {
        echo "$(date) $1" >&2
        exit 1
    }
fi

# Processing resource inputs
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh

python3 utils/input_form_resource_wrapper.py

if ! [ -f "resources/host/inputs.sh" ]; then
    displayErrorMessage "ERROR - Missing file ./resources/host/inputs.sh. Resource wrapper failed"
fi

source resources/host/inputs.sh

# Create script to estblish tunnel form the controller node to the license server
bash create_license_tunnel_script.sh "resources/host/license_tunnel.sh"

# Create remote job directory
cluster_rsync

# On the first run after the cluster starts, the resource wrapper may not have written
# the usercontainer jumphost entry to the controller's ~/.ssh/config yet, and
# license_tunnel.sh fails with "Could not resolve hostname usercontainer" without it
if ! ssh -o StrictHostKeyChecking=no ${resource_publicIp} "grep -q 'Host usercontainer' ~/.ssh/config 2>/dev/null"; then
    echo "Adding usercontainer jumphost entry to the controller's ~/.ssh/config"
    scp -o StrictHostKeyChecking=no ${HOME}/.ssh/config ${resource_publicIp}:.ssh/config
fi

# Wait until the ssh_auth job has installed the controller's public key on the license
# server; if ssh_auth fails, this job is early-cancelled, so the timeout is a backstop
wait_time=0
while ! [ -f ssh_auth_key_installed ]; do
    if [ ${wait_time} -ge 600 ]; then
        displayErrorMessage "ERROR - Timed out waiting for the ssh_auth job to install the public key on the license server"
    fi
    echo "$(date) Waiting for the ssh_auth job to install the public key on the license server..."
    sleep 10
    wait_time=$((wait_time + 10))
done

# Create license tunnel
echo; echo
# Need to forward agent to access license server from controller
# Retried because the controller's sshd fetches authorized keys from the platform API,
# which can fail transiently (AuthorizedKeysCommand failed -> Permission denied)
echo "ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh"
return_code=1
for attempt in 1 2 3 4 5; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh
    return_code=$?
    if [ ${return_code} -eq 0 ]; then
        break
    fi
    echo "$(date) WARNING: license_tunnel.sh failed with code ${return_code} (attempt ${attempt}/5). Retrying in 30s..."
    sleep 30
done
if [ ${return_code} -ne 0 ]; then
    bash cancel.sh
    exit 1
fi

# Launch scheduler
echo; echo
echo "ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/launch_scheduler.sh"
return_code=1
for attempt in 1 2 3 4 5; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${resource_publicIp} ${resource_jobdir}/${resource_label}/launch_scheduler.sh
    return_code=$?
    if [ ${return_code} -eq 0 ]; then
        break
    fi
    echo "$(date) WARNING: launch_scheduler.sh failed with code ${return_code} (attempt ${attempt}/5). Retrying in 30s..."
    sleep 30
done
if [ ${return_code} -ne 0 ]; then
    bash cancel.sh
    exit 1
fi

echo "Start Scheduler Submitted"

# Preparing service.json to connect to webapp
#sed -i "s|.*PORT.*|    \"PORT\": \"${resource_ports}\",|" service.json

# Initialize retry counter
retry_count=0
max_retries=5
while true; do
    # Check if either of the ports are open and listening
    # Check if both ports are open and listening
    if ! ssh -o StrictHostKeyChecking=no ${resource_publicIp} "netstat -tuln | grep -q ${gt_license_port} && netstat -tuln | grep -q ${gt_license_vendor_port}"; then
        # Print a message if one or both ports are not listening
        echo "SSH tunnel is not fully established on remote host. One or both of the ports ${gt_license_port} or ${gt_license_vendor_port} are not listening."
        ssh -o StrictHostKeyChecking=no ${resource_publicIp} ${resource_jobdir}/${resource_label}/license_tunnel.sh
    fi
    
    # Check if the screen session exists on the remote host
    if ssh "${resource_publicIp}" screen -list | grep gt-scheduler > /dev/null 2>&1; then
        echo "$(date) gt-scheduler session is running on ${resource_publicIp}" >> screen-session.log 2>&1
        retry_count=0
    else
        echo "$(date) gt-scheduler session is not running on ${resource_publicIp}" 2>&1 | tee -a screen-session.log
        retry_count=$((retry_count + 1))
    fi

    # Exit after 5 retries
    if [ "$retry_count" -ge "$max_retries" ]; then
        echo "$(date) Maximum retries reached, exiting." 2>&1 | tee -a screen-session.log
        break
    fi

    sleep 90
done


bash cancel.sh

