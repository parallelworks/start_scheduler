import shutil,os
import importlib
import json
import time

def import_workflow(workflow_name):
    time.sleep(1) # FIXME: To prevent strange bug that happens when calling import_workflow
    # Relative path to directory of the workflow to be imported
    iwf_reldir = "imported_workflows"
    os.makedirs(iwf_reldir, exist_ok = True)
    # Absolute path to directory of the workflow to be imported
    iwf_dir = "/pw/workflows/" + workflow_name
    # Absolute path to the main.py of the workflow to be imported
    iwf_main_path = iwf_dir + "/main.py"
    # Relative path to the main.py of the workflow to be imported
    iwf_main_relpath = iwf_reldir + "/" + workflow_name + ".py"
    # Copying file
    shutil.copyfile(iwf_main_path, iwf_main_relpath)
    # MERGING REMOTEPACKS FILES:
    # Read current rpacks to avoid writing duplicated rpacks:
    rpacks_f = open("remotepacks", "r")
    rpacks = rpacks_f.readlines()
    rpacks_f.close()
    rpacks = list(set([l.replace("\n","") for l in rpacks]))
    # Appending imported wf rpacks to importing workflow rpacks
    # - Make sure importing workflow rpacks ends with new line!
    addnewline = not open("remotepacks", "r").readlines()[-1].endswith("\n")
    rpacks_f = open("remotepacks", "a") # Importing workflow
    if addnewline:
        rpacks_f.write("\n")
    irpacks_f = open(iwf_dir + "/remotepacks", "r") # Imported workflow
    irpacks = irpacks_f.readlines()
    for rpack in irpacks:
        rpack = rpack.replace("\n", "")
        if rpack not in rpacks:
            rpacks_f.write(rpack + "\n")
    rpacks_f.close()
    irpacks_f.close()
    return importlib.import_module("." + workflow_name, package = iwf_reldir)


# DEPRECATED
def recursive_workflow_import(wfparams):
    for wfname, wfparams_in in wfparams.items():
        print("Importing workflow {}".format(wfname))
        _ = import_workflow(wfname)
        for pname, pval in wfparams_in.items():
            if pname == "wfparams_json":
                with open(pval, 'r') as json_file:
                    wfparams_in_in = json.load(json_file)
                recursive_workflow_import(wfparams_in_in)