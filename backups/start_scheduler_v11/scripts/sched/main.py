import json
import sys
import time
from pprint import PrettyPrinter
import sched_info
import executor
import cjs

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

pw_http="http://beta.parallel.works"

inp_txt = sys.argv[1]
inp_dict = txt2dict(inp_txt)

version = inp_dict["version"]
webapp_xml = inp_dict["webapp_xml"]
sched_work_dir = inp_dict["sched_work_dir"]
exec_work_dir = inp_dict["exec_work_dir"]
gt_user = inp_dict["gt_user"]
sched_ip = inp_dict["sched_ip"]
pool_names = inp_dict["pool_names"]
pool_info_json = inp_dict["pool_info_json"]
gtdist_exec_pfile = inp_dict["gtdist_exec_pfile"]
log_dir = inp_dict["log_dir"]

if '---' in pool_names:
    pool_names = pool_names.split('---')
else:
    pool_names = [pool_names]



pp = PrettyPrinter(depth=4)

# Get core demand:
# job_records_json = sched_work_dir + "/job_records.json"
#[pool_info, job_records] = json2dict([pool_info_json, job_records_json])
[pool_info] = json2dict([pool_info_json])
active_jobs = sched_info.get_active_jobs(webapp_xml, sched_work_dir)
core_demand = sched_info.count_core_demand(active_jobs)
print("Core demand: {}".format(str(core_demand)))

# Define executor
# Get executor supply
exec_supply = cjs.count_cjs_by_pool(pool_names)
print("Executor supply:")
print(exec_supply)
Executor = executor.AggregatedExecutor(pool_info, pool_names, exec_supply)

# Calculate executor overdemand - Minimizing number of nodes
exec_overdemand = Executor.get_overdemand(core_demand)
print("Executor over demand:")
print(exec_overdemand)

# Get priorities for executors:
Executor.get_priority()

inputs = ["scripts/executor.sh", gtdist_exec_pfile + " -> " + "/tmp/gtdistd-exec.properties"]
for pname,nworkers in exec_overdemand.items():
    pool = [ pool for pool in pool_info if pool["name"] == pname][0]
    # Submit wait-till-iddle jobs to executors
    cpe = int(int(pool['info']['cpuPerWorker'])/2) # Cores per executor
    service_port = str(pool['info']['ports']['serviceport'])
    service_url = pw_http + ":" + service_port
    for i in range(nworkers):
        exec_priority = str(Executor.priority[pname][i])
        cmd = "/bin/bash {}/executor.sh {} {} {} {} {}".format(exec_work_dir, version, gt_user, sched_ip, str(cpe), exec_priority)
        # Run as gt_user
        cmd = "su {} -c \\\"{}\\\"".format(gt_user, cmd)
        stdout = exec_work_dir + "/executor.out"
        stderr = exec_work_dir + "/executor.err"
        cjs_cmd = cjs.get_cjs_cmd(cmd, service_url, inputs = inputs, rwd = exec_work_dir,  stdout = stdout, stderr = stderr, redirected = False)
        time.sleep(0.01)
        print("Starting executor in pool {}".format(pname))
        cjs.Popen_cjs_cmd(cjs_cmd, pname)

# Extra info for debugging
# Based on job logs and webapp only!
#job_records = sched_info.update_job_records(job_records, active_jobs)
#dict2json([job_records], [job_records_json])
