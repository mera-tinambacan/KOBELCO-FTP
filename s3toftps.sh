#!/bin/bash
# Script Name: s3toftps.sh
# Script Description: Transfer of File from S3 to FTPS
# Created by: AWS M. Tinambacan
# Creation Date: 4/1/2024
# Update:  4/4/2024 AWS R. Nuno
#                   Refactor Script
#                   Made several functions for each process.

# Source the parameter functions
source /home/ec2-user/s3toftps/parameter_function.sh

# Configuration
FTPS_SERVER="kobelco-dev.planning-analytics.cloud.ibm.com"
FTPS_DESTINATION_DIRECTORY="prod/connect_test"
S3_BUCKET="ipa-connect-budget/HostToIpa"
BACKUP_S3_BUCKET="ipa-connect-budget/HostToIpa-backup"
LOG_GROUP_NAME="HostToIPA"
LOG_STREAM_NAME="RHEL8-HostToIPA-Stream"

# Temporary directory to store the downloaded file
TEMP_DIR="/tmp"

# SNS Topic ARN for error notifications
SNS_TOPIC_ARN="arn:aws:sns:ap-northeast-1:282801688861:s3-to-IPA-topic"

# Function to put logs to CloudWatch
put_logs() {
    local status_code="$1"
    local log_level="$2"
    local message="$3"
    local timestamp=$(date +%s%3N)
    local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $message\"}"

    if [[ $status_code -ne 0 ]]; then
        # Publish error message to SNS
        aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "$log_level $message" --subject "ERROR $status_code"
    fi
    # Use the AWS CLI to put the log event
    aws logs put-log-events \
        --log-group-name "$LOG_GROUP_NAME" \
        --log-stream-name "$LOG_STREAM_NAME" \
        --log-events "$log_event" >/dev/null 2>&1
}

check_file_existence() {
    local s3_key="$1"
    put_logs "$?" "[INFO] Checking $s3_key from $S3_BUCKET..."
    if aws s3 ls "s3://$S3_BUCKET/$s3_key" &>/dev/null; then
        put_logs "$?" "[INFO]" "$s3_key found."
    else
        put_logs "$?" "[ERROR]" "$s3_key not found."
        exit $?
    fi
}

backup() {
    local s3_key="$1"
    put_logs "$?" "[INFO] Backing up $s3_key to s3://$BACKUP_S3_BUCKET/$s3_key..."
    if aws s3 cp "s3://$S3_BUCKET/$s3_key" "s3://$BACKUP_S3_BUCKET/$s3_key"; then
        put_logs "$?" "[INFO]" "$s3_key is successfully backed up."
    else
        put_logs "$?" "[ERROR]" "Failed to backup $s3_key."
        exit $?
    fi
}

copy_to_temp_dir() {
    local s3_key="$1"
    put_logs "$?" "[INFO]" "Copying $s3_key to s3://$S3_BUCKET/$s3_key" "$TEMP_DIR/$s3_key..."
    if aws s3 cp "s3://$S3_BUCKET/$s3_key" "$TEMP_DIR/$s3_key"; then
        put_logs "$?" "[INFO]" "$s3_key copied successfully."
    else
        put_logs "$?" "[ERROR]" "Failed to copy $s3_key."
        exit $?
    fi
}

fetch_credentials() {
    # Fetch FTP username and password from source
    if USERNAME=$(get_parameter "/ipa-test/username") && PASSWORD=$(get_parameter "/ipa-test/password"); then
        return 0
    else
        put_logs "$?" "[ERROR]" "$USERNAME"
        exit 1
    fi
}

transfer_files() {
    local s3_key="$1"
    put_logs "$?" "[INFO]" "Transferring $s3_key to ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY..."
    copy_to_temp_dir "$s3_key"
    fetch_credentials
    local local_file="$TEMP_DIR/$s3_key"
    curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" -T "$local_file" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/"
    local curl_exit_code=$?
    if [ $curl_exit_code -eq 0 ]; then
        put_logs "$curl_exit_code" "[INFO]" "$s3_key successfully transferred."
    elif [ $curl_exit_code -eq 6 ]; then
        put_logs "$curl_exit_code" "[ERROR]" "Could not resolve host for $s3_key. Please check the FTPS server configuration."
        exit $curl_exit_code
    elif [ $curl_exit_code -eq 67 ]; then
        put_logs "$curl_exit_code" "[ERROR]" "Permission denied for $s3_key. Please check directory permissions on the FTPS server."
        exit $curl_exit_code
    else
        put_logs "[ERROR] $s3_key transfer failed with exit code $curl_exit_code."
        exit $curl_exit_code
    fi
}

delete_files() {
    local s3_key="$1"
    put_logs "$?" "[INFO]" "Deleting $s3_key from $S3_BUCKET..."
    if aws s3 rm "s3://$S3_BUCKET/$s3_key"; then
        put_logs "$?" "[INFO]" "Deletion from S3 complete."
    else
        put_logs "$?" "[ERROR]" "Failed to delete $s3_key from S3 bucket."
        exit $?
    fi

    put_logs "$?" "[INFO]" "Deleting $s3_key from local directory..."
    if rm -f "$TEMP_DIR/$s3_key"; then
        put_logs "$?" "[INFO]" "Deletion from local directory complete."
    else
        put_logs "$?" "[ERROR]" "Failed to delete $s3_key from local directory."
        exit $?
    fi
}

call_api() {
    local process="$1"
    put_logs "$?" "[INFO]" "Calling API for $process process..."
    local api_response=$(/home/ec2-user/s3toftps/APIcall.sh "$process")

# could use grep
    if [[ $api_response == *"error"* ]]; then
        local status_code=$(echo "$api_response" | sed -n 's/.*"code":"\([^"]*\)".*/\1/p')
        local message=$(echo "$api_response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
        put_logs "$status_code" "[ERROR]" "$message"
        return 1
    else
        local status_code=$(echo "$api_response" | sed -n 's/.*"ProcessExecuteStatusCode":"\([^"]*\)".*/\1/p')
        put_logs "$?" "[INFO]" "API call Success."
        put_logs "$?" "[INFO]" "ProcessExecuteStatusCode: $status_code"
    fi
}

# Main function
main() {
    local s3_key="$1"
    local process="$2"

    check_file_existence "$s3_key"
    backup "$s3_key"
    transfer_files "$s3_key"
    delete_files "$s3_key"
    call_api "$process"
}

if [ "$#" -ne 2 ]; then
    put_logs "1" "[ERROR]" "Usage: $0 <s3_key> <process>"
    exit 1
fi

fetch_credentials
main "$1" "$2"

