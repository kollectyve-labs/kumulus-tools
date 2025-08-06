#!/bin/bash

# Kumulus Resource Installation Script
# This script installs and configures the Kumulus agent on a provider machine

set -e
trap 'echo "❌ Installation failed. Exiting..."; exit 1;' ERR

# ---  ---
BACKEND_URL="${KUMULUS_API_URL:-http://localhost:8000/api}"
RESOURCE_ID="${RESOURCE_ID:-}"
PROVIDER_TOKEN="${PROVIDER_TOKEN:-}"
FILENAME="flare-agent-v0.1.0-alpha"
BASTION_ADDRESS=""
BASTION_PORT=7777
BASTION_PUB=""
AGENT_PORT=8700

# Validate required parameters
if [ -z "$RESOURCE_ID" ]; then
    echo "❌ Error: RESOURCE_ID environment variable is required"
    echo "Usage: RESOURCE_ID=your-resource-id KUMULUS_API_URL=http://localhost:8000 $0"
    exit 1
fi

echo "🚀 Starting Kumulus resource installation..."
echo "📋 Resource ID: $RESOURCE_ID"
echo "🔗 Backend URL: $BACKEND_URL"

# Report installation progress
report_progress() {
    local step="$1"
    local status="$2"
    local message="$3"

    echo "📊 $step: $message"

    if [ -n "$RESOURCE_ID" ] && [ -n "$BACKEND_URL" ]; then
        curl -s -X POST "$BACKEND_URL/temp/$RESOURCE_ID/installation" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $PROVIDER_TOKEN" \
            -d "{
                \"step\": \"$step\",
                \"status\": \"$status\",
                \"message\": \"$message\",
                \"timestamp\": \"$(date -Iseconds)\"
            }" || echo "⚠️ Failed to report progress (continuing anyway)"
    fi
}

# Errors Handling
handle_error() {
    local step="$1"
    local error_message="$2"

    echo "❌ ERROR: $error_message"
    report_progress "$step" "failed" "$error_message"
    exit 1
}

# Send Resource specs
send_specs() {
    echo "🔍 Checking machine specifications..."
    report_progress "spec_check" "in_progress" "Checking machine specifications"

    CPU_INFO=$(lscpu | grep "Model name:" | sed 's/Model name: *//' | tr -s ' ' || echo "Unknown CPU")
    RAM_INFO=$(free -h | awk '/Mem:/ {print $2}' || echo "Unknown RAM")
    DISK_INFO=$(df -h / | awk '/\// {print $2}' || echo "Unknown Disk")
    OS_INFO=$(lsb_release -ds 2>/dev/null || echo "Unknown OS")
    MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2}' | head -n 1 || echo "Unknown MAC")
    IP_ADDRESS=$(curl -s https://api.ipify.org || echo "Unknown IP")
    
    MACHINE_SPECS="{
        \"cpu\": \"$CPU_INFO\",
        \"ram\": \"$RAM_INFO\",
        \"disk\": \"$DISK_INFO\",
        \"os\": \"$OS_INFO\",
        \"resourceId\": \"$RESOURCE_ID\",
        \"macAddress\": \"$MAC_ADDRESS\",
        \"ipAddress\": \"$IP_ADDRESS\"
    }"

    echo "💻 Machine specs: CPU: $CPU_INFO, RAM: $RAM_INFO, Disk: $DISK_INFO, OS: $OS_INFO"

    # Send specs to backend
    curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PROVIDER_TOKEN" \
        -d "$MACHINE_SPECS" \
        "$BACKEND_URL/temp/verified-specs" || echo "⚠️ Failed to send specs"

    report_progress "spec_check" "completed" "Machine specifications verified"
}

# Install Docker
install_docker() {
    echo "🔍 Checking Docker installation..."
    # Check if Docker is already installed
    report_progress "docker_check" "in_progress" 10 "Checking Docker installation"
    if command -v docker &>/dev/null; then
        echo "✅ Docker is already installed."
        docker --version
        report_progress "docker_check" "completed" 20 "Docker already available"
    else
        echo "🔄 Docker is not installed. Installing Docker..."
        report_progress "docker_install" "in_progress" 15 "Installing Docker"

        # Detect OS
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [[ "$ID" != "ubuntu" ]]; then
                handle_error "docker_install" "Unsupported OS: $ID"
            fi
        else
            handle_error "docker_install" "Unable to detect OS"
        fi

                
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

        # Start and enable Docker
        sudo systemctl start docker
        sudo systemctl enable docker

        # Add current user to docker group
        sudo usermod -aG docker $USER

        echo "✅ Docker installed successfully!"
        docker --version
        #report_progress "docker_install" "completed" 40 "Docker installed successfully"
    fi
}

uninstall_docker() {

    set -e

    # Remove Docker Engine, CLI, containerd, Buildx, and Compose plugin
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Remove Docker’s official GPG key
    sudo rm -rf /etc/apt/keyrings/docker.asc

    # Remove the Docker repository from Apt sources
    sudo rm -rf /etc/apt/sources.list.d/docker.list
}

# Mark resource as ready
mark_ready() {
    echo "✅ Marking resource as ready..."
    report_progress "mark_ready" "in_progress" "Finalizing resource setup"

    # Make authenticated call to mark resource as ready
    RESPONSE=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PROVIDER_TOKEN" \
        "$BACKEND_URL/temp/mark-ready/$RESOURCE_ID")

    HTTP_CODE="${RESPONSE: -3}"
    RESPONSE_BODY="${RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Resource marked as ready successfully"
        report_progress "mark_ready" "completed" "Resource is ready to provide computing power"
    else
        handle_error "mark_ready" "Failed to mark resource as ready (HTTP $HTTP_CODE): $RESPONSE_BODY"
    fi
}

# Downloading Kumulus agent
download_agent() {
    echo "🔍 Checking agent installation..."
    report_progress "agent_install" "in_progress" "Downloading and running the Kumulus agent"
    # Checking if agent not already downloaded
    if [ -f "${FILENAME}" ]; then
        echo "✅ Agent already downloaded"
    else
        echo "🔄 Downloading agent..."
        # Download the agent
        curl -L "https://github.com/kollectyve-labs/kumulus-tools/releases/download/v0.1.0-alpha/${FILENAME}" -o "${FILENAME}"
        chmod +x "${FILENAME}"
    fi
}

# Run the agent
run_agent() {
    echo "🚀 Starting the agent..."
    nohup ./"${FILENAME}" > agent.log 2>&1 &
    echo $! > agent.pid
}

# Open ssh tunnel to the jumphost so that the agent can receive http requests through the bastion
open_tunnel() {
    echo "Opening tunnel to the bastion..."
    # Check if ssh already in authorized keys
    if grep -q "$BASTION_PUB" ~/.ssh/authorized_keys; then
        echo "✅ Bastion already in authorized keys"
    else
        echo "🔄 Adding bastion to authorized keys"
        # Add bastion public key to authorized keys
        echo "$BASTION_PUB" >> ~/.ssh/authorized_keys
    fi
        # Open tunnel
        ssh -N -R $BASTION_PORT:localhost:$AGENT_PORT ubuntu@$BASTION_ADDRESS
        #echo $! > tunnel.pid
}


# TODO: Improve using ws or similar
# Main installation flow
main() {
    echo "🎯 Starting installation process..."
    send_specs
    #install_docker
    #download_agent
    mark_ready
    #open_tunnel
    #run_agent

    echo ""
    echo "🎉 Installation completed successfully!"
    echo "📊 Your resource is now ready to start providing computing power."
    echo "You can check your dashboard"
}

main
