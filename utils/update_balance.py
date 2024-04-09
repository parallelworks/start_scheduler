#!/pw/.miniconda3/bin/python
import os
import requests
import sys
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

PW_PLATFORM_HOST = os.environ.get('PW_PLATFORM_HOST')
HEADERS = {"Authorization": "Basic {}".format(encode_string_to_base64(os.environ['PW_API_KEY']))}

def get_group_id_by_name(group_name, customer_org_id):

    url = f'https://{PW_PLATFORM_HOST}/api/v2/organization/teams?organization={customer_org_id}'

    res = requests.get(url, headers = HEADERS)

    for group in res.json():
        if group['name'] == group_name:
            return group['id']

def update_group_allocation(orgname, groupId, allocation_used):
    url = f"https://{PW_PLATFORM_HOST}/api/v2/organization/teams/{groupId}"
    payload = {
        "allocation_used": allocation_used
    }
    response = requests.put(url, json=payload,  headers = HEADERS)
    #return response.json()

def main(orgname, customer_org_id, groupname, allocation_used):
    groupId = get_group_id_by_name(groupname, customer_org_id)
    update_group_allocation(orgname, groupId, allocation_used)

if __name__ == '__main__':
    orgname = 'gtmanagedbypw'
    # Org ID obtained from here https://cloud.parallel.works/api/v2/organization
    customer_org_id = '6602e0d4c2750c88894e08d5'
    groupname = 'gtbeta-gtsuite'
    allocation_used = 2
    main(orgname, customer_org_id, groupname, allocation_used)
