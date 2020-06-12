import json
import sys

pool_info_json = sys.argv[1]
pool_name = sys.argv[2]

with open(pool_info_json) as f:
  pool_info_data = json.load(f)

pool_info_txt = sys.argv[3]
pool_info_f = open(pool_info_txt, "w")

for pool in pool_info_data:
  if pool['name'] == pool_name:
    sp = pool['info']['ports']['serviceport']
    cp = pool['info']['ports']['controlport']
    max_workers = pool['settings']['max']
    nvcpu = str(int(int(pool['info']['cpuPerWorker'])/2))
    pool_info_f.write("serviceport={}\n".format(pool['info']['ports']['serviceport']))
    pool_info_f.write("controlport={}\n".format(pool['info']['ports']['controlport']))
    pool_info_f.write("maxworkers={}\n".format(pool['settings']['max']))
    pool_info_f.write("workercpu={}\n".format(nvcpu))
    pool_info_f.close()
    break
