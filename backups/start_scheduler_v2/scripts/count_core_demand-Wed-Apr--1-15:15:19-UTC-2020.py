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
        job_parallel_cpu = 1
        for prog in job.iter('progress'):
            # Pending + running packets
            pr_p = int(prog.attrib["running"]) + int(prog.attrib["pending"])
        for prop in job.iter('property'):
            if prop.attrib["key"] == "solver.parallel-cpu":
                job_parallel_cpu = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-licenses-per-batch":
                max_job_lic = int(prop.text)
        if max_job_lic is None: # No max job licenses were defined
            job_lic_demand = pr_p
        else:
            job_lic_demand = min(pr_p, max_job_lic)

        if job_lic_demand < free_lic:
            core_demand += job_parallel_cpu * job_lic_demand
            free_lic += -job_lic_demand
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