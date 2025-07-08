#!/bin/bash
# Copyright 2024 RustFS Team
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Development management script for RustFS multi-node deployment

# ps -ef | grep rustfs | awk '{print $2}'| xargs kill -9

# Local rustfs.zip path
ZIP_FILE="./rustfs.zip"
# Extract target directory
UNZIP_TARGET="./"

SERVER_LIST=(
    "root@node1" # node1
    "root@node2" # node2
    "root@node3" # node3
    "root@node4" # node4
    # "root@node5" # node5
    # "root@node6" # node6
    # "root@node7" # node7
    # "root@node8" # node8
)

REMOTE_TMP="~/rustfs"

# Deploy rustfs to all servers
deploy() {
    echo "Extracting $ZIP_FILE ..."
    unzip -o "$ZIP_FILE" -d "$UNZIP_TARGET"
    if [ $? -ne 0 ]; then
        echo "Extraction failed, exiting"
        exit 1
    fi

    LOCAL_RUSTFS="${UNZIP_TARGET}rustfs"
    if [ ! -f "$LOCAL_RUSTFS" ]; then
        echo "Extracted rustfs file not found, exiting"
        exit 1
    fi

    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Uploading $LOCAL_RUSTFS to $SERVER:$REMOTE_TMP"
        scp "$LOCAL_RUSTFS" "${SERVER}:${REMOTE_TMP}"
        if [ $? -ne 0 ]; then
            echo "❌ Failed to upload to $SERVER, skipping"
            continue
        fi

        echo "Performing systemctl operations and file replacement on $SERVER"
        ssh "$SERVER" bash <<EOF
set -e
echo "Stopping rustfs service"
sudo systemctl stop rustfs || true
echo "Replacing /usr/local/bin/rustfs"
sudo cp ~/rustfs /usr/local/bin/rustfs
sudo chmod +x /usr/local/bin/rustfs
echo "Starting rustfs service"
sudo systemctl start rustfs
echo "Checking rustfs service status"
sudo systemctl status rustfs --no-pager --lines=10
EOF

        if [ $? -eq 0 ]; then
            echo "✅ Successfully deployed and restarted rustfs on $SERVER"
        else
            echo "❌ Failed to deploy or restart rustfs on $SERVER"
        fi
    done
}

# Clear all files in /data/rustfs0~3 directories (including hidden files)
clear_data_dirs() {
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Clearing all files in $SERVER:/data/rustfs0~3"
        ssh "$SERVER" bash <<EOF
for i in {0..3}; do
    DIR="/data/rustfs$i"
    echo "Processing $DIR"
    if [ -d "$DIR" ]; then
        echo "Clearing $DIR"
        sudo rm -rf "$DIR"/* "$DIR"/.[!.]* "$DIR"/..?* 2>/dev/null || true
        echo "Successfully cleared $DIR"
    else
        echo "$DIR does not exist, skipping"
    fi
done
EOF
    done
}

# Control rustfs service
stop_rustfs() {
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Stopping rustfs service on $SERVER"
        ssh "$SERVER" "sudo systemctl stop rustfs"
    done
}

start_rustfs() {
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Starting rustfs service on $SERVER"
        ssh "$SERVER" "sudo systemctl start rustfs"
    done
}

restart_rustfs() {
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Restarting rustfs service on $SERVER"
        ssh "$SERVER" "sudo systemctl restart rustfs"
    done
}

# Add SSH public key to all servers' ~/.ssh/authorized_keys
add_ssh_key() {
    if [ -z "$2" ]; then
        echo "Usage: $0 addkey <pubkey_file>"
        exit 1
    fi
    PUBKEY_FILE="$2"
    if [ ! -f "$PUBKEY_FILE" ]; then
        echo "Specified public key file does not exist: $PUBKEY_FILE"
        exit 1
    fi
    PUBKEY_CONTENT=$(cat "$PUBKEY_FILE")
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Adding public key to $SERVER:~/.ssh/authorized_keys"
        ssh "$SERVER" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUBKEY_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
            echo "✅ Successfully added public key to $SERVER"
        else
            echo "❌ Failed to add public key to $SERVER"
        fi
    done
}

monitor_logs() {
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Monitoring logs on $SERVER:/var/logs/rustfs/rustfs.log ..."
        ssh "$SERVER" "tail -F /var/logs/rustfs/rustfs.log" |
            sed "s/^/[$SERVER] /" &
    done
    wait
}

set_env_file() {
    if [ -z "$2" ]; then
        echo "Usage: $0 setenv <env_file>"
        exit 1
    fi
    ENV_FILE="$2"
    if [ ! -f "$ENV_FILE" ]; then
        echo "Specified environment file does not exist: $ENV_FILE"
        exit 1
    fi
    for SERVER in "${SERVER_LIST[@]}"; do
        echo "Uploading $ENV_FILE to $SERVER:~/rustfs.env"
        scp "$ENV_FILE" "${SERVER}:~/rustfs.env"
        if [ $? -ne 0 ]; then
            echo "❌ Failed to upload to $SERVER, skipping"
            continue
        fi
        echo "Replacing $SERVER:/etc/default/rustfs"
        ssh "$SERVER" "sudo mv ~/rustfs.env /etc/default/rustfs"
        if [ $? -eq 0 ]; then
            echo "✅ Successfully replaced /etc/default/rustfs on $SERVER"
        else
            echo "❌ Failed to replace /etc/default/rustfs on $SERVER"
        fi
    done
}

# Main command dispatcher
case "$1" in
    deploy)
        deploy
        ;;
    clear)
        clear_data_dirs
        ;;
    stop)
        stop_rustfs
        ;;
    start)
        start_rustfs
        ;;
    restart)
        restart_rustfs
        ;;
    addkey)
        add_ssh_key "$@"
        ;;
    monitor)
        monitor_logs
        ;;
    setenv)
        set_env_file "$@"
        ;;
    *)
        echo "Usage: $0 {deploy|clear|stop|start|restart|addkey|monitor|setenv}"
        echo "Commands:"
        echo "  deploy  - Deploy rustfs binary to all servers"
        echo "  clear   - Clear all data directories on all servers"
        echo "  stop    - Stop rustfs service on all servers"
        echo "  start   - Start rustfs service on all servers"
        echo "  restart - Restart rustfs service on all servers"
        echo "  addkey  - Add SSH public key to all servers"
        echo "  monitor - Monitor logs from all servers"
        echo "  setenv  - Set environment file on all servers"
        exit 1
        ;;
esac
