#!/bin/bash
jobdir=$(dirname $0)
cd ${jobdir}

source inputs.sh


# Check if SSH access is available using the jumphost
ssh -q -o BatchMode=yes -J usercontainer ${resource_ssh_usercontainer_options} ${gt_license_user}@${gt_license_ip} exit

# Exit if SSH connection fails
if [ $? -ne 0 ]; then
    echo; echo
    echod "ERROR: Controller has no SSH access to the license server." 
    echod "       ssh -J usercontainer ${resource_ssh_usercontainer_options} ${gt_license_user}@${gt_license_ip}"
    exit 1
fi


# Create license tunnels
# FIXME: It assumes ~/.ssh/config is present and defines the usercontainer host!
#        Won't work in onprem resources!
ssh -J usercontainer ${resource_ssh_usercontainer_options} -fN \
    -L 0.0.0.0:${gt_license_port}:localhost:${gt_license_port} \
    -L 0.0.0.0:${gt_license_vendor_port}:localhost:${gt_license_vendor_port} \
    ${gt_license_user}@${gt_license_ip} </dev/null &>/dev/null &

echo; echo;
echo "Tunnel to license server"
netstat -tuln |  grep "${gt_license_port}\|${gt_license_vendor_port}"
echo; echo;

# Initialize cancel script
echo '#!/bin/bash' > cancel.sh
# Cancel all jobs in the SLURM queue
echo "scancel -u ${USER}" >> cancel.sh
# Kill the screen session
echo 'screen -X -S gt-scheduler quit' >> cancel.sh
chmod +x cancel.sh

# Start a detached screen session and run test.sh inside it
screen -dmS gt-scheduler bash -c "./scheduler.sh &> logs.out"

# Activate streaming
bash stream.sh &> stream.out &
stream_pid=$!
echo "kill ${stream_pid} 2>/dev/null" >> cancel.sh

# Kill tunnel processes 
echo "kill \$(ps -x | grep ssh | grep ${gt_license_port} | awk '{print \$1}')" >> cancel.sh
# Kill connections back to usercontainer
echo "kill \$(ps -x | grep ssh | grep usercontainer | awk '{print \$1}')" >> cancel.sh
# Kill logs
echo "kill \$(ps -x | grep logs.out | awk '{print \$1}')" >> cancel.sh