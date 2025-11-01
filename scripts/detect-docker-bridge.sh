#!/bin/bash

# Docker Bridge IP Detection Utility
# Detects the correct Docker bridge IP for service registration across platforms

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored status messages
print_status() {
    local level="$1"
    local message="$2"
    case "$level" in
        "info")
            echo -e "${BLUE}ℹ️  $message${NC}" >&2
            ;;
        "success")
            echo -e "${GREEN}✅ $message${NC}" >&2
            ;;
        "warning")
            echo -e "${YELLOW}⚠️  $message${NC}" >&2
            ;;
        "error")
            echo -e "${RED}❌ $message${NC}" >&2
            ;;
    esac
}

# Function to detect Docker bridge IP
detect_docker_bridge_ip() {
    local detected_ip=""
    local detection_method=""
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        print_status "error" "Docker CLI not found. Please install Docker."
        return 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info > /dev/null 2>&1; then
        print_status "error" "Docker daemon is not running. Please start Docker."
        return 1
    fi
    
    print_status "info" "Detecting Docker bridge IP for service registration..."

    # On macOS, use host.docker.internal directly (Linux bridge methods don't work)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        detected_ip="host.docker.internal"
        detection_method="macOS Docker Desktop (host.docker.internal)"
        print_status "success" "macOS detected - using host.docker.internal"
        echo "$detected_ip"
        return 0
    fi

    # Method 1: Try to get the bridge IP from Docker network inspect (Linux)
    if [[ -z "$detected_ip" ]]; then
        print_status "info" "Method 1: Checking Docker bridge network..."
        detected_ip=$(docker network inspect bridge --format='{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null || true)
        if [[ -n "$detected_ip" && "$detected_ip" != "<no value>" ]]; then
            detection_method="Docker bridge network gateway"
            print_status "success" "Found bridge IP via Docker network: $detected_ip"
        else
            print_status "warning" "Could not detect IP via Docker bridge network"
            detected_ip=""
        fi
    fi
    
    # Method 2: Try to get IP from docker0 interface (Linux)
    if [[ -z "$detected_ip" ]]; then
        print_status "info" "Method 2: Checking docker0 interface..."
        if command -v ip &> /dev/null; then
            detected_ip=$(ip route show | grep docker0 | grep -E 'src [0-9.]+' | head -1 | sed -n 's/.*src \([0-9.]*\).*/\1/p' 2>/dev/null || true)
            if [[ -n "$detected_ip" ]]; then
                detection_method="docker0 interface (Linux)"
                print_status "success" "Found bridge IP via docker0 interface: $detected_ip"
            fi
        fi
        
        # Fallback for Linux using ifconfig
        if [[ -z "$detected_ip" ]] && command -v ifconfig &> /dev/null; then
            detected_ip=$(ifconfig docker0 2>/dev/null | grep 'inet ' | awk '{print $2}' | sed 's/addr://' || true)
            if [[ -n "$detected_ip" ]]; then
                detection_method="docker0 interface via ifconfig (Linux)"
                print_status "success" "Found bridge IP via ifconfig: $detected_ip"
            fi
        fi
        
        if [[ -z "$detected_ip" ]]; then
            print_status "warning" "Could not detect IP via docker0 interface"
        fi
    fi
    
    # Method 3: Try host.docker.internal resolution (Docker Desktop)
    if [[ -z "$detected_ip" ]]; then
        print_status "info" "Method 3: Checking host.docker.internal..."
        detected_ip=$(docker run --rm alpine nslookup host.docker.internal 2>/dev/null | grep 'Address:' | tail -1 | awk '{print $2}' || true)
        if [[ -n "$detected_ip" && "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            detection_method="host.docker.internal resolution (Docker Desktop)"
            print_status "success" "Found bridge IP via host.docker.internal: $detected_ip"
        else
            print_status "warning" "Could not resolve host.docker.internal"
            detected_ip=""
        fi
    fi
    
    # Method 4: Try to get the default route IP that containers would use to reach host
    if [[ -z "$detected_ip" ]]; then
        print_status "info" "Method 4: Checking container's view of host..."
        detected_ip=$(docker run --rm alpine route -n 2>/dev/null | grep '^0.0.0.0' | awk '{print $2}' | head -1 || true)
        if [[ -n "$detected_ip" && "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            detection_method="Container default gateway"
            print_status "success" "Found bridge IP via container routing: $detected_ip"
        else
            print_status "warning" "Could not detect IP via container routing"
            detected_ip=""
        fi
    fi
    
    # Method 5: Platform-specific fallbacks
    if [[ -z "$detected_ip" ]]; then
        print_status "info" "Method 5: Using platform-specific fallbacks..."
        
        case "$(uname -s)" in
            Linux*)
                # Common Linux Docker bridge IP
                detected_ip="172.17.0.1"
                detection_method="Linux default (172.17.0.1)"
                print_status "warning" "Using Linux default: $detected_ip"
                ;;
            Darwin*)
                # macOS with Docker Desktop
                detected_ip="host.docker.internal"
                detection_method="macOS default (host.docker.internal)"
                print_status "warning" "Using macOS default: $detected_ip"
                ;;
            CYGWIN*|MINGW32*|MSYS*|MINGW*)
                # Windows with Docker Desktop
                detected_ip="host.docker.internal"
                detection_method="Windows default (host.docker.internal)"
                print_status "warning" "Using Windows default: $detected_ip"
                ;;
            *)
                print_status "error" "Unknown platform: $(uname -s)"
                return 1
                ;;
        esac
    fi
    
    # Validate the detected IP
    if [[ -z "$detected_ip" ]]; then
        print_status "error" "Could not detect Docker bridge IP"
        return 1
    fi
    
    # Test connectivity if it's an IP address
    if [[ "$detected_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_status "info" "Testing connectivity to detected IP: $detected_ip"
        if ping -c 1 -W 2 "$detected_ip" > /dev/null 2>&1; then
            print_status "success" "IP $detected_ip is reachable"
        else
            print_status "warning" "IP $detected_ip may not be reachable (this might be normal)"
        fi
    fi
    
    print_status "success" "Docker bridge IP detected: $detected_ip"
    print_status "info" "Detection method: $detection_method"
    
    # Output the IP (this is what calling scripts will capture)
    echo "$detected_ip"
    return 0
}

# Function to export the IP as environment variable
export_docker_bridge_ip() {
    local bridge_ip
    bridge_ip=$(detect_docker_bridge_ip)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 && -n "$bridge_ip" ]]; then
        export DOCKER_BRIDGE_IP="$bridge_ip"
        print_status "success" "Exported DOCKER_BRIDGE_IP=$bridge_ip"
        return 0
    else
        print_status "error" "Failed to detect and export Docker bridge IP"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly
    case "${1:-detect}" in
        "detect")
            detect_docker_bridge_ip
            ;;
        "export")
            export_docker_bridge_ip
            ;;
        "test")
            bridge_ip=$(detect_docker_bridge_ip)
            if [[ $? -eq 0 ]]; then
                print_status "info" "Testing Docker bridge IP: $bridge_ip"
                echo "DOCKER_BRIDGE_IP=$bridge_ip"
                echo "Use this IP for service registration host configuration"
            fi
            ;;
        *)
            echo "Usage: $0 [detect|export|test]"
            echo "  detect - Detect and print the Docker bridge IP (default)"
            echo "  export - Detect and export as DOCKER_BRIDGE_IP environment variable"
            echo "  test   - Detect and show usage information"
            exit 1
            ;;
    esac
fi
