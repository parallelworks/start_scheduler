import json
import datetime
import sys
from pprint import PrettyPrinter
import os, shutil
import xml.etree.ElementTree as ET
import math
from copy import deepcopy


# Converts the timestamp from the job.log file to datetime
def timestap_to_datetime(el):
    date_time = el.split(" ")[0].split("\t")[0]
    date = date_time.split("T")[0]
    time = date_time.split("T")[1]
    year = int(date.split('-')[0])
    month = int(date.split('-')[1])
    day = int(date.split('-')[2])
    hour = int(time.split(":")[0])
    minute = int(time.split(":")[1])
    second = int(time.split(":")[2].split(".")[0])
    microsecond = int(time.split(":")[2].split(".")[1])
    dt = datetime.datetime(year, month, day, hour, minute, second, microsecond)
    return dt.strftime("%m/%d/%Y, %H:%M:%S")

def get_running_and_queued(job_dict):
    rqc = 0
    for key,value in job_dict["sim_packets"].items():
        if value["status"] == "QUEUED" or value["status"] == "RUNNING":
           rqc += 1
    return rqc

def kill_job(job_name):
    shutil.rmtree(sched_work_dir + "/" + "jobs/" + job_name)

# Counts current core demand by looking are the running + pending packets
# Considers the license per job and maximum number of licenses to avoid
# requesting cores that don't have a license
# product_available --> To know remaining product runtime
# product_limits    --> To know total product licenses
def count_core_demand(active_jobs, product_available, product_limits):
    core_demand = 0
    # Use a copy! Don't change limits!
    copy_product_limits =  deepcopy(product_limits)

    for job,job_info in active_jobs.items():

        if job_info["model.product"] not in product_available:
            print("WARNING: Cannot run job {}. Product {} is not available!".format(job, job_info["model.product"]))
            kill_job(job)
            continue

        # Simulation packets running and queued
        job_packets = get_running_and_queued(job_info)
        # Set defaults:
        job_lic = job_packets
        prod_av = product_available[job_info["model.product"]]
        prod_lim = copy_product_limits[job_info["model.product"]]

        if prod_av["run_time"] < 0 and job_packets > 0:
            print("WARNING: Cannot run job {}. No run time available for product {}!".format(job, job_info["model.product"]))
            kill_job(job)
            continue

        # Do not use prod_av here!
        # - Will compare running and queued packets (from active jobs) to the total licenses.
        # - Will not submit more packets than available licenses!
        if prod_lim["licenses"] == 0:
            # print("WARNING: Cannot run job {}. No licenses available for product {}!".format(job, job_info["model.product"]))
            # kill_job(job) or queue(job)
            continue

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

        # Check that there are enough product licenses in total
        if job_lic_demand < prod_lim['licenses']:
            core_demand += job_core_demand
            prod_lim["licenses"] += -job_lic_demand
        else:
            core_demand += job_info["solver.parallel-cpu"] * prod_lim['licenses']
            prod_lim["licenses"] = 0

    return core_demand


