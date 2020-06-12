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
                   "executor_pools": "",
                   "gt_user": "",
                   "api_key": "",
                   "log_dir": "",
                   "pf_dir": Path("./properties_files"),
                   "scripts": Path("./scripts")}

    case_logs = {"stdout": "sched.out", "stderr": "sched.err"}
    case_arg_names = ["license", "executor_pools", "gt_user", "api_key", "pf_dir", "log_dir"]
    cmd = "/bin/bash scripts/cog-job-daemon.sh"
    return SimpleBashRunner(cmd, cmd_arg_names = case_arg_names, inputs = case_inputs, logs = case_logs, stream_host = "goofs.parallel.works")

# ---- RUN WORKFLOW ---- #
def run(wf_pwargs, wf_dir = "start_scheduler"):
    os.makedirs(wf_dir, exist_ok=True)
    print("START_SCHEDULER INPUTS:")
    print(wf_pwargs)
    sched_runner = define()
    sched_runner.inputs["license"] = wf_pwargs.license
    sched_runner.inputs["executor_pools"] = wf_pwargs.executor_pools
    sched_runner.inputs["gt_user"] = wf_pwargs.gt_user
    sched_runner.inputs["api_key"] = os.environ['PW_API_KEY']
    sched_runner.inputs["log_dir"] = wf_dir

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