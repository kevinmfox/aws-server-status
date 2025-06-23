from flask import Flask, render_template
import pymysql

app = Flask(__name__)

with open('/opt/server-status/master-ip.txt', 'r') as f:
    master_ip = f.read().strip()

DB_CONFIG = {
    'host': master_ip,
    'user': 'server-status',
    'password': 'ahN64B0tyx3N',
    'database': 'servers',
    'cursorclass': pymysql.cursors.DictCursor
}

@app.route("/")
def status_matrix():
    conn = pymysql.connect(**DB_CONFIG)
    try:
        with conn.cursor() as cursor:
            # get all recent ping results (last 3 minutes, 1 row per pair)
            statement = """
                SELECT 
                    source_instance_id, 
                    destination_instance_id, 
                    success, 
                    latency
                FROM status_entries
                WHERE time >= NOW() - INTERVAL 3 MINUTE
            """
            cursor.execute(statement)
            results = cursor.fetchall()

            # build instance set
            instances = sorted(set(row['source_instance_id'] for row in results) |
                               set(row['destination_instance_id'] for row in results))

            # build the matrix
            matrix = {src: {dst: {"status": None, "latency": None} for dst in instances} for src in instances}

            for row in results:
                src = row['source_instance_id']
                dst = row['destination_instance_id']
                matrix[src][dst]["status"] = row['success']
                if row['success'] == 1:
                    matrix[src][dst]['latency'] = row['latency']

            # get server info
            statement = """
                SELECT 
                    instance_id, 
                    hostname, 
                    private_ip, 
                    public_ip,
                    availability_zone, 
                    vpc_id, 
                    vpc_name,
                    subnet_id, 
                    subnet_name, 
                    last_seen
                FROM server_info
                ORDER BY hostname            
            """
            cursor.execute(statement)
            instance_info = cursor.fetchall()
    finally:
        conn.close()

    return render_template('index.html', instances=instances, instance_info=instance_info, matrix=matrix)
