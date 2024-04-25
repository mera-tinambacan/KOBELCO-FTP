#!/bin/bash

# Script Name: ftpstos3.sh
# Description: to backup files in IPA shared folder to a backup directory
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

# Source the put_logs functions and constants
source /home/ec2-user/s3toftps/common_function.sh

fetch_credentials() {
    if USERNAME=$(get_parameter "/ipa-test/username") && PASSWORD=$(get_parameter "/ipa-test/password"); then
        return 0
    else
        put_logs "$?" "[ERROR]" "$USERNAME"
        exit 1
    fi
}

check_interface_file() {
    local file="$1"
    if grep -qF "$file" "$INTERFACE_FILE"; then
        return 0
    else
        return 1
    fi
}

check_file_existence() {
    local file="$1"
    if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" >/dev/null; then
        put_logs "$?" "[INFO]" "$file found in FTPS Server."
        return 0
    else
        put_logs "$?" "[INFO]" "$file not found in FTPS Server."
        return 1
    fi
}

backup_file_to_ftp() {
    local file="$1"
    if check_file_existence "$file"; then
        # Copy the file to the backup directory
        if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" | \
            curl -s --ftp-ssl -T - -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$file"; then
            put_logs "$?" "[INFO]" "File $file copied to backup directory."
            return 0
        else
            put_logs "$?" "[ERROR]" "Failed to copy file $file to backup directory."
            return 1
        fi
    else
        put_logs "$?" "[INFO]" "File $file not found on FTPS server."
        return 1
    fi
}

copy_to_temp_dir() {
    local file="$1"
    if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" -o "$TEMP_DIR/$file"; then
        put_logs "$?" "[INFO]" "File $file successfully downloaded to tmp"  
    else
        put_logs "$?" "[INFO]" "File $file not found on FTPS server."
    exit 1
  fi
}

transfer_files() {
    local file="$1"

    if aws s3 cp "$TEMP_DIR/$file" "s3://$S3_BUCKET2/"; then
        # Write the transferred file name to a file on FTP server
        echo "$file" >> "$TEMP_DIR/file_transferred.txt"
        put_logs "$?" "[INFO]" "File $file successfully transferred from IPA server to S3 bucket."
        return 0
    else
        put_logs "$?" "[ERROR]" "Failed to copy file $file from temporary directory to S3 bucket."
        return 1
    fi
}

delete_files() {
    local file="$1"
    if curl -k --user "$USERNAME:$PASSWORD" --ftp-ssl -Q "OPTS UTF8 ON" -Q "DELE $FTPS_DESTINATION_DIRECTORY/$file" "ftp://$FTPS_SERVER/"; then
        put_logs "$?" "[INFO]" "File $file deleted from source directory."
        return 0
    else
        put_logs "$?" "[ERROR]" "Failed to delete file $file from source directory."
        return 1
    fi
}

# Main script
main(){
    file_list=$(cat "$INTERFACE_FILE")
    echo "File list fetched: $file_list"
  
    # Iterate over each line in the file_list
    while IFS= read -r file; do
        echo "Processing file: $file"
        if check_interface_file "$file"; then
            if backup_file_to_ftp "$file"; then
                copy_to_temp_dir "$file"
                transfer_files "$file"
                delete_files "$file"
            fi
        else
            echo "File $file not found in interface file."
        fi
    done <<< "$file_list"
  
    # Move the file_transferred.txt to FTP server
    curl -T "$TEMP_DIR/file_transferred.txt" --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/"
  
    put_logs "$?" "[INFO]" "Transfer of files completed."
    echo "Transfer of files completed."
}

fetch_credentials
main

# Main script
# Mark H. (4/17) comment: add copy to s3 function
#                       : Make a list of interface file names to a text file. Only copy the I/F file that matches in the list.
#                       : Ignore file that is not included in list.
#                       : Test for double byte file names.. use -Q "OPTS UTF8 ON" in all curl command that list, download, and upload
#                       : Poll file until it exist. Polling will stop if time is greater or equal to 12 midnight(this can be changed)

# Function to backup a single file from source directory to backup directory
# backup_single_file() {
#   local myfile="$1"
#   # Check if file exists on the server
#   if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" >/dev/null; then
#     put_logs "INFO" "File $myfile found on FTPS server."
#     # Copy the file to the backup directory
#     if curl -s -k --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" | \
#       curl -s -k --ftp-ssl -T - -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$myfile"; then
#       # Delete file from source directory
#       curl -k --user "$USERNAME:$PASSWORD" --ftp-ssl -Q "OPTS UTF8 ON" -Q "DELE $FTPS_DESTINATION_DIRECTORY/$myfile" "ftp://$FTPS_SERVER/"
#       put_logs "INFO" "File $myfile copied to backup directory."
#       put_logs "INFO" "File $file has been deleted from the source directory."
#       echo "Backup of $myfile completed."
#       return 0
#     else
#       put_logs "ERROR" "Failed to copy file $myfile to backup directory."
#       return 1
#     fi
#   else
#     put_logs "INFO" "File $myfile not found on FTPS server."
#     return 1
#   fi
#}
