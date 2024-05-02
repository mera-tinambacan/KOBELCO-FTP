import boto3

def lambda_handler(event, function):
    # Initialize the SSM client
    ssm_client = boto3.client('ssm')
    
    instance_id = 'i-0b19a5fd796205c40'
    command = 'cip sTEST'
    cloudwatch_log_group = '/aws/lambda/Test-Launch-Aauto'
    
    # Execute the SSM Run Command
    response = ssm_client.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunPowerShellScript',
        Parameters={'commands': [command]},
        CloudWatchOutputConfig={'CloudWatchOutputEnabled': True, 'CloudWatchLogGroupName': cloudwatch_log_group}
    )

