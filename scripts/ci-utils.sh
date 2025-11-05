#!/bin/bash

# CI utilities for pipeline dev scripts
# Provides functions for interacting with Gitea CI/CD

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

# Download CI artifacts from Gitea
download_ci_artifacts() {
    local run_number="$1"

    # Check for GIT_PAT
    if [ -z "$GIT_PAT" ]; then
        echo -e "${RED}Error: GIT_PAT environment variable not set${NC}"
        echo "Usage: GIT_PAT=your_token ./getLatestLogsFromCI.sh [run_number]"
        exit 1
    fi

    if [ -z "$run_number" ]; then
        print_status "info" "Fetching latest run number from actions page..."
        # Scrape the actions page to find latest run
        PAGE_HTML=$(curl -s -H "Authorization: token $GIT_PAT" "${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions")
        # Try to extract run number from URL pattern /actions/runs/NUMBER
        run_number=$(echo "$PAGE_HTML" | grep -o 'actions/runs/[0-9]\+' | head -1 | grep -o '[0-9]\+')

        if [ -z "$run_number" ]; then
            print_status "error" "Could not determine latest run number"
            echo "Please specify run number manually:"
            echo "  GIT_PAT=\$GIT_PAT ./getLatestLogsFromCI.sh <run_number>"
            echo ""
            echo "Find run number at: ${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions"
            exit 1
        fi
    fi

    print_status "info" "Downloading artifacts from run #$run_number..."

    # Create output directory
    mkdir -p ci-artifacts
    cd ci-artifacts

    # Download test-results
    print_status "info" "Downloading test-results.zip..."
    ARTIFACT_URL="${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}/actions/runs/${run_number}/artifacts/test-results"
    curl -L -H "Authorization: token $GIT_PAT" -o test-results.zip "$ARTIFACT_URL"

    if [ -f test-results.zip ]; then
        print_status "success" "Downloaded test-results.zip"

        # Extract
        unzip -o test-results.zip
        rm test-results.zip

        print_status "info" "Extracted test results:"
        find . -type f -name "*.xml" -o -name "*.html" | head -20
        echo ""

        # Show test failures if any
        if ls test-results/test/*.xml >/dev/null 2>&1; then
            print_status "warning" "Test results summary:"
            grep -h "testcase.*FAILED" test-results/test/*.xml 2>/dev/null || echo "No failures found in XML"
        fi
    else
        print_status "error" "Failed to download test-results.zip"
        exit 1
    fi

    echo ""
    print_status "success" "Done! Check ci-artifacts/ directory"
    REPORT_PATH="$(pwd)/reports/tests/test/index.html"
    echo "file://${REPORT_PATH}"
}