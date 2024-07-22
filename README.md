## GT Scheduler
### Overview
This guide explains how to start an elastic SLURM cluster, submit the GT_SCHEDULER workflow, and run GT jobs. Note that each cluster can run only one GT_SCHEDULER job at a time.

### Steps to Use the Cluster
##### 1. Start Cluster
##### 2. Submit GT_SCHEDULER workflow
Submit the GT_SCHEDULER workflow to the cluster. This scheduler calculates the required number of cores to run all GT jobs concurrently and efficiently.
##### 3. Submit GT Jobs
- Option 1: Submit GT jobs directly from GTISE to the cluster's external IP address using the distributed mode.
- Option 2: Start GTISE on the cluster's controller node using the gtise remote desktop workflow and submit the jobs to localhost.

### Scheduler Logic
The scheduler workflow ensures optimal utilization by running all GT jobs concurrently while minimizing the number of executor nodes. SLURM jobs are submitted to start executor nodes for running GT jobs. Executor nodes are started on demand and are deleted when idle.

### Persistent Storage
- A persistent disk is attached and mounted under /software, and NFS exported to compute nodes with the GT software.
- Another persistent disk is attached under /var/opt/gtsuite, serving as the scheduler’s work directory.

Restarting the cluster deletes all data except for what is stored on the persistent disks.

### License Server Access
Executor jobs access the license server through an SSH tunnel. The license server details (hostname, IP address, username, and port) are hardcoded in the workflow’s XML or YML file. The organization’s page tracks the license product usage for each GT product on each cluster.

