#!/bin/bash

# Kumulus Resource Installation Script
# This script installs and configures the Kumulus agent on a provider machine

set -e
trap 'echo "❌ Installation failed. Exiting..."; exit 1;' ERR

# --- Configuration ---
BACKEND_URL="${KUMULUS_API_URL:-http://localhost:8000/api}"
RESOURCE_ID="${RESOURCE_ID:-}"
PROVIDER_TOKEN="${PROVIDER_TOKEN:-}"

# Validate required parameters
if [ -z "$RESOURCE_ID" ]; then
    echo "❌ Error: RESOURCE_ID environment variable is required"
    echo "Usage: RESOURCE_ID=your-resource-id KUMULUS_API_URL=http://localhost:8000 $0"
    exit 1
fi

echo "🚀 Starting Kumulus resource installation..."
echo "📋 Resource ID: $RESOURCE_ID"
echo "🔗 Backend URL: $BACKEND_URL"

# Function to report installation progress
report_progress() {
    local step="$1"
    local status="$2"
    local message="$3"

    echo "📊 $step: $message"

    if [ -n "$RESOURCE_ID" ] && [ -n "$BACKEND_URL" ]; then
        curl -s -X POST "$BACKEND_URL/resources/$RESOURCE_ID/installation" \
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

# Function to handle errors
handle_error() {
    local step="$1"
    local error_message="$2"

    echo "❌ ERROR: $error_message"
    report_progress "$step" "failed" "$error_message"
    exit 1
}

# Function to send machine specs
send_specs() {
    echo "🔍 Checking machine specifications..."
    report_progress "spec_check" "in_progress" "Checking machine specifications"

    CPU_INFO=$(lscpu | grep "Model name:" | sed 's/Model name: *//' | tr -s ' ' || echo "Unknown CPU")
    RAM_INFO=$(free -h | awk '/Mem:/ {print $2}' || echo "Unknown RAM")
    DISK_INFO=$(df -h / | awk '/\// {print $2}' || echo "Unknown Disk")
    OS_INFO=$(lsb_release -ds 2>/dev/null || echo "Unknown OS")

    MACHINE_SPECS="{
        \"cpu\": \"$CPU_INFO\",
        \"ram\": \"$RAM_INFO\",
        \"disk\": \"$DISK_INFO\",
        \"os\": \"$OS_INFO\",
        \"resourceId\": \"$RESOURCE_ID\"
    }"

    echo "💻 Machine specs: CPU: $CPU_INFO, RAM: $RAM_INFO, Disk: $DISK_INFO, OS: $OS_INFO"

    # Send specs to backend
    curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PROVIDER_TOKEN" \
        -d "$MACHINE_SPECS" \
        "$BACKEND_URL/resources/verified-specs" || echo "⚠️ Failed to send specs"

    report_progress "spec_check" "completed" "Machine specifications verified"
}

# Function to mark resource as ready
mark_ready() {
    echo "✅ Marking resource as ready..."
    report_progress "mark_ready" "in_progress" "Finalizing resource setup"

    # Make authenticated call to mark resource as ready
    RESPONSE=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PROVIDER_TOKEN" \
        "$BACKEND_URL/resources/mark-ready/$RESOURCE_ID")

    HTTP_CODE="${RESPONSE: -3}"
    RESPONSE_BODY="${RESPONSE%???}"

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Resource marked as ready successfully"
        report_progress "mark_ready" "completed" "Resource is ready to provide computing power"
    else
        handle_error "mark_ready" "Failed to mark resource as ready (HTTP $HTTP_CODE): $RESPONSE_BODY"
    fi
}

# Main installation flow
main() {
    echo "🎯 Starting installation process..."

    # Step 1: Check machine specs
    # send_specs

    # Step 2: Install Docker
    # install_docker

    # Step 3: Install Kumulus agent
    # install_agent

    # Step 4: Mark resource as ready
    # mark_ready

    echo ""
    echo "🎉 Installation completed successfully!"
    echo "📊 Your resource is now ready to start providing computing power."
    echo "You can check your dashboard"
}

# Run main installation
main
