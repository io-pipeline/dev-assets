#!/usr/bin/env bash
set -euo pipefail

# Clone or update reference-code repositories listed in reference-code/repos.manifest.tsv
# Format: name|git_url|branch (use '-' to use default remote HEAD)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST_DEFAULT="${ROOT_DIR}/reference-code/repos.manifest.tsv"

source "${SCRIPT_DIR}/shared-utils.sh"

DEPTH=""
DO_UPDATE=false
DO_LIST=false
MANIFEST_PATH="${MANIFEST_DEFAULT}"

usage() {
  cat <<EOF
Usage: $0 [--update] [--no-update] [--list] [--depth N] [--manifest PATH]

Options:
  --update         Fetch and pull existing repos (default: no)
  --no-update      Skip updates for existing repos (default)
  --list           Dry run: list actions but do not clone/pull
  --depth N        Shallow clone with depth N
  --manifest PATH  Path to manifest (default: ${MANIFEST_DEFAULT})

Manifest format (TSV):
  name|git_url|branch
  Use '-' for branch to keep remote default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) DO_UPDATE=true; shift ;;
    --no-update) DO_UPDATE=false; shift ;;
    --list) DO_LIST=true; shift ;;
    --depth) DEPTH="$2"; shift 2 ;;
    --manifest) MANIFEST_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# Prefer existing manifest files in dev-assets/scripts before creating a default
# Candidate manifests (checked in order)
CANDIDATE_MANIFESTS=(
  "${SCRIPT_DIR}/config/reference-repos.tsv"
  "${SCRIPT_DIR}/%20config/reference-repos.tsv"
  "${ROOT_DIR}/reference-code/repos.manifest.tsv"
)

# If the user didn't explicitly pass --manifest (i.e. MANIFEST_PATH == MANIFEST_DEFAULT),
# try to find an existing candidate and use it.
if [[ "${MANIFEST_PATH}" == "${MANIFEST_DEFAULT}" ]]; then
  for cand in "${CANDIDATE_MANIFESTS[@]}"; do
    if [[ -f "${cand}" ]]; then
      MANIFEST_PATH="${cand}"
      break
    fi
  done
fi

# Create default manifest if it doesn't exist (only for the default location)
if [[ ! -f "${MANIFEST_PATH}" ]]; then
  if [[ "${MANIFEST_PATH}" == "${MANIFEST_DEFAULT}" ]]; then
    print_status "info" "Creating default manifest at: ${MANIFEST_PATH}"
    mkdir -p "$(dirname "${MANIFEST_PATH}")"
    cat > "${MANIFEST_PATH}" <<'EOF'
# Reference repositories manifest
# Format: name|git_url|branch (use '-' for default branch)
# Common reference repos:
spring-boot|https://github.com/spring-projects/spring-boot.git|-
spring-framework|https://github.com/spring-projects/spring-framework.git|-
vue-core|https://github.com/vuejs/core.git|main
quarkus|https://github.com/quarkusio/quarkus.git|-
EOF
  else
    print_status "error" "Manifest not found: ${MANIFEST_PATH}"
    exit 1
  fi
fi

mkdir -p "${ROOT_DIR}/reference-code"

print_status "header" "Reference Code Sync"
print_status "info" "Using manifest: ${MANIFEST_PATH}"
print_status "info" "Update mode: $(if $DO_UPDATE; then echo "ENABLED"; else echo "DISABLED (use --update)"; fi)"

TOTAL=0; OK=0; ERR=0

# Temporarily disable 'errexit' so read/EOF doesn't abort the script
set +e

