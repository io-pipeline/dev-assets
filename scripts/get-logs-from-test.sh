#!/bin/bash

# Script to download latest CI test artifacts from Gitea
# Usage: ./getLatestLogsFromCI.sh [run_number]
#
# Environment variables:
#   GITEA_PAT - Required for authentication
#
# Example:
#   GITEA_PAT=your_token ./getLatestLogsFromCI.sh
#   GITEA_PAT=your_token ./getLatestLogsFromCI.sh 50

set -e

# Parse repository information from git remote URL
parse_git_repo_info() {
    local git_url
    git_url=$(git remote get-url origin 2>/dev/null)

    if [ -z "$git_url" ]; then
        echo -e "${RED}Error: Not a git repository or no remote 'origin' found${NC}"
        exit 1
    fi

    # Extract owner and repo from URL
    # Handle both HTTPS and SSH formats:
    # https://git.rokkon.com/io-pipeline/account-service.git
    # git@git.rokkon.com:io-pipeline/account-service.git

    if [[ $git_url =~ https://([^/]+)/([^/]+)/([^/.]+) ]]; then
        GITEA_URL="https://${BASH_REMATCH[1]}"
        REPO_OWNER="${BASH_REMATCH[2]}"
        REPO_NAME="${BASH_REMATCH[3]}"
    elif [[ $git_url =~ git@([^:]+):([^/]+)/([^/.]+) ]]; then
        GITEA_URL="https://${BASH_REMATCH[1]}"
        REPO_OWNER="${BASH_REMATCH[2]}"
        REPO_NAME="${BASH_REMATCH[3]}"
    else
        echo -e "${RED}Error: Could not parse repository URL: $git_url${NC}"
        echo "Expected format: https://host.com/owner/repo.git or git@host.com:owner/repo.git"
        exit 1
    fi
}

# Parse repository info
parse_git_repo_info

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for GITEA_PAT
if [ -z "$GITEA_PAT" ]; then
    echo -e "${RED}Error: GITEA_PAT environment variable not set${NC}"
    echo "Usage: GITEA_PAT=your_token ./getLatestLogsFromCI.sh [run_number]"
    exit 1
fi

RUN_NUMBER=${1:-}

if [ -z "$RUN_NUMBER" ]; then
    echo -e "${GREEN}Fetching latest run number from actions page...${NC}"
    # Scrape the actions page to find latest run
    PAGE_HTML=$(curl -s -H "Authorization: token $GITEA_PAT" "${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions")
    # Try to extract run number from URL pattern /actions/runs/NUMBER
    RUN_NUMBER=$(echo "$PAGE_HTML" | grep -o 'actions/runs/[0-9]\+' | head -1 | grep -o '[0-9]\+')

    if [ -z "$RUN_NUMBER" ]; then
        echo -e "${RED}Could not determine latest run number${NC}"
        echo "Please specify run number manually:"
        echo "  GITEA_PAT=\$GITEA_PAT ./getLatestLogsFromCI.sh <run_number>"
        echo ""
        echo "Find run number at: ${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions"
        exit 1
    fi
fi

echo -e "${GREEN}Downloading artifacts from run #${RUN_NUMBER}...${NC}"

# Create output directory
mkdir -p ci-artifacts
cd ci-artifacts

# Download test-results
echo -e "${GREEN}Downloading test-results.zip...${NC}"
ARTIFACT_URL="${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_NUMBER}/artifacts/test-results"
curl -L -H "Authorization: token $GITEA_PAT" -o test-results.zip "$ARTIFACT_URL"

if [ -f test-results.zip ]; then
    echo -e "${GREEN}Downloaded test-results.zip${NC}"

    # Extract
    unzip -o test-results.zip
    rm test-results.zip

    echo -e "${GREEN}Extracted test results:${NC}"
    find . -type f -name "*.xml" -o -name "*.html" | head -20
    echo ""

    # Show test failures if any
    if ls test-results/test/*.xml >/dev/null 2>&1; then
        echo -e "${YELLOW}Test results summary:${NC}"
        grep -h "testcase.*FAILED" test-results/test/*.xml 2>/dev/null || echo "No failures found in XML"
    fi
else
    echo -e "${RED}Failed to download test-results.zip${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Done! Check ci-artifacts/ directory${NC}"
REPORT_PATH="$(pwd)/reports/tests/test/index.html"
echo "file://${REPORT_PATH}"
