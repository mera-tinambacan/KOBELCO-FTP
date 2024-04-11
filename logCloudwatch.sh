#!/bin/bash

LOG_GROUP_NAME="HostToIPA"
LOG_STREAM_NAME="RHEL6-HostToIPA-Stream"
LOG_FILE="file2.log"

# Function to send log event to CloudWatch Logs
send_log_event() {
    local log_event=$1
    aws logs put-log-events \
        --log-group-name "$LOG_GROUP_NAME" \
        --log-stream-name "$LOG_STREAM_NAME" \
        --log-events "$log_event"
}

# Send each line to CloudWatch Logs
while IFS= read -r line; do
    timestamp=$(date -u +%s%3N)
    # Escape double quotes in the log message and convert to JSON
    log_event=$(jq -n --argjson ts "$timestamp" --arg msg "$line" '{"timestamp":$ts|tonumber, "message":$msg}')
    # Send log event to CloudWatch Logs
    send_log_event "$log_event"
done < "$LOG_FILE"
