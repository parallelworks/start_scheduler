#!/bin/bash

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
#export sshcmd="ssh -A -o StrictHostKeyChecking=no ${resource_publicIp}"

cluster_rsync_exec

echo "Start Scheduler Submitted"

# Preparing service.json to connect to webapp
#sed -i "s|.*PORT.*|    \"PORT\": \"${resource_ports}\",|" service.json


while true; do
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

