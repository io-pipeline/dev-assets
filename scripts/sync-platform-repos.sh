#!/usr/bin/env bash
set -euo pipefail

# Sync platform repositories from PROJECT_MAPPING.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAPPING_FILE="${ROOT_DIR}/PROJECT_MAPPING.md"
PLATFORM_DIR="${ROOT_DIR}/platform-code"

source "${SCRIPT_DIR}/shared-utils.sh"

DO_UPDATE=false
DEPTH=""
USE_SSH=true

usage() {
  cat <<EOF
Usage: $0 [--update] [--depth N] [--ssh|--https]

Syncs all platform repositories from PROJECT_MAPPING.md into platform-code/

Options:
  --update    Fetch and pull existing repos (default: no)
  --depth N   Shallow clone depth
  --ssh       Use SSH URLs (default)
  --https     Use HTTPS URLs
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) DO_UPDATE=true; shift ;;
    --depth) DEPTH="$2"; shift 2 ;;
    --ssh) USE_SSH=true; shift ;;
    --https) USE_SSH=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ ! -f "${MAPPING_FILE}" ]]; then
  print_status "error" "PROJECT_MAPPING.md not found at ${MAPPING_FILE}"
  exit 1
fi

mkdir -p "${PLATFORM_DIR}"

print_status "header" "Platform Repository Sync"
print_status "info" "Target directory: ${PLATFORM_DIR}"
print_status "info" "Update mode: $(if $DO_UPDATE; then echo "ENABLED"; else echo "DISABLED (use --update)"; fi)"
print_status "info" "URL format: $(if $USE_SSH; then echo "SSH"; else echo "HTTPS"; fi)"

# Parse PROJECT_MAPPING.md for repos
declare -A REPOS=()

# Parse Services table
while IFS= read -r line; do
  # Match lines with backticked git.rokkon.com repos
  if [[ "$line" =~ \|[[:space:]]*([^|]+)[[:space:]]*\|[[:space:]]*\`(git\.rokkon\.com/[^`]+)\` ]]; then
    name="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    name="$(echo "$name" | xargs)"  # trim
    # Skip header row
    [[ "$name" =~ "Service Name" ]] && continue
    REPOS["$name"]="$repo"
  fi
done < <(sed -n '/^## Services/,/^##/p' "${MAPPING_FILE}")

# Parse Modules table
while IFS= read -r line; do
  if [[ "$line" =~ \|[[:space:]]*([^|]+)[[:space:]]*\|[[:space:]]*\`(git\.rokkon\.com/[^`]+)\` ]]; then
    name="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    name="$(echo "$name" | xargs)"
    [[ "$name" =~ "Module Name" ]] && continue
    REPOS["$name"]="$repo"
  fi
done < <(sed -n '/^## Modules/,/^##/p' "${MAPPING_FILE}")

# Parse Supporting Projects table
while IFS= read -r line; do
  if [[ "$line" =~ \|[[:space:]]*([^|]+)[[:space:]]*\|[[:space:]]*\`(git\.rokkon\.com/[^`]+)\` ]]; then
    name="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    name="$(echo "$name" | xargs)"
    [[ "$name" =~ "Project Name" ]] && continue
    REPOS["$name"]="$repo"
  fi
done < <(sed -n '/^## Supporting Projects/,/^##/p' "${MAPPING_FILE}")

print_status "info" "Found ${#REPOS[@]} repositories to sync"
echo

TOTAL=0; OK=0; ERR=0
set +e

for name in "${!REPOS[@]}"; do
  repo="${REPOS[$name]}"
  ((TOTAL++))

  # Convert to full URL
  if $USE_SSH; then
    url="git@${repo}.git"
    url="${url/git\.rokkon\.com\//git.rokkon.com:}"  # Fix SSH format
  else
    url="https://${repo}.git"
  fi

  dest="${PLATFORM_DIR}/${name}"

  if [[ -d "${dest}/.git" ]]; then
    print_status "info" "[${name}] already cloned"
    if $DO_UPDATE; then
      (
        cd "${dest}"
        echo "  Remote: $(git remote get-url origin 2>/dev/null || echo 'unknown')"
        git fetch --all --prune 2>/dev/null || true
        # Pull on current branch
        git pull --ff-only 2>&1 | grep -v "Already up to date" || true
      ) && { print_status "success" "[${name}] updated"; ((OK++)); } || { print_status "error" "[${name}] update failed"; ((ERR++)); }
    else
      print_status "skip" "[${name}] skipping update"
      ((OK++))
    fi
  else
    print_status "info" "[${name}] cloning from ${url}"
    CLONE_ARGS=("git" "clone")
    [[ -n "$DEPTH" ]] && CLONE_ARGS+=("--depth" "$DEPTH")
    CLONE_ARGS+=("$url" "${dest}")

    if "${CLONE_ARGS[@]}" 2>&1 | grep -v "Cloning into"; then
      print_status "success" "[${name}] cloned"
      ((OK++))
    else
      print_status "error" "[${name}] failed - check access"
      ((ERR++))
    fi
  fi
done

set -e

echo
print_status "header" "Platform Sync Complete"
echo "Total: ${TOTAL}  OK: ${OK}  Errors: ${ERR}"
[[ $ERR -gt 0 ]] && print_status "warn" "Check SSH keys/credentials for failed repos"
