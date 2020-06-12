import json
import os
from copy import deepcopy
import joblog
import webapp
#import lmstat
#import alerts as alerts_mod

def get_running_and_queued(job_dict):
    rqc = 0
    rqc_status = ["QUEUED", "SUBMITTING", "SUBMITTED", "RUNNING"]
    for key,value in job_dict["sim_packets"].items():
        status = value["status"]
        if any([st == status for st in rqc_status]):
           rqc += 1
    return rqc

# Counts current core demand by looking are the running + pending packets
# Considers the license per job and
# FIXME: Cannot avoid requesting cores that don't have a license
# product_available --> To know remaining product runtime
# product_limits    --> To know total product licenses
# FIXME: Cannot use model.product!
def count_core_demand(active_jobs):
    core_demand = 0
    if not active_jobs:
        return 0

    for job,job_info in active_jobs.items():

        # Simulation packets running and queued
        job_packets = get_running_and_queued(job_info)
        # Set defaults:
        job_lic = job_packets

        if job_info["scheduler.max-licenses-per-batch"] is None:
            job_lic_demand = job_lic
            job_packet_demand = job_packets

        else: # Max job licenses defined
            job_lic_demand = min(job_lic, job_info["scheduler.max-licenses-per-batch"])
            job_packet_demand = min(job_packets, job_lic_demand)


        if job_info["scheduler.max-cores-per-batch"] is None:
            job_core_demand = job_info["solver.parallel-cpu"] * job_packet_demand
        else: # Max job cores defined
            job_core_demand = min(job_info["solver.parallel-cpu"] * job_packet_demand, job_info["scheduler.max-cores-per-batch"])
            job_lic_demand = int(job_core_demand / job_info["solver.parallel-cpu"])

        core_demand += job_core_demand
    return core_demand


# Returns a dictionary with job information extracted from the job log
# Merges information from the webapp and the job.log
# Active jobs are jobs that are not completed
# Active jobs SHOULD appear in the webapp_xml
def get_active_jobs(webapp_xml, sched_work_dir):
    jobs_dir = sched_work_dir + "/" + "jobs"
    jobs_dict = webapp.webapp2dict(webapp_xml)
    for job in jobs_dict.keys():
        job_log = jobs_dir + "/" + job + "/job.log"
        if os.path.isfile(job_log):
            jobs_dict[job].update(joblog.joblog2dict(job_log))
        else: # If job has been killed by deleting its job_dir --> No longer active
            del jobs_dict[job]
    return jobs_dict

# Update job records JSON file with active jobs info
def update_job_records(job_records, active_jobs):
    if job_records:
        for job,job_info in active_jobs.items():
            job_records[job] = job_info
    else:
        job_records = deepcopy(active_jobs)
    return job_records


    if os.path.isfile(job_records_json):
        with open(job_records_json, 'r') as json_file:
            job_records = json.load(json_file)

        for job,job_info in active_jobs.items():
            job_records[job] = job_info

        with open(job_records_json, 'w') as json_file:
            json.dump(job_records, json_file, indent = 4)
    else:
         with open(job_records_json, 'w') as json_file:
            json.dump(active_jobs, json_file, indent = 4)

