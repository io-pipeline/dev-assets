#!/bin/bash

# validate-published-assets.sh
# Validates that all build artifacts are published to Gitea, GitHub, and Reposilite

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GITHUB_ORG="io-pipeline"
GITEA_BASE="https://git.rokkon.com"
REPOSILITE_BASE="https://maven.rokkon.com"
GITHUB_BASE="https://github.com/${GITHUB_ORG}"

# Auth tokens from environment
GITHUB_TOKEN="${GH_PAT_MERGER:-${GITHUB_TOKEN}}"
GITEA_TOKEN="${GITEA_PAT:-${GIT_PAT}}"
REPOSILITE_TOKEN="${REPOS_PAT}"

# Projects to check (services with JAR + Container)
SERVICE_PROJECTS=(
    "account-service"
    "connector-admin"
    "connector-intake-service"
    "mapping-service"
    "module-chunker"
    "module-echo"
    "module-embedder"
    "module-opensearch-sink"
    "module-parser"
    "module-pipeline-probe"
    "module-proxy"
    "opensearch-manager"
    "platform-registration-service"
)

# Special projects
SPECIAL_PROJECTS=(
    "grpc"                          # Has JARs and NPM packages, no container
    "libraries"                     # Has sub-projects
    "quarkus-pipeline-devservices"  # Maven-based, JAR only
)

# Libraries sub-projects
LIBRARY_SUBPROJECTS=(
    "pipeline-api"
    "pipeline-commons"
    "dynamic-grpc"
    "dynamic-grpc-registration-clients"
    "data-util"
    "grpc-wiremock"
)

# Output file
OUTPUT_FILE="validation-report-$(date +%Y%m%d-%H%M%S).md"

# Helper function to check URL
check_url() {
    local url="$1"
    local token="$2"
    local auth_header=""

    if [[ -n "$token" ]]; then
        auth_header="-H \"Authorization: Bearer ${token}\""
    fi

    if eval curl -s -o /dev/null -w "%{http_code}" ${auth_header} -L "$url" | grep -q "^2"; then
        echo "true"
    else
        echo "false"
    fi
}

# Helper to create markdown link
make_link() {
    local url="$1"
    local status="$2"

    if [[ "$status" == "true" ]]; then
        echo "✅ [link]($url)"
    else
        echo "❌ [link]($url)"
    fi
}

# Check Gitea container
check_gitea_container() {
    local project="$1"
    local url="${GITEA_BASE}/${GITHUB_ORG}/-/packages/container/${project}/latest"
    local status=$(check_url "$url" "$GITEA_TOKEN")
    echo "$status|$url"
}

# Check GitHub container (ghcr.io) using gh CLI
check_github_container() {
    local project="$1"

    # Use gh CLI to check if container package exists
    if gh api "/orgs/${GITHUB_ORG}/packages/container/${project}" &>/dev/null; then
        local url="https://github.com/${GITHUB_ORG}/packages/container/${project}"
        echo "true|$url"
    else
        local url="https://github.com/orgs/${GITHUB_ORG}/packages?ecosystem=container"
        echo "false|$url"
    fi
}

# Check Reposilite Maven artifact
check_reposilite_jar() {
    local group="io.pipeline"
    local artifact="$1"
    local version="1.0.0-SNAPSHOT"
    local group_path="${group//./\/}"
    local url="${REPOSILITE_BASE}/snapshots/${group_path}/${artifact}/${version}/maven-metadata.xml"
    local status=$(check_url "$url" "$REPOSILITE_TOKEN")
    echo "$status|$url"
}

# Check GitHub Packages Maven artifact using gh CLI
check_github_jar() {
    local artifact="$1"
    local package_name="io.pipeline.${artifact}"

    # Use gh CLI to check if package exists
    if gh api "/orgs/${GITHUB_ORG}/packages/maven/${package_name}" &>/dev/null; then
        local url="https://github.com/orgs/${GITHUB_ORG}/packages/maven/package/${package_name}"
        echo "true|$url"
    else
        local url="https://github.com/orgs/${GITHUB_ORG}/packages?q=${artifact}"
        echo "false|$url"
    fi
}

# Check NPM package
check_npm_package() {
    local package="$1"
    local url="https://www.npmjs.com/package/${package}"

    # Check if package exists on NPM using registry API
    if curl -s "https://registry.npmjs.org/${package}" | grep -q "\"name\""; then
        echo "true|$url"
    else
        echo "false|$url"
    fi
}

# Initialize report
cat > "$OUTPUT_FILE" <<'EOF'
# Published Assets Validation Report

Generated: $(date '+%Y-%m-%d %H:%M:%S')

## Legend
- ✅ = Asset found and accessible
- ❌ = Asset not found or not accessible
- N/A = Not applicable for this project type

