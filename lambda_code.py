import boto3
import json

def get_process_name(bucket_name, file_key):
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=bucket_name, Key=file_key)
    interface_file_contents = response['Body'].read().decode('utf-8')
    process_name_mapping = json.loads(interface_file_contents)
    return process_name_mapping

def lambda_handler(event, context):
    try:
        ssm = boto3.client('ssm')
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        file_key = event['Records'][0]['s3']['object']['key']

        # Get the process name mapping from the interface file
        interface_file_key = 'HostToIpa/interface_file_hosttoipa.json'
        try:
            process_name_mapping = get_process_name(bucket_name, interface_file_key)
        except Exception as e:
            print(f"An error occurred while retrieving the interface file from S3: {str(e)}")
            return

        # Extract the file name from the uploaded file key
        uploaded_file_name = file_key.split('/')[-1]

        # Get the process name corresponding to the uploaded file
        process_name = process_name_mapping.get(uploaded_file_name)
        if not process_name:
            print(f"No process name found for file {uploaded_file_name}.")
            return

        command = f'cip s{process_name}'
        instance_id = 'i-0b19a5fd796205c40'
        cloudwatch_log_group = '/aws/lambda/Test-Launch-Aauto'

        # Execute the SSM Run Command
        try:
            response = ssm.send_command(
                InstanceIds=[instance_id],
                DocumentName='AWS-RunPowerShellScript',
                Parameters={'commands': [command]},
                CloudWatchOutputConfig={'CloudWatchOutputEnabled': True, 'CloudWatchLogGroupName': cloudwatch_log_group}
            )
        except Exception as e:
            print(f"An error occurred while executing the command: {str(e)}")
            return
    except Exception as e:
        print(f"An unexpected error occurred: {str(e)}")
        return
