#!/bin/bash

# Shared utilities for all startup scripts
# Source this file in other scripts: source "$(dirname "$0")/shared-utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get project root directory
get_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}

# Print colored status messages
print_status() {
    local level="$1"
    local message="$2"
    case "$level" in
        "info")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
        "success")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "error")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "header")
            echo -e "${CYAN}🚀 $message${NC}"
            echo -e "${CYAN}$(printf '=%.0s' {1..50})${NC}"
            ;;
    esac
}

# Get Docker bridge IP for service registration
get_docker_bridge_ip() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local bridge_script
    bridge_script="$script_dir/detect-docker-bridge.sh"

    if [[ -x "$bridge_script" ]]; then
        "$bridge_script" detect 2>/dev/null
    else
        # Fallback to common default
        echo "172.17.0.1"
    fi
}

# Set registration host environment variable
set_registration_host() {
    local service_name
    service_name="$1"
    local env_var_name
    env_var_name="${2:-${service_name^^}_HOST}"  # Default to SERVICE_HOST

    # Check if already set
    if [[ -n "${!env_var_name}" ]]; then
        print_status "info" "$env_var_name already set to: ${!env_var_name}"
        # Still set DOCKER_HOST_IP if not set
        if [[ -z "$DOCKER_HOST_IP" ]]; then
            export DOCKER_HOST_IP="${!env_var_name}"
        fi
        return 0
    fi

    # Detect Docker bridge IP
    local bridge_ip
    bridge_ip=$(get_docker_bridge_ip)

    if [[ -n "$bridge_ip" ]]; then
        export "$env_var_name"="$bridge_ip"
        print_status "success" "Set $env_var_name=$bridge_ip (Docker bridge IP)"
        # Also set DOCKER_HOST_IP for consistent access
        if [[ -z "$DOCKER_HOST_IP" ]]; then
            export DOCKER_HOST_IP="$bridge_ip"
            print_status "success" "Set DOCKER_HOST_IP=$bridge_ip"
        fi
    else
        print_status "warning" "Could not detect Docker bridge IP, using localhost"
        export "$env_var_name"="localhost"
        if [[ -z "$DOCKER_HOST_IP" ]]; then
            export DOCKER_HOST_IP="localhost"
        fi
    fi
}

# Check if a service is running on a specific port
check_port() {
    local port="$1"
    local service_name="$2"
    
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_status "warning" "$service_name is already running on port $port"
        return 0
    else
        return 1
    fi
}

# Kill process on a specific port
kill_process_on_port() {
    local port="$1"
    local service_name="$2"
    
    if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_status "info" "No service found running on port $port."
        return 0
    fi

    local pid
    pid=$(lsof -Pi :$port -sTCP:LISTEN -t)
    
    if [[ -n "$pid" ]]; then
        print_status "warning" "Killing process $pid for $service_name on port $port..."
        if kill "$pid"; then
            # Wait a moment for the process to terminate
            sleep 2
            if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                print_status "success" "Process $pid terminated successfully."
                return 0
            else
                print_status "warning" "Process $pid may not have terminated. Trying force kill..."
                if kill -9 "$pid"; then
                    sleep 2
                    if ! lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
                        print_status "success" "Process $pid force-killed successfully."
                        return 0
                    fi
                fi
                print_status "error" "Failed to kill process $pid on port $port."
                return 1
            fi
        else
            print_status "error" "Failed to send kill signal to process $pid."
            return 1
        fi
    else
        print_status "info" "No process found for $service_name on port $port."
        return 0
    fi
}

# Check if Consul is running and accessible (optional check)
check_consul() {
    local consul_url="${CONSUL_URL:-http://localhost:8500}"
    
    if curl -s --connect-timeout 5 "$consul_url/v1/status/leader" > /dev/null 2>&1; then
        print_status "success" "Consul is running at $consul_url"
        return 0
    else
        print_status "info" "Consul not currently running (will be started by Quarkus DevServices)"
        return 1
    fi
}

# Check status of common infrastructure services (for status display)
check_infrastructure_status() {
    print_status "info" "Checking infrastructure services..."
    
    # Check Consul (8500)
    if curl -s --connect-timeout 3 "http://localhost:8500/v1/status/leader" > /dev/null 2>&1; then
        print_status "success" "Consul (8500) - Running"
    else
        print_status "info" "Consul (8500) - Not running (will auto-start with Quarkus)"
    fi
    
    # Check MySQL (3306)
    if nc -z localhost 3306 2>/dev/null; then
        print_status "success" "MySQL (3306) - Running"
    else
        print_status "info" "MySQL (3306) - Not running (will auto-start with Quarkus)"
    fi
    
    # Check OpenSearch (9200)
    if curl -s --connect-timeout 3 "http://localhost:9200/_cluster/health" > /dev/null 2>&1; then
        print_status "success" "OpenSearch (9200) - Running"
    else
        print_status "info" "OpenSearch (9200) - Not running (will auto-start with Quarkus)"
    fi
}

# Start a Quarkus service in dev mode
start_quarkus_service() {
    local service_name
    service_name="$1"
    local port
    port="$2"
    local gradle_path
    gradle_path="$3"
    local description
    description="$4"

    local project_root
    project_root="$(get_project_root)"

    print_status "header" "Starting $service_name"
    print_status "info" "Port: $port"
    print_status "info" "Description: $description"
    print_status "info" "Quarkus DevServices will auto-start required infrastructure"
    
    # Check if already running and offer to kill
    if check_port "$port" "$service_name"; then
        print_status "warning" "$service_name is already running on port $port."
        read -p "Would you like to kill the existing process and restart? (y/N) " -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            kill_process_on_port "$port" "$service_name"
        else
            print_status "info" "Cancelled by user."
            exit 0
        fi
    fi
    
    # Change to project root
    cd "$project_root" || {
        print_status "error" "Cannot change to project root: $project_root"
        exit 1
    }
    
    
    print_status "info" "Starting $service_name in Quarkus dev mode..."
    print_status "info" "DevServices will automatically start: Consul, MySQL, OpenSearch, etc."
    print_status "info" "Press Ctrl+C to stop"
    echo
    
    # Start the service
    ./gradlew "$gradle_path:quarkusDev"
}

# Wait for service to be ready
wait_for_service() {
    local service_name
    service_name="$1"
    local port
    port="$2"
    local max_attempts
    max_attempts="${3:-30}"
    local attempt=1
    
    print_status "info" "Waiting for $service_name to be ready on port $port..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s --connect-timeout 2 "http://localhost:$port/health" > /dev/null 2>&1; then
            print_status "success" "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo
    print_status "error" "$service_name did not become ready within $((max_attempts * 2)) seconds"
    return 1
}

# Export functions for use in other scripts
export -f get_project_root
export -f print_status
export -f get_docker_bridge_ip
export -f set_registration_host
export -f check_port
export -f check_consul
export -f check_infrastructure_status
export -f start_quarkus_service
export -f wait_for_service
export -f kill_process_on_port
