#!/bin/bash
# Script Name: s3toftps.sh
# Script Description: Transfer of File from S3 to FTPS
# Created by: AWS M. Tinambacan
# Creation Date: 4/1/2024
# Update:  4/04/2024 AWS R. Nuno
#                    Refactor Script
#                    Made several functions for each process.
# Update:  4/15/2024 AWS R. Nuno
#                    Enabled Upload all Files
# Update:  4/17/2024 AWS R. Nuno
#                    Fix 文字化け when transferring file
# Update: 4/17/2024  AWS G. Mayuga
#                    put put_logs function and constants to common_function
# Update: 4/18/2024  AWS R. Nuno
#                    added check_interface_file function
#                    removed API status logs , moved it to APIcall.sh

# Souce the put_logs functions and constants
source /home/ec2-user/s3toftps/common_function.sh

check_interface_file() {
    local s3_key="$1"
    if [[ -n $s3_key ]]; then
        if grep -qF "$s3_key" "$INTERFACE_FILE"; then
            put_logs "$?" "[INFO]" "$s3_key is valid"
            check_file_existence $s3_key
            echo $s3_key
        else
            put_logs "$?" "[INFO]" "$s3_key is invalid"
            exit 1
        fi
    else
        s3_files=$(aws s3 ls "s3://$S3_BUCKET/" | awk 'NF == 4' | awk '{print $4}')
        while IFS= read -r s3_key; do
            if grep -qF "$s3_key" "$INTERFACE_FILE"; then
                put_logs "$?" "[INFO]" "$s3_key is valid"
                check_file_existence $s3_key
                echo $s3_key
            else
                put_logs "$?" "[INFO]" "$s3_key is invalid"
            fi
        done <<< "$s3_files"
    fi
}

check_file_existence() {
    local s3_key="$1"
    put_logs "$?" "[INFO] Checking $s3_key from $S3_BUCKET..."
    if aws s3 ls "s3://$S3_BUCKET/$s3_key" &>/dev/null; then
        put_logs "$?" "[INFO]" "$s3_key found in S3 Bucket."
    else
        put_logs "$?" "[ERROR]" "$s3_key not found in S3 Bucket."
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
    curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" -T "$local_file" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/"

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
    if [[ $? -eq 0 ]]; then
        put_logs "$?" "[INFO]" "API Call for $process process is success."
    else
        put_logs "$?" "[ERROR]" "Something unexpected occurred in API."
    fi
}

# Main function
main() {
    local process="$1"
    local s3_key="$2"

    validated_files=$(check_interface_file $s3_key)
    if [[ -n "$validated_files" ]]; then
        # Iterate over each line in s3_keys
        while IFS= read -r validated_file; do
            put_logs "$?" "[INFO]" "Processing S3 key: $validated_file"
            backup "$validated_file"
            transfer_files "$validated_file"
            delete_files "$validated_file"
            call_api "$process"
        done <<< "$validated_files"
    else
        put_logs "$?" "[ERROR]" "$s3_key file not found."
        exit 1
    fi
}

if [ "$#" -gt 2 ] || [ "$#" -lt 1 ]; then
    put_logs "1" "[ERROR]" "Usage: $0 <s3_key> <process> or Usage: $0 <process>"
    exit 1
fi

fetch_credentials
main "$1" "$2"

