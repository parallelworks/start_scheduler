## Start Scheduler
The start scheduler workflow creates a Google VM that acts as a GT scheduler. The workflow is associated to a single worker pool with a static IP and Google Persistent disk. These two ensure that every time a VM is started the Static IP and scheduler's work directory are preserved.

To send jobs from GTISE to the scheduler just enter the scheduler's IP address in `GTISE --> File --> Options --> Run Distributed`. To get the IP address please go to the corresponding job directory in the PW IDE and open the `start_scheduler/sched.out` file, as shown in the image below. However, note that this process is only required once as the IP address will always be the same for a given scheduler pool.


<div style="text-align:left;"><img src="https://drive.google.com/uc?id=1TMP0waeTDsYm_K1wkNlYR4Psw9h4WIQ4" height="450"></div>


### Inputs:

#### Required Info:
- **Executor Pools**: The scheduler sends packets to the GT executor pools. Please select one or more executor pools. If more than one executor pool is selected the [_smart pool selector_](https://docs.google.com/document/d/1PCFMaSbcy6YsWNoJ1GpO-Oe4EdFI8L9PPfibWo9AQJs/edit?usp=sharing) algorithm will be used to distribute the load among the different executor pools. This algorithm minimizes the number iddle cores and executor VMs.

- **Cloud platform**
- **GT user name**: Linux user that starts the scheduler service and user in the `/etc/systemd/system/gtdistd.service.d/override.conf` file.
- **GT version**
- **License servers**: `<port1>@<host1>:<port2>@<host2>`. On Windows, the separator is a semicolon.



#### Advanced GT Info:
- **Activate job summary service**: Select whether to active the job summary service in the scheduler's properties file.

#### Advanced PW Info:
- **Core demand sensing cycle duration [s]**: Specify the cycle duration for sensing the core demand. Core demand is sensed every cycle.
- **Over demand satisfaction fraction [0,1]**: Fraction of the core over demand to satisfy every cycle. If the value 1 is selected all the core over demand is satisfied in just one cycle. Select less than 1 if the packet runtime is much smaller than VM startup time.

#### Create SSH Tunnel:
To connect to the scheduler VM through a tunnel follow the instruction in this section:
1. Add the SSH public keys of the client to `/pw/workflows/start_scheduler/authorized_keys` before starting the workflow. Make sure the keys are in the right format (see instructions below).
2. Run the workflow and wait for the scheduler to start. Watch the streaming logs under `/pw/jobs/job_number/start_scheduler/sched.out`
3. Start the SSH tunnel in the client host (see instructions bellow).
4. Introduce 0.0.0.0 (localhost) as the IP of the scheduler VM in the Network Distributed configuration in GTISE.

**CORRECT FORMAT**
```
ssh-rsa AAAAB3Nza_LONG_PUBLIC_KEY_JhhEGu60qQ== user@machine
```

Keys generated with Putty must be converted to the format above from the format below:

**WRONG FORMAT**
```
---- BEGIN SSH2 PUBLIC KEY ----
Comment: "rsa-key-20210630"
AAAAB3Nza_LONG_PUBLIC_KEY_JhhEGu60qQ==
---- END SSH2 PUBLIC KEY ----
```


#### Linux Machine:
Run this command in your local terminal to start the tunnel
```
ssh -N \
    -L 0.0.0.0:8979:127.0.0.1:8979 \
    -L 0.0.0.0:8970:127.0.0.1:8970 \
    tunnel@scheduler_vm_ip
```

#### Windows Machine:
Add the information to the tunnels section below before opening your session.

<div style="text-align:left;"><img src="https://drive.google.com/uc?id=1pr1tZjQZ1kigsTCM1KMpyL6P6NDJR0Xu" height="450"></div>



<div style="text-align:left;"><img src="https://drive.google.com/uc?id=1s0uMyrl24zVn24lsH8gmLDTZB59pUGHO" height="450"></div>