while IFS= read -r raw; do
  # Handle line continuations ending with backslash and trim CR
  line="${raw%$'\r'}"
  while [[ "${line: -1}" == "\\" ]]; do
    line="${line::-1}"
    IFS= read -r cont || cont=""
    line+="${cont%$'\r'}"
  done

  # Skip blanks/comments
  [[ -z "${line}" ]] && continue
  [[ "${line}" =~ ^# ]] && continue

  # Split fields on '|'
  IFS='|' read -r -a FIELDS <<< "${line}"
  NAME="${FIELDS[0]-}"
  URL="${FIELDS[1]-}"
  BRANCH="${FIELDS[2]-}"
  # Normalize and trim CR/LF
  NAME="${NAME//[$'\r\n']/}"
  URL="${URL//[$'\r\n']/}"
  BRANCH="${BRANCH//[$'\r\n']/}"

  # Validate required fields
  if [[ -z "${NAME}" || -z "${URL}" ]]; then
    [[ -n "${NAME}${URL}" ]] && print_status "warn" "Skipping invalid entry: ${line}"
    continue
  fi

  ((TOTAL++))

  DEST="${ROOT_DIR}/reference-code/${NAME}"
  if [[ -d "${DEST}/.git" ]]; then
    print_status "info" "[${NAME}] already cloned"
    if ${DO_LIST}; then
      if ${DO_UPDATE}; then
        print_status "info" "[${NAME}] would fetch & fast-forward"
      else
        print_status "info" "[${NAME}] exists (skip update)"
      fi
      ((OK++))
      continue
    fi

    if ${DO_UPDATE}; then
      (
        cd "${DEST}"
        echo "  Remote: $(git remote get-url origin 2>/dev/null || echo 'unknown')"
        git fetch --all --prune || true
        if [[ -n "${BRANCH}" && "${BRANCH}" != "-" ]]; then
          git checkout "${BRANCH}" 2>/dev/null || true
        fi
        # Try to fast-forward; ignore if diverged
        git pull --ff-only 2>&1 | grep -v "Already up to date" || true
      ) && { print_status "success" "[${NAME}] updated"; ((OK++)); } || { print_status "error" "[${NAME}] update failed"; ((ERR++)); }
    else
      print_status "skip" "[${NAME}] skipping update"
      ((OK++))
    fi
    continue
  fi

  # Clone fresh
  print_status "info" "[${NAME}] cloning from ${URL}"
  if ${DO_LIST}; then
    print_status "info" "[${NAME}] would clone to ${DEST}"
    ((OK++))
    continue
  fi

  CLONE_ARGS=("git" "clone")
  if [[ -n "${DEPTH}" ]]; then
    CLONE_ARGS+=("--depth" "${DEPTH}")
  fi
  if [[ -n "${BRANCH}" && "${BRANCH}" != "-" ]]; then
    CLONE_ARGS+=("--branch" "${BRANCH}")
  fi
  CLONE_ARGS+=("${URL}" "${DEST}")

  # Use exit status instead of piping output through grep which caused false failures
  if "${CLONE_ARGS[@]}" >/dev/null 2>&1; then
    print_status "success" "[${NAME}] cloned"
    ((OK++))
  else
    # If clone failed and a specific branch was requested, retry without --branch (fallback to default)
    if [[ -n "${BRANCH}" && "${BRANCH}" != "-" ]]; then
      print_status "warning" "[${NAME}] clone with branch '${BRANCH}' failed; retrying without --branch (will use remote default)"
      # Build fallback clone args (omit --branch)
      FALLBACK_ARGS=("git" "clone")
      if [[ -n "${DEPTH}" ]]; then
        FALLBACK_ARGS+=("--depth" "${DEPTH}")
      fi
      FALLBACK_ARGS+=("${URL}" "${DEST}")
      # Run fallback and show output to help debugging
      if "${FALLBACK_ARGS[@]}"; then
        print_status "success" "[${NAME}] cloned (fallback to remote default branch)"
        ((OK++))
      else
        print_status "error" "[${NAME}] clone failed even without --branch (check access/branch)"
        ((ERR++))
      fi
    else
      print_status "error" "[${NAME}] clone failed (check access for ${URL})"
      ((ERR++))
    fi
  fi

done < "${MANIFEST_PATH}"

# Re-enable 'errexit'
set -e

echo
print_status "header" "Reference Code Sync Complete"
echo "Total: ${TOTAL}  OK: ${OK}  Errors: ${ERR}"
if (( ERR > 0 )); then
  print_status "warn" "Some repositories failed. Check network/credentials."
fi
