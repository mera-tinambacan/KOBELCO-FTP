#!/bin/bash
# Update: Mark H. tekito -> tekitou
#	          AssignAdminPassword -> tekitou
# 		  tm1server.log -> tm1server.log.org
#		  add 5 mins to date
#         Mark H. 2024/04/08 
#		  Made 3 variation of log7.sh
# 	          - log7-start.sh to simulate log API log start
#		  - log7-finish.sh to simulate log API log finish
#		  - log7-error.sh to simulate creation of error
#		  Accept parameter 

# Function to replace timestamps with current timestamp in log lines
# Add 5 mins to current time to simulate logging of IPA.
replace_timestamp() {
    while read -r line; do
        current_timestamp=$(date -d "+5min" +"%Y-%m-%d %H:%M:%S.%3N")
        echo "${line/20[0-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-5][0-9]:[0-5][0-9].[0-9][0-9][0-9]/$current_timestamp}"
    done
}

# Function to modify filename with current timestamp
modify_filename() {
    current_timestamp=$(date +"%Y%m%d%H%M%S")
    echo "$1" | sed "s/\(.*_\)[0-9]\{14\}\(_.*\)/\1$current_timestamp\2/"
}

# Replace timestamps in lines containing "AssignAdminPassword" and append modified content to new file
#grep -e "tekitou" tm1server.log.org | replace_timestamp >> file5.log
#grep -e "tekitou" tm1server.log.org.finish | replace_timestamp >> tm1server.log.tmp
grep -e "$1" tm1server.log.org.finish | replace_timestamp >> tm1server.log.tmp

# Modify filename for TM1ProcessError file
#modified_filename=$(modify_filename "TM1ProcessError_20231130140136_41513540_tekitou.log")

# Upload modified log file
curl --ftp-ssl -u fs_kobelco-dev:6mCQhWJ90jnUdL -T tm1server.log.tmp ftp://kobelco-dev.planning-analytics.cloud.ibm.com/prod/connect_test/tm1server.log

# Upload modified TM1ProcessError file
#curl --ftp-ssl -u fs_kobelco-dev:6mCQhWJ90jnUdL -T "TM1ProcessError_20231130140134_41513540_sample.log" ftp://kobelco-dev.planning-analytics.cloud.ibm.com/prod/connect_test/"$modified_filename"


# Function to create a CSV file with filename based on JOBNAME and current datestamp
create_csv_on_ftps() {
    jobname="$1"
    current_datestamp=$(date +"%Y%m%d")
    filename="${jobname}_${current_datestamp}.csv"
    
    # send an empty string to create the file directly on the server
    curl --ftp-ssl -u fs_kobelco-dev:6mCQhWJ90jnUdL -T /dev/null "ftp://kobelco-dev.planning-analytics.cloud.ibm.com/prod/connect_test/$filename"
    echo "CSV file created on FTP server: $filename"
}

# Check if exactly 1 argument is provided
[[ "$#" -ne 1 ]] && echo "Please provide 1 job name" && exit 1
JOBNAME="$1"

create_csv_on_ftps "$JOBNAME"