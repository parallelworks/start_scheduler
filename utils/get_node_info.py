#!/usr/bin/python3
import os
import sys
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

PW_PLATFORM_HOST = os.environ.get('PW_PLATFORM_HOST')
HEADERS = {"Authorization": "Basic {}".format(encode_string_to_base64(os.environ['PW_API_KEY']))}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Process resource_name, resource_namespace and org_name')
    parser.add_argument('--resource_name', type=str, help='Name of the resource')
    parser.add_argument('--resource_namespace', type=str, help='Namespace (owner user) of the resource')
    parser.add_argument('--org_name', type=str, required=True, help='Name of the organization of the resource owner')
    args = parser.parse_args()

    URL = f'https://{PW_PLATFORM_HOST}/api/organizations/{args.org_name}/users/{args.resource_namespace}/clusters/{args.resource_name}/nodes'

    # includeFailed is required because the API omits failed nodes by default and
    # the scheduler uses this output precisely to detect failed nodes
    res = requests.get(URL, headers=HEADERS, params={'includeFailed': 'true'})

    if res.status_code != 200:
        sys.exit(f'ERROR: GET {URL} returned status code {res.status_code}: {res.text[:500]}')

    try:
        nodes = res.json()
    except ValueError:
        sys.exit(f'ERROR: GET {URL} did not return valid JSON: {res.text[:500]}')

    if nodes is None:
        nodes = []

    # The API exposes the node hostname under "name" but consumers of this output
    # (jq in scheduler-libs.sh) select nodes by the "hostname" key
    for node in nodes:
        node['hostname'] = node.get('name')

    print(json.dumps(nodes, indent=4))
