import sys,re,os,json
import datetime

def get_lic_info(out, product_names):
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
def update_usage(usage_json, lic_info):
    if os.path.isfile(usage_json):
        # Load usage:
        with open(usage_json, 'r') as json_file:
            usage = json.load(json_file)

        # Last time file was modified
        last_mod = datetime.datetime.fromtimestamp(os.path.getmtime(usage_json))
        for product,lics in lic_info.items():
            usage[product] += lics["used"] * (datetime.datetime.now()-last_mod).total_seconds()

    else:
        usage = dict.fromkeys(lic_info.keys(), 0)

    with open(usage_json, 'w') as json_file:
        json.dump(usage, json_file, indent = 4)
    return usage