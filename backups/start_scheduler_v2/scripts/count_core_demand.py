import sys
import requests
import os
import xml.etree.ElementTree as ET

# Counts current core demand by looking are the running + pending packets
# Considers the license per job and maximum number of licenses to avoid
# requesting cores that don't have a license
def count_core_demand(webapp_xml, max_lic = 999999):
    if not os.path.isfile(webapp_xml):
        return 0
    tree = ET.parse(webapp_xml)
    root = tree.getroot()
    core_demand = 0
    lic_demand = 0
    free_lic = max_lic
    for job in root.iter('job'):
        max_job_lic = None
        max_job_cores = None
        job_parallel_cpu = 1
        for prog in job.iter('progress'):
            # Job packet demand = Pending + running packets (initially)
            job_pd = int(prog.attrib["running"]) + int(prog.attrib["pending"])
        for prop in job.iter('property'):
            if prop.attrib["key"] == "solver.parallel-cpu":
                job_parallel_cpu = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-licenses-per-batch":
                max_job_lic = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-cores-per-batch":
                max_job_cores = int(prop.text)

        # Set defaults:
        job_cores = job_parallel_cpu * job_pd
        job_lic = job_pd

        # Max job licenses defined
        if max_job_lic is not None:
            job_lic = min(job_lic, max_job_lic)
            job_cores = job_parallel_cpu * min(job_pd, job_lic)

        # Max job cores defined
        if max_job_cores is not None:
            job_cores = min(job_cores, max_job_cores)
            job_lic = int(job_cores/job_parallel_cpu)

        # Check that there are enough licenses in total
        if job_lic < free_lic:
            core_demand += job_cores
            free_lic += -job_lic
        else:
            core_demand += job_parallel_cpu * free_lic
            free_lic = 0

        if free_lic == 0:
            return core_demand
    return core_demand

if __name__ == "__main__":
    webapp_xml = sys.argv[1]
    max_licenses = 999999
    if len(sys.argv) == 3:
        max_licenses = int(sys.argv[2])
    core_demand = count_core_demand(webapp_xml, max_lic = max_licenses)
    print(core_demand)