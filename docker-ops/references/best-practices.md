# Docker best practices

## Dockerfile patterns

### Base image selection

| Use case | Base image | Size | Security |
|---|---|---|---|
| Go, Rust (static binaries) | `scratch` | ~0 MB | Minimal attack surface |
| Static binaries with TLS/DNS | `gcr.io/distroless/static-debian12` | ~2 MB | No shell, no package manager |
| Java, Python, Node.js | `gcr.io/distroless/java21-debian12` etc. | ~50-200 MB | Runtime only, no shell |
| General purpose (minimal) | `debian:bookworm-slim` | ~75 MB | Smaller than full Debian |
| Alpine (smallest general) | `alpine:3.20` | ~8 MB | musl libc (may cause compatibility issues) |
| RHEL-compatible | `registry.access.redhat.com/ubi9-minimal` | ~35 MB | Red Hat Universal Base Image |

**Alpine caution**: Alpine uses musl libc instead of glibc. This causes issues with some C extensions (Python, Ruby, Node.js native modules), and DNS resolution differs. Use `-slim` Debian variants if you hit musl compatibility problems.

### Multi-stage build patterns

Builder pattern (compiled languages):

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o server .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

Dependencies-first pattern (interpreted languages):

```dockerfile
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production

FROM node:22-slim
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

Test stage pattern (the final stage only builds if tests pass, under the default or `--target=production`):

```dockerfile
FROM builder AS test
RUN go test -v ./...

FROM builder AS production
```

### Layer optimisation

1. **Order by change frequency** (least to most): system packages (rarely change), dependency manifests (change occasionally), application source (changes frequently).

2. **Combine related RUN commands** so all apt packages land in a single layer with the cache cleaned in the same step:

```dockerfile
# Good: single layer, cache cleaned in-step
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Bad: multiple layers, apt cache left in a layer
RUN apt-get update
RUN apt-get install curl
RUN apt-get install ca-certificates
```

3. **Use BuildKit cache mounts** instead of manual cleanup:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates
```

### ARG and ENV patterns

```dockerfile
# Build-time argument with default
ARG APP_VERSION=1.0.0

# Persist ARG value as ENV (ARGs reset after FROM)
FROM base AS final
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION}
```

`ARG` values declared before `FROM` are available only to `FROM` instructions; re-declare them after `FROM` to use them in the build. Runtime-only values should be set via `docker run -e` or the Compose `environment:`, not baked into the image.

### ENTRYPOINT + CMD pattern

```dockerfile
# ENTRYPOINT: the executable. CMD: default arguments (overridable at runtime)
ENTRYPOINT ["python", "manage.py"]
CMD ["runserver", "0.0.0.0:8000"]
# docker run myapp migrate  -> python manage.py migrate
# docker run myapp shell    -> python manage.py shell
```

Use the exec form (`["cmd", "arg"]`) not the shell form (`cmd arg`) so the process runs as PID 1 and receives SIGTERM directly for correct signal handling.

## Security best practices

These are the Docker-level build and run knobs. The security programme that decides scanning gates, admission policy, and signature enforcement is `container-security`; the handling discipline for any secret literal is `secrets-hygiene`.

### Image security checklist

1. **Pin base image versions**: `FROM node:22.5.1-slim`, not `FROM node:latest`.
2. **Scan images** in the pipeline (`docker scout cves myimage:latest`, or a scanner of choice).
3. **Use a non-root user**: always add a `USER` instruction.
4. **Minimise packages**: `--no-install-recommends`, remove docs and man pages.
5. **No secrets in the image**: `--secret` mounts for build, files or env-from-secret for runtime.
6. **Read-only rootfs**: `--read-only` with tmpfs for the writable paths.
7. **Drop capabilities**: `--cap-drop ALL --cap-add <needed>`.
8. **Sign images** for supply-chain verification (e.g. `cosign sign`); the enforcement side is `container-security`.

### Secrets management

Build-time secrets never enter a layer:

```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm install
RUN --mount=type=secret,id=ssh_key,target=/root/.ssh/id_rsa,mode=0600 \
    git clone git@github.com:private/repo.git
```

```bash
docker buildx build \
  --secret id=npmrc,src=$HOME/.npmrc \
  --secret id=ssh_key,src=$HOME/.ssh/id_rsa .
```

Runtime secrets in Compose mount as files, never as environment variables:

