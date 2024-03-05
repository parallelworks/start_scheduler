#!/bin/bash
source inputs.sh
bash stream.sh &
stream_pid=$!
echo "kill ${stream_pid} 2>/dev/null" >> cancel.sh


# Set the duration for the loop (in seconds)
duration=$((30 * 60))  # 30 minutes
interval=2            # 2 seconds interval

# Calculate the end time
end_time=$((SECONDS + duration))

# Create a file to write the dates
output_file="dates.txt"

# Loop until the end time is reached
while [ $SECONDS -lt $end_time ]; do
    # Write the current date and time to the file
    date
    # Wait for the specified interval
    sleep $interval
done
