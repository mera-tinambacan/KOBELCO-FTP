#!/bin/bash
# Update: Mark H. tekito -> tekitou
#	          AssignAdminPassword -> tekitou
# 		  tm1server.log -> tm1server.log.org
#		  add 5 mins to date

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
grep -e "tekitou" tm1server.log.org | replace_timestamp >> tm1server.log.tmp

# Modify filename for TM1ProcessError file
modified_filename=$(modify_filename "TM1ProcessError_20231130140134_41513540_tekitou.log")

# Upload modified log file
curl --ftp-ssl -u fs_kobelco-dev:6mCQhWJ90jnUdL -T tm1server.log.tmp ftp://kobelco-dev.planning-analytics.cloud.ibm.com/prod/connect_test/tm1server.log

# Upload modified TM1ProcessError file
curl --ftp-ssl -u fs_kobelco-dev:6mCQhWJ90jnUdL -T "TM1ProcessError_20231130140134_41513540_sample.log" ftp://kobelco-dev.planning-analytics.cloud.ibm.com/prod/connect_test/"$modified_filename"

