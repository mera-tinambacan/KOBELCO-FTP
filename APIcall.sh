#!/bin/bash

# Souce the put_logs functions and constants
cd "$(dirname "$0")"
CURDIR=$(pwd)
source $CURDIR/common_function.sh
#source /home/ec2-user/s3toftps/common_function.sh

# Cloudwatch Log Group & Stream
LOG_GROUP_NAME="HostToIPA"
LOG_STREAM_NAME="RHEL6-HostToIPA-Stream" 

# Process Name
#process="PC77_000_IF取込プロセス呼び出し"

# Getting all needed confidential credentials
fetch_credentials() {
    if non_interactive_id=$(get_parameter "/api-test/non_interactive_id") && password=$(get_parameter "/api-test/password"); then
        return 0
    else
        put_logs "$?" "[INFO]" "$non_interactive_id" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        exit 1
    fi
}

# Checking status code
check_status_code() {
    local status_code="$1"
    # Remove double quotes from the API response body
    local api_response=$2
    local ifid=$3

    # Check for status codes in the 2xx range (Success)
    if [[ $status_code -ge 200 && $status_code -lt 300 ]]; then
	 s_message=$(echo $api_response | jq -sr '.[0].ProcessExecuteStatusCode')
         put_logs "$status_code" "[INFO]" "APIcall.sh IFID: $ifid Code: $status_code - Success Response: $s_message" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"

    # Check for status codes in the 3xx range (Redirection)
    elif [[ $status_code -ge 300 && $status_code -lt 400 ]]; then
        if  [[ $status_code -eq 304 ]]; then
            put_logs "$status_code" "[ERROR]" "APIcall.sh IFID: $ifid Code: $status_code - Not Modified. Response: $api_response" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        else
            put_logs "$status_code" "[INFO]" "APIcall.sh IFID: $ifid Code: $status_code - Redirection detected. Response: $api_response" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        fi

    # Check for status codes in the 4xx range (Client errors)
    elif [[ $status_code -ge 400 && $status_code -lt 500 ]]; then
        if [[ $status_code -eq 401 ]]; then
            put_logs "$status_code" "[ERROR]" "APIcall.sh IFID: $ifid Code: $status_code - Invalid authentication credentials." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
            return 1
        else
            # Extract error code and message from the API response
            local error_code=$(echo "$api_response" | jq -sr '.[0].error.code')
            local message=$(echo "$api_response" | jq -sr '.[0].error.message')
            put_logs "$status_code" "[ERROR]" "APIcall.sh IFID: $ifid Code: $error_code - Error Response: $message" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
            return 1
        fi

    # Check for status codes in the 5xx range (Server errors)
    elif [[ $status_code -ge 500 && $status_code -lt 600 ]]; then
        put_logs "$status_code" "[ERROR]" "APIcall.sh IFID: $ifid Code: $status_code - Server error detected. Please try again later." "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    else
        # Log an error for unexpected status codes
        put_logs "$status_code" "[ERROR]" "APIcall.sh IFID: $ifid Code: $status_code - Unexpected status, Response: $api_response" "$LOG_GROUP_NAME" "$LOG_STREAM_NAME"
        return 1
    fi
}

APIcall() {
    #local process=$1
    local ifid=$1
    # checking if there was argument passed
    if [ -z "$ifid" ]; then
    #if [ -z "$process" ]; then
        #echo "Error: No argument passed. Please provide a process name."
        echo "Error: No argument passed. Please provide an IFID."
        exit 1
    fi
    
    process=$(awk -v ifid=$ifid '$3==ifid {print $2}' $IFFILE) 
    if [ -z "$process" ]; then
        echo "Error: No process passed. Please provide a process name."
	exit 1 
    fi

    # Fetch credentials for API authentication
    fetch_credentials

    auth_value=$(echo -n "${non_interactive_id}:${password}:LDAP" | base64)
    #api_url="https://kobelco.planning-analytics.cloud.ibm.com/tm1/api/awsconnect/api/v1/Processes('$process')/tm1.ExecuteWithReturn"
    api_url="https://kobelco.planning-analytics.cloud.ibm.com/tm1/api/temp/api/v1/Processes('$process')/tm1.ExecuteWithReturn?IFID=$ifid"
    data="{\"Parameters\": [{\"Name\": \"IFID\", \"Value\": \"$ifid\"}]}"
    # Make the API call and capture response and http status code
    temp_response=$(curl -X POST -s -w "%{http_code}" -H "Authorization: CAMNamespace $auth_value" -H "Content-Type: application/json" -d "$data" "$api_url")

    # Extract the status code and response body from the API response
    statusCode=$(echo $temp_response | jq -sc '.[1]')  # use -oE to search for 3 digit matches
    response=$(echo $temp_response | jq -sc '.[0]')   # remove the statusCode in temp_response

    # Check the status code and log appropriate messages
    check_status_code $statusCode "$response" $ifid
    [[ $? -eq 1 ]] && exit 1

    # Format the response as JSON and echo it
    #response="{\"statusCode\": $statusCode, \"response\": \"$response\"}"
    #echo "$response"
}

APIcall "$1"

exit 0
