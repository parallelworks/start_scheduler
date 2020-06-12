import boto3
from botocore.exceptions import ClientError
import sys
import json
from pprint import PrettyPrinter
import datetime

pp = PrettyPrinter(depth=4)

# usage / limit
alert_fracs = [0.5, 0.75, 0.9, 1, 1.05, 1.1]
CC = "alvaro@parallelworks.com"
RECIPIENT = "alvarovidalto@gmail.com"

def initialize(limits):
    alerts = dict.fromkeys(limits.keys())
    for prod in alerts.keys():
        alerts[prod] = dict.fromkeys(alert_fracs)
        for af in alert_fracs:
            alerts[prod][af] = {"sent": False, "date": None}
    return alerts

def create_msg(pname, plim, used, alim):
    used = round(used/3600)
    plim = round(plim/3600)
    if alim < 1:
        percentage = str(int(alim*100))
        msg = "You have used more than {}% of {} hours (used: {}, max: {}). Contact GT sales if you need to purchase more hours."
        msg = msg.format(percentage, pname, str(used), str(plim))
    elif alim == 1:
        msg = "You have used all the hours of {} (used: {}, max: {}). Contact GT sales to purchase more hours."
        msg = msg.format(pname, str(used), str(plim))
    else:
        msg = "You have now run {} hours past your allotted {} solver hours (used: {}, max: {}). Please contact GT sales immediately to arrange for the purchase of these already used hours."
        msg = msg.format(str(used-plim), pname, str(used), str(plim))
    return msg

def send_email(RECIPIENT, CC,  msg):
    # Replace sender@example.com with your "From" address.
    # This address must be verified with Amazon SES.
    SENDER = "Parallel Works <alvaro@parallelworks.com>"
    BCC = SENDER
    # Replace recipient@example.com with a "To" address. If your account
    # is still in the sandbox, this address must be verified.
    #RECIPIENT = "alvarovidalto@gmail.com"

    # Specify a configuration set. If you do not want to use a configuration
    # set, comment the following variable, and the
    # ConfigurationSetName=CONFIGURATION_SET argument below.
    #CONFIGURATION_SET = "ConfigSet"

    # If necessary, replace us-west-2 with the AWS Region you're using for Amazon SES.
    AWS_REGION = "us-east-1"

    # The subject line for the email.
    SUBJECT = "GT USAGE ALERT"

    # The email body for recipients with non-HTML email clients.
    BODY_TEXT = ("GT USAGE ALERT\r\n"
                 "".format(msg))

    # The HTML body of the email.
    BODY_HTML = """<html>
    <head></head>
    <body>
      <h1>GT USAGE ALERT</h1>
      <p>{}</p>
    </body>
    </html>
                """.format(msg)

    # The character encoding for the email.
    CHARSET = "UTF-8"

    # Create a new SES resource and specify a region.
    client = boto3.client('ses', region_name=AWS_REGION)

    # Try to send the email.
    try:
        #Provide the contents of the email.
        response = client.send_email(
            Destination={
                'ToAddresses': [
                    RECIPIENT,
                ],
                'CcAddresses': [
                    CC,
                ],
                'BccAddresses': [
                    BCC,
                ],
            },
            Message={
                'Body': {
                    'Html': {
                        'Charset': CHARSET,
                        'Data': BODY_HTML,
                    },
                    'Text': {
                        'Charset': CHARSET,
                        'Data': BODY_TEXT,
                    },
                },
                'Subject': {
                    'Charset': CHARSET,
                    'Data': SUBJECT,
                },
            },
            Source=SENDER,
            # If you are not using a configuration set, comment or delete the
            # following line
            #ConfigurationSetName=CONFIGURATION_SET,
        )
        # Display an error if something goes wrong.
    except ClientError as e:
        print(e.response['Error']['Message'])
    else:
        print("Email sent! Message ID:"),
        print(response['MessageId'])

def check(limits, usage, alerts):
    for pname,plim in limits.items():
        used = usage[pname]
        uratio = used/plim
        for alim,aval in alerts[pname].items():
            if uratio >= float(alim):
                if not aval["sent"]:
                    msg = create_msg(pname, plim, used, float(alim))
                    send_email(RECIPIENT, CC, msg)
                    aval["sent"] = True
                    aval["date"] = datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S")
            else: # If for some reason the limits are updated
                aval["sent"] = False
                aval["date"] = None
    return alerts


def update(alerts, usage, limits):
    if not alerts:
        alerts = initialize(limits)
    alerts = check(limits, usage, alerts)
    return alerts
