#!/bin/bash

# Source the parameter functions
source parameter_function.sh

# Configuration
FTPS_SERVER="ftp://localhost"
FTPS_SOURCE_DIRECTORY="source"
FTPS_BACKUP_DIRECTORY="backup"
FTPS_FILE="source.csv"
S3_BUCKET="mydestination-directory"
LOG_GROUP_NAME="ipaFtp-Log"
LOG_STREAM_NAME="ipaFtp-Stream"
TEMP_DIR="/tmp"

# Fetch FTP username and password from source
USERNAME=$(get_parameter "/ftp/username")
PASSWORD=$(get_parameter "/ftp/password")

# Logging function
put_logs() {
  local log_level="$1"
  local message="$2"
  local timestamp=$(date +%s%3N)
  local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $message\"}"
  
  # Use the AWS CLI to put the log event
  aws logs put-log-events \
    --log-group-name "$LOG_GROUP_NAME" \
    --log-stream-name "$LOG_STREAM_NAME" \
    --log-events "$log_event"
}

# Download file function
download_file() {
  if curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" --head --fail "$FTPS_SERVER/$FTPS_SOURCE_DIRECTORY/$FTPS_FILE" >/dev/null; then
    put_logs "Downloading $FTPS_FILE from $FTPS_SERVER/$FTPS_SOURCE_DIRECTORY"
    curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" "$FTPS_SERVER/$FTPS_SOURCE_DIRECTORY/$FTPS_FILE" -o "$TEMP_DIR/$FTPS_FILE"
  else
    put_logs "[ERROR] $FTPS_FILE does not exist on FTPS."
    exit 1
  fi
}

# Backup file function
backup_file() {
  download_file
  put_logs "Copying $FTPS_FILE from source to backup directory: $FTPS_SERVER/$FTPS_BACKUP_DIRECTORY"
  curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" -T "$TEMP_DIR/$FTPS_FILE" "$FTPS_SERVER/$FTPS_BACKUP_DIRECTORY/$FTPS_FILE" || {
    put_logs "[ERROR] Failed to copy $FTPS_FILE to backup directory."
    exit 1
  }
  put_logs "[INFO] Backup complete."
}

# Delete files function
delete_files() {
  put_logs "Deleting $FTPS_FILE from source directory: $FTPS_SERVER/$FTPS_SOURCE_DIRECTORY"
  if curl -k --ftp-ssl --user "$USERNAME:$PASSWORD" -Q "DELE $FTPS_SOURCE_DIRECTORY/$FTPS_FILE" "$FTPS_SERVER"; then
    put_logs "[INFO] Deletion from source complete."
  else
    put_logs "[ERROR] Failed to delete $FTPS_FILE from source directory."
    exit 1
  fi
  
  put_logs "Deleting $FTPS_FILE from temporary directory..."
  if rm "$TEMP_DIR/$FTPS_FILE"; then
    put_logs "[INFO] Deletion from temporary directory complete."
  else
    put_logs "[ERROR] Failed to delete $FTPS_FILE from temporary directory."
    exit 1
  fi
}

main_function() {
  backup_file
  local local_file="$TEMP_DIR/$FTPS_FILE"
  put_logs "[INFO] Transferring $local_file to S3 $S3_BUCKET bucket"
  aws s3 cp "$local_file" "s3://$S3_BUCKET" || {
    put_logs "[ERROR] Failed to transfer $FTPS_FILE to S3 $S3_BUCKET bucket."
    exit 1
  }
  put_logs "[INFO] Transfer complete."
  delete_files
}

main_function