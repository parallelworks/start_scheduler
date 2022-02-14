import parsl
import os
from parsl.app.app import python_app, bash_app
from parsl.data_provider.files import File
from .utils import Path
from .wfpools import get_pool_info, get_job_pool

from pprint import PrettyPrinter
pp = PrettyPrinter(indent = 4)

# FIXME: Find better streaming approach! Currently needs the /pw/modules/wftemplates/stream.sh file!
stream_script = "/pw/modules/wfbuilder/stream.sh"
if not os.path.isfile(stream_script):
    stream_script = os.getcwd() + "/wfbuilder/stream.sh"

# stream_host = "goofs.parallel.works"
class SimpleBashRunner():
    def __init__(self, cmd, cmd_arg_names = [], inputs = {}, outputs = {}, logs = {}, user = None, stream_host = None, stream_port = "", write_pool_info = False):
        self.cmd = str(cmd)
        self.cmd_arg_names = list(cmd_arg_names)
        self.inputs = dict(inputs)
        self.outputs = dict(outputs)
        # Optional logs (std.out and std.err)
        self.logs = dict(logs)
        if not "stdout" in self.logs:
            self.logs["stdout"] = None
        if not "stderr" in self.logs:
            self.logs["stderr"] = None

        # User to run command
        self.user = user
        # Optional streaming of logs
        self.stream_host = stream_host
        self.stream_port = stream_port
        # Write pool information of the pool where the job is running
        self.write_pool_info = write_pool_info
        self.api_key = os.environ['PW_API_KEY']

    def run(self):

        # Get pool information of the pool where the job is running
        if self.write_pool_info:
            pool_name = get_job_pool()
            pool_info = get_pool_info(pool_name, self.api_key)
            print("---- POOL INFO ----", flush = True)
            pp.pprint(pool_info)
        else:
            pool_info = {}

        cwd_dir = os.getcwd()
        # Check if streaming is activated (and has everything it needs)
        stream = False
        if self.stream_host is not None:
            if all(std is not None for std in self.logs.values()):
                if os.path.isfile(stream_script):
                    stream =  True
                else:
                    print("WARNING: Cannot find Streaming script {}!".format(stream_script), flush = True)
            else:
                print("WARNING: Must select standard output and error files for streaming!", flush = True)

        # Generate command for run_bash_app:
        def generate_command():
            command = [self.cmd]
            ios = {**self.inputs, **self.outputs} # Inputs and outputs dict
            for cmd_arg_name in self.cmd_arg_names:
                if cmd_arg_name in ios:
                    arg = ios[cmd_arg_name]
                else:
                    raise Exception("Parameter {} not found in inputs or outputs ({})".format(cmd_arg_name, ios))
                if hasattr(arg, 'path'):
                    if "/./" in arg.path: # arg.filename in /path/./to/file gives file instead of ./to/file
                        command.append("\"" + arg.path.split("/./")[-1] + "\"")
                    else:
                        command.append("\"" + arg.filename + "\"")
                else:
                    command.append("\"" + str(arg) + "\"")

            command = " ".join(command)
            if self.user is not None:
                command = "su {} -c \"{}\"".format(self.user, command.replace("\"","\\\""))
            return command

        # Cannot pass objects without an path attribute as inputs or outputs!
        def clean_ios(raw_ios):
            ios = []
            for io in raw_ios:
                if hasattr(io, 'path'):
                    ios.append(io)
            return ios

        @bash_app
        def run_bash_app(command, inputs = [], outputs = [], stdout = self.logs["stdout"], stderr = self.logs["stderr"], pool_info = {}):
            import os
            import subprocess
            subprocess.run(["sudo","service","docker","start"])

            # Write pool_info
            if pool_info:
                import json
                with open("pool_info.json", 'w') as json_file:
                    json.dump(pool_info, json_file, indent = 4)

            # Make sure directories for output files exist # FIXME: Doesn't work for DOE case only ???
            debug_f = open("DEBUG.txt", "w")
            debug_f.write("---- COMMAND ------ \n{}\n".format(command))
            debug_f.write("---- INPUTS ------- \n{}\n".format("\n".join([inp.path for inp in inputs])))
            debug_f.write("---- OUTPUTS ------ \n{}\n".format("\n".join([out.path for out in outputs])))
            debug_f.write("---- STD ---------- \n{}\n".format(str(stdout) + "\n" + str(stderr)))
            for o in outputs + [stdout, stderr]:
                if o is not None: # Do nothing if stdout or stderr is None
                    opath = os.path.abspath(o).replace(os.getcwd() + '/','')
                    odir = os.path.dirname(opath)
                if odir:
                    os.makedirs(odir, exist_ok=True)

            if stream:
                debug_f.write("---- STREAMING ---- \n")
                host_stdout = cwd_dir + "/" + stdout # cwd_dir is in PW
                host_stderr = cwd_dir + "/" + stderr
                cmd_stdout = ["bash", "stream.sh", str(self.stream_host), host_stdout, stdout, "30", self.stream_port]
                cmd_stderr = ["bash", "stream.sh", str(self.stream_host), host_stderr, stderr, "30", self.stream_port]
                debug_f.write(" ".join(cmd_stdout) + "\n")
                debug_f.write(" ".join(cmd_stderr) + "\n")
                out_popen = subprocess.Popen(cmd_stdout)
                err_popen = subprocess.Popen(cmd_stderr)
                command = command + "; sleep 30; kill " + " ".join([str(out_popen.pid), str(err_popen.pid)])
                debug_f.write("---- MODIFIED COMMAND ------ \n{}\n".format(command))

            debug_f.close()
            return command

        command = generate_command()
        inputs = clean_ios(list(self.inputs.values()))
        outputs = clean_ios(list(self.outputs.values()))
        output_keys = list(self.outputs.keys())
        print("---- COMMAND ----\n{}".format(command), flush = True)
        print("---- INPUTS  ----\n{}".format(" ".join([inp.path for inp in inputs])), flush = True)
        print("---- OUTPUTS ----\n{}".format(" ".join([out.path for out in outputs])), flush = True)
        print("---- STD --------\n{}".format(str(self.logs["stdout"]) + " " + str(self.logs["stderr"])), flush = True)
        # OPTIONAL: Stream standard output:
        if stream:
            print("---- STREAMING ----\n{}\n{}".format(str(self.stream_host), self.stream_port), flush = True)
            inputs.append(Path(stream_script))
            # Make sure local streaming directory exists
            for std in self.logs.values():
                local_path = os.path.abspath(std).replace(os.getcwd() + '/','')
                local_dir = os.path.dirname(local_path)
                if local_dir:
                    os.makedirs(local_dir, exist_ok=True)

        fut = run_bash_app(command, inputs = inputs, outputs = outputs, pool_info = pool_info)
        # For bash_apps with no outputs = []
        if not outputs:
            out = fut
        else:
            out = dict(zip(output_keys, fut.outputs))
        return out
