#!/bin/bash

# Script to install / uninstall Docker on a Linux machine

# Errors Handling
handle_error() {
    local step="$1"
    local error_message="$2"

    echo "❌ ERROR: $error_message"
    report_progress "$step" "failed" "$error_message"
    exit 1
}

install_docker() {
    #!/bin/bash
set -e

# Uninstall old versions (if any)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
done

# Update the apt package index and install required packages
sudo apt-get update
sudo apt-get install -y ca-certificates curl

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the Docker repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"${UBUNTU_CODENAME:-$VERSION_CODENAME}\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the apt package index again
sudo apt-get update

# Install Docker Engine, CLI, containerd, Buildx, and Compose plugin
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

}

# Uninstall docker

uninstall_docker() {
    #!/bin/bash
set -e

# Remove Docker Engine, CLI, containerd, Buildx, and Compose plugin
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Remove Docker’s official GPG key
sudo rm -rf /etc/apt/keyrings/docker.asc

# Remove the Docker repository from Apt sources
sudo rm -rf /etc/apt/sources.list.d/docker.list
}

uninstall_docker
#install_docker
