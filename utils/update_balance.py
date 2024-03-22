#!/pw/.miniconda3/bin/python
import os
import requests
import sys
import json

# This script needs to run in the user container to access the PW_API_KEY
# Therefore, it is called by the main script using the reverse ssh tunnel

PW_PLATFORM_HOST = os.environ.get('PW_PLATFORM_HOST')
PW_API_KEY = os.environ.get('PW_API_KEY')
# Org ID obtained from here https://cloud.parallel.works/api/v2/organization
GT_ORGANIZATION_ID = '63572a4c1129281e00477a0c'
GT_ORGANIZATION_URL = f'https://{PW_PLATFORM_HOST}/api/v2/organization/teams?organization={GT_ORGANIZATION_ID}&key={PW_API_KEY}'

def get_group_id_by_name(group_name):
    
    res = requests.get(GT_ORGANIZATION_URL)

    for group in res.json():
        if group['name'] in group_name:
            return group['id']

def update_group_allocation(orgname, groupId, allocation_used):
    url = f"https://{PW_PLATFORM_HOST}/api/v2/organization/teams/{groupId}?key={PW_API_KEY}"
    print(url)
    payload = {
        "allocation_used": allocation_used
    }
    response = requests.put(url, json=payload)
    print(response.json())
    #return response.json()

if __name__ == '__main__':
    orgname = 'parallelworks'
    allocation_used = 3
    groupId = get_group_id_by_name('alvaro-test')
    update_group_allocation(orgname, groupId, allocation_used)

