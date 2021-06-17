import os
import xml.etree.ElementTree as ET

# Convert info from webapp to job log
def webapp2dict(webapp_xml):
    jobs_dict = {}
    if not os.path.isfile(webapp_xml):
        return 0
    tree = ET.parse(webapp_xml)
    root = tree.getroot()
    for job in root.iter('job'):
        for name in job.iter("name"):
            job_name = name.text
        job_id = job.attrib["id"]

        jobs_dict[job_id] = {
            "Name": job_name,
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
