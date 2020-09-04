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

    if float(wf_pwargs.od_frac) > 1.0 or float(wf_pwargs.od_frac) < 0:
        print("Over demand satisfaction fraction is {} and must be between zero and one!".format(wf_pwargs.od_frac))
        sys.exit()
    # ---- IMPORT WORKFLOW TEMPLATES ---- #
    if not os.path.isdir("wfbuilder"):
        shutil.copytree("/pw/modules/wfbuilder", "wfbuilder")
    from wfbuilder.pwrunners import SimpleBashRunner

    sched_runner = SimpleBashRunner(
        cmd = "/bin/bash scripts/scheduler.sh",
        cmd_arg_names = ["license", "executor_pools", "version", "gt_user", "sum_serv", "ds_cycle", "od_frac", "api_key", "pf_dir", "log_dir", "cloud"],
        inputs =  {
            "license": wf_pwargs.license,
            "executor_pools": wf_pwargs.executor_pools,
            "version": wf_pwargs.version,
            "gt_user": wf_pwargs.gt_user,
            "sum_serv": wf_pwargs.sum_serv,
            "ds_cycle": wf_pwargs.ds_cycle,
            "od_frac": wf_pwargs.od_frac,
            "api_key": os.environ['PW_API_KEY'],
            "log_dir": wf_dir,
            "cloud": wf_pwargs.cloud,
            "pf_dir": Path("./properties_files"),
            "scripts": Path("./scripts")
        },
        logs = {
            "stdout": wf_dir + "/scheduler.out",
            "stderr": wf_dir + "/scheduler.err"
        },
        user = wf_pwargs.gt_user,
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