# Returns a dictionary with job information extracted from the job log
def joblog2dict(job_log):
    job_log_f = open(job_log, "r")
    job_log_lines = [jl.replace("\n","") for jl in job_log_f.readlines()]
    job_log_f.close()

    job_name = job_log_lines[0].split(" ")[0].split("\t")[1]
    sim_packet_names = []
    merge_pname = None
    #job_dict = {"status": None, "run_time": 0, "split_status": None,
    #            "merge_status": None, "sim_packets": None}
    job_dict = {
        "status": None,
        "run_time": 0,
        "split_status": None,
        "sim_packets": None}

    # Events are logged to the job.log
    for el in job_log_lines: # el: event line
        # Type of event
        # - start, submitted, finish, produced, status and has (has x results)
        etype = el.split(" ")[1]
        # Script only logs status (for metering) and produced (for counting demand) events:
        if etype == "status":
            # Only changes of status are reported!
            status = el.split(" ")[-1]
            # Subject of the status event (job, packet, split or merge)
            esubject = el.split(" ")[0].split("\t")[1]
            packet_name = esubject.split("-")[-1]

            # Subject is Job
            if esubject == job_name:
                job_dict["status"] = status

            # Subject is a sim packet
            elif packet_name in sim_packet_names:
                if status == "RUNNING":
                    # Packet status change from not running to running. Only changes are reported!
                    job_dict["sim_packets"][packet_name]["start_time"] =  timestap_to_datetime(el)

                elif status != "RUNNING": # Current status
                    if job_dict["sim_packets"][packet_name]["status"] == "RUNNING": # Previous status
                        # Last time at which the packet stop running
                        end_time = datetime.datetime.strptime(timestap_to_datetime(el), "%m/%d/%Y, %H:%M:%S")
                        # Last time at which the packet started running
                        start_time = datetime.datetime.strptime(job_dict["sim_packets"][packet_name]["start_time"], "%m/%d/%Y, %H:%M:%S")
                        # Add the last run time to the total packets run time and to its job's run time
                        job_dict["sim_packets"][packet_name]["run_time"] += (end_time - start_time).total_seconds()
                        job_dict["run_time"] += (end_time - start_time).total_seconds()
                # Update status
                job_dict["sim_packets"][packet_name]["status"] = status

        elif etype == "produced":
            nsp = int(el.split(" ")[2])
            merge_pname = str(nsp+1).zfill(4)
            # Initialize sim_packets dictionary
            sim_packet_names = [str(pn).zfill(4) for pn in range(1, nsp + 1)]
            job_dict["sim_packets"] = dict.fromkeys(sim_packet_names, None)
            for pn in sim_packet_names:
                job_dict["sim_packets"][pn] = {"status": None, "start_time": None, "run_time": 0}

    return job_dict


# Convert info from webapp to job log
def webapp2dict(webapp_xml):
    jobs_dict = {}
    if not os.path.isfile(webapp_xml):
        return 0
    tree = ET.parse(webapp_xml)
    root = tree.getroot()
    for job in root.iter('job'):
        job_id = job.attrib["id"]
        jobs_dict[job_id] = {
            "model.product": None,
            "solver.parallel-cpu": 1,
            "scheduler.max-licenses-per-batch": None,
            "scheduler.max-cores-per-batch": None
        }
        for prop in job.iter('property'):
            if prop.attrib["key"] == "model.product":
                jobs_dict[job_id]["model.product"] = prop.text

            if prop.attrib["key"] == "solver.parallel-cpu":
                jobs_dict[job_id]["solver.parallel-cpu"] = int(prop.text)

            if prop.attrib["key"] == "scheduler.max-licenses-per-batch":
                jobs_dict[job_id]["scheduler.max-licenses-per-batch"] = int(prop.text)

            if prop.attrib["key"] == "scheduler.max-cores-per-batch":
                jobs_dict[job_id]["scheduler.max-cores-per-batch"] = int(prop.text)

    return jobs_dict

# Merges information from the webapp and the job.log
# Active jobs are jobs that are not completed
# Active jobs SHOULD appear in the webapp_xml
def get_active_jobs(webapp_xml, sched_work_dir):
    jobs_dir = sched_work_dir + "/" + "jobs"
    jobs_dict = webapp2dict(webapp_xml)
    for job in jobs_dict.keys():
        job_log = jobs_dir + "/" + job + "/job.log"
        if os.path.isfile(job_log): # If job has been killed by deleting its job_dir
            jobs_dict[job].update(joblog2dict(job_log))
    return jobs_dict

# Update job records JSON file with active jobs info
def update_job_records(job_records_json, active_jobs):
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


def get_product_usage(job_records):
    product_usage = {}
    for job,job_info in job_records.items():
        if job_info["model.product"] not in product_usage:
            product_usage[job_info["model.product"]] = {"licenses": 0, "run_time": 0}

        product_usage[job_info["model.product"]]["run_time"] += job_info["run_time"]

        for sp, sp_info in job_info["sim_packets"].items():
            if sp_info["status"] == "RUNNING":
                product_usage[job_info["model.product"]]["licenses"] += 1
    return product_usage


