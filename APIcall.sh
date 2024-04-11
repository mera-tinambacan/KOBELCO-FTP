APIcall() {
    local process=$1
    # checking if there was argument passed
    if [ -z "$process" ]; then
        echo "Error: No argument passed. Please provide a process name."
        return
    fi

    # temporary only. API Credentials
    non_interactive_id="kobelco01_tm1_automation"
    password="90372X8rJDgi"
    auth_value=$(echo -n "${non_interactive_id}:${password}:LDAP" | base64)
    api_url="https://kobelco.planning-analytics.cloud.ibm.com/tm1/api/awsconnect/api/v1/Processes('$process')/tm1.ExecuteWithReturn"

    response=$(curl -s -X POST "$api_url" \
    -H "Authorization: CAMNamespace $auth_value" \
    -H "Content-Type: application/json")

    # checking if the process / passed argument exist
    if [ $response == *"error"* ]; then
        exit 1
    else
        echo "$response"
    fi
}

APIcall "$1"

