#!/bin/bash

# set the hostname
sudo hostnamectl set-hostname "${new_hostname}"
echo "${new_hostname}" | sudo tee /etc/hostname > /dev/null
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t${new_hostname}/" /etc/hosts

# prep the server
sudo apt-get update
sudo apt-get install git python3-pymysql -y

TARGET_DIR="/opt/server-status"
PYTHON_BIN="/usr/bin/python3"

sudo mkdir -p $TARGET_DIR

echo "${master_ip}" > $TARGET_DIR/master-ip.txt

# pull down the python app script
curl -o $TARGET_DIR/child.py https://raw.githubusercontent.com/kevinmfox/server-status/main/scripts/child.py

sudo chmod +x $TARGET_DIR/child.py

# setup our service to run the script every X seconds
cat <<EOFAPP > /etc/systemd/system/child-status.service
[Unit]
Description=Report server status
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/server-status/child.py
Restart=always
User=root
EOFAPP

cat <<EOFTIMER > /etc/systemd/system/child-status.timer
[Unit]
Description=Timer for child-status service
After=network.target

[Timer]
OnBootSec=30
OnUnitActiveSec=30
Unit=child-status.service

[Install]
WantedBy=timers.target
EOFTIMER

sudo systemctl daemon-reexec
sudo systemctl enable --now child-status.timer