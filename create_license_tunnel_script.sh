#!/bin/bash
tunnel_script=$1

rm -f ${HOME}/.ssh/config
cat >> ${HOME}/.ssh/config <<HERE
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
Host usercontainer
    IdentityFile /home/${PW_USER}/.ssh/pw_id_rsa
    HostName localhost
    User ${PW_USER}
    Port 2222
HERE

source resources/host/inputs.sh

echo '#!/bin/bash' > ${tunnel_script}
chmod +x ${tunnel_script}
cat resources/host/inputs.sh >> ${tunnel_script}
cat >> ${tunnel_script} <<HERE

# Check if SSH access is available using the jumphost, retrying to
# ride out transient connection drops on the license server
access_ok=false
for attempt in 1 2 3 4 5; do
    if ssh -q -o BatchMode=yes -o ConnectTimeout=10 -J usercontainer ${resource_ssh_usercontainer_options} ${gt_license_user}@${gt_license_ip} exit; then
        access_ok=true
        break
    fi
    echo "WARNING: No SSH access to the license server yet (attempt \${attempt}/5). Retrying in 30s..."
    sleep 30
done

# Exit if SSH connection fails
if [ "\${access_ok}" != "true" ]; then
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