```yaml
services:
  app:
    secrets:
      - db_password
    environment:
      DB_PASSWORD_FILE: /run/secrets/db_password

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

## Compose best practices

### Service dependencies

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_healthy    # wait for health check
      redis:
        condition: service_started    # just wait for container start
```

Use `service_healthy` when the dependency needs initialisation time (databases, message brokers).

### Resource limits

```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M
```

### Environment variable precedence

1. `docker compose run -e` (highest)
2. `environment:` in compose.yaml
3. `env_file:` in compose.yaml
4. `.env` file in the project root (variable substitution only)

### Named volumes for data persistence

```yaml
volumes:
  postgres-data:
    driver: local
    driver_opts:              # optional NFS mount
      type: nfs
      o: addr=192.168.1.100,rw,nfsvers=4.1
      device: ":/exports/postgres"
```

Prefer named volumes over bind mounts for database data in production, for portability and Docker-managed lifecycle.

### Profile-based services

```yaml
services:
  app:
    image: myapp              # always started (no profile)

  debug-tools:
    image: nicolaka/netshoot
    profiles: [debug]
    network_mode: "service:app"

  load-test:
    image: grafana/k6
    profiles: [testing]
```

## Image optimisation

### Size reduction techniques

1. **Multi-stage builds**: build tools stay out of the final image.
2. **Distroless / scratch**: minimal base images.
3. **Combined RUN**: fewer layers, less per-layer metadata overhead.
4. **Cache mounts**: package-manager cache does not land in a layer.
5. **Strip binaries**: `go build -ldflags="-s -w"`, `strip --strip-all binary`.
6. **.dockerignore**: shrinks the build context and prevents accidental inclusion.

### Analysing image size

```bash
docker history myimage:latest                                   # layer sizes
docker image inspect myimage:latest --format '{{.Size}}'        # total size
dive myimage:latest                                             # interactive layer analysis
docker scout recommendations myimage:latest                     # smaller-base suggestions
```

### Registry optimisation

```bash
# Multi-platform images push once, shared layers across architectures
docker buildx build --platform linux/amd64,linux/arm64 --push -t myapp:v1 .

# Registry cache for CI/CD
docker buildx build \
  --cache-from type=registry,ref=registry.example.com/myapp:cache \
  --cache-to type=registry,ref=registry.example.com/myapp:cache,mode=max \
  --push -t myapp:latest .
```

## Development workflow

### Compose watch (hot reload)

```yaml
services:
  app:
    build: .
    develop:
      watch:
        - action: sync           # live sync (interpreted languages)
          path: ./src
          target: /app/src
          ignore:
            - node_modules/
        - action: rebuild         # full rebuild (dependency changes)
          path: package.json
        - action: sync+restart    # sync then restart process
          path: ./config
          target: /app/config
```

```bash
docker compose watch
```

### Development vs production Compose

```yaml
# compose.yaml (base)
services:
  app:
    image: myapp:latest
    environment:
      NODE_ENV: production

# compose.override.yaml (auto-loaded in dev)
services:
  app:
    build: .
    volumes:
      - ./src:/app/src
    environment:
      NODE_ENV: development
      DEBUG: "true"
    ports:
      - "9229:9229"  # debugger
```

`docker compose up` automatically merges `compose.yaml` with `compose.override.yaml`. For production, run the explicit set `docker compose -f compose.yaml -f compose.prod.yaml up` to skip the override.

## Networking best practices

1. **Always use custom bridge networks** (not the default `docker0`): enables DNS resolution by container name.
2. **Disable the userland proxy**: `"userland-proxy": false` in daemon.json for better performance.
3. **Avoid `--network host`** unless benchmarking or truly needed: it breaks container isolation.
4. **Segment networks**: put frontend, backend, and database on separate networks; connect only services that must communicate.
5. **Use IPAM configuration** to avoid subnet conflicts with your LAN or VPN.

## Upgrade and migration

### Docker Engine upgrade procedure

1. Check release notes for breaking changes (API minimum version, removed features).
2. Back up `/var/lib/docker/` and `/etc/docker/daemon.json`.
3. Stop running containers, or enable `live-restore`.
4. Update packages: `apt-get update && apt-get install docker-ce docker-ce-cli containerd.io`.
5. Verify: `docker version`, `docker info`, `docker ps`.
6. Test critical workloads before the production rollout.

The v29-specific migration checklist (containerd image store, API 1.44, removed drivers) is in `versions.md`.
