# Reposilite Repository Manager

Lightweight artifact repository supporting Maven, npm, and Docker registries.

## Quick Start

### First Run Setup

```bash
# 1. Deploy the stack (uses temporary token: admin/changeme123)
docker-compose -f reposilite-stack.yml up -d

# 2. Wait for it to start
docker logs -f reposilite

# 3. Access web UI
# URL: https://maven.rokkon.com
# Login: admin / changeme123

# 4. Open Console tab in web UI (requires WebSocket support in Traefik - already configured)
# Type this command to generate a permanent token:
token-generate admin m

# This creates a user 'admin' with management (m) permissions
# Copy the generated secure password!

# 5. Stop and remove the temporary token
docker-compose -f reposilite-stack.yml down

# 6. Edit reposilite-stack.yml and REMOVE this line:
#    - REPOSILITE_OPTS=--token admin:changeme123

# 7. Restart with permanent credentials
docker-compose -f reposilite-stack.yml up -d

# 8. Login with your new permanent token
```

### Access

- **URL**: https://maven.rokkon.com
- **First login**: `admin` / `changeme123` (temporary)
- **After setup**: `admin` / `<your-generated-token>`

## Setup Repositories

After first login, Reposilite will have default repositories. You need to configure:

### 1. Maven (Java) - Default Setup
- **Releases**: `releases` (already exists)
- **Snapshots**: `snapshots` (already exists)
- **Proxy Maven Central**: Create new repository → Type: Proxy → URL: `https://repo1.maven.org/maven2/`

### 2. npm (Node.js)
Create repository via Web UI:
- Name: `npm`
- Type: `hosted` (or proxy to https://registry.npmjs.org/)

### 3. Docker Registry
Create repository via Web UI:
- Name: `docker`
- Type: `hosted`

## Using the Repositories

### Maven (pom.xml or settings.xml)

```xml
<repositories>
  <repository>
    <id>reposilite-releases</id>
    <url>https://maven.rokkon.com/releases</url>
  </repository>
  <repository>
    <id>reposilite-snapshots</id>
    <url>https://maven.rokkon.com/snapshots</url>
    <snapshots><enabled>true</enabled></snapshots>
  </repository>
  <repository>
    <id>reposilite-proxy</id>
    <url>https://maven.rokkon.com/maven-central</url>
  </repository>
</repositories>

<distributionManagement>
  <repository>
    <id>reposilite-releases</id>
    <url>https://maven.rokkon.com/releases</url>
  </repository>
  <snapshotRepository>
    <id>reposilite-snapshots</id>
    <url>https://maven.rokkon.com/snapshots</url>
  </snapshotRepository>
</distributionManagement>
```

### Maven Authentication (~/.m2/settings.xml)

```xml
<servers>
  <server>
    <id>reposilite-releases</id>
    <username>admin</username>
    <password>YOUR_TOKEN_HERE</password>
  </server>
  <server>
    <id>reposilite-snapshots</id>
    <username>admin</username>
    <password>YOUR_TOKEN_HERE</password>
  </server>
</servers>
```

### npm (.npmrc)

```ini
registry=https://maven.rokkon.com/npm/
//maven.rokkon.com/npm/:_authToken=YOUR_TOKEN_HERE
```

### Docker

```bash
# Login
docker login maven.rokkon.com
# Username: admin
# Password: YOUR_TOKEN_HERE

# Tag and push
docker tag myimage:latest maven.rokkon.com/docker/myimage:latest
docker push maven.rokkon.com/docker/myimage:latest

# Pull
docker pull maven.rokkon.com/docker/myimage:latest
```

## Configuration

### Create Access Tokens

1. Login to https://maven.rokkon.com
2. Go to Settings → Tokens
3. Create tokens for different users/CI systems
4. Tokens format: `username:token-value`

### Proxy Apache Maven Central (Recommended)

This caches Apache artifacts locally:

1. Go to Repositories → Create
2. Name: `maven-central` (or `apache-proxy`)
3. Type: Proxy
4. Proxied URL: `https://repo1.maven.org/maven2/`
5. Save

Then use in your `pom.xml`:
```xml
<repository>
  <id>reposilite-proxy</id>
  <url>https://maven.rokkon.com/maven-central</url>
</repository>
```

### Storage Locations

Data is persisted in Docker volumes:
- `reposilite-data` - All artifacts and repositories
- `reposilite-config` - Configuration files

To backup:
```bash
docker run --rm -v reposilite-data:/data -v $(pwd):/backup alpine tar czf /backup/reposilite-backup.tar.gz /data
```

## Monitoring

```bash
# View logs
docker logs -f reposilite

# Check storage usage
docker exec reposilite du -sh /app/data

# Restart service
docker-compose -f reposilite-stack.yml restart
```

## Troubleshooting

### Can't access maven.rokkon.com
- Verify Traefik is running: `docker ps | grep traefik`
- Check Traefik network exists: `docker network ls | grep traefik`
- Verify DNS points to your server

### Docker push fails
- Ensure you're using `/v2` endpoint (handled automatically)
- Check Docker daemon allows insecure registry if not using HTTPS (shouldn't be needed with Traefik SSL)

### Maven can't download
- Check proxy repository is configured
- Verify token has read permissions
- Test: `curl -u admin:TOKEN https://maven.rokkon.com/releases/`

## Advanced: Configuration File

After first run, you can edit `/app/configuration/configuration.cdn` in the container:

```bash
docker exec -it reposilite vi /app/configuration/configuration.cdn
```

Or mount a config file in the compose:
```yaml
volumes:
  - ./reposilite-config.cdn:/app/configuration/configuration.cdn
```
