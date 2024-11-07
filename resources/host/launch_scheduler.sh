#!/bin/bash
jobdir=$(dirname $0)
cd ${jobdir}

source inputs.sh

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