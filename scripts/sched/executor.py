import math
import os
import glob

class AggregatedExecutor():
    def __init__(self, pool_info, pool_names, allow_idle_cores = True):
        self.pools = self.get_pools(pool_info, pool_names)
        self.pool_names = [ p["name"] for p in self.pools ]
        self.allow_idle_cores = allow_idle_cores
        self.supply = self.get_supply(pool_names)

    # FIXME: Not the cleanest way of doing this.
    # When a cjs command is submitted a file is written to '/tmp/pname-**' using mkstemp
    def get_supply(self, pool_names):
        cjs_by_pool = dict.fromkeys(pool_names, 0)
        for pname in pool_names:
            cjs_by_pool[pname] = len(glob.glob('/tmp/' + pname + "-**"))
        return cjs_by_pool

    def get_pools(self, pool_info_data, pool_names):
        # Only use executor pools
        exec_pools = [pool for pool in pool_info_data if pool['name'] in pool_names]
        # Only use pools with more than 1 vCPU
        exec_pools = [pool for pool in exec_pools if int(pool['info']['cpuPerWorker']) > 1]
        # Handle contradictory pool settings:
        # In case a pool is off or has no serviceport --> Set min/max sliders to zero
        #                                             --> Delete cjs submissions records
        for pool in exec_pools:
            service_port = str(pool['info']['ports']['serviceport'])
            if pool["status"] == "off" or not service_port.isdigit():
                pool["settings"]["min"] = 0
                pool["settings"]["max"] = 0
                # FIXME: Not the cleanest place to do this!
                # - Delete all cjs submission records to this pool
                [os.remove(f) for f in glob.glob('/tmp/' + pool['name'] + "-**")]

        # Sort pools by number of vcpus
        cpus_per_pool = [int(pool['info']['cpuPerWorker'])/2 for pool in exec_pools]
        if cpus_per_pool:
            cpus_per_pool, indices = zip(*sorted(zip(cpus_per_pool, range(len(cpus_per_pool))), reverse = True))
        else:
            indices = []
        # Remove pools with duplicate number of vCPUs
        exec_pools = [exec_pools[i] for i in indices if cpus_per_pool[i] not in cpus_per_pool[:i]]
        return exec_pools

    def get_cores(self):
        core_supply = 0
        for pool in self.pools:
            pool_cpus = int(int(pool['info']['cpuPerWorker'])/2)
            core_supply += pool_cpus * self.supply[pool["name"]]
        return core_supply

    def get_overdemand(self, core_demand, od_frac):
        core_supply = self.get_cores()
        overdemand = core_demand - core_supply
        overdemand = math.ceil(overdemand * float(od_frac))
        pool_names = [p["name"] for p in self.pools]
        exec_overdemand = dict.fromkeys(pool_names, 0)

        # Step 1: Send packets to pools with min slider > 1 from small to large
        # From small to large
        self.pools.reverse()
        for pool in self.pools:
            running_workers = self.supply[pool["name"]]
            min_slider =  pool['settings']['min']
            needed_workers = max(0, min_slider - running_workers)
            if needed_workers > 0:
                pool_cpus = int(int(pool['info']['cpuPerWorker'])/2)
                overdemand += - needed_workers * pool_cpus
                exec_overdemand[pool["name"]] += needed_workers
                self.supply[pool["name"]] += needed_workers

        # Step 2: Send at least min_workers per pool type
        min_workers = 0 # Deactivated
        # From small to large
        for pool in self.pools:
            running_workers = self.supply[pool["name"]]
            pool_cpus = int(int(pool['info']['cpuPerWorker'])/2)
            demanded_workers = int(overdemand / pool_cpus)
            needed_workers = min(min_workers - running_workers, demanded_workers, pool['settings']['max'] - running_workers)
            if needed_workers > 0:
                overdemand += - needed_workers * pool_cpus
                exec_overdemand[pool["name"]] += needed_workers
                self.supply[pool["name"]] += needed_workers

        # Step 3: Minimize number of full nodes
        # From large to small
        self.pools.reverse()
        for pool in self.pools:
            pool_cpus = int(int(pool['info']['cpuPerWorker'])/2)
            demanded_workers = int(overdemand / pool_cpus)
            running_workers =  self.supply[pool["name"]]
            needed_workers = min(demanded_workers, pool['settings']['max'] - running_workers)
            if needed_workers > 0:
                overdemand += - needed_workers * pool_cpus
                exec_overdemand[pool["name"]] += needed_workers
                self.supply[pool["name"]] += needed_workers

        # Step 4: Distribute remaining packets to the smallest possible node
        if self.allow_idle_cores and overdemand > 0:
            # From small to large
            self.pools.reverse()
            for pool in self.pools:
                if pool['settings']['max'] > self.supply[pool["name"]]:
                    pool_cpus = int(int(pool['info']['cpuPerWorker'])/2)
                    overdemand += - pool_cpus
                    exec_overdemand[pool["name"]] += 1
                    self.supply[pool["name"]] += 1
                    break
            # Return to original: from large to small
            self.pools.reverse()

        return exec_overdemand

    def get_priority(self):
        npools = len(self.pools)
        self.priority = dict.fromkeys(self.pool_names, None)
        for pi, pool in enumerate(self.pools):
            priority = []
            max_workers = pool["settings"]["maxWorkers"]
            for worker in range(self.supply[pool["name"]]):
                priority.append(round((pi+1) * (1 -  worker/max_workers)/npools, len(str(max_workers))))
            # Make sure first values have lower priorities
            priority.reverse()
            self.priority[pool["name"]] = priority



# For debugging
if __name__ == "__main__":
    import sys, json
    core_demand = int(sys.argv[1])
    pool_info_json = sys.argv[2]
    pool_names = sys.argv[3].split("---")
    # Load Pool info:
    with open(pool_info_json, 'r') as json_file:
        pool_info = json.load(json_file)

    # Define executor
    exec_supply = dict.fromkeys(pool_names, 1)
    Executor = AggregatedExecutor(pool_info, pool_names, exec_supply)
    print("Executor supply:")
    print(Executor.supply)
    # Calculate executor overdemand - Minimizing number of nodes
    exec_overdemand = Executor.get_overdemand(core_demand)
    print("Executor over demand:")
    print(exec_overdemand)
    print(Executor.supply)
    Executor.get_priority()
    print(Executor.priority)
    pw_http="http://beta2.parallel.works"
    exec_work_dir = "exec_work_dir"
    gt_user = "gt_user"
    sched_ip = "123"
    for pname,nworkers in exec_overdemand.items():
        pool = [ pool for pool in pool_info if pool["name"] == pname][0]
        # Submit wait-till-iddle jobs to executors
        cpe = int(int(pool['info']['cpuPerWorker'])/2) # Cores per executor
        service_port = str(pool['info']['ports']['serviceport'])
        service_url = pw_http + ":" + service_port
        for i in range(nworkers):
            exec_priority = str(Executor.priority[pname][i])
            cmd = "/bin/bash {}/executor.sh {} {} {} {}".format(exec_work_dir, gt_user, sched_ip, str(cpe), exec_priority)
            print(cmd)
