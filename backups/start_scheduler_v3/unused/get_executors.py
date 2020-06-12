import sys
import os
import xml.etree.ElementTree as ET

def get_executors(webapp_xml):
    executors = []
    if not os.path.isfile(webapp_xml):
        return executors
    tree = ET.parse(webapp_xml)
    root = tree.getroot()
    for job in root.iter('executors'):
        for ctxt in job.iter('context'):
            # Job packet demand = Pending + running packets (initially)
            executors.append(ctxt.attrib['hostname'].split('.')[0])
    return executors

if __name__ == "__main__":
    webapp_xml = sys.argv[1]
    executors = get_executors(webapp_xml)
    hostname = sys.argv[2]
    if hostname in executors:
        print("true")
    else:
        print("false")