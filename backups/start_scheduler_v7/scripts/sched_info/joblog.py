import datetime
import xml.etree.ElementTree as ET

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
