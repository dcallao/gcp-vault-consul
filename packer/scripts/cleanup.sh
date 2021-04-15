#!/usr/bin/env bash
set -euxo pipefail

echo "Running"

echo "Cleanup install artifacts"
sudo rm -f /root/.ssh/authorized_keys
sudo rm -f /etc/ssh/ssh_host_*
#sudo rm -rf /tmp/*
history -c

echo "Complete"