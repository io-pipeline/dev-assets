# validate-published-assets.sh

Validates that all build artifacts (containers, JARs, NPM packages) are correctly published to their target repositories across Gitea, GitHub, Reposilite, and NPM.

## Purpose

This script performs comprehensive validation of the dual CI/CD publishing pipeline by checking:
- **Gitea Container Registry** (`git.rokkon.com`) - Internal container images
- **GitHub Container Registry** (`ghcr.io`) - Public container images
- **Reposilite Maven** (`maven.rokkon.com`) - Internal Maven artifacts
- **GitHub Packages Maven** - Public Maven artifacts
- **NPM Registry** (`npmjs.org`) - Public NPM packages

## Usage

```bash
./validate-published-assets.sh
```

The script will:
1. Check all configured projects and their artifacts
2. Generate a timestamped markdown report: `validation-report-YYYYMMDD-HHMMSS.md`
3. Display the report to stdout

### Required Environment Variables

The script uses these authentication tokens (automatically detected):

- **GITHUB_TOKEN** or **GH_PAT_MERGER** - GitHub API access
- **GITEA_PAT** or **GIT_PAT** - Gitea API access
- **REPOS_PAT** - Reposilite Maven repository access

These should already be configured in your environment. The script will indicate which tokens are detected.

## Project Types

### Service Projects (JAR + Container)
These projects publish both Docker containers and Maven JARs:
- account-service
- connector-admin
- connector-intake-service
- mapping-service
- module-chunker
- module-echo
- module-embedder
- module-opensearch-sink
- module-parser
- module-pipeline-probe
- module-proxy
- opensearch-manager
- platform-registration-service

**Expected for each service:**
- ✅ Gitea container at `git.rokkon.com/io-pipeline/-/packages/container/{service}/latest`
- ✅ GitHub container at `ghcr.io/io-pipeline/{service}` (via GitHub Actions)
- ✅ Reposilite JAR at `maven.rokkon.com/snapshots/io/pipeline/{service}/1.0.0-SNAPSHOT/`
- ✅ GitHub Maven package at `github.com/orgs/io-pipeline/packages/maven/package/io.pipeline.{service}`

### Library Projects (JAR only)
Located in the `libraries/` directory, these publish only Maven JARs:
- pipeline-api
- pipeline-commons
- dynamic-grpc
- dynamic-grpc-registration-clients
- data-util
- grpc-wiremock

**Expected for each library:**
- ✅ Reposilite JAR at `maven.rokkon.com/snapshots/io/pipeline/{library}/1.0.0-SNAPSHOT/`
- ✅ GitHub Maven package at `github.com/orgs/io-pipeline/packages/maven/package/io.pipeline.{library}`

### Special Projects

#### grpc (JARs + NPM)
- **grpc-stubs**: Maven JAR + NPM package `@io-pipeline/grpc-stubs`
- **grpc-google-descriptor**: Maven JAR only

**Expected:**
- ✅ Reposilite JARs
- ✅ GitHub Maven packages
- ✅ NPM package for grpc-stubs at `npmjs.com/package/@io-pipeline/grpc-stubs`

#### quarkus-pipeline-devservices (Maven, JAR only)
Maven-based project (not Gradle), publishes only JAR.

**Expected:**
- ✅ Reposilite JAR
- ✅ GitHub Maven package

## Interpreting Results

### Status Indicators

- **✅** = Asset found and accessible at the linked URL
- **❌** = Asset not found or inaccessible (click link to investigate)
- **N/A** = Not applicable for this project type

### Complete Status

A project is marked as **Complete** (✅) only when **ALL** expected artifacts are published:
- Services: All 4 checks (Gitea container + GitHub container + Reposilite JAR + GitHub JAR)
- Libraries: Both checks (Reposilite JAR + GitHub JAR)
- grpc-stubs: All 3 checks (Reposilite + GitHub + NPM)

### Common Issues

#### GitHub Containers Missing (Expected Initially)
When you see all GitHub containers failing, this is normal if:
- The `.github/workflows/build-and-publish.yml` workflows haven't run yet
- Workflows have `paths-ignore: ['.github/**']` to avoid infinite loops
- The first actual code push will trigger container builds

