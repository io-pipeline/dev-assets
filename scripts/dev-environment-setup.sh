#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITEA_URL="git.rokkon.com"
GITEA_SSH_PORT="2222"
GIT_ORG="io-pipeline"
BASE_DIR="${HOME}/IdeaProjects/gitea"

# List of repositories to clone
# Format: "repo-name:protocol" where protocol is "https" or "ssh"
# Use SSH for repos you need to push to
REPOS=(
    "account-service:https"
    "grpc:https"
    "libraries:https"
    "dev-assets:ssh"
)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Pipeline Development Environment Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
echo ""

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "git is not installed"
    exit 1
fi
print_status "git is installed: $(git --version | head -1)"

# Check if java is installed
if ! command -v java &> /dev/null; then
    print_info "Java not found - will be needed for compilation later"
else
    print_status "Java is installed: $(java -version 2>&1 | head -1)"
fi

# Check if gradle is available (via wrapper or global)
if command -v gradle &> /dev/null; then
    print_status "Gradle is installed: $(gradle --version | grep Gradle | head -1)"
else
    print_info "Gradle not found globally - projects will use Gradle wrapper"
fi

echo ""

# Create base directory if it doesn't exist
if [ ! -d "$BASE_DIR" ]; then
    echo -e "${BLUE}Creating base directory: ${BASE_DIR}${NC}"
    mkdir -p "$BASE_DIR"
    print_status "Created $BASE_DIR"
else
    print_status "Base directory exists: $BASE_DIR"
fi

echo ""
cd "$BASE_DIR"

# Clone repositories
echo -e "${BLUE}Cloning repositories...${NC}"
echo ""

for repo_config in "${REPOS[@]}"; do
    # Parse repo name and protocol
    IFS=':' read -r repo protocol <<< "$repo_config"
    REPO_DIR="$BASE_DIR/$repo"

    if [ -d "$REPO_DIR/.git" ]; then
        print_info "$repo already exists - pulling latest changes"
        cd "$REPO_DIR"

        # Check if there are uncommitted changes
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            print_error "$repo has uncommitted changes - skipping pull"
        else
            git pull origin main || git pull origin master || print_error "Failed to pull $repo"
            print_status "Updated $repo"
        fi

        cd "$BASE_DIR"
    else
        echo -e "  Cloning ${YELLOW}$repo${NC} via ${BLUE}$protocol${NC}..."

        # Determine clone URL based on protocol
        if [ "$protocol" = "ssh" ]; then
            CLONE_URL="ssh://git@${GITEA_URL}:${GITEA_SSH_PORT}/${GIT_ORG}/${repo}.git"
        else
            CLONE_URL="https://${GITEA_URL}/${GIT_ORG}/${repo}.git"
        fi

        if git clone "$CLONE_URL" "$REPO_DIR"; then
            print_status "Cloned $repo"
        else
            print_error "Failed to clone $repo"
            if [ "$protocol" = "https" ]; then
                print_info "You may need to authenticate with: git config --global credential.helper store"
            else
                print_info "You may need SSH keys configured for ${GITEA_URL}"
            fi
        fi
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Repository checkout complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Show repository status
echo -e "${BLUE}Repository status:${NC}"
echo ""
for repo_config in "${REPOS[@]}"; do
    # Parse repo name from config
    IFS=':' read -r repo protocol <<< "$repo_config"
    REPO_DIR="$BASE_DIR/$repo"
    if [ -d "$REPO_DIR/.git" ]; then
        cd "$REPO_DIR"
        BRANCH=$(git branch --show-current)
        COMMIT=$(git rev-parse --short HEAD)
        echo -e "  ${GREEN}✓${NC} ${YELLOW}$repo${NC} - branch: ${BLUE}$BRANCH${NC} (${COMMIT})"
    else
        echo -e "  ${RED}✗${NC} ${YELLOW}$repo${NC} - not cloned"
    fi
done

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Next Steps:${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "1. Compilation (coming soon - will build all projects)"
echo "2. Test execution (coming soon - will run all tests)"
echo "3. Docker image builds (coming soon)"
echo ""
echo -e "${GREEN}Setup script complete!${NC}"
echo ""
echo "To enable compilation in this script, uncomment the build section below"
echo ""

# ========================================
# COMPILATION SECTION (Currently disabled)
# ========================================
# Uncomment to enable compilation after testing

# echo -e "${BLUE}Building projects...${NC}"
# echo ""
#
# # Build grpc first (dependency for other projects)
# if [ -d "$BASE_DIR/grpc" ]; then
#     echo -e "${YELLOW}Building grpc...${NC}"
#     cd "$BASE_DIR/grpc"
#     if [ -f "gradlew" ]; then
#         ./gradlew clean build publishToMavenLocal --no-daemon
#         print_status "Built grpc"
#     else
#         print_error "No gradlew found in grpc"
#     fi
#     echo ""
# fi
#
# # Build libraries (may be dependency for other projects)
# if [ -d "$BASE_DIR/libraries" ]; then
#     echo -e "${YELLOW}Building libraries...${NC}"
#     cd "$BASE_DIR/libraries"
#     if [ -f "gradlew" ]; then
#         ./gradlew clean build publishToMavenLocal --no-daemon
#         print_status "Built libraries"
#     elif [ -f "build.sh" ]; then
#         ./build.sh
#         print_status "Built libraries"
#     else
#         print_info "No build script found in libraries"
#     fi
#     echo ""
# fi
#
# # Build account-service
# if [ -d "$BASE_DIR/account-service" ]; then
#     echo -e "${YELLOW}Building account-service...${NC}"
#     cd "$BASE_DIR/account-service"
#     if [ -f "gradlew" ]; then
#         ./gradlew clean build --no-daemon
#         print_status "Built account-service"
#     else
#         print_error "No gradlew found in account-service"
#     fi
#     echo ""
# fi
#
# echo -e "${GREEN}All builds complete!${NC}"
