#!/bin/bash
​
# create a port mapping from the user node to the license server
# yum install autossh
# autossh -M 0 -f -N -R $REMOTE_MAPPED_PORT:localhost:$LISTENING_PORT $REMOTE_USER@$REMOTE_IP
​
# run this as root
​
LICENSE_USER=flexlm
LICENSE_PORT=27005
LICENSE_SERVER=35.224.78.64
​
#ssh -L $LICENSE_PORT:localhost:$LICENSE_PORT $LICENSE_USER@$LICENSE_SERVER -fNT
echo autossh -M 0 -f -N -L $LICENSE_PORT:localhost:$LICENSE_PORT $LICENSE_USER@$LICENSE_SERVER
autossh -M 0 -f -N -L $LICENSE_PORT:localhost:$LICENSE_PORT $LICENSE_USER@$LICENSE_SERVER