## Summary

EOF

echo "| Repository | Gitea Container | GitHub Container | Reposilite JAR | GitHub JAR | Complete? |" >> "$OUTPUT_FILE"
echo "|------------|-----------------|------------------|----------------|------------|-----------|" >> "$OUTPUT_FILE"

# Track overall status
total_checks=0
passed_checks=0

# Process service projects (JAR + Container)
for project in "${SERVICE_PROJECTS[@]}"; do
    echo -e "${YELLOW}Checking ${project}...${NC}"

    # Check containers
    gitea_container_result=$(check_gitea_container "$project")
    gitea_container_status="${gitea_container_result%%|*}"
    gitea_container_url="${gitea_container_result##*|}"

    github_container_result=$(check_github_container "$project")
    github_container_status="${github_container_result%%|*}"
    github_container_url="${github_container_result##*|}"

    gitea_container_md=$(make_link "$gitea_container_url" "$gitea_container_status")
    github_container_md=$(make_link "$github_container_url" "$github_container_status")

    # Check JARs
    reposilite_jar_result=$(check_reposilite_jar "$project")
    reposilite_jar_status="${reposilite_jar_result%%|*}"
    reposilite_jar_url="${reposilite_jar_result##*|}"

    github_jar_result=$(check_github_jar "$project")
    github_jar_status="${github_jar_result%%|*}"
    github_jar_url="${github_jar_result##*|}"

    reposilite_jar_md=$(make_link "$reposilite_jar_url" "$reposilite_jar_status")
    github_jar_md=$(make_link "$github_jar_url" "$github_jar_status")

    total_checks=$((total_checks + 4))
    [[ "$gitea_container_status" == "true" ]] && passed_checks=$((passed_checks + 1))
    [[ "$github_container_status" == "true" ]] && passed_checks=$((passed_checks + 1))
    [[ "$reposilite_jar_status" == "true" ]] && passed_checks=$((passed_checks + 1))
    [[ "$github_jar_status" == "true" ]] && passed_checks=$((passed_checks + 1))

    # Determine if complete (all 4 checks must pass)
    if [[ "$gitea_container_status" == "true" && "$github_container_status" == "true" && "$reposilite_jar_status" == "true" && "$github_jar_status" == "true" ]]; then
        complete="✅"
    else
        complete="❌"
    fi

    # Write row
    echo "| $project | $gitea_container_md | $github_container_md | $reposilite_jar_md | $github_jar_md | $complete |" >> "$OUTPUT_FILE"
done

# Process special projects
echo "| **grpc** | N/A | N/A | See below | See below | See below |" >> "$OUTPUT_FILE"
echo "| **libraries** | N/A | N/A | See below | See below | See below |" >> "$OUTPUT_FILE"
echo "| **quarkus-pipeline-devservices** | N/A | N/A | See below | See below | See below |" >> "$OUTPUT_FILE"

# Add libraries section
cat >> "$OUTPUT_FILE" <<'EOF'

## Library Sub-Projects

| Library | Reposilite JAR | GitHub JAR | Complete? |
|---------|----------------|------------|-----------|
EOF

for lib in "${LIBRARY_SUBPROJECTS[@]}"; do
    echo -e "${YELLOW}Checking library ${lib}...${NC}"

    reposilite_jar_result=$(check_reposilite_jar "$lib")
    reposilite_jar_status="${reposilite_jar_result%%|*}"
    reposilite_jar_url="${reposilite_jar_result##*|}"

    github_jar_result=$(check_github_jar "$lib")
    github_jar_status="${github_jar_result%%|*}"
    github_jar_url="${github_jar_result##*|}"

    reposilite_jar_md=$(make_link "$reposilite_jar_url" "$reposilite_jar_status")
    github_jar_md=$(make_link "$github_jar_url" "$github_jar_status")

    total_checks=$((total_checks + 2))
    [[ "$reposilite_jar_status" == "true" ]] && passed_checks=$((passed_checks + 1))
    [[ "$github_jar_status" == "true" ]] && passed_checks=$((passed_checks + 1))

    if [[ "$reposilite_jar_status" == "true" && "$github_jar_status" == "true" ]]; then
        complete="✅"
    else
        complete="❌"
    fi

    echo "| $lib | $reposilite_jar_md | $github_jar_md | $complete |" >> "$OUTPUT_FILE"
done

# Add summary statistics
cat >> "$OUTPUT_FILE" <<EOF

## Special Projects

### grpc Project

| Artifact | Reposilite | GitHub Maven | NPM | Complete? |
|----------|------------|--------------|-----|-----------|
EOF

