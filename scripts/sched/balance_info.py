import json
import os
import requests
from copy import deepcopy

# API use for now only use limit
def get_balance(pw_http, api_key):
    balance = {}
    response = requests.get('{}/api/account?key={}'.format(pw_http, api_key))
    for p in json.loads(response.text)['runhrs']['products']:
        balance[p['description'].lower()] = float(p['remain'])
    return balance

def read_sched_prop_file(sched_prop_file):
    sched_propf_info = {}
    sched_propf_info['max-licenses'] = {}
    sched_propf_info['permitted-licenses'] = []
    with open(sched_prop_file, 'r') as fp:
        Lines = fp.readlines()
        for line in Lines:
            if line.startswith('#'):
                continue

            if 'GTDistributed.scheduler.max-licenses' in line:
                pname = line.split('.')[3].split('=')[0].rstrip().lower().replace(' ','')
                pval = line.split('=')[1].rstrip().replace(' ','')
                sched_propf_info['max-licenses'][pname] = pval
            elif 'GTDistributed.scheduler.validation.permitted-licenses' in line:
                sched_propf_info['permitted-licenses'] = [pname.rstrip().lower().replace(' ','') for pname in line.split('=')[1].split(',')]

    return sched_propf_info


def write_sched_prop_file(sched_prop_file, sched_propf_info):
    fp = open(sched_prop_file, 'r')
    sched_propf_lines = fp.readlines()
    fp.close()
    with open(sched_prop_file, 'w') as fp:
        for line in sched_propf_lines:
            if line.startswith('#'):
                fp.write(line)
            elif 'GTDistributed.scheduler' not in line:
                fp.write(line)
            elif 'GTDistributed.scheduler.max-licenses' in line:
                pname = line.split('.')[3].split('=')[0].rstrip().lower()
                line_start = line.split('=')[0]
                fp.write(line_start + ' = ' + sched_propf_info['max-licenses'][pname] + '\n')
                sched_propf_info['max-licenses'][pname] = 'saved'
            elif 'GTDistributed.scheduler.validation.permitted-licenses' in line:
                permitted_licenses = [pl.upper() for pl in sched_propf_info['permitted-licenses']]
                fp.write('GTDistributed.scheduler.validation.permitted-licenses = ' + ','.join(permitted_licenses) + '\n')
                sched_propf_info['permitted-licenses'] = 'saved'
            else:
                fp.write(line)

        # Check that all properties file info were written!
        for pname, pval in sched_propf_info['max-licenses'].items():
            if pval != 'saved':
                fp.write('GTDistributed.scheduler.max-licenses.' + pname.upper() + ' = ' + pval + '\n')
        if sched_propf_info['permitted-licenses'] != 'saved':
            permitted_licenses = [pl.upper() for pl in sched_propf_info['permitted-licenses']]
            if len(permitted_licenses) == 1:
                permitted_licenses = permitted_licenses[0]
            else:
                permitted_licenses = ','.join(permitted_licenses)
            fp.write('GTDistributed.scheduler.validation.permitted-licenses = ' + permitted_licenses + '\n')


def check_balance(balance, sched_prop_file):
    sched_propf_info = read_sched_prop_file(sched_prop_file)
    # Set all licenses to zero by default!
    sched_propf_info['max-licenses'] = dict.fromkeys(sched_propf_info['max-licenses'].keys(), '0')
    sched_propf_info_new = deepcopy(sched_propf_info)
    warnings = []
    for pname, premain in balance.items():
        # - Are we going to have hard/soft limits per product?
        if float(premain) <= 0: # FIXME: Should be less than the soft or hard limits?
            warnings.append("No more core-hours left of product {}!".format(pname))
            warnings.append("Submission of new packets will be inhibited for this product.")

            sched_propf_info_new['max-licenses'][pname] = '0'
            if pname in sched_propf_info['permitted-licenses']:
                sched_propf_info_new['permitted-licenses'].remove(pname)
        else:
            sched_propf_info_new['max-licenses'][pname] = '-1'
            if pname not in sched_propf_info['permitted-licenses']:
                sched_propf_info_new['permitted-licenses'].append(pname)

    if sched_propf_info_new != sched_propf_info:
        [print(warning) for warning in warnings]
        write_sched_prop_file(sched_prop_file, sched_propf_info_new)


if __name__ == '__main__':
    balance = {'gtsuite': 1, 'gtpowerxrt': 1, 'gtautoliononed': 1}
    #balance = {'gtsuite': 1}
    check_balance(balance, 'sched.txt')

    import sys
    sys.exit()
    api_key = '12341a0e870c78aeeeff8cf980744b3c'
    pw_http = 'https://beta2.parallel.works'
    sched_work_dir='/var/opt/gtsuite/'
    gtdistd_ctrl =  sched_work_dir + '/run/gtdistd.ctrl'
    check_balance(pw_http, api_key, gtdistd_ctrl)
