#!/bin/bash

source utils/workflow-libs.sh

# Processing resource inputs
source /etc/profile.d/parallelworks.sh
source /etc/profile.d/parallelworks-env.sh
source /pw/.miniconda3/etc/profile.d/conda.sh
conda activate

if [ -f "/swift-pw-bin/utils/input_form_resource_wrapper.py" ]; then
    version=$(cat /swift-pw-bin/utils/input_form_resource_wrapper.py | grep VERSION | cut -d':' -f2)
    if [ -z "$version" ] || [ "$version" -lt 15 ]; then
        python utils/input_form_resource_wrapper.py
    else
        python /swift-pw-bin/utils/input_form_resource_wrapper.py
    fi
else
    python utils/input_form_resource_wrapper.py
fi

if ! [ -f "resources/host/inputs.sh" ]; then
    displayErrorMessage "ERROR - Missing file ./resources/host/inputs.sh. Resource wrapper failed"
fi

source resources/host/inputs.sh


cluster_rsync_exec

echo "Start Scheduler Submitted"


while true; do
    # Check if the screen session exists on the remote host
    if ssh "${resource_publicIp}" screen -list | grep gt-scheduler; then
        echo "$(date) gt-scheduler session is running on ${resource_publicIp}" >> screen-session.log 2>&1
    else
        echo "$(date) gt-scheduler session is not running on ${resource_publicIp}" >> screen-session.log 2>&1
        break
    fi
    sleep 60
done


bash cancel.sh

