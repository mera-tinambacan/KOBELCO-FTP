# constants

FTPS_SERVER="kobelco-dev.planning-analytics.cloud.ibm.com"
FTPS_DESTINATION_DIRECTORY="prod/connect_test"
FTPS_BACKUP_DIRECTORY="prod/connect_test/backup"
TEMP_DIR="/tmp"
SNS_TOPIC_ARN="arn:aws:sns:ap-northeast-1:282801688861:s3-to-IPA-topic"

# S3 BUCKET NAME
HOSTTOIPA_S3="ipa-connect-budget/HostToIpa"
HOSTTOIPA_S3_BACKUP="ipa-connect-budget/HostToIpa-backup"
IPATOHOST_S3="ipa-connect-budget/IpaToHost"

# INTERFACE_FILE
cd "$(dirname "$0")"
CURDIR=$(pwd)
IFFILE="${CURDIR}/interface_file.txt"
#HOSTTOIPA_IF="${CURDIR}/interface_file.txt"
#HOSTTOIPA_IF="${CURDIR}/interface_file_hosttoipa.txt"
#IPATOHOST_IF="/home/ec2-user/s3toftps/interface_file_ipatohost.txt"
#IPATOHOST_IF="${CURDIR}/interface_file_ipatohost.txt"
#IPATOHOST_IF="${CURDIR}/interface_file.txt"

# functions
get_parameter() {
  local name="$1"
  aws ssm get-parameter --name "$name" --query "Parameter.Value" --output text
}

# Function to put logs to CloudWatch
put_logs() {
    local status_code="$1"
    local log_level="$2"
    local message="$3"
    local log_group_name="$4"
    local log_stream_name="$5"
    local timestamp=$(date +%s%3N)
    #local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $message\"}"
    local escaped_message=$(echo "$message" | sed 's/"/\\"/g')  # Escape double quotes
    local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $escaped_message\"}"

   
    # This is for APICall.sh  
    if [[ "$log_level" == "[ERROR]" ]]; then
        # Publish error message to SNS
        aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "${log_level} ${message}" --subject "ERROR $status_code"
    elif [[ "$message" == *"successfully transferred from IPA server to S3 bucket"* ]]; then
        # Publish success file transfer message to SNS
        aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "$message" --subject "Successful File Transfer"
    fi

    # Use the AWS CLI to put the log event
    aws logs put-log-events \
        --log-group-name "$log_group_name" \
        --log-stream-name "$log_stream_name" \
        --log-events "$log_event" >/dev/null 2>&1

}

