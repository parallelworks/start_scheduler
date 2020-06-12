import sys
import os, shutil
import parsl
from parslpw import pwconfig,pwargs
from parsl.data_provider.files import File
print(parsl.__version__)

# Import Path()
sys.path.append("/pw/modules/utils")
from path import Path

# ---- DEFINE RUNNER ---- #
def define():
    # ---- IMPORT WORKFLOW TEMPLATES ---- #
    if not os.path.isdir("wfbuilder"):
        shutil.copytree("/pw/modules/wfbuilder", "wfbuilder")
    from wfbuilder.pwrunners import SimpleBashRunner

    case_inputs = {"license": "",
                   "pool_name": "",
                   "gt_user": "",
                   "ds_freq": "",
                   "api_key": "",
                   "cpe": "",
                   "sched_lic": "",
                   "exec_log_dir": "",
                   "pf_dir": Path("./properties_files"),
                   "scripts": Path("./scripts")}

    case_logs = {"stdout": "sched.out", "stderr": "sched.err"}
    case_arg_names = ["license", "pool_name", "gt_user", "ds_freq", "api_key", "pf_dir", "exec_log_dir", "cpe", "sched_lic"]
    cmd = "/bin/bash scripts/cog-job-daemon.sh"
    return SimpleBashRunner(cmd, cmd_arg_names = case_arg_names, inputs = case_inputs, logs = case_logs, stream_host = "beta.parallel.works")

# ---- RUN WORKFLOW ---- #
def run(wf_pwargs, wf_dir = "start_scheduler"):
    os.makedirs(wf_dir, exist_ok=True)
    print("START_SCHEDULER INPUTS:")
    print(wf_pwargs)
    sched_runner = define()
    sched_runner.inputs["license"] = wf_pwargs.license
    sched_runner.inputs["pool_name"] = wf_pwargs.pool_name
    sched_runner.inputs["gt_user"] = wf_pwargs.gt_user
    sched_runner.inputs["ds_freq"] = wf_pwargs.ds_freq
    sched_runner.inputs["api_key"] = os.environ['PW_API_KEY']
    exec_log_dir = os.getcwd() + '/' + wf_dir + "/executors"
    os.makedirs(exec_log_dir, exist_ok=True)
    sched_runner.inputs["exec_log_dir"] = exec_log_dir

    if pwargs.cpe_def == "True":
        sched_runner.inputs["cpe"] = wf_pwargs.cpe
    else:
        sched_runner.inputs["cpe"] = "-1" # Will trigger default

    if pwargs.sched_lic_def == "True":
        sched_runner.inputs["sched_lic"] = wf_pwargs.sched_lic
    else:
        sched_runner.inputs["sched_lic"] = "-1" # Will trigger default

    sched_runner.logs = {"stdout": wf_dir + "/sched.out", "stderr": wf_dir + "/sched.err"}

    try:
        parsl.load(pwconfig)
    except:
        pass

    return sched_runner.run()


# ---- RUN WORKFLOW --- #
if __name__ == "__main__":
    # Runs only when executed (not when imported)
    sched_fut = run(pwargs)
    sched_fut.result()