#### GitHub Maven Packages Missing
If GitHub Maven packages are missing but Reposilite has them:
- Check that the project has a `.github/workflows/` that publishes to GitHub Packages
- Verify the workflow uses `publishAllPublicationsToGitHubPackagesRepository` task
- Ensure `GITHUB_TOKEN` has `packages: write` permission

#### Gitea Containers Present, JARs Missing
This indicates:
- The Docker build succeeded (runs in `docker` job)
- The Maven/Gradle publish step failed or didn't run (runs in `build` job)
- Check Gitea Actions logs for the `build` job

#### All Artifacts Missing for a Service
This means:
- The service hasn't had a successful Gitea build yet
- Check if the service has a `.gitea/workflows/build-and-publish.yml`
- Verify the last Gitea Actions run status

## Success Rate Expectations

### Initial State (Before GitHub Sync)
- **Expected: ~40-50%** - Only Gitea and Reposilite assets
- Gitea containers: Published for active services
- Reposilite JARs: Published for all built projects
- GitHub: No containers or packages yet

### After GitHub Workflows Run
- **Expected: ~90-100%** - All assets published
- All containers on both Gitea and GitHub
- All JARs in both Reposilite and GitHub Packages
- NPM packages published

### Current Baseline
Based on the most recent run, we expect:
- Libraries: 100% complete (5/6, data-util needs investigation)
- grpc artifacts: Maven 100%, NPM should be 100%
- Services: Varies by build status
- Overall: 28-70% depending on build completion

## How the Script Works

### 1. Authentication Setup
Uses environment variables for API tokens, falling back to common alternatives:
- `GH_PAT_MERGER` or `GITHUB_TOKEN`
- `GITEA_PAT` or `GIT_PAT`
- `REPOS_PAT`

### 2. GitHub Checks (via `gh` CLI)
Uses the GitHub CLI for accurate package detection:
```bash
gh api "/orgs/io-pipeline/packages/maven/io.pipeline.{artifact}"
gh api "/orgs/io-pipeline/packages/container/{service}"
```

This is more reliable than URL checking and provides accurate exists/not-exists status.

### 3. URL-Based Checks
For Gitea and Reposilite:
- Checks HTTP status codes with authentication headers
- Returns 2xx = success, anything else = failure
- Links point to actual package locations for manual verification

### 4. NPM Registry Check
Uses the NPM registry API:
```bash
curl -s "https://registry.npmjs.org/@io-pipeline/{package}"
```

Checks for valid JSON response with package name.

### 5. Report Generation
- Timestamped markdown file for record-keeping
- Links in the report are clickable for investigation
- Summary statistics show overall health
- Can be committed to git for historical tracking

## Troubleshooting

### Script Fails with "command not found: gh"
Install GitHub CLI:
```bash
# Debian/Ubuntu
sudo apt install gh

# Or via brew
brew install gh
```

### All Checks Failing
Check authentication:
```bash
echo $GH_PAT_MERGER
echo $GITEA_PAT
echo $REPOS_PAT
```

### Specific Package Investigation
Click the ❌ links in the report to see:
- For GitHub: The package search page or 404
- For Gitea: The container registry page or error
- For Reposilite: The maven-metadata.xml or 404
- For NPM: The package page or 404

## Maintenance

### Adding New Projects
Edit the arrays at the top of the script:

```bash
# For services with JAR + Container
SERVICE_PROJECTS=(
    "your-new-service"
)

# For libraries (JAR only)
LIBRARY_SUBPROJECTS=(
    "your-new-library"
)
```

### Changing Group ID
If the Maven group changes from `io.pipeline`, update:
```bash
check_reposilite_jar() {
    local group="io.pipeline"  # <-- Change here
    ...
}
```

## Output Files

- **validation-report-*.md** - Timestamped reports for each run
- Can be committed to git for tracking publication history over time
- Markdown format allows easy viewing in GitHub/Gitea UI

## Integration with CI/CD

This script can be run:
- **Manually** - After making changes to verify publication
- **In CI/CD** - As a post-deploy validation step
- **Scheduled** - As a nightly check for drift detection
- **Pre-release** - To verify all assets before tagging a release

## Related Documentation

- [DUAL_CICD_PATTERN.md](../../bom/DUAL_CICD_PATTERN.md) - Workflow setup documentation
- GitHub Actions: `.github/workflows/build-and-publish.yml` in each project
- Gitea Actions: `.gitea/workflows/build-and-publish.yml` in each project
