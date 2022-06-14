#!/bin/bash

# INPUTS:
pf_dir="./properties_files"
coaster_host=localhost

# WORKFLOW:
job_number=$(basename ${PWD})
remote_dir=/tmp/pworks/job-${job_number}

# Read arguments in format "--pname pval" into export pname=pval
f_read_cmd_args(){
    index=1
    args=""
    for arg in $@; do
	    prefix=$(echo "${arg}" | cut -c1-2)
	    if [[ ${prefix} == '--' ]]; then
	        pname=$(echo $@ | cut -d ' ' -f${index} | sed 's/--//g')
	        pval=$(echo $@ | cut -d ' ' -f$((index + 1)))
	        echo "export ${pname}=${pval}" >> $(dirname $0)/env.sh
	        export "${pname}=${pval}"
	    fi
        index=$((index+1))
    done
}

# Map all files the directory dname to the remote directory in the cjs format
get_dir_stagein() {
    local dname=$1
    for f in $(find ${dname} -type f); do
        if [ -z "${stagein}" ]; then
            stagein="${PWD}/${f} -> ${remote_dir}/${f}"
        else
            stagein="${stagein} : ${PWD}/${f} -> ${remote_dir}/${f}"
        fi
    done
    echo ${stagein}
}

# Set serviceport variable with the service port number of a pool provided the name of the pool
get_pool_serviceport() {
    local scheduler_pool=$1

    max_retries=20
    k=0
    while true; do
        k=$((k+1))
        if [ "${k}" -gt "${max_retries}" ]; then
	        echo "Max retries have been reached. Giving up."
	        exit 1
        fi
        echo "Searching for service port"
        serviceport=$(curl -s https://${PARSL_CLIENT_HOST}/api/resources?key=${PW_API_KEY} | grep -E 'name|serviceport' | tr -d '", ' | sed 'N;s/\n/=/' | grep name\:${scheduler_pool}= | rev | cut -d':' -f1 | rev)
        if [[ ${serviceport} -gt 0 ]]; then
	        break
        else
	        echo "No service port found. Make sure pool is turned on!"
	        echo "Trying again ..."
	        sleep 30
        fi
    done
}


f_read_cmd_args $@

scripts=$(get_dir_stagein scripts)
properties_files=$(get_dir_stagein ${pf_dir})
scheduler_pool=$(echo ${scheduler_pool} | tr '[:upper:]' '[:lower:]')

stagein="
    ${scripts} : \
    ${properties_files} : \
    ${PWD}/authorized_keys -> ${remote_dir}/authorized_keys : \
    ${PWD}/stream.sh -> ${remote_dir}/stream.sh"



get_pool_serviceport ${scheduler_pool}
COASTERURL=http://${coaster_host}:${serviceport}
echo "Coaster URL: $COASTERURL"

echo "For more logs, open scheduler.out and scheduler.err log files once they appear in the job directory."


cjs_args="${executor_pools} ${version} ${sum_serv} ${ds_cycle} ${od_pct} ${PW_API_KEY} ${pf_dir} ${cloud} ${PARSL_CLIENT_SSH_PORT} ${PWD} ${PARSL_CLIENT_HOST} "

cog-job-submit -provider "coaster-persistent" \
               -service-contact "$COASTERURL" \
    	       -attributes "maxWallTime=99999:00:00" \
               -redirected \
               -stdout "${remote_dir}/scheduler.out" \
               -stderr "${remote_dir}/scheduler.err" \
    	       -directory "${remote_dir}" \
               -stagein "${stagein}" \
    	       bash -c "mkdir -p ${remote_dir}; cd ${remote_dir}; bash ./scripts/scheduler.sh ${cjs_args}"


# Send alert if job failed!
pool_status=$(curl -s https://${PARSL_CLIENT_HOST}/api/resources?key=${PW_API_KEY} | grep -E 'name|status' | tr -d '", ' | sed 'N;s/\n/=/' | grep ${scheduler_pool}= | rev | cut -d':' -f1 | rev)
if [[ ${pool_status} == "on" ]]; then
    msg="Failed START_SCHEDULER job ${job_number} in account ${PW_USER} - @avidalto"
    cat alert_slack.sh | sed "s|__MSG__|${msg}|g" > alert_slack_.sh
    bash alert_slack_.sh
fi
