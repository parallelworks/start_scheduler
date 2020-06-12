from xml.etree.ElementTree import iterparse
import sys
import requests

# Count running or queued
def count_rq(webapp_xml):
    try:
        rqc = 0
        for _, elem in iterparse(webapp_xml):
            if "completed" in elem.attrib:
                rqc += int(elem.attrib["running"]) + int(elem.attrib["pending"])
        return rqc
    except:
        return -1

if __name__ == "__main__":
    webapp_xml = sys.argv[1]
    rqc = count_rq(webapp_xml)
    print(rqc)