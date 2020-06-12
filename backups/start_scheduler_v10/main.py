import sys
import os, shutil
import parsl
from parslpw import pwconfig,pwargs
from parsl.data_provider.files import File
print(parsl.__version__)

# Import Path()
sys.path.append("/pw/modules/utils")
from path import Path

# ---- RUN WORKFLOW ---- #
def run(wf_pwargs, wf_dir = "start_scheduler"):
    os.makedirs(wf_dir, exist_ok=True)
    print("START_SCHEDULER INPUTS:")
    print(wf_pwargs)

   # ---- IMPORT WORKFLOW TEMPLATES ---- #
    if not os.path.isdir("wfbuilder"):
        shutil.copytree("/pw/modules/wfbuilder", "wfbuilder")
    from wfbuilder.pwrunners import SimpleBashRunner

    sched_runner = SimpleBashRunner(
        cmd = "/bin/bash scripts/cog-job-daemon.sh",
        cmd_arg_names = ["license", "executor_pools", "gt_user", "sum_serv", "api_key", "pf_dir", "log_dir"],
        inputs =  {
            "license": wf_pwargs.license,
            "executor_pools": wf_pwargs.executor_pools,
            "gt_user": wf_pwargs.gt_user,
            "sum_serv": wf_pwargs.sum_serv,
            "api_key": os.environ['PW_API_KEY'],
            "log_dir": wf_dir,
            "pf_dir": Path("./properties_files"),
            "scripts": Path("./scripts")
        },
        logs = {
            "stdout": wf_dir + "/sched.out",
            "stderr": wf_dir + "/sched.err"
        },
        stream_host = "goofs.parallel.works"
    )
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