#!/bin/bash

# Script Name: ftpstos3.sh
# Description: to backup files in IPA shared folder to a backup directory
# Created by: AWS Mera T.
# Creation Date: 4/15/2024
# Script run: 1. bash ftpstos3.sh single <file name>; or
#             2. bash ftpstos3.sh all   

# Souce the put_logs functions and constants
source /home/ec2-user/s3toftps/common_function.sh

fetch_credentials() {
    if USERNAME=$(get_parameter "/ipa-test/username") && PASSWORD=$(get_parameter "/ipa-test/password"); then
        return 0
    else
        put_logs "$?" "[ERROR]" "$USERNAME"
        exit 1
    fi
}

# Function to backup a single file from source directory to backup directory
backup_single_file() {
  local myfile="$1"
  # Check if file exists on the server
  if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" >/dev/null; then
    put_logs "INFO" "File $myfile found on FTPS server."
    # Copy the file to the backup directory
    if curl -s -k --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" | \
      curl -s -k --ftp-ssl -T - -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$myfile"; then
      # Delete file from source directory  
      curl -k --user "$USERNAME:$PASSWORD" --ftp-ssl -Q "OPTS UTF8 ON" -Q "DELE $FTPS_DESTINATION_DIRECTORY/$myfile" "ftp://$FTPS_SERVER/"
      put_logs "INFO" "File $myfile copied to backup directory."
      put_logs "INFO" "File $file has been deleted from the source directory."
      echo "Backup of $myfile completed."
      return 0
    else
      put_logs "ERROR" "Failed to copy file $myfile to backup directory."
      return 1
    fi
  else
    put_logs "INFO" "File $myfile not found on FTPS server."
    return 1
  fi
}

# Function to backup files listed in file_list.txt from source directory to backup directory
backup_all_files() {
  echo "Starting backup_files_from_list..."
  # Get the list of files from file_list.txt
  file_list=$(cat "$INTERFACE_FILE")
  echo "File list fetched: $file_list"
  
  # Iterate over each line in the file_list
  while IFS= read -r file; do
    echo "Processing file: $file"
    # Trim whitespace from file name
    file=$(echo "$file" | tr -d '[:space:]')
    # Check if the file exists on the server
    if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" >/dev/null; then
      echo "File $file found on FTPS server."
      # Copy the file to the backup directory
      if curl -s -k --ftp-ssl -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$file" | \
        curl -s -k --ftp-ssl -T - -u "$USERNAME:$PASSWORD" -Q "OPTS UTF8 ON" "ftp://$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$file"; then
        # Delete file from source directory  
        curl -k --user "$USERNAME:$PASSWORD" --ftp-ssl -Q "OPTS UTF8 ON" -Q "DELE $FTPS_DESTINATION_DIRECTORY/$file" "ftp://$FTPS_SERVER/"
        echo "File $file copied to backup directory."
        echo "File $file has been deleted from the source directory."
      else
        echo "Failed to copy file $file to backup directory."
      fi
    else
      echo "File $file not found on FTPS server."
    fi
  done <<< "$file_list"
  
  echo "Backup of files from file_list.txt completed."
}

# Main script
# Mark H. (4/17) comment: add copy to s3 function
#                       : Make a list of interface file names to a text file. Only copy the I/F file that matches in the list.
#                       : Ignore file that is not included in list.
#                       : Test for double byte file names.. use -Q "OPTS UTF8 ON" in all curl command that list, download, and upload 
#     : Poll file until it exist. Polling will stop if time is greater or equal to 12 midnight(this can be changed)

fetch_credentials
if [ "$1" == "single" ]; then
  backup_single_file "$2"
elif [ "$1" == "all" ]; then
  backup_all_files
else
  echo "Usage: $0 [single <file_name> | all]"
fi
