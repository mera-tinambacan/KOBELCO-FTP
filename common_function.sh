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

# LOG GROUP NAME
HOSTTOIPA_LG="HostToIPA"
IPATOHOST_LG="IPAToHost"

# LOG STREAM NAME
HOSTTOIPA_LS="RHEL6-HostToIPA-Stream"
IPATOHOST_LS="RHEL6-IPAToHost-Stream"

# INTERFACE_FILE
HOSTTOIPA_IF="/home/ec2-user/s3toftps/interface_file.txt"
IPATOHOST_IF="/home/ec2-user/s3toftps/Interface_file_IPAtoHost.txt"

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
    local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $message\"}"

    if [[ "$log_level" == "[ERROR]" ]]; then
        # Publish error message to SNS
        aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "$log_level $message" --subject "ERROR $status_code"
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


