#!/bin/bash

# This script sets up proper locale configuration to prevent warnings

# Install locales package and configure en_US.UTF-8
sudo apt-get update
sudo apt-get install -y locales
sudo sed -i "/en_US.UTF-8/s/^# //g" /etc/locale.gen
sudo locale-gen

# Set up environment variables
cat << EOF | sudo tee /etc/profile.d/locale.sh
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
EOF

# Configure SSH server to accept locale settings
echo "AcceptEnv LANG LC_*" | sudo tee -a /etc/ssh/sshd_config
sudo systemctl restart sshd