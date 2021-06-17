import os

# DATA FORMAT TRANSFORMATION FUNCTIONS

def csv2txts(csv_path, out_dir, exclude = [], sep = "=", txt_basename = "row.txt"):
    # Convert CSV file in the format:
    # x,y
    # 1,2
    # 3,4
    # To the files
    # 0/input.txt
    # 1/input.txt
    # In the format
    # x=1
    # y=2
    # - Read csv
    csv_f = open(csv_path, "r")
    csv_lines = [l.replace("\n","") for l in csv_f.readlines()]
    csv_f.close()
    txt_paths = []
    for k,line in enumerate(csv_lines):
        # Read header:
        if k == 0:
            pnames = line.split(',')
        else:
            # Define runner directory
            out_dir_i = out_dir + "/" + str(k-1)
            os.makedirs(out_dir_i, exist_ok=True)
            # Create input file:
            txt_path = out_dir_i + "/" + txt_basename
            txt_paths.append(txt_path)
            txt_f = open(txt_path, "w")
            pvalues = line.split(',')
            params = dict(zip(pnames,pvalues))
            for pname,pvalue in params.items():
                if pname not in exclude:
                    txt_f.write(pname + sep + pvalue + "\n")
            txt_f.close()
    return txt_paths

def txts2csv(txt_paths, csv_path, exclude = [], sep = "="):
    if hasattr(csv_path, 'path'):
        csv_path = csv_path.path
    # Inverse of csv2txts:
    csv_f = open(csv_path, "w")
    for i,txt_path in enumerate(txt_paths):
        if hasattr(txt_path, 'path'):
            txt_path = txt_path.path
        txt_f = open(txt_path, "r")
        txt_lines = [l.replace("\n","") for l in txt_f.readlines()]
        txt_f.close()
        pnames = [line.split(sep)[0] for line in txt_lines]
        pvalues = [sep.join(line.split(sep)[1:]) for line in txt_lines]
        included = []
        for pnum,pname in enumerate(pnames):
            if pname not in exclude:
                included.append(pnum)
        pnames = [str(pnames[pnum]) for pnum in included]
        pvalues = [str(pvalues[pnum]) for pnum in included]
        params = dict(zip(pnames,pvalues))
        if i == 0:
            header = pnames
            invalid_pnames = []
            for ipn in pnames:
                if "," in ipn:
                    invalid_pnames.append(ipn)
            if invalid_pnames:
                csv_f.write("Names cannot contain the [,] character! Rule violating names:\n")
                [csv_f.write(pname + "\n") for pname in invalid_pnames]
                csv_f.close()
                return
            #invalid_pnames = [ ipn if "," in ipn for ipn in pnames ]
            csv_f.write(",".join(header) + "\n")
            csv_f.write(",".join(pvalues) + "\n")
        else:
            # To make sure order is correct and parameter is present
            pvalues = [ params[pname] for pname in header ]
            csv_f.write(",".join(pvalues) + "\n")
