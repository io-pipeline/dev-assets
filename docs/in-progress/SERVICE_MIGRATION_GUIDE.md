# Service Migration Guide - Monorepo to Multi-Repo

This guide provides step-by-step instructions for extracting services from the monorepo into individual Gitea repositories.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Project List & Status](#project-list--status)
3. [Step-by-Step Migration Process](#step-by-step-migration-process)
4. [Configuration Patterns](#configuration-patterns)
5. [CI/CD Setup](#cicd-setup)
6. [Testing Strategy](#testing-strategy)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- Gradle 9.2
- Docker
- Git with SSH access to git.rokkon.com
- Access to Gitea and GitHub registries

### Required Artifacts (Must be published first)
1. **BOM** - `io.pipeline:pipeline-bom:1.0.0-SNAPSHOT`
2. **BOM Catalog** - `io.pipeline:pipeline-bom-catalog:1.0.0-SNAPSHOT`
3. **gRPC Stubs** - `io.pipeline:grpc-stubs:1.0.0-SNAPSHOT`
4. **Libraries** - All `io.pipeline:*` libraries published to Maven Local
5. **DevServices** - `io.pipeline:devservices-docker-compose:1.0.0-SNAPSHOT`

### Infrastructure Services
The shared dev infrastructure must be running:
```bash
cd /path/to/pipeline-engine-refactor
docker compose -f src/test/resources/compose-devservices.yml up -d
```

---

## Project List & Status

| # | Service Name | Gitea Repo | Monorepo Source | Status |
|---|--------------|------------|-----------------|--------|
| 1 | platform-registration-service | `git.rokkon.com/io-pipeline/platform-registration-service` | `applications/platform-registration-service` | ✅ Complete |
| 2 | account-service | `git.rokkon.com/io-pipeline/account-service` | `applications/account-manager` | ✅ Complete |
| 3 | connector-admin | `git.rokkon.com/io-pipeline/connector-admin` | `applications/connector-service` | ✅ Complete (41 tests passing) |
| 4 | opensearch-manager | `git.rokkon.com/io-pipeline/opensearch-manager` | `applications/opensearch-manager` | ✅ Complete (compiles, uses testcontainers) |
| 5 | connector-intake-service | `git.rokkon.com/io-pipeline/connector-intake-service` | `applications/connector-intake-service` | ✅ Complete |
| 6 | mapping-service | `git.rokkon.com/io-pipeline/mapping-service` | `applications/mapping-service` | ✅ Complete |
| 7 | module-chunker | `git.rokkon.com/io-pipeline/module-chunker` | `modules/chunker` | ✅ Complete |
| 8 | module-parser | `git.rokkon.com/io-pipeline/module-parser` | `modules/parser` | ✅ Complete (includes Apache Tika) |
| 9 | module-echo | `git.rokkon.com/io-pipeline/module-echo` | `modules/echo` | ✅ Complete |
| 10 | module-embedder | `git.rokkon.com/io-pipeline/module-embedder` | `modules/embedder` | ✅ Complete (DJL/PyTorch) |
| 11 | repository-service | `git.rokkon.com/io-pipeline/repository-service` | `applications/_legacy/repo-service` | ⬜ Pending (Redis refactor) |
| 12 | module-opensearch-sink | `git.rokkon.com/io-pipeline/module-opensearch-sink` | `modules/opensearch-sink` | ⬜ Pending |
| 13 | pipestream-engine | `git.rokkon.com/io-pipeline/pipestream-engine` | `applications/pipestream-engine` | ⬜ Pending (deprecated, code-only) |
| 14 | module-test-harness | `git.rokkon.com/io-pipeline/module-test-harness` | `modules/test-harness` | ⬜ Pending |

---

## Step-by-Step Migration Process

### Step 1: Clone Empty Gitea Repository

```bash
cd /home/krickert/IdeaProjects/gitea
git clone ssh://git@git.rokkon.com:2222/io-pipeline/SERVICE-NAME.git
```

### Step 2: Copy Source Files from Monorepo

```bash
cd /home/krickert/IdeaProjects/pipeline-engine-refactor/applications/SOURCE-DIR
rsync -av \
  --exclude='build' \
  --exclude='bin' \
  --exclude='logs' \
  --exclude='.gradle' \
  --exclude='node_modules' \
  --exclude='.vite' \
  --exclude='.quinoa' \
  . /home/krickert/IdeaProjects/gitea/SERVICE-NAME/
```

### Step 3: Copy Standard Configuration Files

```bash
cd /home/krickert/IdeaProjects/gitea/SERVICE-NAME

# Copy from platform-registration-service (our template)
cp ../platform-registration-service/.gitignore .
cp ../platform-registration-service/settings.gradle .
cp ../platform-registration-service/gradle/wrapper/gradle-wrapper.properties gradle/wrapper/
cp -r ../platform-registration-service/.gitea .
cp ../platform-registration-service/renovate.json .
cp ../platform-registration-service/DOCKER.md .

# Copy Dockerfiles if missing
mkdir -p src/main/docker
cp ../platform-registration-service/src/main/docker/* src/main/docker/

# Copy test infrastructure
cp /home/krickert/IdeaProjects/pipeline-engine-refactor/src/test/resources/compose-devservices.yml src/test/resources/
cp /home/krickert/IdeaProjects/pipeline-engine-refactor/src/test/resources/compose-test-services.yml src/test/resources/
```

### Step 4: Update Project-Specific Files

#### 4a. Update `settings.gradle`
```gradle
rootProject.name = 'SERVICE-NAME'  // Change this line
```

#### 4b. Update `build.gradle`

Add these at the top after plugins:
```gradle
plugins {
    alias(libs.plugins.java)
    alias(libs.plugins.quarkus)
    alias(libs.plugins.maven.publish)  // Add this
}

dependencies {
    implementation 'io.quarkus:quarkus-container-image-docker'  // Add this
    
    // Dev services infrastructure (shared Docker Compose stack)
    runtimeOnly 'io.pipeline:devservices-docker-compose:1.0.0-SNAPSHOT'  // Add this
    
    // Use published BOM from Maven Local
    implementation platform('io.pipeline:pipeline-bom:1.0.0-SNAPSHOT')
    
    // ... existing dependencies ...
    
    // Test dependencies
    testImplementation 'io.quarkus:quarkus-junit5'
    testImplementation 'io.pipeline:grpc-wiremock:1.0.0-SNAPSHOT'
    testImplementation libs.smallrye.reactive.messaging.in.memory  // Add this for Kafka mocking
}
```

Add publishing configuration at the end:
```gradle
// Publishing configuration
publishing {
    publications {
        maven(MavenPublication) {
            from components.java
            pom {
                name.set('SERVICE Display Name')
                description.set('Service description')
                url.set('https://github.com/io-pipeline/SERVICE-NAME')

                licenses {
                    license {
                        name.set('Apache License 2.0')
                        url.set('https://www.apache.org/licenses/LICENSE-2.0')
                    }
                }

                developers {
                    developer {
                        id.set('krickert')
                        name.set('Pipeline Engine Team')
                    }
                }

                scm {
                    connection.set('scm:git:git://github.com/io-pipeline/SERVICE-NAME.git')
                    developerConnection.set('scm:git:ssh://github.com/io-pipeline/SERVICE-NAME.git')
                    url.set('https://github.com/io-pipeline/SERVICE-NAME')
                }
            }
        }
    }

    repositories {
        maven {
            name = "Gitea"
            url = uri("https://git.rokkon.com/api/packages/io-pipeline/maven")
            credentials {
                username = project.findProperty("gitea.user") ?: System.getenv("GITEA_USER") ?: "krickert"
                password = project.findProperty("gitea.token") ?: System.getenv("GITEA_TOKEN")
            }
        }

        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/io-pipeline/SERVICE-NAME")
            credentials {
                username = System.getenv("GITHUB_ACTOR") ?: System.getenv("GH_USER")
                password = System.getenv("GITHUB_TOKEN") ?: System.getenv("GH_PAT")
            }
        }
    }
}
```

#### 4c. Update `application.properties`

Add at the very top:
```properties
# Application
quarkus.application.name=SERVICE-NAME
quarkus.application.version=1.0.0

# Container Image Configuration
quarkus.container-image.registry=git.rokkon.com
quarkus.container-image.group=io-pipeline
quarkus.container-image.name=SERVICE-NAME
quarkus.container-image.tag=latest
quarkus.container-image.additional-tags=${quarkus.application.version}
```

Fix compose file paths (if they exist):
```properties
# OLD (monorepo paths):
%dev.quarkus.compose.devservices.files=../../src/test/resources/compose-devservices.yml
%test.quarkus.compose.devservices.files=../../src/test/resources/compose-test-services.yml

# NEW (standalone repo paths):
%dev.quarkus.compose.devservices.files=src/test/resources/compose-devservices.yml
%test.quarkus.compose.devservices.files=src/test/resources/compose-test-services.yml
```

#### 4d. Update DOCKER.md

Replace all instances of `platform-registration-service` with `SERVICE-NAME` and update port numbers.

### Step 5: Build and Test

```bash
cd /home/krickert/IdeaProjects/gitea/SERVICE-NAME

# Test compilation
./gradlew clean build -x test --no-daemon

# Run tests (may have pre-existing failures)
./gradlew test --no-daemon

# Build Docker image
./gradlew build -Dquarkus.container-image.build=true -x test --no-daemon

# Verify image
docker images | grep SERVICE-NAME
```

### Step 6: Commit and Push

```bash
git add -A
git commit -m "Initial commit: Extract SERVICE-NAME from monorepo

- Core service functionality
- Gradle 9.2 configuration with BOM catalog
- Quarkus container-image-docker for builds
- DevServices integration (shared and test compose files)
- CI/CD workflow for Gitea Actions
- Renovate configuration
- Tests: X completed, Y failed (baseline from monorepo)"

git push
```

### Step 7: Add Gitea Repository Secrets

Go to: `https://git.rokkon.com/io-pipeline/SERVICE-NAME/settings/secrets`

Add these secrets:
- **`GIT_USER`** = `krickert`
- **`GIT_TOKEN`** = (your Gitea token - see renovate-stack.yml or Gitea user settings)

For GitHub mirroring (if needed):
- **`GITHUB_TOKEN`** = (your GitHub PAT)

---

## Configuration Patterns

### New Repository Structure (Post-Migration Pattern)

The migration revealed a new, simplified pattern for services using the published BOM:

#### **settings.gradle** - Standard Pattern
```gradle
pluginManagement {
    repositories {
        // Gradle Plugin Portal (proxied through Nexus)
        maven {
            url = uri('https://maven.rokkon.com/repository/gradle-plugins/')
            allowInsecureProtocol = false
        }
        gradlePluginPortal()
        mavenCentral()
    }
}

rootProject.name = 'service-name'

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)

    versionCatalogs {
        libs {
            // Import version catalog from published BOM
            from("io.pipeline:pipeline-bom-catalog:1.0.0-SNAPSHOT")
        }
    }

    repositories {
        // Maven Local for published Pipeline artifacts during development
        mavenLocal() {
            content {
                includeGroupByRegex "io\\.pipeline(\\..*)?"
            }
        }

        // Gitea Maven registry (for BOM catalog and internal artifacts)
        maven {
            url = uri('https://git.rokkon.com/api/packages/io-pipeline/maven')
            allowInsecureProtocol = false
            content {
                includeGroupByRegex "io\\.pipeline(\\..*)?"
            }
        }

        // Nexus as Maven Central mirror (fast local cache on NAS)
        maven {
            url = uri('https://maven.rokkon.com/repository/maven-public/')
            allowInsecureProtocol = false
        }

        // Fallback to Maven Central
        mavenCentral()
    }
}
```

**Key Changes from Old Pattern:**
- **No Sonatype repository** - Now included in Nexus (maven-public)
- **`RepositoriesMode.PREFER_SETTINGS`** - Enforces repository configuration
- **BOM catalog from published artifact** - No more `files("../../gradle/libs.versions.toml")`
- **Nexus as primary source** - Faster builds with local NAS caching

#### **build.gradle** - Publishing Pattern
```gradle
plugins {
    alias(libs.plugins.java)
    alias(libs.plugins.quarkus)
    alias(libs.plugins.maven.publish)  // Required for publishing
}

dependencies {
    implementation platform('io.pipeline:pipeline-bom:1.0.0-SNAPSHOT')
    // ... other dependencies ...
}

// Publishing configuration
publishing {
    publications {
        maven(MavenPublication) { publication ->
            from components.java
            artifact(file("${buildDir}/quarkus-app/quarkus-run.jar")) { artifact ->
                artifact.classifier = 'runner'
                artifact.builtBy tasks.named('quarkusBuild')
            }
            pom { pom ->
                name.set('Service Name')
                description.set('Service description')
                url.set('https://github.com/io-pipeline/service-name')
                // ... licenses, developers, scm ...
            }
        }
    }

    repositories {
        // Publish to Maven Local for development
        mavenLocal()

        // Publish to Reposilite (primary artifact repository)
        maven {
            name = "Reposilite"
            url = uri(version.toString().endsWith('-SNAPSHOT')
                ? "https://maven.rokkon.com/snapshots"
                : "https://maven.rokkon.com/releases")
            credentials {
                username = project.findProperty("reposilite.user") ?: System.getenv("REPOS_USER") ?: "admin"
                password = project.findProperty("reposilite.token") ?: System.getenv("REPOS_PAT")
            }
        }

        // Publish to Gitea Maven registry (backup)
        maven {
            name = "Gitea"
            url = uri("https://git.rokkon.com/api/packages/io-pipeline/maven")
            credentials {
                username = project.findProperty("gitea.user") ?: System.getenv("GIT_USER") ?: "krickert"
                password = project.findProperty("gitea.token") ?: System.getenv("GIT_TOKEN")
            }
        }
    }
}
```

**Key Points:**
- **Dual publishing**: Reposilite (primary) + Gitea (backup)
- **Runner JAR artifact**: Includes Quarkus runner for deployment
- **Credential flexibility**: Properties, environment variables, or defaults

#### **Special Cases**

**Services with Apache Tika** (e.g., module-parser):
```gradle
// In settings.gradle repositories block, add:
// Apache snapshots for Tika
maven {
    url = uri("https://repository.apache.org/content/repositories/snapshots/")
    content {
        includeGroup "org.apache.tika"
    }
    mavenContent {
        snapshotsOnly()
    }
}
```

**Services with DJL/PyTorch** (e.g., module-embedder):
- No special configuration needed
- DJL dependencies (djl-huggingface-tokenizers, djl-pytorch-model-zoo, djl-pytorch-jni) compile OOTB
- OS-specific JNI dependencies handled automatically by standard repository structure

**Services with Testcontainers** (e.g., opensearch-manager):
- Alternative to Docker Compose for test infrastructure
- See `dev-assets/docs/developer_guides/kafka/Kafka_Apicurio_Guide_for_Quarkus.md` for details

---

### Standard Kafka/Apicurio Pattern (for ALL services with Kafka)

```properties
# Apicurio Registry indexing (REQUIRED for Protobuf)
quarkus.index-dependency.apicurio-registry.group-id=io.apicurio
quarkus.index-dependency.apicurio-registry.artifact-id=apicurio-registry-protobuf-serde-kafka

# Kafka bootstrap servers (all profiles)
kafka.bootstrap.servers=${KAFKA_BOOTSTRAP_SERVERS:localhost:9094}
%dev.kafka.bootstrap.servers=localhost:9094
%test.kafka.bootstrap.servers=localhost:9095
%prod.kafka.bootstrap.servers=kafka:9092

# Per-channel configuration (replace CHANNEL-NAME and specific values)
mp.messaging.outgoing.CHANNEL-NAME.connector=smallrye-kafka
mp.messaging.outgoing.CHANNEL-NAME.topic=TOPIC-NAME
mp.messaging.outgoing.CHANNEL-NAME.key.serializer=org.apache.kafka.common.serialization.StringSerializer
mp.messaging.outgoing.CHANNEL-NAME.value.serializer=io.apicurio.registry.serde.protobuf.ProtobufKafkaSerializer
mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.auto-register=true
mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.artifact-id=ARTIFACT-ID
mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.artifact-type=PROTOBUF
mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.proto.message-name=ProtoMessageName
mp.messaging.outgoing.CHANNEL-NAME.bootstrap.servers=${kafka.bootstrap.servers}
%dev.mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.url=http://localhost:8081/apis/registry/v3
%test.mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.url=http://localhost:8082/apis/registry/v3
%prod.mp.messaging.outgoing.CHANNEL-NAME.apicurio.registry.url=http://apicurio-registry:8080/apis/registry/v3

# Global connector defaults (CRITICAL - applies to all channels)
%dev.mp.messaging.connector.smallrye-kafka.bootstrap.servers=${kafka.bootstrap.servers}
%dev.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=http://localhost:8081/apis/registry/v3
%test.mp.messaging.connector.smallrye-kafka.bootstrap.servers=${kafka.bootstrap.servers}
%test.mp.messaging.connector.smallrye-kafka.apicurio.registry.url=http://localhost:8082/apis/registry/v3
# NOTE: %prod connector config is optional - channels can use their own URLs
```

### Database Pattern

```properties
# Database
quarkus.datasource.db-kind=mysql

# Dev - use shared devservices MySQL
%dev.quarkus.datasource.jdbc.url=jdbc:mysql://localhost:3306/pipeline_SERVICE_dev
%dev.quarkus.datasource.username=pipeline
%dev.quarkus.datasource.password=password

# Test - use compose-test-services MySQL on different port
%test.quarkus.datasource.jdbc.url=jdbc:mysql://localhost:3307/pipeline_SERVICE_test
%test.quarkus.datasource.username=pipeline
%test.quarkus.datasource.password=password

# Hibernate strategies
%dev.quarkus.hibernate-orm.schema-management.strategy=none
%dev.quarkus.flyway.migrate-at-start=true
%test.quarkus.hibernate-orm.schema-management.strategy=drop-and-create
%test.quarkus.hibernate-orm.sql-load-script=import.sql
%test.quarkus.flyway.migrate-at-start=false
%prod.quarkus.hibernate-orm.schema-management.strategy=validate
%prod.quarkus.flyway.migrate-at-start=true
```

### DevServices Pattern

```properties
# Dev - use shared infrastructure (assumed always running)
%dev.quarkus.devservices.enabled=true
%dev.quarkus.compose.devservices.files=src/test/resources/compose-devservices.yml
%dev.quarkus.compose.devservices.project-name=pipeline-shared-devservices
%dev.quarkus.compose.devservices.start-services=true
%dev.quarkus.compose.devservices.stop-services=false
%dev.quarkus.compose.devservices.reuse-project-for-tests=true

# Test - isolated compose stack with different ports
%test.quarkus.devservices.enabled=true
%test.quarkus.compose.devservices.files=src/test/resources/compose-test-services.yml
%test.quarkus.compose.devservices.project-name=pipeline-test-services
%test.quarkus.compose.devservices.start-services=true
%test.quarkus.compose.devservices.stop-services=false
%test.quarkus.compose.devservices.reuse-project-for-tests=true
```

---

## CI/CD Setup

### Gitea Actions Workflow

File: `.gitea/workflows/build-and-publish.yml`

**Required Secrets (in Gitea repo settings):**
- `GIT_USER` - Gitea username (krickert)
- `GIT_TOKEN` - Gitea access token
- `GITHUB_TOKEN` - GitHub PAT (auto-provided by Gitea Actions)

**Workflow does:**
1. Build and test the application
2. Publish Maven artifacts to Gitea Maven + GitHub Packages (on main branch)
3. Build Docker image using Quarkus
4. Push Docker image to Gitea Container Registry (on main branch)
5. Tag with `latest`, version, and commit SHA

### Manual Build Commands

```bash
# Build only
./gradlew build

# Build with Docker
./gradlew build -Dquarkus.container-image.build=true

# Build and push Docker
./gradlew build \
  -Dquarkus.container-image.build=true \
  -Dquarkus.container-image.push=true

# Publish to Maven Local
./gradlew publishToMavenLocal

# Publish to Gitea Maven
./gradlew publishAllPublicationsToGiteaRepository

# Publish to GitHub Packages
./gradlew publishAllPublicationsToGitHubPackagesRepository
```

---

## Testing Strategy

### Test Infrastructure

**Development (`%dev` profile):**
- Uses `src/test/resources/compose-devservices.yml`
- Shared infrastructure (MySQL: 3306, Kafka: 9094, Apicurio: 8081)
- Infrastructure assumed to be always running
- Ports: Dev ports (see Port Allocation below)

**Tests (`%test` profile):**
- Uses `src/test/resources/compose-test-services.yml`
- Isolated infrastructure with different ports to avoid conflicts
- Ports: Test ports (MySQL: 3307, Kafka: 9095, Apicurio: 8082)
- Automatically started/stopped by Quarkus DevServices

**Production (`%prod` profile):**
- Uses Docker service names (mysql, kafka, apicurio-registry)
- Configured via environment variables

### Test Dependencies

Required in `build.gradle`:
```gradle
testImplementation 'io.quarkus:quarkus-junit5'
testImplementation 'io.pipeline:grpc-wiremock:1.0.0-SNAPSHOT'
testImplementation libs.smallrye.reactive.messaging.in.memory  // For Kafka mocking
```

### Running Tests

```bash
# Run all tests
./gradlew test

# Run specific test class
./gradlew test --tests "io.pipeline.account.AccountServiceTest"

# Run tests with debug output
./gradlew test --info

# Skip tests during build
./gradlew build -x test
```

### Test Expectations

- Some tests may fail in the original monorepo (pre-existing failures)
- Goal: Match or improve the monorepo test results
- **DO NOT delete or comment out failing tests** - fix the underlying issues
- WireMock is used for mocking dependent gRPC services

---

## Port Allocation

### Dev Services (shared, always running)
- MySQL: `3306`
- Consul: `8500`
- Kafka: `9092` (internal), `9094` (localhost)
- Apicurio Registry: `8081`
- Redis: `6379`
- MinIO: `9000`, `9001`
- OpenSearch: `9200`, `9600`
- Traefik: `38080`, `8080`

### Test Services (isolated, auto-started)
- MySQL: `3307`
- Kafka: `9095`
- Apicurio Registry: `8082`
- MinIO: `9010`

### Service Ports
- platform-registration-service: `38101`
- repository-service: `38102`
- account-service: `38105`
- connector-intake-service: `38103`
- connector-admin: `38104`
- opensearch-manager: `38106`
- mapping-service: `38107`

---

## Troubleshooting

### Build Failures

**"Could not find pipeline-bom-catalog"**
- Solution: Publish BOM first: `cd /path/to/bom && ./gradlew publishToMavenLocal`

**"Could not find io.pipeline:grpc-stubs"**
- Solution: Publish gRPC: `cd /path/to/grpc && ./gradlew publishToMavenLocal`

**"Could not find io.pipeline:pipeline-commons"**
- Solution: Publish libraries: `cd /path/to/libraries && ./gradlew publishAllToMavenLocal`

**"BOM version mismatch"**
- Remove any `enforcedPlatform()` declarations
- Use only: `implementation platform('io.pipeline:pipeline-bom:1.0.0-SNAPSHOT')`

### Test Failures

**"Missing registry base url, set apicurio.registry.url"**
- Add `%test.mp.messaging.outgoing.CHANNEL.apicurio.registry.url=http://localhost:8082/apis/registry/v3`
- Add global connector config for %test profile

**"Could not find compose-test-services.yml"**
- Copy from monorepo: `cp /path/to/monorepo/src/test/resources/compose-test-services.yml src/test/resources/`
- Fix path in properties: `src/test/resources/compose-test-services.yml` (not `../../src/test/resources/`)

**Tests timing out**
- Increase timeout: `%test.quarkus.devservices.timeout=120s`
- Check Docker resources (memory, CPU)

### Docker Build Failures

**"Unable to find root of Dockerfile files"**
- Dockerfiles missing: Copy from another service's `src/main/docker/`
- Or regenerate: `quarkus ext add container-image-docker` (may need manual fixes)

**"Connection refused" when running container**
- Ensure devservices infrastructure is running
- Check Docker network: `docker network inspect pipeline-shared-devservices_pipeline-test-network`
- Verify environment variables match service configuration

### CI/CD Failures

**"Unauthorized" when publishing**
- Add `GIT_USER` and `GIT_TOKEN` secrets in Gitea repo settings
- Token can be found in renovate-stack.yml or create new one in Gitea user settings

**Workflow not triggering**
- Check `.gitea/workflows/` directory exists (not `.github/workflows/`)
- Verify Gitea Actions is enabled (should be by default)
- Check Gitea Actions logs in repo UI

---

## Common Mistakes to Avoid

1. ❌ **Don't copy `gradle/libs.versions.toml`** - It's imported from BOM catalog
2. ❌ **Don't use `../../` paths** - Use paths relative to project root
3. ❌ **Don't forget the topic name** - `mp.messaging.outgoing.CHANNEL.topic=TOPIC-NAME`
4. ❌ **Don't skip %test and %prod Apicurio URLs** - All three profiles need them
5. ❌ **Don't delete/comment failing tests** - Fix the root cause or accept baseline failures
6. ❌ **Don't forget to copy Dockerfiles** - rsync excludes them by default
7. ❌ **Don't forget compose files** - Both devservices and test-services needed
8. ❌ **Don't use wrong secret names** - Use `GIT_USER`/`GIT_TOKEN`, not `GITEA_*`

---

## Quick Reference Checklist

- [ ] Clone empty Gitea repo
- [ ] Copy source with rsync (exclude build artifacts)
- [ ] Copy standard files (gitignore, settings, wrapper, workflow, renovate, docker.md)
- [ ] Copy Dockerfiles to `src/main/docker/`
- [ ] Copy both compose files to `src/test/resources/`
- [ ] Update `rootProject.name` in settings.gradle
- [ ] Add maven-publish, container-image-docker to build.gradle
- [ ] Add devservices-docker-compose dependency
- [ ] Add publishing configuration to build.gradle
- [ ] Add application name and container config to properties
- [ ] Fix compose file paths (remove `../../`)
- [ ] Verify Kafka/Apicurio config (all 3 profiles!)
- [ ] Update DOCKER.md service name and ports
- [ ] Build without tests: `./gradlew build -x test`
- [ ] Run tests: `./gradlew test`
- [ ] Build Docker: `./gradlew build -Dquarkus.container-image.build=true -x test`
- [ ] Commit and push
- [ ] Add Gitea secrets: GIT_USER, GIT_TOKEN
- [ ] Verify CI/CD workflow runs
- [ ] Mark TODO as complete

---

## Lessons Learned from Recent Migrations

### Repository Structure Simplification (Nov 2024)

The migration of 8 services (connector-admin, opensearch-manager, connector-intake-service, mapping-service, module-chunker, module-parser, module-echo, module-embedder) revealed important patterns:

1. **Sonatype No Longer Needed**
   - Nexus (maven.rokkon.com/repository/maven-public/) now includes Sonatype content
   - Remove all `s01.oss.sonatype.org` references from settings.gradle
   - Simplifies configuration and reduces potential points of failure

2. **Published BOM Catalog is Reliable**
   - All 8 services successfully migrated to `from("io.pipeline:pipeline-bom-catalog:1.0.0-SNAPSHOT")`
   - No need for file-based version catalogs (`files("../../gradle/libs.versions.toml")`)
   - Works even for complex dependencies (DJL/PyTorch, Apache Tika)

3. **Dual Publishing Strategy**
   - **Reposilite** (https://maven.rokkon.com): Primary artifact repository, fast, reliable
   - **Gitea Maven** (https://git.rokkon.com/api/packages/io-pipeline/maven): Backup, Git-integrated
   - Both repositories accept the same credentials pattern

4. **SSH Remote Required for Push**
   - HTTPS git remotes cause authentication issues in automated environments
   - Always use: `ssh://git@git.rokkon.com:2222/io-pipeline/SERVICE-NAME.git`
   - Set with: `git remote set-url origin ssh://git@git.rokkon.com:2222/io-pipeline/SERVICE-NAME.git`

5. **Gradle Wrapper Often Missing**
   - Many services had incomplete gradle wrapper (missing gradle/wrapper/gradle-wrapper.jar)
   - Copy entire `gradle/` directory from a working service (e.g., connector-admin, module-parser)
   - Use Gradle 9.2.0-all distribution

### Testing Patterns

1. **Docker Compose vs Testcontainers**
   - **Docker Compose**: Better for complex multi-service setups (MySQL + Kafka + Apicurio)
   - **Testcontainers**: Better for single/independent services (OpenSearch + Kafka)
   - Both approaches work, choose based on service dependencies

2. **MySQL Integration for Apicurio**
   - Apicurio uses MySQL for persistent schema storage
   - Include `init-db` service to create required databases
   - Health checks ensure proper startup ordering

3. **Kafka Listener Configuration**
   - **PLAINTEXT** (kafka-test:9092): Container-to-container (Apicurio → Kafka)
   - **LOCALHOST** (localhost:9093): Host-to-container (tests → Kafka)
   - **CONTROLLER** (kafka-test:9094): KRaft internal
   - This dual-listener pattern is critical for Docker networking

4. **Critical Apicurio Property**
   - `apicurio.registry.deserializer.value.return-class` prevents ClassCastException
   - Without it, deserializer creates `DynamicMessage` instead of concrete classes
   - Must specify fully qualified Java class name

### Special Dependencies

1. **Apache Tika** (module-parser)
   - Requires Apache snapshots repository for snapshot versions
   - Add to settings.gradle with `snapshotsOnly()` and `includeGroup "org.apache.tika"`
   - Compiles successfully with standard pattern

2. **DJL/PyTorch** (module-embedder)
   - No special configuration needed
   - OS-specific JNI dependencies (djl-pytorch-jni) handled automatically
   - PyTorch model packaging can be addressed separately as needed

3. **OpenNLP** (module-chunker)
   - Works with standard BOM pattern
   - No special repository configuration needed

### Migration Success Metrics

**Services Successfully Migrated:** 10 of 14 (71%)
- 2 services from initial migration (platform-registration-service, account-service)
- 8 services from BOM migration (Nov 2024)

**Test Results:**
- connector-admin: 41 tests passing
- All other services: Compilation successful
- Some test suites need configuration (opensearch-manager)

**Build Times:**
- Initial migration: ~30 seconds per service
- Subsequent builds: ~5-10 seconds (Gradle caching + Nexus caching)

### Recommended Migration Order

Based on successful pattern:

1. **Simple Services First** (no external dependencies)
   - module-echo ✅
   - mapping-service ✅

2. **Services with Standard Dependencies**
   - connector-intake-service ✅
   - module-chunker ✅

3. **Services with Complex Dependencies**
   - module-parser (Apache Tika) ✅
   - module-embedder (DJL/PyTorch) ✅

4. **Services with Complex Test Setup**
   - connector-admin (MySQL + Kafka + Apicurio) ✅
   - opensearch-manager (testcontainers) ✅

5. **Services with Legacy Issues**
   - repository-service (Redis refactor needed)
   - pipestream-engine (deprecated)

---

## Additional Resources

**Documentation:**
- Kafka/Apicurio Integration Guide: `dev-assets/docs/developer_guides/kafka/Kafka_Apicurio_Guide_for_Quarkus.md`
- Comprehensive guide with Docker Compose, Testcontainers, and integration details

**Reference Implementations:**
- **connector-admin**: Complete Docker Compose setup with MySQL, Kafka, Apicurio
- **opensearch-manager**: Testcontainers setup for OpenSearch and Kafka
- **module-parser**: Apache Tika snapshot repository pattern
- **module-embedder**: DJL/PyTorch dependency pattern

---

## Notes

- **Template service:** Use `connector-admin` or `opensearch-manager` as reference (most recent migrations)
- **Shared infrastructure:** `devservices-docker-compose` library provides compose files
- **Test isolation:** Each service gets isolated test infrastructure on different ports
- **Renovate:** Auto-discovers repos matching `io-pipeline/*` and creates dependency update PRs
- **Mirrors:** Gitea automatically mirrors to GitHub (configured at org level)
- **BOM Catalog:** Centralized in `pipeline-bom`, published to both Reposilite and Gitea


