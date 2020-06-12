import sys
import os
import json
from random import randint
import tempfile
import glob
import subprocess

def replace_root_dir(path, root_dir):
    if not root_dir.endswith("/"):
        root_dir = root_dir + "/"
    if "./" in path:
        return root_dir + path.split("./")[1]
    else:
        if path.startswith("/"):
            return path
        else:
            return root_dir + os.path.basename(path) # path

# Inputs: Local path and remote working directotry
# Outputs: Local to remote mapping
def map_stage_in(lpath, rwd):
    if "->" in lpath:
        return lpath

    rpath = replace_root_dir(lpath, rwd)
    return "{} -> {}".format(lpath, rpath)

# Inputs: Remote path and local directory
# Outputs: Local to remote mapping
def map_stage_out(rpath, lwd = None):
    if "<-" in rpath:
        return rpath

    if lwd is None:
        lwd = os.getcwd()
    lpath = replace_root_dir(rpath, lwd)
    os.makedirs(os.path.dirname(lpath), exist_ok=True)
    return "{} <- {}".format(lpath, rpath)

def get_cjs_cmd(cmd, service_url, inputs = [], outputs = [], stdout = None, stderr = None, redirected = False, rwd = None):
    if rwd is None:
        rwd = "/tmp/pworks/" + str(randint(0,99999)).zfill(5)
    cwd = os.getcwd()
    input_maps = " : ".join([map_stage_in(inp, rwd) for inp in inputs])
    if input_maps:
        input_maps = " -stagein \"" + input_maps + "\""

    output_maps = " : ".join([map_stage_out(outp) for outp in outputs])
    if output_maps:
        output_maps = " -stageout \"" + output_maps + " \""

    std = ""
    if redirected:
        std = std + " -redirected "
    if stdout is not None:
        std = std + " -stdout \"{}\"".format(stdout)
    if stderr is not None:
        std = std + " -stderr \"{}\"".format(stderr)

    return "cog-job-submit -provider \"coaster-persistent\" -attributes \"maxWallTime=240:00:00\" {} -service-contact \"{}\"{}{} -directory \"{}\" /bin/bash -c \"mkdir -p {}; cd {}; {}\"".format(
        std, service_url, input_maps, output_maps, rwd, rwd, rwd, cmd)


def Popen_cjs_cmd(cjs_cmd, pool_name = None):
    # To track submitted cjs commands by pool name
    if pool_name is not None:
        _, cjs_fname = tempfile.mkstemp(prefix = pool_name + "-")
        #cjs_cmd = "sleep 1" # For debugging
        cjs_cmd = "{}; rm {}".format(cjs_cmd, cjs_fname)
    subprocess.Popen(cjs_cmd, shell = True)


def count_cjs_by_pool(pool_names):
    cjs_by_pool = dict.fromkeys(pool_names, 0)
    for pname in pool_names:
        cjs_by_pool[pname] = len(glob.glob('/tmp/' + pname + "-**"))
    return cjs_by_pool


if __name__ == "__main__":
    cmd = "/bin/bash ${exec_work_dir}/wti.sh ${GT_USER} ${sched_ip}"
    service_url = "http://beta.parallel.works:9001"
    inputs = ["pools_info.json", "read_pool_info.py"]
    cjs_cmd = get_cjs_cmd(cmd, service_url, inputs = [], outputs = [], rwd = "${exec_work_dir}")
    print(cjs_cmd)
