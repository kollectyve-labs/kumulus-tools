#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting..."; exit 1;' ERR

exec > >(tee -i /var/log/docker_install.log) 2>&1

# Provider Status Reporting Configuration
KUMULUS_API_URL="${KUMULUS_API_URL:-http://localhost:8000}"
PROVIDER_ID="${PROVIDER_ID:-}"
PROVIDER_TOKEN="${PROVIDER_TOKEN:-}"

# Function to report installation progress
report_progress() {
    local step="$1"
    local status="$2"
    local progress="$3"
    local message="$4"
    
    if [ -n "$PROVIDER_ID" ] && [ -n "$KUMULUS_API_URL" ]; then
        echo "📊 Reporting progress: $step - $status ($progress%)"
        
        curl -s -X POST "$KUMULUS_API_URL/api/providers/$PROVIDER_ID/installation" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $PROVIDER_TOKEN" \
            -d "{
                \"step\": \"$step\",
                \"status\": \"$status\",
                \"progress\": $progress,
                \"message\": \"$message\",
                \"timestamp\": \"$(date -Iseconds)\"
            }" || echo "⚠️ Failed to report progress (continuing anyway)"
    fi
}

# Function to handle errors with reporting
handle_error() {
    local step="$1"
    local error_message="$2"
    
    echo "❌ ERROR: $error_message"
    report_progress "$step" "failed" 0 "$error_message"
    exit 1
}

# Check if the script is run as root or with sudo privileges
if [ "$(id -u)" -eq 0 ]; then
    echo "⚠️ Warning: This script is running as root. Proceeding..."
else
    echo "🔒 Running as a non-root user. Sudo privileges are required for installation."
    if ! sudo -v; then
        handle_error "permission_check" "You must have sudo privileges to run this script."
    fi
fi

# Ensure safe Git directory and correct ownership
INSTALL_DIR="/opt/kumulus-provider"
if [ -d "$INSTALL_DIR" ]; then
    git config --global --add safe.directory "$INSTALL_DIR"
    chown -R $(logname):$(logname) "$INSTALL_DIR"
fi

REPO_URL="https://github.com/kollectyve-labs/kumulus-provider.git"

echo "🚀 Starting Provider Setup..."
report_progress "setup_start" "in_progress" 0 "Starting provider setup"

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

    # Uninstall conflicting packages
    echo "🔄 Uninstalling conflicting packages..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc || echo "ℹ️ No conflicting packages found."

    # Set up Docker's apt repository
    echo "📦 Setting up Docker's apt repository..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    echo "🔄 Installing Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add current user to docker group
    sudo usermod -aG docker $USER

    echo "✅ Docker installed successfully!"
    docker --version
    report_progress "docker_install" "completed" 40 "Docker installed successfully"
fi

# Clone or update the repository
echo "📥 Setting up Kumulus provider repository..."
report_progress "repo_setup" "in_progress" 50 "Setting up repository"

if [ -d "$INSTALL_DIR" ]; then
    echo "📁 Directory $INSTALL_DIR already exists. Updating..."
    cd "$INSTALL_DIR"
    git pull origin main || handle_error "repo_setup" "Failed to update repository"
else
    echo "📥 Cloning repository..."
    sudo git clone "$REPO_URL" "$INSTALL_DIR" || handle_error "repo_setup" "Failed to clone repository"
    sudo chown -R $(logname):$(logname) "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

report_progress "repo_setup" "completed" 60 "Repository setup complete"

# Install Deno if not already installed
echo "🦕 Checking Deno installation..."
report_progress "deno_install" "in_progress" 70 "Installing Deno"

if ! command -v deno &>/dev/null; then
    echo "🔄 Installing Deno..."
    curl -fsSL https://deno.land/x/install/install.sh | sh
    export DENO_INSTALL="${DENO_INSTALL:-$HOME/.deno}"
    export PATH="$DENO_INSTALL/bin:$PATH"
    echo "✅ Deno installed successfully: $(deno --version)"
    report_progress "deno_install" "completed" 80 "Deno installed successfully"
else
    echo "✅ Deno is already installed: $(deno --version)"
    report_progress "deno_install" "completed" 80 "Deno already available"
fi

# Set up environment variables for the agent
echo "⚙️ Configuring environment..."
report_progress "config_setup" "in_progress" 85 "Configuring environment"

# Create environment file for the agent
cat > "$INSTALL_DIR/.env" << EOF
PROVIDER_ID=${PROVIDER_ID}
KUMULUS_API_URL=${KUMULUS_API_URL}
PROVIDER_TOKEN=${PROVIDER_TOKEN}
HEARTBEAT_INTERVAL=30000
EOF

echo "✅ Environment configured"
report_progress "config_setup" "completed" 88 "Environment configured"

# Run the provider agent with Deno
echo "🚀 Starting the provider agent using Deno..."
report_progress "agent_start" "in_progress" 90 "Starting Kumulus Spark Agent"

# Export environment variables for the agent
export PROVIDER_ID="${PROVIDER_ID}"
export KUMULUS_API_URL="${KUMULUS_API_URL}"
export PROVIDER_TOKEN="${PROVIDER_TOKEN}"
export HEARTBEAT_INTERVAL="30000"

# Start agent in background and check if it starts successfully
deno run --allow-env --allow-read --allow-net --unstable-cron --allow-run --allow-write main.ts &
AGENT_PID=$!

# Wait a moment for agent to start
sleep 5

# Check if agent is still running
if kill -0 $AGENT_PID 2>/dev/null; then
    report_progress "agent_start" "completed" 100 "Kumulus Spark Agent started successfully"
    echo "🎉 Setup complete! The provider is now running."
    echo "Agent PID: $AGENT_PID"
    echo "The agent will now start sending heartbeats to the console."
    echo ""
    echo "📊 You can monitor your provider status at: ${KUMULUS_API_URL}/dashboard"
    echo "🔧 Agent logs are available in: /var/log/docker_install.log"
    echo ""
    echo "To stop the agent: kill $AGENT_PID"
    echo "To restart: cd $INSTALL_DIR && ./provider-setup.sh"
    
    # Keep the script running to maintain the agent
    wait $AGENT_PID
else
    handle_error "agent_start" "Agent failed to start properly"
fi
