import sys,re,os,json
import datetime

product_names = ["GTAdvancedCombustion", "GTAutoLionOneD", "GTpowerX", "GTsuite"]

def get_lic_info(out):
    out_f = open(out, "r")
    out_lines = [jl.replace("\n","") for jl in out_f.readlines()]
    out_f.close()
    lic_info = {} #dict.fromkeys(product_names)
    for out_line in out_lines:
        for product in product_names:
            if out_line.startswith("Users of {}".format(product)):
                issued = re.findall('\d+', out_line.split(":")[1])[0]
                used = re.findall('\d+', out_line.split(":")[1])[1]
                lic_info[product] = {"issued": int(issued), "used": int(used)}
                break
    return lic_info

#{"GTpowerX": 0, "GTsuite": 0.0, "GTAdvancedCombustion": 0.0, "GTAutoLionOneD": 1133.274986}
def update_usage(usage, lic_info):
    if usage:
        # Last time file was modified
        last_mod = datetime.datetime.strptime(usage["last_updated"], "%m/%d/%Y, %H:%M:%S")
        # datetime.datetime.fromtimestamp(os.path.getmtime(usage_json))
        usage["last_updated"] = datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S")
        for product,lics in lic_info.items():
            usage[product] += lics["used"] * (datetime.datetime.now()-last_mod).total_seconds()
    else:
        usage = dict.fromkeys(lic_info.keys(), 0)
        usage["last_updated"] = datetime.datetime.now().strftime("%m/%d/%Y, %H:%M:%S")
    return usage
