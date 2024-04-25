#!/bin/bash

# Script Name: ftpstos3.sh
# Description: to transfer the files from IPA to S3 that are listed on interface_file.txt; Append the file names that have been succesfully transferred to file_transferred.txt; sleep and poll for 60 seconds before checking for new files in the IPA to process.
# Created by: AWS Mera T.
# Creation Date: 4/15/2024
# Script run: 1. bash ftpstos3.sh single <file name>; or
#             2. bash ftpstos3.sh all
# Update: 4/18/2024 AWS Mera T.
#                   put put_logs function and constants to common_function
#                   backup and delete the files that are listed in the interface_file.txt only
#                   use -Q "OPTS UTF8 ON" in all curl command
#                   backup_single_file function is put on comment
# Update: 4/19/2024 AWS Mera T.
#                   separate each function for readability
#                   added transfer of files from IPA to s3
# Update 4/22/2022  AWS Mera T.
#                   added poll_files() - Sleeping for 60 seconds before checking for new files to process
#                   updated the script description

# Source the put_logs functions and constants
source /home/ec2-user/s3toftps/common_function.sh

#constants
LOG_GROUP_NAME="IPAToHost"
LOG_STREAM_NAME="RHEL6-IPAToHost-Stream"


fetch_credentials() {
    if USERNAME=$(get_parameter "/ipa-test/username") && PASSWORD=$(get_parameter "/ipa-test/password"); then
        return 0
    else
        put_logs "$?" "[ERROR]" "$USERNAME" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        exit 1
    fi
}

check_interface_file() {
    local file="$1"
    if grep -qw "$file" "$IPATOHOST_IF"; then
        return 0
    else
        return 1
    fi
}

check_file_existence() {
    local file="$1"
    if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" >/dev/null; then
        put_logs "$?" "[INFO]" "$file found in FTPS Server." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 0
    else
        put_logs "$?" "[INFO]" "$file NOT found in FTPS Server." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    fi
}

backup_file_to_ftp() {
    local file="$1"
    if check_file_existence "$file"; then
        # Copy the file to the backup directory
        if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" | \
            curl -s --ftp-ssl -T - -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$file"; then
            put_logs "$?" "[INFO]" "File $file copied to backup directory." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
            return 0
        else
            put_logs "$?" "[ERROR]" "Failed to copy file $file to backup directory." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
            return 1
        fi
    else
        put_logs "$?" "[INFO]" "File $file NOT found on FTPS server." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    fi
}

copy_to_temp_dir() {
    local file="$1"
    if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" -o "$TEMP_DIR/$file"; then
        put_logs "$?" "[INFO]" "File $file successfully downloaded to tmp" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME" 
    else
        put_logs "$?" "[INFO]" "File $file NOT found on FTPS server." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        exit 1
    fi
}

transfer_files() {
    local file="$1"

    if aws s3 cp "$TEMP_DIR/$file" "s3://$IPATOHOST_S3/"; then
        # Write the transferred file name to a file on FTP server
        echo "$file" >> "$TEMP_DIR/file_transferred.txt"
        put_logs "$?" "[INFO]" "File $file successfully transferred from IPA server to S3 bucket." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 0
    else
        put_logs "$?" "[ERROR]" "Failed to copy file $file from temporary directory to S3 bucket." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    fi
}

delete_files() {
    local file="$1"
    if curl -k --user "$USERNAME:$PASSWORD" --ftp-ssl -Q "OPTS UTF8 ON" -Q "DELE $FTPS_DESTINATION_DIRECTORY/$file" "ftp://$FTPS_SERVER/"; then
        put_logs "$?" "[INFO]" "File $file deleted from source directory." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        # Delete the file from the temporary directory
        rm -f "$TEMP_DIR/$file"
        put_logs "$?" "[INFO]" "File $file deleted from temporary directory." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 0
    else
        put_logs "$?" "[ERROR]" "Failed to delete file $file from source directory." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    fi
}

# Main processing function
process_file() {
    local file="$1"
    echo "Processing file: $file"
    
    if check_interface_file "$file"; then
        if backup_file_to_ftp "$file"; then
            copy_to_temp_dir "$file"
            transfer_files "$file"
            delete_files "$file"
            echo "File $file has been transferred."
        fi
    else
        echo "File $file NOT found in interface file."
    fi
}

# Polling function
poll_files() {
    local end_time="23:59"
    while true; do
        current_time=$(date +"%H:%M")
        if [[ "$current_time" > "$end_time" ]]; then
            echo "Polling finished."
            break
            exit 0
        fi

        # Check for files not listed in file_transferred.txt
        while IFS= read -r file; do
            if grep -qw "$file" "$TEMP_DIR/file_transferred.txt"; then
                continue
            fi

            if check_file_existence "$file"; then
                process_file "$file"
            fi
        done < "$IPATOHOST_IF"

        echo "Sleeping for 60 seconds before checking for new files."
        sleep 60
    done
}

fetch_credentials
poll_files