# Check grpc-stubs
echo -e "${YELLOW}Checking grpc-stubs...${NC}"
reposilite_result=$(check_reposilite_jar "grpc-stubs")
reposilite_status="${reposilite_result%%|*}"
reposilite_url="${reposilite_result##*|}"

github_result=$(check_github_jar "grpc-stubs")
github_status="${github_result%%|*}"
github_url="${github_result##*|}"

npm_result=$(check_npm_package "@io-pipeline/grpc-stubs")
npm_status="${npm_result%%|*}"
npm_url="${npm_result##*|}"

reposilite_md=$(make_link "$reposilite_url" "$reposilite_status")
github_md=$(make_link "$github_url" "$github_status")
npm_md=$(make_link "$npm_url" "$npm_status")

total_checks=$((total_checks + 3))
[[ "$reposilite_status" == "true" ]] && passed_checks=$((passed_checks + 1))
[[ "$github_status" == "true" ]] && passed_checks=$((passed_checks + 1))
[[ "$npm_status" == "true" ]] && passed_checks=$((passed_checks + 1))

if [[ "$reposilite_status" == "true" && "$github_status" == "true" && "$npm_status" == "true" ]]; then
    grpc_complete="✅"
else
    grpc_complete="❌"
fi

echo "| grpc-stubs | $reposilite_md | $github_md | $npm_md | $grpc_complete |" >> "$OUTPUT_FILE"

# Check grpc-google-descriptor
echo -e "${YELLOW}Checking grpc-google-descriptor...${NC}"
reposilite_result=$(check_reposilite_jar "grpc-google-descriptor")
reposilite_status="${reposilite_result%%|*}"
reposilite_url="${reposilite_result##*|}"

github_result=$(check_github_jar "grpc-google-descriptor")
github_status="${github_result%%|*}"
github_url="${github_result##*|}"

reposilite_md=$(make_link "$reposilite_url" "$reposilite_status")
github_md=$(make_link "$github_url" "$github_status")

total_checks=$((total_checks + 2))
[[ "$reposilite_status" == "true" ]] && passed_checks=$((passed_checks + 1))
[[ "$github_status" == "true" ]] && passed_checks=$((passed_checks + 1))

if [[ "$reposilite_status" == "true" && "$github_status" == "true" ]]; then
    descriptor_complete="✅"
else
    descriptor_complete="❌"
fi

echo "| grpc-google-descriptor | $reposilite_md | $github_md | N/A | $descriptor_complete |" >> "$OUTPUT_FILE"

# quarkus-pipeline-devservices
cat >> "$OUTPUT_FILE" <<'EOF'

### quarkus-pipeline-devservices (Maven Project)

| Artifact | Reposilite | GitHub Maven | Complete? |
|----------|------------|--------------|-----------|
EOF

echo -e "${YELLOW}Checking quarkus-pipeline-devservices...${NC}"
reposilite_result=$(check_reposilite_jar "quarkus-pipeline-devservices")
reposilite_status="${reposilite_result%%|*}"
reposilite_url="${reposilite_result##*|}"

github_result=$(check_github_jar "quarkus-pipeline-devservices")
github_status="${github_result%%|*}"
github_url="${github_result##*|}"

reposilite_md=$(make_link "$reposilite_url" "$reposilite_status")
github_md=$(make_link "$github_url" "$github_status")

total_checks=$((total_checks + 2))
[[ "$reposilite_status" == "true" ]] && passed_checks=$((passed_checks + 1))
[[ "$github_status" == "true" ]] && passed_checks=$((passed_checks + 1))

if [[ "$reposilite_status" == "true" && "$github_status" == "true" ]]; then
    devservices_complete="✅"
else
    devservices_complete="❌"
fi

echo "| quarkus-pipeline-devservices | $reposilite_md | $github_md | $devservices_complete |" >> "$OUTPUT_FILE"

# Add summary statistics
cat >> "$OUTPUT_FILE" <<EOF

## Overall Statistics

- **Total Checks**: $total_checks
- **Passed**: $passed_checks
- **Failed**: $((total_checks - passed_checks))
- **Success Rate**: $(( passed_checks * 100 / total_checks ))%

## Authentication Tokens Used

- **GitHub Token**: $(if [[ -n "$GITHUB_TOKEN" ]]; then echo "✅ Provided"; else echo "❌ Missing"; fi)
- **Gitea Token**: $(if [[ -n "$GITEA_TOKEN" ]]; then echo "✅ Provided"; else echo "❌ Missing"; fi)
- **Reposilite Token**: $(if [[ -n "$REPOSILITE_TOKEN" ]]; then echo "✅ Provided"; else echo "❌ Missing"; fi)

---
*Generated by validate-published-assets.sh*
EOF

echo -e "${GREEN}Report generated: ${OUTPUT_FILE}${NC}"
cat "$OUTPUT_FILE"
