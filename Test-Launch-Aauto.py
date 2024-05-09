import boto3
import json
import os

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    ec2 = boto3.client('ec2')

    ### Initial processing   
    file_key = event['Records'][0]['s3']['object']['key']
    file_name = os.path.basename(file_key)
    table_id = os.path.splitext(file_name)[0]

    print(f"[INFO]：Start A-AUTO job startup process. Target table ID：[{table_id}]")

    ### Get instance information
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
        print("[INFO]: A-AUTO job startup processing terminated abnormally. Target table ID：[{table_id}]")
        return

    ### Set values from S3 Lambda configuration file
    try:
        bucket_name = os.environ['S3_BUCKET_NAME']
        json_file_base_path = os.environ['JSON_FILE_PATH']
        json_file_path = os.path.join(json_file_base_path, 'interface_file_hosttoipa.json')
        s3_response = s3.get_object(Bucket=bucket_name, Key=json_file_path)
        json_data = json.loads(s3_response['Body'].read().decode('utf-8'))
        network_id = json_data[table_id]
    except Exception as e:
        print(f"[ERR]：Could not obtain value from Lambda configuration file. Target table ID：[{table_id}]")
        print(f"[INFO]：A-AUTO job startup processing terminated abnormally. Target table ID：[{table_id}]")
        return
    
    ### A-AUTO job execution command sending process    
    try:
        command = f'cip s{network_id}'
        document_name = os.environ['DOCUMENT_NAME']
        cloudwatch_log_group = '/aws/lambda/Test-Launch-Aauto'

        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName = document_name,
            Parameters={'commands': [command]},
            CloudWatchOutputConfig={'CloudWatchOutputEnabled': True, 'CloudWatchLogGroupName': cloudwatch_log_group}
        )
        print(f"[INFO]: Command executed successfully. Target table ID：[{table_id}]")
        print(f"[INFO]：Target Network ID：[{network_id}]")
        return
    except Exception as e:
        print(f"[ERR]: An error occurred while executing the command. Target table ID：[{table_id}]")
        print(f"[INFO]: A-AUTO job startup process terminated abnormally. Target table ID: [{table_id}]")
        print(f"[INFO]: Target network ID: [{network_id}]")
        return