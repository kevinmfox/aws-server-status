import boto3
import pymysql
from datetime import datetime

with open('/opt/server-status/master-ip.txt', 'r') as f:
    master_ip = f.read().strip()

DB_CONFIG = {
    'host': master_ip,
    'user': 'server-status',
    'password': 'ahN64B0tyx3N',
    'database': 'servers',
    'cursorclass': pymysql.cursors.DictCursor
}

def get_missing_entries():
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute("SELECT instance_id, availability_zone FROM server_info WHERE vpc_id IS NULL")
    results = cursor.fetchall()
    cursor.close()
    conn.close()
    return results

def get_instance_network_info(instance_id, region):
    ec2 = boto3.client('ec2', region_name=region)

    response = ec2.describe_instances(InstanceIds=[instance_id])
    reservation = response['Reservations'][0]
    instance = reservation['Instances'][0]

    subnet_id = instance['SubnetId']
    vpc_id = instance['VpcId']

    subnet_name = None
    vpc_name = None

    subnet_info = ec2.describe_subnets(SubnetIds=[subnet_id])['Subnets'][0]
    vpc_info = ec2.describe_vpcs(VpcIds=[vpc_id])['Vpcs'][0]

    for tag in subnet_info.get('Tags', []):
        if tag['Key'] == 'Name':
            subnet_name = tag['Value']

    for tag in vpc_info.get('Tags', []):
        if tag['Key'] == 'Name':
            vpc_name = tag['Value']

    return {
        'vpc_id': vpc_id,
        'vpc_name': vpc_name,
        'subnet_id': subnet_id,
        'subnet_name': subnet_name
    }

def update_entry(instance_id, network_info):
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute("""
        UPDATE server_info SET
            vpc_id = %s,
            vpc_name = %s,
            subnet_id = %s,
            subnet_name = %s
        WHERE instance_id = %s
    """, (
        network_info['vpc_id'],
        network_info['vpc_name'],
        network_info['subnet_id'],
        network_info['subnet_name'],
        instance_id
    ))
    conn.commit()
    cursor.close()
    conn.close()

def cleanup_old_entries():
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()

    # Remove servers not seen in the last 10 minutes
    cursor.execute("""
        DELETE FROM server_info
        WHERE last_seen IS NULL OR last_seen < NOW() - INTERVAL 10 MINUTE
    """)

    # Remove old status entries (older than 30 minutes)
    cursor.execute("""
        DELETE FROM status_entries
        WHERE time < NOW() - INTERVAL 30 MINUTE
    """)

    conn.commit()
    cursor.close()
    conn.close()

entries = get_missing_entries()
for entry in entries:
    instance_id = entry['instance_id']
    region = entry['availability_zone'][:-1]
    try:
        network_info = get_instance_network_info(instance_id, region)
        update_entry(instance_id, network_info)
    except Exception as e:
        print(f'Update failed: {e}')
cleanup_old_entries()
