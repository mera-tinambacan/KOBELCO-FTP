import boto3
import json
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    ec2 = boto3.client('ec2')

    # Extract bucket name and file key from the S3 event    
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    file_key = event['Records'][0]['s3']['object']['key']
    interface_file_key = 'HostToIpa/interface_file_hosttoipa.json'
        
    # Retrieve interface file from S3    
    try:
        response = s3.get_object(Bucket=bucket_name, Key=interface_file_key)
        interface_file_contents = response['Body'].read().decode('utf-8')
        try:
            process_name_mapping = json.loads(interface_file_contents)
        except json.JSONDecodeError:
            print("[ERR]: Unable to parse the interface file as JSON.")
            return
    except Exception as e:
        print(f"[ERR]: An error occurred while retrieving the interface file from S3. {str(e)}")
        return
    
    # Get the uploaded file name and process name    
    uploaded_file_name = file_key.split('/')[-1]
    process_name = process_name_mapping.get(uploaded_file_name)
    
    if not process_name:
        print(f"[INFO]: No process name found for file {uploaded_file_name}.")
        return
    
    # Get instance information
    try:
        name_tag_value = os.environ['INSTANCE_NAME_TAG']
        
        filters = [{
            'Name': 'tag:Name',
            'Values': [name_tag_value]
        }]
        instance_details = ec2.describe_instances(Filters=filters)
        instance_id = instance_details['Reservations'][0]['Instances'][0]['InstanceId']
    except Exception as e:
        print("[ERR]: Could not obtain instance information.")
        print("[INFO]: A-AUTO job startup processing terminated abnormally.")
        return {'success': False}

    # A-AUTO job execution command sending process    
    try:
        command = f'cip s{process_name}'
        cloudwatch_log_group = '/aws/lambda/Test-Launch-Aauto'

        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunPowerShellScript',
            Parameters={'commands': [command]},
            CloudWatchOutputConfig={'CloudWatchOutputEnabled': True, 'CloudWatchLogGroupName': cloudwatch_log_group}
        )
    except Exception as e:
        print(f"[ERR]: An error occurred while executing the command. {str(e)}")
        return
