# constants

FTPS_SERVER="kobelco-dev.planning-analytics.cloud.ibm.com"
FTPS_DESTINATION_DIRECTORY="prod/connect_test"
FTPS_BACKUP_DIRECTORY="prod/connect_test/backup"
S3_BUCKET="ipa-connect-budget/HostToIpa"
S3_BUCKET2="ipa-connect-budget/IpaToHost"
BACKUP_S3_BUCKET="ipa-connect-budget/HostToIpa-backup"
LOG_GROUP_NAME="HostToIPA"
LOG_GROUP_NAME2="IPAToHost"
LOG_STREAM_NAME="RHEL6-HostToIPA-Stream"
LOG_STREAM_NAME2="RHEL6-IPAToHost-Stream"
TEMP_DIR="/tmp"
SNS_TOPIC_ARN="arn:aws:sns:ap-northeast-1:282801688861:s3-to-IPA-topic"
INTERFACE_FILE="/home/ec2-user/s3toftps/interface_file.txt"
INTERFACE_FILE2="/home/ec2-user/s3toftps/Interface_file_IPAtoHost.txt"

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
        --log-group-name "$LOG_GROUP_NAME" \
        --log-stream-name "$LOG_STREAM_NAME" \
        --log-events "$log_event" >/dev/null 2>&1
}

