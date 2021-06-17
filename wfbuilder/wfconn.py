from argparse import Namespace

def get_wf_pwargs(wf_pwargs_dict, wf_io):
    wf_conn = {}
    for pname,pval in wf_pwargs_dict.items():
        if type(pval) == str: # Need this for nested workflows
            if pval in wf_io.keys():
                wf_pwargs_dict[pname] = wf_io[pval]
                wf_conn[pval] = pname
    return Namespace(**wf_pwargs_dict), wf_conn
