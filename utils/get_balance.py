#!/pw/.miniconda3/bin/python
import os
import requests
import sys
import json

# This script needs to run in the user container to access the PW_API_KEY
# Therefore, it is called by the main script using the reverse ssh tunnel
# Prints the balance in json format

PW_PLATFORM_HOST = os.environ.get('PW_PLATFORM_HOST')
PW_API_KEY = os.environ.get('PW_API_KEY')
GT_ORGANIZATION_ID = '63572a4c1129281e00477a0c'
GT_ORGANIZATION_URL = f'https://{PW_PLATFORM_HOST}/api/v2/organization/teams?organization={GT_ORGANIZATION_ID}&key={PW_API_KEY}'
# FIXME: Get from license server
GT_PRODUCTS = ['gtsuite', 'gtautoliononed', 'gtpowerxrt']

def check_group_existence(group_names, existing_groups):
    """Check if all group names exist in the retrieved groups."""
    for group_name in group_names:
        if group_name not in existing_groups:
            raise ValueError(f"Group '{group_name}' not found.")


def get_balance(group_names, res):
    balance = {gt_product: 0 for gt_product in GT_PRODUCTS}

    for group in res.json():
        if group['name'] in group_names:
            product_name = group['name'].split('-')[-1]
            allocation_used = group['allocations']['used']['value']
            allocation_total = group['allocations']['total']['value']
            balance[product_name] = allocation_total-allocation_used 
    
    print(json.dumps(balance), flush = True)

if __name__ == '__main__':
    group_names = sys.argv[1].split('---')

    res = requests.get(GT_ORGANIZATION_URL)
    existing_groups = [group['name'] for group in res.json()]

    check_group_existence(group_names, existing_groups)

    get_balance(group_names, res)

    