import json
import subprocess
import os

# FIXME: If workflow has more than one pool!
def get_job_pool():
    pw_conf = open("pw.conf","r")
    while True:
        line = pw_conf.readline()
        if "sites" in line:
            return line.split("[")[1].split("]")[0]

def get_pool_info(pool_name, api_key):
    cmd = "curl -s https://beta2.parallel.works/api/resources?key=" + api_key
    curl_p = subprocess.run(cmd.split(" "), capture_output = True)
    pools = json.loads(curl_p.stdout)
    for pool in pools:
        if pool["name"].replace('_','') == pool_name:
            return pool
