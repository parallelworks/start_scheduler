import sys
import json
from pprint import PrettyPrinter
import datetime

pp = PrettyPrinter(depth=4)

# usage / limit
alert_fracs = [0.5, 0.75, 0.9, 1, 1.05, 1.1]

def initialize(limits):
    alerts = dict.fromkeys(limits.keys())
    for prod in alerts.keys():
        alerts[prod] = dict.fromkeys(alert_fracs)
        for af in alert_fracs:
            alerts[prod][af] = {"sent": False, "date": None}
    return alerts
    
def send(pname, plim, used, alim):
    used = round(used/3600)
    plim = round(plim/3600)
    if alim < 1:
        percentage = str(alim*100)
        msg = "You have used more than {}% of {} hours (used: {}, max: {}). Contact GT sales if you need to purchase more hours."
        msg = msg.format(percentage, pname, str(used), str(plim)) 
    elif alim == 1:
        msg = "You have used all the hours of {} (used: {}, max: {}). Contact GT sales to purchase more hours."
        msg = msg.format(pname, str(used), str(plim))
    else:
        msg = "You have now run {} hours past your allotted {} solver hours (used: {}, max: {}). Please contact GT sales immediately to arrange for the purchase of these already used hours."
        msg = msg.format(str(used-plim), pname, str(used), str(plim))
    print(msg)

    

def check(limits, usage, alerts):
    for pname,plim in limits.items():
        used = usage[pname]
        uratio = used/plim
        for alim,aval in alerts[pname].items():
            if uratio >= float(alim):
                if not aval["sent"]:
                    send(pname, plim, used, float(alim))
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
