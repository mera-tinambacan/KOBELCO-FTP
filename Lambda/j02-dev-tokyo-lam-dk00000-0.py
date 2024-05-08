import json
import os
import boto3
import time



def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ssm = boto3.client('ssm')
    ec2_client = boto3.client('ec2')

    # Initial processing
    file_key = event['Records'][0]['s3']['object']['key']
    file_name = os.path.basename(file_key)
    table_id = os.path.splitext(file_name)[0]
    
    print(f"[INFO]：A-AUTOジョブ起動処理を開始します。対象テーブルID：[{table_id}]")
        
    # Get instance information
    try:
        name_tag_value = os.environ['INSTANCE_NAME_TAG']
        
        filters = [{
            'Name': 'tag:Name',
            'Values': [name_tag_value]
        }]
        instance_details = ec2_client.describe_instances(Filters=filters)
        instance_id = instance_details['Reservations'][0]['Instances'][0]['InstanceId']
    except Exception as e:
        print(f"[ERR]：インスタンス情報を取得できませんでした。対象テーブルID：[{table_id}]")
        print(f"[INFO]：A-AUTOジョブ起動処理が異常終了しました。 対象テーブルID：[{table_id}] ")
        return {'success': False}
    
    # Set values from S3 Lambda configuration file
    try:
        bucket_name = os.environ['S3_BUCKET_NAME']
        json_file_base_path = os.environ['JSON_FILE_PATH']
        json_file_path = os.path.join(json_file_base_path, 'j02-dev-tokyo-lam-dk00000-0_RUNETLJOBNETWORK.json')
        s3_response = s3.get_object(Bucket=bucket_name, Key=json_file_path)
        json_data = json.loads(s3_response['Body'].read().decode('utf-8'))
        network_id = json_data[table_id]
    except Exception as e:
        print(f"[ERR]：Lambda用設定ファイルから値を取得できませんでした。対象テーブルID：[{table_id}]")
        print(f"[INFO]：A-AUTOジョブ起動処理が異常終了しました。 対象テーブルID：[{table_id}] ")
        return {'success': False}
            
    # A-AUTO job execution command sending process
    try:
        send_command = f'cip s{network_id}'
        document_name = os.environ['DOCUMENT_NAME']
        
        response = ssm.send_command(
            InstanceIds = [instance_id],
            DocumentName = document_name,
            Parameters = {
                'commands':  [f'cmd.exe /c "{send_command}"']
            }
        )
        print(f"[INFO]：A-AUTOジョブ起動処理が正常終了しました。対象テーブルID：[{table_id}]")
        print(f"[INFO]：対象ネットワークID：[{network_id}] ")
        return {'success': True}
        
    except Exception as e:
        print(f"[ERR]：A-AUTOジョブ起動コマンドの送信に失敗しました。対象テーブルID：[{table_id}]")
        print(f"[INFO]：A-AUTOジョブ起動処理が異常終了しました。 対象テーブルID：[{table_id}] ")
        print(f"[INFO]：対象ネットワークID：[{network_id}] ")
        return {'success': False}