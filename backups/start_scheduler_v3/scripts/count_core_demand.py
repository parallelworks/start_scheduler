import sys
import requests
import os
import xml.etree.ElementTree as ET
import math

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
        max_cases_per_packet = 1
        min_cases_per_packet = 1
        for prog in job.iter('progress'):
            job_cases =  int(prog.attrib["pending"]) + int(prog.attrib["running"])
        for prop in job.iter('property'):
            if prop.attrib["key"] == "solver.parallel-cpu":
                job_parallel_cpu = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-licenses-per-batch":
                max_job_lic = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-cores-per-batch":
                max_job_cores = int(prop.text)
            if prop.attrib["key"] == "scheduler.max-cases-per-packet":
                max_cases_per_packet = int(prop.text)
            if prop.attrib["key"] == "scheduler.min-cases-per-packet":
                min_cases_per_packet = int(prop.text)

        # FIXME: We don't know the cases per packet, just min and max
        # Minimizes packets subject to min and max specs
        # For example, if min=1, max=2 and cases=3 --> 2 packets (1x2 + 1x1)
        #              if min=2, max=2 and cases=3 --> 1 packet
        #              if min=2, max=3 and cases=4 --> 1 packet
        #              if min=2, max=5 and cases=14 -> 3 packets (2x5 + 1x4)
        job_packets_a = math.ceil(job_cases / max_cases_per_packet)
        job_packets_b = math.floor(job_cases / max_cases_per_packet) + math.floor((job_cases % max_cases_per_packet) / min_cases_per_packet)
        job_packets = min(job_packets_a, job_packets_b)

        # Set defaults:
        job_lic = job_packets

        if max_job_lic is None:
            job_lic_demand = job_lic
            job_packet_demand = job_packets
        else: # Max job licenses defined
            job_lic_demand = min(job_lic, max_job_lic)
            job_packet_demand = min(job_packets, job_lic_demand)

        if max_job_cores is None:
            job_core_demand = job_parallel_cpu * job_packet_demand
        else: # Max job cores defined
            job_core_demand = min(job_parallel_cpu * job_packet_demand, max_job_cores)
            job_lic_demand = int(job_core_demand / job_parallel_cpu)

        # Check that there are enough licenses in total
        if job_lic_demand < free_lic:
            core_demand += job_core_demand
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
