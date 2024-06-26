#!/bin/bash
#sed -i "s|.*JOB_STATUS.*|    \"JOB_STATUS\": \"Canceled\",|" service.json
source utils/workflow-libs.sh
cancel_jobs_by_script
