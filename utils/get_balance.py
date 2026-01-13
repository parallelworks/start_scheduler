#!/usr/bin/python3
import os
import requests
import argparse
import json
from base64 import b64encode

def encode_string_to_base64(text):
    # Convert the string to bytes
    text_bytes = text.encode('utf-8')
    # Encode the bytes to base64
    encoded_bytes = b64encode(text_bytes)
    # Convert the encoded bytes back to a string
    encoded_string = encoded_bytes.decode('utf-8')
    return encoded_string

# This script needs to run in the user container to access the PW_API_KEY
# Therefore, it is called by the main script using the reverse ssh tunnel
# Prints the balance in json format

PW_PLATFORM_HOST = os.environ.get('PW_PLATFORM_HOST')
HEADERS = {"Authorization": "Basic {}".format(encode_string_to_base64(os.environ['PW_API_KEY']))}
# FIXME: Get from license server
GT_PRODUCTS = ['gtlinear', 'gtpowerx', 'gtsuite', 'gtautoliononed', 'gtpowerxrt', 'gtxchem', 'gtfemag', 'gtautothreedflow', 'gtautomation', 'cosimthermal', 'gtadvancedcombustion', 'gtautolionthreed', 'gtjmagmachine', 'gtthreedmbd', 'gtthreedmbdadvancedtribology', 'gtthreedmbdmachinery', 'gtthreedmbdvehicledynamics']

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
            if 'used' in group['allocations']:
                allocation_used = group['allocations']['used']
            else:
                allocation_used = 0
            
            if 'total' in group['allocations']:
                allocation_total = group['allocations']['total']
            else:
                allocation_total = 0
            balance[product_name] = allocation_total-allocation_used 
    
    print(json.dumps(balance), flush = True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Process customer_name, customer_org_id and customer_org_name')
    parser.add_argument('--customer_name', type=str, help='Name of the customer')
    parser.add_argument('--customer_org_id', type=str, help='Organization ID of the customer')
    parser.add_argument('--customer_org_name', type=str, help='Organization name of the customer')
    args = parser.parse_args()
    # Customers of the PW managed solution all share the same user account in PW. 
    # Therefore, the customer name is used to identify each customer. 
    # The customer name is used to create groups with license hour allocations
    # The names of these groups are in the format <customer_name>-<gt_product_name>
    customer_name = args.customer_name
    # Org ID obtained from here https://cloud.parallel.works/api/v2/organization
    # Users of the PW managed solution will all be under the same organization
    customer_org_id = args.customer_org_id 
    customer_org_name = args.customer_org_name 

    group_names = [f'{customer_name}-{gt_prod}' for gt_prod in GT_PRODUCTS]

    GT_ORGANIZATION_URL = f'https://{PW_PLATFORM_HOST}/api/organizations/{customer_org_name}/groups?organization={customer_org_id}'

    res = requests.get(GT_ORGANIZATION_URL, headers = HEADERS)
    existing_groups = [group['name'] for group in res.json()]

    #check_group_existence(group_names, existing_groups)

    get_balance(group_names, res)