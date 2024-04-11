#!/bin/bash
# Update: April 5, 2024 Mark H.
# Update: April 8, 2024 Meracle T.
#                       change condition for argument
#                       -n $1 -> "$#" -ne 1
#                       add log_file_to_cloudwatch function
#	  April 9, 2024 Mark H.
#	                refactor a lot of things 
#			Continue looping until 1. job process finished. 
#			2. loop equal or greater than 1 day

MYDIR=/home/ec2-user/s3toftps

# Source the parameter functions
source $MYDIR/parameter_function.sh

# Configuration
FTPS_SERVER="kobelco-dev.planning-analytics.cloud.ibm.com"
FTPS_DESTINATION_DIRECTORY="prod/connect_test"
USERNAME=$(get_parameter "/ipa-test/username")
PASSWORD=$(get_parameter "/ipa-test/password")
LOG_GROUP_NAME="HostToIPA"
LOG_STREAM_NAME="RHEL6-HostToIPA-Stream"
IPA_LOG_FILE="tm1server.log"
POLLTIMEINTERVAL=30
DATENOW=$(date +%s)

#echo "$USERNAME"

# Function to put logs into CloudWatch
put_logs() {
  local log_level="$1"
  local message="$2"
  local timestamp=$(date +%s%3N)
  local log_event="{\"timestamp\": $timestamp, \"message\": \"$log_level - $message\"}"
  aws logs put-log-events \
    --log-group-name "$LOG_GROUP_NAME" \
    --log-stream-name "$LOG_STREAM_NAME" \
    --log-events "$log_event" \
    --region ap-northeast-1 >/dev/null 2>&1
}

log_file_to_cloudwatch() {
   returnfinish=1 
   for line in "${newlogs[@]}"; do
       put_logs "INFO" "${line}"
       Finished_log="Process ${JOBNAME}:  finished executing normally," 
       if [[ "${line}" == *"$Finished_log"* ]]; then
	  returnfinish=0
       fi
   done
   return $returnfinish 
}

check_file() {
   local myfile=$1 
   # Check if file exists on the server
   if curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" >/dev/null; then 
     put_logs "INFO" "File $myfile found on FTPS server."
     # Download $myfile
     curl -s --ftp-ssl -u "$USERNAME:$PASSWORD"  "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/$myfile" -o $MYDIR/$myfile
     return 0
   else
     put_logs "INFO" "File $myfile not found or no new log found on FTPS server."
     return 1 
   fi
}

check_latest_IPA_log() {
   # Check if file size > 0
   if [[ -s $MYDIR/$IPA_LOG_FILE ]]; then
      # Check logs from today and hour/min is equal to 5 mins ago..
      mapfile -t newlogs < <( grep $JOBNAME $MYDIR/$IPA_LOG_FILE | tail | awk -v dt=$(date -d '5 mins ago' +'%Y-%m-%d') -v tm=$(date +'%H:%M') '$4==dt && $5>=tm')
   fi
   
   # Check if array size > 0 
   if [[ ${#newlogs[@]} -gt 0 ]]; then
      log_file_to_cloudwatch $MYDIR/$IPA_LOG_FILE
      return $? 
   else
      return 1
   fi
}

check_time_over_1day(){ 
   DATENOW2=$(date +%s)
   #check polling time is 600 sec but it should be 86400(24 hours)
   #break loop once time period elapses
   [[ $((DATENOW2 - DATENOW)) -ge 600 ]] && break
}

# Function to poll the file on FTPS server
poll_file() {
  local file="$1"
  local errorfile="$2"

  # Polling loop
  while true; do
      # check existence of tm1server.log
      check_file $1
      ret_log="$?"
      # check latest IPA since 5 mins ago and thereafter, check for finished task
      check_latest_IPA_log
      latest_log="$?"
      # If tm1server exist and have logs 5 mins before and thereafter ret_log = 0 else ret_log =1 
      [[ $ret_log -eq 0 && $latest_log -eq 0 ]] && ret_log=0 || ret_log=1
	
      # Check recent errorlog with Jobname
      ERRORLOG=$(curl -s --ftp-ssl -u "$USERNAME:$PASSWORD" -l "ftp://$FTPS_SERVER/$FTPS_DESTINATION_DIRECTORY/" |\
      		 awk -v datetime=$(date -d '5 min ago' +%Y%m%d%H%M%S) -v job=$JOBNAME -F"_" '$2>datetime && $0~job' | tail -1)

      if [[ -n $ERRORLOG ]];  then
      	 # check TM1Process...<process>.log meantime tekitou
         check_file $ERRORLOG
         ret_err_log="$?"
	 ####### Send SNS code below
         # <code me here> or call function
         # 1. Send SNS
	 # 2. Backup ERROR LOG
	 # 3. Delete ERROR LOG
      else
         ret_err_log=1
      fi

      # If tm1server.log exist and have recent log or error file exist break loop
      if [[ $ret_log -eq 0 || $ret_err_log -eq 0 ]]; then
	 break
      else
	 # loop again	 
	 check_time_over_1day	 
	 echo "Checking again after $POLLTIMEINTERVAL"
	 sleep $POLLTIMEINTERVAL
      fi
  done
}

# Main

# Ask for job name as an argument
[[ "$#" -ne 1 ]] && echo "Please provide 1 job name" && exit
JOBNAME=$1

IPA_ERROR_FILE="TM1ProcessError_$(date +%Y%m%d).*$1.log"
poll_file $IPA_LOG_FILE $IPA_ERROR_FILE
