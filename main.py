import sys, socket
import os, shutil, json
import requests
from time import sleep

import parsl
from parslpw import pwconfig,pwargs
from parsl.data_provider.files import File
print(parsl.__version__)


if not os.path.isdir("wfbuilder"):
    shutil.copytree("/pw/modules/wfbuilder", "wfbuilder")
import wfbuilder


def post_to_slack(message, e=None):
    msg = {
        "text": message,
        "blocks": [{"type": "section", "text": {"type": "mrkdwn", "text": message}}],
    }
    if e != None:
        msg["blocks"].append(
            {
                "type": "section",
                "text": {"type": "mrkdwn", "text": "```" + str(e) + "```"},
            }
        )
    msg["blocks"].append(
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "_Sent by {script} on {host}_".format(
                    script = os.path.realpath(__file__),
                    host = os.environ['PW_USER'] + '@' + socket.gethostname()
                ),
            },
        }
    )
    url = "https://hooks.slack.com/services/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"

    requests.post(
        url, data=json.dumps(msg), headers={"Content-Type": "application/json"}
    )


def get_pool_name():
    with open("pw.conf") as fp:
        Lines = fp.readlines()
        for line in Lines:
            if 'sites' in line:
                return line.split('[')[1].split(']')[0]


def get_pool_info(pool_name, url_resources, retries = 3):
    while retries >= 0:
        res = requests.get(url_resources)
        for pool in res.json():
            # FIXME: BUG sometimes pool['name'] is None when you just started the pool
            if type(pool['name']) == str:
                if pool['name'].replace('_','') == pool_name.replace('_',''):
                    return pool
        print('Retrying get_pool_info({}, {}, retries = {})'.format(pool_name, url_resources, str(retries)))
        sleep(3)
        retries += -1
    raise(Exception('Pool name not found response: ' + pool_name))


# ---- RUN WORKFLOW ---- #
def run(wf_pwargs, wf_dir = "start_scheduler"):
    os.makedirs(wf_dir, exist_ok=True)
    print("START_SCHEDULER INPUTS:")
    print(wf_pwargs)

    if float(wf_pwargs.od_frac) > 1.0 or float(wf_pwargs.od_frac) < 0:
        print("Over demand satisfaction fraction is {} and must be between zero and one!".format(wf_pwargs.od_frac))
        sys.exit()

    # ---- IMPORT WORKFLOW TEMPLATES ---- #
    sched_runner = wfbuilder.pwrunners.SimpleBashRunner(
        cmd = "/bin/bash scripts/scheduler.sh",
        cmd_arg_names = ["executor_pools", "version", "sum_serv", "ds_cycle", "od_frac", "api_key", "pf_dir", "log_dir", "cloud"],
        inputs =  {
            "executor_pools": wf_pwargs.executor_pools.lower(),
            "version": wf_pwargs.version,
            "sum_serv": wf_pwargs.sum_serv,
            "ds_cycle": wf_pwargs.ds_cycle,
            "od_frac": wf_pwargs.od_frac,
            "api_key": os.environ['PW_API_KEY'],
            "log_dir": wf_dir,
            "cloud": wf_pwargs.cloud,
            "pf_dir": wfbuilder.Path("./properties_files"),
            "scripts": wfbuilder.Path("./scripts"),
            "pub_keys": wfbuilder.Path("./authorized_keys")
        },
        logs = {
            "stdout": wf_dir + "/scheduler.out",
            "stderr": wf_dir + "/scheduler.err"
        },
        stream_host = "localhost",
        stream_port = os.environ['PARSL_CLIENT_SSH_PORT']
    )
    return sched_runner.run()


# ---- RUN WORKFLOW --- #
if __name__ == "__main__":
    # Runs only when executed (not when imported)
    parsl.load(pwconfig)
    sched_fut = run(pwargs)

    try:
        sched_fut.result()
    except:
        print('Workflow failed!')

        pool_info = get_pool_info(
            get_pool_name(),
            'https://' + os.environ['PARSL_CLIENT_HOST'] +"/api/resources?key=" + os.environ['PW_API_KEY']
        )
        print(json.dumps(pool_info, indent = 4))

        # If workflow was not killed by turning off the pool send an alert!
        if pool_info['status'] == 'on':
            job = os.path.basename(os.getcwd())
            msg = "START_SCHEDULER workflow failed! @avidalto"
            post_to_slack(msg, e = None)