#!/usr/bin/python3
"""Write inputs.sh from inputs.json.

The platform no longer writes inputs.json and inputs.sh into the job directory, so
the workflow YAML writes inputs.json from the form values and runs this script,
which validates it and derives inputs.sh the way input_form_resource_wrapper.py
flattens the resource inputs: nested keys joined with "_" and booleans in
lowercase, so main.sh can source it.
"""
import json
import sys


def flatten(values, prefix=''):
    for key, value in values.items():
        if isinstance(value, dict):
            yield from flatten(value, f'{prefix}{key}_')
        else:
            yield f'{prefix}{key}', value


def to_shell(value):
    if isinstance(value, bool):
        return str(value).lower()
    # An input the form hid and ignored renders empty or as "undefined"
    if value is None or value == 'undefined':
        return ''
    return str(value)


if __name__ == '__main__':
    with open('inputs.json') as f:
        contents = f.read()
    try:
        inputs = json.loads(contents)
    except ValueError as error:
        # A value the platform did not render leaves invalid JSON: fail here, with the
        # file in the log, instead of later inside the resource wrapper
        print(f'ERROR: inputs.json is not valid JSON ({error}):\n{contents}', file=sys.stderr)
        sys.exit(1)

    with open('inputs.sh', 'w') as f:
        for key, value in flatten(inputs):
            f.write(f'export {key}="{to_shell(value)}"\n')

    with open('inputs.sh') as f:
        print(f.read(), end='')
