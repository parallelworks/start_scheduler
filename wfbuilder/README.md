wimport.py: import workflows or connectors by names
data_reformat.py: Convert data in one format to another (from csv to various txt, json2csv, ...)


All connectors return a list of or single wf_pwargs namespace
wf_connectors.py: update wf_pwargs based on the workflows involved
dformat_connectors.py: update wf_pwargs based on input data format (csv, json, txt, ...)
