import platform
import pymysql
import re
import requests
import socket
import subprocess
from datetime import datetime, timedelta, UTC

with open('/opt/server-status/master-ip.txt', 'r') as f:
    master_ip = f.read().strip()

DB_CONFIG = {
    'host': master_ip,
    'user': 'server-status',
    'password': 'ahN64B0tyx3N',
    'database': 'servers',
    'cursorclass': pymysql.cursors.DictCursor
}
METADATA_URL = "http://169.254.169.254/latest"
TOKEN_URL = f"{METADATA_URL}/api/token"
HEADERS = {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}

hostname = socket.gethostname()

def is_aws_instance():
    try:
        response = requests.put(TOKEN_URL, headers=HEADERS, timeout=0.2)
        return response.status_code == 200
    except requests.RequestException:
        return False

def get_public_ip():
    try:
        response = requests.get("https://api.ipify.org", timeout=2)
        return response.text
    except requests.RequestException:
        return None

def get_private_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None

def get_metadata_token():
    try:
        response = requests.put(TOKEN_URL, headers=HEADERS, timeout=2)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Failed to get metadata token: {e}")
        return None

def get_metadata(path, token):
    try:
        headers = {"X-aws-ec2-metadata-token": token}
        url = f"{METADATA_URL}/meta-data/{path}"
        response = requests.get(url, headers=headers, timeout=2)
        response.raise_for_status()
        return response.text
    except Exception as e:
        print(f"Failed to get {path}: {e}")
        return None

def get_ec2_metadata():
    if is_aws_instance():
        token = get_metadata_token()
        if not token:
            return None

        return {
            "instance_id": get_metadata("instance-id", token),
            "availability_zone": get_metadata("placement/availability-zone", token),
            "hostname": hostname,
            "public_ip": get_metadata("public-ipv4", token),
            "private_ip": get_metadata("local-ipv4", token)
        }

    return {
        "instance_id": "test-host",
        "availability_zone": "home",
        "hostname": hostname,
        "public_ip": get_public_ip(),
        "private_ip": get_private_ip()
    }


def register_self(conn, metadata):
    with conn.cursor() as cursor:
        statement = """
            INSERT INTO server_info (
                instance_id,
                hostname,
                private_ip,
                public_ip,
                availability_zone,
                last_seen
            ) VALUES (%s, %s, %s, %s, %s, UTC_TIMESTAMP())
            ON DUPLICATE KEY UPDATE 
                hostname = VALUES(hostname),
                private_ip = VALUES(private_ip),
                public_ip = VALUES(public_ip),
                availability_zone = VALUES(availability_zone),
                last_seen = UTC_TIMESTAMP()
        """
        cursor.execute(statement, (
            metadata['instance_id'],
            hostname,
            metadata['private_ip'],
            metadata['public_ip'],
            metadata['availability_zone']
        ))
    conn.commit()

def get_live_servers(conn, my_instance_id):
    with conn.cursor() as cursor:
        statement = """
            SELECT
                instance_id,
                private_ip
            FROM server_info
            WHERE last_seen >= %s 
            AND instance_id != %s 
            AND private_ip IS NOT NULL
        """
        cursor.execute(statement,
        (
            datetime.now(UTC) - timedelta(minutes=5),
            my_instance_id
        ))
        return cursor.fetchall()

def ping_host(ip):
    try:
        if platform.system() != "Windows":
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '2', ip],
                capture_output=True, text=True, timeout=3, check=False
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "time=" in line:
                        latency = float(line.split("time=")[1].split(" ")[0])
                        return True, latency
        else:
            result = subprocess.run(
                ['ping', '-n', '1', '-w', '2', ip],
                capture_output=True, text=True, timeout=3, check=False
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    match = re.search(r'time[=<]([0-9]+)ms', line)
                    if match:
                        latency = int(match.group(1))
                        return True, latency
        return False, None
    except Exception:
        return False, None


def report_status(conn, dest_id, latency, success, metadata):
    with conn.cursor() as cursor:
        statement = """
            INSERT INTO status_entries (
                time, 
                source_instance_id, 
                destination_instance_id, 
                success, 
                latency
            ) VALUES (UTC_TIMESTAMP(), %s, %s, %s, %s)
        """
        cursor.execute(statement, (
            metadata['instance_id'],
            dest_id,
            int(success),
            latency if success else None
        ))
    conn.commit()

metadata = get_ec2_metadata()
print(metadata)

conn = pymysql.connect(**DB_CONFIG)

register_self(conn, metadata)

servers = get_live_servers(conn, metadata['instance_id'])

success, latency = ping_host('8.8.8.8')
report_status(conn, 'google', latency, success, metadata)

for server in servers:
    success, latency = ping_host(server['private_ip'])
    report_status(conn, server['instance_id'], latency, success, metadata)

conn.close()