#!/bin/bash

echo "     #############################################"
echo "     #                                           #"
echo "     #      Script powered by Chiappina.com      #"
echo "     #                                           #"
echo "     #############################################"
echo
echo "     Disclaimer: Use this script at your own risk!     "
echo "Always ensure you have proper backups before proceeding."
echo
sleep 2

# Prompt user for VMID and new size
echo "Fetching container list..."
pct list
echo
read -p "Enter the VMID of the container you want to resize: " VMID
read -p "Enter the new size (e.g., 5G): " NEW_SIZE

# Confirm with the user
echo "You have selected VMID: $VMID and new size: $NEW_SIZE"
read -p "Are you sure you want to continue? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Operation aborted."
    exit 1
fi

# Stop the container, if running
echo "Stopping container $VMID..."
pct stop "$VMID" 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "Container $VMID stopped successfully."
else
    echo "Container $VMID was not running."
fi

# Find and display the LV path (search for any disk number)
echo "Finding logical volume path for VMID $VMID..."
DISK_NAME=$(lvdisplay | grep "vm-$VMID-disk-" | grep -v snap | head -n1 | awk '{print $3}' | sed 's#.*/##')
LV_PATH=$(lvdisplay | grep -A1 "$DISK_NAME" | grep "LV Path" | awk '{print $3}')

if [[ -z "$LV_PATH" ]]; then
    echo "Failed to find LV path. Exiting."
    exit 1
fi
echo "LV Path: $LV_PATH"
echo "Disk name: $DISK_NAME"

# Activate the logical volume
echo "Activating logical volume $LV_PATH..."
lvchange -a y "$LV_PATH" || { echo "Failed to activate logical volume. Exiting."; exit 1; }

# Reduce the logical volume and filesystem
echo "Reducing logical volume and filesystem to $NEW_SIZE..."
lvreduce -r -L "$NEW_SIZE" "$LV_PATH" || { echo "Logical volume reduction failed. Exiting."; exit 1; }

# Deactivate the logical volume
echo "Deactivating logical volume $LV_PATH..."
lvchange -a n "$LV_PATH" || { echo "Failed to deactivate logical volume. Exiting."; exit 1; }

# Edit the container configuration
CONF_FILE="/etc/pve/lxc/$VMID.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    echo "Container configuration file not found. Exiting."
    exit 1
fi

echo "Updating container configuration file $CONF_FILE..."
sed -i "s|rootfs:.*|rootfs: local-lvm:$DISK_NAME,size=$NEW_SIZE|" "$CONF_FILE" || { echo "Failed to update container configuration. Exiting."; exit 1; }

# Start the container
echo "Starting container $VMID..."
pct start "$VMID" || { echo "Failed to start container. Please check manually."; exit 1; }

echo "Container $VMID resized and started successfully!"
exit 0
