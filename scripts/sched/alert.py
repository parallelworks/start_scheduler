import socket
import os, json
import requests
from pathlib import Path

def post_to_slack_once(message, e=None):
    sent_file = message.replace(' ', '_').replace('!', '').replace(':', '')
    if not os.path.isfile(sent_file):
        post_to_slack(message, e = e)
        Path(sent_file).touch()

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
                    host = os.environ['USER'] + '@' + socket.gethostname()
                ),
            },
        }
    )
    url = "https://hooks.slack.com/services/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"

    requests.post(
        url, data=json.dumps(msg), headers={"Content-Type": "application/json"}
    )

