import json
import sys
import time
import os
import subprocess
from pprint import PrettyPrinter
import sched_info
import executor
import cjs
import balance_info

def json2dict(json_paths):
    json_paths = list(json_paths)
    dict_list = []
    for jp in json_paths:
        try:
            with open(jp, 'r') as json_file:
                dict_list.append(json.load(json_file))
        except:
            dict_list.append({})
    return dict_list


def dict2json(dict_list, json_paths):
   for index, jp in enumerate(json_paths):
       with open(jp, 'w') as json_file:
           json.dump(dict_list[index], json_file, indent = 4)


def txt2dict(txt_fpath, sep = "="):
    txt_f = open(txt_fpath, "r")
    txt_lines = [tl.replace("\n","").lstrip() for tl in txt_f.readlines()]
    txt_f.close()
    dicti = {}
    for tl in txt_lines:
        dicti[tl.split(sep)[0]] = tl.split(sep)[1]
    return dicti

# FIXME: Does close the tunnels if no longer in use!
def open_tunnel(sp):
    sp = str(sp)
    tunnel_reg_file = ('/tmp/port-' + sp)
    open_tunnel_cmd = "setsid ssh -L {}:localhost:{} localhost -fNT".format(sp, sp)
    if not os.path.isfile(tunnel_reg_file):
        subprocess.Popen(open_tunnel_cmd, shell = True)
        open(tunnel_reg_file, 'a').close()


inp_txt = sys.argv[1]
inp_dict = txt2dict(inp_txt)

version = inp_dict["version"]
webapp_xml = inp_dict["webapp_xml"]
sched_work_dir = inp_dict["sched_work_dir"]
exec_work_dir = inp_dict["exec_work_dir"]
pool_names = inp_dict["pool_names"]
pool_info_json = inp_dict["pool_info_json"]
gtdist_exec_pfile = inp_dict["gtdist_exec_pfile"]
od_frac = float(inp_dict["od_pct"])/100
cloud = inp_dict["cloud"]
sched_ip_int = inp_dict["sched_ip_int"]
api_key = inp_dict["api_key"]
lic_hostname = inp_dict["lic_hostname"]
pw_url = inp_dict["pw_url"]
allow_ps = inp_dict["allow_ps"]

#gtdistd_ctrl = sched_work_dir + '/gtdistd/run/gtdistd.ctrl'

# Check balance will exit here if balance < 0
# http://localhost --> DOES NOT WORK HERE!
balance = balance_info.get_balance(pw_url, api_key)
balance_info.check_balance(balance, sched_work_dir + '/gtdistd/gtdistd-sched.properties')


if '---' in pool_names:
    pool_names = pool_names.lower().split('---')
else:
    pool_names = [pool_names.lower()]


pp = PrettyPrinter(depth=4)

# Get core demand:
# job_records_json = sched_work_dir + "/job_records.json"
#[pool_info, job_records] = json2dict([pool_info_json, job_records_json])
[pool_info] = json2dict([pool_info_json])
# Make sure pool name is lowercase!
for pool in pool_info:
    pool['name'] = pool['name'].lower()

active_jobs = sched_info.get_active_jobs(webapp_xml, sched_work_dir)
active_jobs = sched_info.remove_jobs_with_no_balance(active_jobs, balance)
core_demand = sched_info.count_core_demand(active_jobs, allow_ps)
print("Core demand: {}".format(str(core_demand)))

# Define executor
Executor = executor.AggregatedExecutor(pool_info, pool_names)

print("Executor supply:")
print(Executor.supply)

# Calculate executor overdemand - Minimizing number of nodes
exec_overdemand = Executor.get_overdemand(core_demand, od_frac)
print("Executor demand (od_frac = {}):".format(str(od_frac)))
print(exec_overdemand)

# Get priorities for executors:
Executor.get_priority()

for pname,nworkers in exec_overdemand.items():
    pool = [ pool for pool in pool_info if pool["name"] == pname][0]
    # Submit wait-till-iddle jobs to executors
    cpe = int(int(pool['info']['cpuPerWorker'])/2) # Cores per executor
    service_port = str(pool['info']['ports']['serviceport'])
    open_tunnel(service_port)
    service_url = "http://localhost:" + service_port
    for i in range(nworkers):
        exec_priority = str(Executor.priority[pname][i])
        cjs_cmd = cjs.get_cjs_cmd(
            "/bin/bash /tmp/executor.sh {} {} {} {} {} {}".format(version, str(cpe), exec_priority, cloud, sched_ip_int, lic_hostname),
            service_url,
            inputs = ["scripts/executor.sh", gtdist_exec_pfile + " -> " + "/tmp/gtdistd-exec.properties"],
            rwd = '/tmp/',
            stdout = "/tmp/executor.out",
            stderr = "/tmp/executor.err",
            redirected = False
        )
        time.sleep(0.01)
        print("Submitting executor.sh job to pool {}".format(pname))
        cjs.Popen_cjs_cmd(cjs_cmd, pname)


# Extra info for debugging
# Based on job logs and webapp only!
#job_records = sched_info.update_job_records(job_records, active_jobs)
#dict2json([job_records], [job_records_json])
