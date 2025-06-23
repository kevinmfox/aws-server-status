#!/bin/bash

# set the hostname
sudo hostnamectl set-hostname "${new_hostname}"
echo "${new_hostname}" | sudo tee /etc/hostname > /dev/null
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t${new_hostname}/" /etc/hosts

# prep the server
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install mysql-server python3-flask python3-pymysql unzip curl -y

# install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# get our SQL server setup
cat <<EOFSQL > /tmp/init.sql
CREATE USER 'admin'@'%' IDENTIFIED BY 'ahN64B0tyx3N';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

CREATE DATABASE servers;
CREATE USER 'server-status'@'%' IDENTIFIED BY 'ahN64B0tyx3N';
GRANT ALL PRIVILEGES ON servers.* TO 'server-status'@'%';
FLUSH PRIVILEGES;

USE servers;
CREATE TABLE server_info (
  instance_id varchar(32) NOT NULL,
  hostname varchar(32) NOT NULL,
  private_ip varchar(45) DEFAULT NULL,
  public_ip varchar(45) DEFAULT NULL,
  availability_zone varchar(45) NOT NULL,
  vpc_id varchar(45) DEFAULT NULL,
  vpc_name varchar(45) DEFAULT NULL,
  subnet_id varchar(45) DEFAULT NULL,
  subnet_name varchar(45) DEFAULT NULL,
  last_seen timestamp NULL DEFAULT NULL,
  PRIMARY KEY (instance_id),
  UNIQUE KEY instance_id_UNIQUE (instance_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE status_entries (
  time timestamp NOT NULL,
  source_instance_id varchar(45) NOT NULL,
  destination_instance_id varchar(45) NOT NULL,
  success tinyint NOT NULL,
  latency float DEFAULT NULL,
  PRIMARY KEY (time,source_instance_id,destination_instance_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
EOFSQL

mysql < /tmp/init.sql
sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl restart mysql

TARGET_DIR="/opt/server-status"
PYTHON_BIN="/usr/bin/python3"

sudo mkdir -p $TARGET_DIR/templates

echo "127.0.0.1" > $TARGET_DIR/master-ip.txt

# pull down the application files
curl -o $TARGET_DIR/master.py https://raw.githubusercontent.com/kevinmfox/server-status/main/scripts/master.py
curl -o $TARGET_DIR/app.py https://raw.githubusercontent.com/kevinmfox/server-status/main/web-app/app.py
curl -o $TARGET_DIR/templates/index.html https://raw.githubusercontent.com/kevinmfox/server-status/main/web-app/index.html

# setup our flask web app service
cat <<EOFAPP > /etc/systemd/system/server-status.service
[Unit]
Description=Server Status Flask App
After=network.target

[Service]
Environment="FLASK_APP=app.py"
Environment="FLASK_RUN_PORT=80"
Environment="FLASK_RUN_HOST=0.0.0.0"
WorkingDirectory=/opt/server-status
ExecStart=/usr/bin/flask run
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOFAPP

systemctl daemon-reexec
systemctl enable --now server-status

# setup the script that will update the server information (via AWS CLI)
sudo chmod +x $TARGET_DIR/master.py
(crontab -l 2>/dev/null; echo "* * * * * $PYTHON_BIN $TARGET_DIR/master.py >> /var/log/server_status.log 2>&1") | crontab -