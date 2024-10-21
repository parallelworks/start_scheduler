#!/bin/bash
tunnel_script=$1

source resources/host/inputs.sh

echo '#!/bin/bash' > ${tunnel_script}
chmod +x ${tunnel_script}
cat resources/host/inputs.sh >> ${tunnel_script}
cat >> ${tunnel_script} <<HERE
sudo dnf install autossh -y

# Check if SSH access is available using the jumphost
ssh -q -o BatchMode=yes -J usercontainer ${resource_ssh_usercontainer_options} ${gt_license_user}@${gt_license_ip} exit

# Exit if SSH connection fails
if [ \$? -ne 0 ]; then
    echo; echo
    echo "ERROR: Controller has no SSH access to the license server." 
    echo "       ssh -J usercontainer ${resource_ssh_usercontainer_options} ${gt_license_user}@${gt_license_ip}"
    exit 1
fi

echo "Creating tunnel with autossh"
ssh -J usercontainer \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=5 \
    -o ConnectTimeout=10 \
    -o ExitOnForwardFailure=yes \
    -o TCPKeepAlive=yes \
    -o ConnectionAttempts=5 \
    -fN \
    -L 0.0.0.0:${gt_license_port}:localhost:${gt_license_port} \
    -L 0.0.0.0:${gt_license_vendor_port}:localhost:${gt_license_vendor_port} \
    ${gt_license_user}@${gt_license_ip} </dev/null &>/dev/null &

sleep 5

echo
echo "License server ports"
netstat -tuln |  grep "${gt_license_port}\|${gt_license_vendor_port}"

HERE