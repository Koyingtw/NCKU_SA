#!/usr/bin/env python3


import subprocess
import argparse

def create_snapshot(snapshot_name):
    subprocess.run(["zfs", "snapshot", f"sa_pool/data@{snapshot_name}"])

def remove_snapshot(snapshot_name):
    #print(snapshot_name)
    if snapshot_name == "all":
        list_snapshots_cmd = ["zfs", "list", "-H", "-t", "snapshot", "-o", "name", "-r", "sa_pool/data"]
        snapshots = subprocess.check_output(list_snapshots_cmd).decode().strip().split('\n')
        for snapshot in snapshots:
            destroy_cmd = ["zfs", "destroy", snapshot]
            subprocess.run(destroy_cmd)
    else:
        subprocess.run(["zfs", "destroy", f"sa_pool/data@{snapshot_name}"])

def list_snapshots():
    result = subprocess.run(["zfs", "list", "-rH", "-t", "snapshot", "-o", "name", "sa_pool/data"], stdout=subprocess.PIPE)
    output = result.stdout.decode('utf-8')
    print(output)

def rollback_snapshot(snapshot_name):
    subprocess.run(["zfs", "rollback", "-r", f"sa_pool/data@{snapshot_name}"])

def create_logrotate_config():
    config = f"/var/log/fakelog.log\n" \
             f"{{\n" \
             f"    rotate 9\n" \
             f"    size 1K\n" \
             f"    postrotate\n" \
             f"        sudo cp /var/log/fakelog.log.* /sa_data/log/\n" \
             f"    endscript\n" \
             f"}}\n"
    #with open("/usr/local/etc/logrotate.d/sabktool", "w") as f:
        #f.write(config)
    subprocess.run(["logrotate", "/usr/local/etc/logrotate.d/sabktool"])

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='ZFS Snapshot Tool')
    parser.add_argument('command', type=str, choices=['create', 'remove', 'list', 'roll', 'logrotate'], help='Command to execute')
    parser.add_argument('args', nargs='?', type=str, help='Arguments for the command')

    args = parser.parse_args()
    command = args.command

    if command == "list":
        #print("list")
        list_snapshots()
        exit(0)
    elif command == "logrotate":
        create_logrotate_config()
    else:
        #parser.add_argument('args', nargs='+', type=str, help='Arguments for the command')
        args = parser.parse_args()
        command_args = args.args

    if command == "create":
        snapshot_name = command_args
        create_snapshot(snapshot_name)
    elif command == "remove":
        snapshot_name = command_args
        remove_snapshot(snapshot_name)
    elif command == "list":
        list_snapshots()
    elif command == "roll":
        snapshot_name = command_args
        rollback_snapshot(snapshot_name)
    elif command == "logrotate":
        create_logrotate_config()
