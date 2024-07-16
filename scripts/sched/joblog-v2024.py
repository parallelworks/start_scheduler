import datetime
import xml.etree.ElementTree as ET


def joblog2dict(job_log):
    job_log_f = open(job_log, "r")
    job_log_lines = [jl.replace("\n","") for jl in job_log_f.readlines()]
    job_log_f.close()

    job_name = job_log_lines[0].split("\t")[1].split(' ')[0]
    sim_packet_names = []
    merge_pname = None
    #job_dict = {"status": None, "run_time": 0, "split_status": None,
    #            "merge_status": None, "sim_packets": None}
    job_dict = {"status": None, "sim_packets": None}

    # Events are logged to the job.log
    for el in job_log_lines: # el: event line
        # Type of event
        # - start, submitted, finish, produced, status and has (has x results)
        etype = el.split("\t")[1].split(' ')[1]

        # Script only logs status (for metering) and produced (for counting demand) events:
        if etype == "status":
            # Only changes of status are reported!
            status = el.split("\t")[-1].split(' ')[-1]
            # Subject of the status event (job, packet, split or merge)
            esubject = el.split("\t")[1].split(' ')[0]
            packet_name = esubject.split("-")[-1]
 
            # Subject is Job
            if esubject == job_name:
                job_dict["status"] = status

            # Subject is a sim packet
            elif packet_name in sim_packet_names:
                job_dict["sim_packets"][packet_name]["status"] = status

        elif etype == "produced":
            nsp = int(el.split("\t")[1].split(' ')[2])
            merge_pname = str(nsp+1).zfill(4)
            # Initialize sim_packets dictionary
            sim_packet_names = [str(pn).zfill(4) for pn in range(1, nsp + 1)]
            job_dict["sim_packets"] = dict.fromkeys(sim_packet_names, None)
            for pn in sim_packet_names:
                #job_dict["sim_packets"][pn] = {"status": None, "start_time": None, "run_time": 0}
                job_dict["sim_packets"][pn] = {"status": None}

    return job_dict