def get_product_available(usage, limits):
    available =  deepcopy(limits)
    for product in usage.keys():
        if product not in available:
            print("WARNING: Product {} not found in available products but present in product usage!".format(product))
            continue
        else:
            available[product]["licenses"] = limits[product]["licenses"] - usage[product]["licenses"]
            available[product]["run_time"] = limits[product]["run_time"] - usage[product]["run_time"]
    return available

def send_usage_alert(msg):
    print(msg)

def get_product_alerts(alerts_json, limits):
    #if os.path.isfile(alerts_json):
    try:
        with open(alerts_json, 'r') as json_file:
            alerts = json.load(json_file)
    #else:
    except:
        alerts = {}
        for product in limits.keys():
            alerts[product] = {"warning": False, "hardstop": False}

        with open(alerts_json, 'w') as json_file:
            json.dump(alerts, json_file, indent = 4)
    return alerts

def update_product_alerts(alerts_json, usage, limits, warning_frac = 0.8):
    alerts = get_product_alerts(alerts_json, limits)
    for product in usage.keys():
        warning_percentage = str(int(warning_frac * 100))
        used_rt = str(usage[product]["run_time"])
        limit_rt = str(limits[product]["run_time"])
        used_frac = usage[product]["run_time"] / limits[product]["run_time"]

        if used_frac > 1 and alerts[product]["hardstop"] == False:
            msg = "ERROR: Usage ({}) of product {} has exceeded limit ({})!".format(used_rt, product, limit_rt)
            send_usage_alert(msg)
            alerts[product]["hardstop"] = True
            with open(alerts_json, 'w') as json_file:
                json.dump(alerts, json_file, indent = 4)

        elif all([used_frac > warning_frac, not alerts[product]["warning"], not alerts[product]["hardstop"]]):
            msg = "WARNING: Usage ({}) of product {} has exceeded {}% of limit ({})!".format(used_rt, product, warning_percentage, limit_rt)
            send_usage_alert(msg)
            alerts[product]["warning"] = True
            with open(alerts_json, 'w') as json_file:
                json.dump(alerts, json_file, indent = 4)

        elif used_frac < warning_frac:
            alerts[product]["warning"] = False
            alerts[product]["hardstop"] = False
            with open(alerts_json, 'w') as json_file:
                json.dump(alerts, json_file, indent = 4)


if __name__ == "__main__":
    webapp_xml = sys.argv[1]
    sched_work_dir = sys.argv[2]

    pp = PrettyPrinter(depth=4)
    #webapp_xml = "/home/avidalto/projects/2020/cog-job-submit/xmls_for_parsing/openmpi_2jobs_licenselimit_running_2.xml"
    #webapp_xml = "/home/avidalto/projects/2020/cog-job-submit/xmls_for_parsing/openmpi_2jobs_licenselimit_running.xml"
    #sched_work_dir = "/home/avidalto/projects/2020/plog"
    job_records_json = sched_work_dir + "/job_records.json"
    product_limits_json = sched_work_dir + "/product_limits.json"
    product_alerts_json = sched_work_dir + "/product_alerts.json"
    core_demand_txt = sched_work_dir + "/CORE_DEMAND"

    if os.path.isfile(product_limits_json):
        with open(product_limits_json, 'r') as json_file:
            product_limits = json.load(json_file)
    else:
        msg = "ERROR: No product limit found!"
        print(msg)
        raise msg

    active_jobs = get_active_jobs(webapp_xml, sched_work_dir)
    update_job_records(job_records_json, active_jobs)

    with open(job_records_json, 'r') as json_file:
        job_records = json.load(json_file)

    # Only changes when a packet status changes from RUNNING to something else
    product_usage = get_product_usage(job_records)
    if product_usage:
        print("\nPRODUCT USAGE:")
        pp.pprint(product_usage)
        print("\n")
    update_product_alerts(product_alerts_json, product_usage, product_limits, warning_frac = 0.8)
    product_available = get_product_available(product_usage, product_limits)
    core_demand = count_core_demand(active_jobs, product_available, product_limits)
    with open(core_demand_txt, "w") as cdt:
        cdt.write(str(core_demand) + "\n")
    #pp.pprint(active_jobs)

