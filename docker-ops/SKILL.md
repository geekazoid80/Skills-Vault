---
name: docker-ops
description: "Docker Engine day-to-day operations: dockerd/containerd/runc architecture, Dockerfile and BuildKit builds (multi-stage, cache mounts, multi-platform, build secrets, Bake), Docker Compose v2, networking (bridge/host/overlay/macvlan/ipvlan, embedded DNS, iptables/nftables), storage drivers and volumes, daemon.json configuration, and the security knobs (rootless mode, user namespaces, seccomp, capabilities, read-only rootfs). WHEN: \"Docker\", \"Dockerfile\", \"docker build\", \"docker run\", \"docker-compose\", \"Docker Compose\", \"BuildKit\", \"buildx\", \"docker bake\", \"dockerd\", \"daemon.json\", \"containerd image store\", \"overlay2\", \"docker network\", \"docker volume\", \"rootless Docker\", \"Docker Desktop\", \"docker scout\", \"docker system prune\". Do NOT use for: runtime SELECTION or Docker-vs-Podman-vs-containerd comparison (container-runtime-selection); Podman or containerd operations (podman-ops, containerd-ops); container and Kubernetes security STRATEGY such as image scanning, admission control, supply-chain integrity and runtime protection (container-security); Kubernetes orchestration choice (container-orchestration-selection); ingress and reverse proxy for published services (nginx-load-balancing, load-balancer-selection); CI/CD build pipelines (cicd-platforms-ops, gh-actions-ci)."
license: MIT
metadata:
  version: 1.0.0
---

# Docker operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: docker-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Docker Engine operations: building images with the Dockerfile and BuildKit, running containers, wiring them with Compose v2, networking and storage, and configuring the daemon. It assumes Docker is the chosen runtime; the Docker-vs-Podman-vs-containerd decision lives in `container-runtime-selection`. It covers Docker's own security knobs (rootless mode, user namespaces, seccomp, capabilities, read-only rootfs) at the operational level, but routes the security strategy (image scanning as a gate, admission control, supply-chain integrity, runtime protection) to `container-security`.

Coverage spans supported Docker Engine releases, currently 25.0 through 29.x. The architecture is stable across them; the moving parts are the containerd image store default, nftables, and removed storage drivers, all in `## Version notes`.

## When to use

- Writing or optimising a Dockerfile: multi-stage builds, base-image choice, layer cache ordering, BuildKit cache mounts, build secrets, multi-platform builds, Bake.
- Authoring a Compose v2 project: `depends_on` health conditions, profiles, watch mode, resource limits, secrets, override files.
- Configuring Docker networking: custom bridge networks, the embedded DNS, overlay for Swarm, macvlan/ipvlan, published ports, iptables/nftables behaviour.
- Managing storage: named volumes, bind mounts, tmpfs, storage drivers, the containerd image store, mount propagation.
- Editing `daemon.json`: log rotation, address pools, live-restore, alternative runtimes, the containerd-snapshotter feature flag.
- Hardening a container at run time: dropping capabilities, non-root user, read-only filesystem, seccomp profile, rootless daemon.
- Troubleshooting a container or the daemon: logs, `inspect`, `stats`, `events`, `system df`, OOM kills, exit codes, networking and build failures.

## When not to use

- **Runtime selection**: choosing between Docker, Podman, containerd, or another OCI runtime, or comparing their trade-offs, is `container-runtime-selection`. That umbrella decides which runtime fits; this skill operates Docker once chosen.
- **Sibling runtimes**: Podman-specific operation (rootless-by-default, pods, `podman generate`) is `podman-ops`; direct containerd operation (`ctr`, `nerdctl`, CRI, config.toml) is `containerd-ops`. This skill uses the containerd that Docker bundles, but does not operate a standalone containerd.
- **Container and Kubernetes security strategy**: image scanning methodology and CI gate policy, admission control (OPA Gatekeeper, Kyverno, Pod Security Standards), supply-chain integrity (SLSA, cosign, SBOM), and behavioural runtime protection are `container-security`. This skill wires the Docker-level knobs; the security programme that decides how to use them lives there.
- **Kubernetes orchestration**: cluster choice and orchestration design are `container-orchestration-selection`. Note Kubernetes removed the dockershim in 1.24, so a Kubernetes node does not run the Docker daemon; it talks to containerd (or CRI-O) directly.
- **Ingress and reverse proxy** for a published service: `nginx-load-balancing` and the vendor-neutral `load-balancer-selection`. Publishing a container port is here; fronting it with a proxy is there.
- **Certificates and secrets**: in-cluster or service certificates are `cert-manager`; the handling discipline for any token, registry credential, or build secret is `secrets-hygiene`; operating a central secret store is `hashicorp-vault-ops`.
- **CI/CD build pipelines**: the pipeline that runs `docker build` is `cicd-platforms-ops` and `gh-actions-ci`. The Dockerfile and cache-export flags are here; the pipeline that invokes them is there.
- **Observability**: metrics and dashboards for the daemon and containers are `prometheus-configuration` and `grafana-dashboards`.

## Classify the request first

Every request resolves to one of these, which determines the reference to load. Also identify the Docker Engine version; the key boundaries are v23 (BuildKit default), v25 (BuildKit fully default, API baseline), v28 (nftables experimental), v29 (containerd image store default, API minimum 1.44). If unclear, ask, then default guidance to the latest stable (29.x).

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | dockerd/containerd/runc delegation, BuildKit LLB and builder drivers, bridge/overlay internals, embedded DNS, containerd image store layout, logging drivers, contexts, live-restore | `references/architecture.md` |
| Build + design | Dockerfile patterns, multi-stage and test stages, base-image selection, layer-cache ordering, cache mounts, ARG/ENV, ENTRYPOINT+CMD, image-size optimisation, Compose patterns, network and upgrade practice | `references/best-practices.md` |
| Troubleshooting / diagnostics | `logs`, `inspect`, `stats`, `events`, `top`, `diff`, `system df`, OOM and exit codes, networking/storage/build/daemon debugging, health-check and Compose diagnostics | `references/diagnostics.md` |
| Version-specific | v29 containerd image store default, nftables, API minimum 1.44, removed drivers, keep-alive, migration from v28 | `references/versions.md` |

## Core model (condensed)

**The CLI talks to a daemon that delegates to containerd and runc.**

```
Docker CLI -> dockerd -> containerd -> containerd-shim-runc-v2 -> runc -> Linux kernel
```

`dockerd` listens on a Unix socket (`/var/run/docker.sock`), a TCP socket, or a Windows named pipe, and owns image builds (delegated to BuildKit), container lifecycle, and volume and network management. It hands all container execution to containerd, which owns the content-addressable store, container supervision through shims, and the overlayfs snapshotter. runc is the OCI reference runtime that reads the generated `config.json` and sets up namespaces, cgroups, seccomp, and capabilities. The shim keeps a container alive if containerd (or the daemon, with `live-restore`) restarts. As of v29 the daemon no longer manages its own image store; that moved to containerd's content store.

**BuildKit is the build engine and the default since v23.** It compiles the Dockerfile into LLB, a directed acyclic graph, so independent instructions run in parallel and the cache keys on instruction plus input content rather than instruction order. Reach for `buildx` and a `docker-container` builder for multi-platform, remote cache, and provenance.

**Compose v2 is a Go CLI plugin (`docker compose`).** The legacy Python `docker-compose` v1 is end-of-life. Compose merges `compose.yaml` with `compose.override.yaml` automatically for local development.

**Custom bridge networks give you name-based DNS; the default `docker0` does not.** On a user-defined bridge, containers resolve each other by name through the embedded DNS at `127.0.0.11`. Always create a custom network rather than leaning on `docker0`.

**Isolation is a configuration you earn.** Docker runs containers as root by default, so add a non-root `USER`, drop all capabilities and add back only what is needed, mount the root filesystem read-only with a writable tmpfs, and prefer the rootless daemon where its limitations allow. These are the Docker-level knobs; the strategy that decides scanning gates and admission policy is `container-security`.

**Anti-patterns:** using `:latest` in production instead of a pinned tag or digest; `COPY . .` at the top of a Dockerfile, busting the cache on every source change; running as root with no `USER`; no `.dockerignore`, so `.git`, `node_modules`, and `.env` land in the build context; `ADD` where `COPY` is meant; no `HEALTHCHECK`, so a hung container looks healthy; baking a secret into a layer with `ENV SECRET=` or `COPY .env`; relying on the default `docker0` bridge and losing name resolution; and `--network host` used routinely, discarding network isolation.

## Dockerfile and BuildKit

**Multi-stage builds** are the primary route to a minimal production image: compile in a fat builder stage, copy only the artefact into a `scratch` or distroless final stage.

```dockerfile
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /app/server .
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

**Order layers by change frequency** (system packages, then dependency manifests, then source) and copy dependency manifests before source so a code change does not reinstall dependencies. Use BuildKit **cache mounts** instead of hand-cleaning package caches:

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends build-essential
```

**Build secrets** never enter a layer:

```bash
docker buildx build --secret id=npmrc,src=$HOME/.npmrc .
```
```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm install
```

**Multi-platform builds** need a container builder, and share layers across architectures when pushed once:

```bash
docker buildx create --name mybuilder --use --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 \
  --tag registry.example.com/myapp:v1.0 --push .
```

**Cache export** speeds CI. Backends are `registry`, `local`, `gha`, `s3`, `azblob`, and `inline`; `mode=max` caches all intermediate layers, `mode=min` (the default) only the final ones.

```bash
docker buildx build \
  --cache-to type=registry,ref=registry.example.com/myapp:cache,mode=max \
  --cache-from type=registry,ref=registry.example.com/myapp:cache \
  --push -t registry.example.com/myapp:latest .
```

**Docker Bake** (HCL) declares multi-target builds so a whole project builds from one file. Compose Specification v5.0.0 (December 2025) removed Compose's internal builder in favour of Bake.

Prefer specific tags over `:latest`, `COPY` over `ADD`, the exec form of `ENTRYPOINT`/`CMD` for correct signal handling as PID 1, and always ship a `.dockerignore`. Fuller patterns (base-image table, ARG/ENV rules, image-size techniques) are in `references/best-practices.md`.

## Docker Compose v2

Compose v2 runs as `docker compose` (space, not hyphen). Key features:

- **Health-gated dependencies**: `depends_on` with `condition: service_healthy` waits for a health check; `service_started` waits only for container start. Use `service_healthy` for anything with an init time (databases, brokers).
- **Profiles**: activate services conditionally with `--profile debug`.
- **Watch mode** (`docker compose watch`, v2.22.0+): `sync`, `rebuild`, or `sync+restart` on file changes for a fast inner loop.
- **Secrets**: mount as files under `/run/secrets/`, never as environment variables.
- **Resource limits**: `deploy.resources.limits` and `reservations` for CPU and memory.

```yaml
services:
  api:
    build: .
    depends_on:
      db:
        condition: service_healthy
    develop:
      watch:
        - action: sync
          path: ./src
          target: /app/src
        - action: rebuild
          path: package.json
```

Environment precedence, from highest: `docker compose run -e`, then `environment:`, then `env_file:`, then the project-root `.env` (substitution only). `docker compose up` auto-merges `compose.yaml` with `compose.override.yaml`; for production run an explicit file set (`-f compose.yaml -f compose.prod.yaml`) to skip the dev override. More in `references/best-practices.md`.

## Networking

| Driver | Scope | Use |
|---|---|---|
| bridge | local | Default; a custom bridge adds name-based DNS between containers |
| host | local | No network namespace; container uses the host stack |
| overlay | swarm | Multi-host via VXLAN encapsulation (UDP 4789) |
| macvlan | local | Container gets its own MAC and IP on the physical LAN |
| ipvlan | local | Like macvlan but shares the MAC; L2 or L3 modes |
| none | local | No networking |

Create a **custom bridge** rather than using `docker0`, because only user-defined networks get the embedded DNS:

```bash
docker network create --driver bridge \
  --subnet 172.20.0.0/16 --gateway 172.20.0.1 myapp-net
```

Docker programs iptables for outbound MASQUERADE, published-port DNAT (`-p 8080:80` via the DOCKER chain), inter-container FORWARD, and cross-bridge isolation. **Segment** frontend, backend, and database onto separate networks and connect only services that must talk. Disabling the userland proxy (`"userland-proxy": false`) improves performance. Docker Engine v29 can generate **nftables** rules directly instead of going through iptables-nft translation; it is opt-in and stable-experimental (see `## Version notes`). Internals (veth pairs, `docker_gwbridge`, overlay VNIs) are in `references/architecture.md`.

## Storage and volumes

- **Named volumes** are Docker-managed and persist across container restarts; use them for database data in production, not bind mounts.
- **Bind mounts** map a host path in (`-v /host:/container`); good for source in development.
- **tmpfs** is in-memory and not persisted (`--tmpfs /tmp:rw,size=100m`).

Named volumes live at `/var/lib/docker/volumes/<name>/_data/`. Mount propagation (`rprivate` default, `rshared`, `rslave`) controls how mounts cross the host/container boundary.

| Driver | Status (v29) | Notes |
|---|---|---|
| overlay2 | Default (legacy store) | Requires `ftype=1` on XFS |
| fuse-overlayfs | Supported | Rootless on older kernels |
| btrfs | Supported | Native snapshotting |
| zfs | Supported | Enterprise features |
| devicemapper | Removed in v29 | Migrate to overlay2 |
| aufs | Removed in v29 | Migrate to overlay2 |

With the containerd image store (default on new v29 installs) the overlayfs snapshotter under `/var/lib/containerd/` manages image layers instead of the overlay2 graphdriver. Verify the active store with `docker info | grep "Storage Driver"`.

## Daemon and security posture

Daemon behaviour is set in `/etc/docker/daemon.json`. Common keys: `log-driver` and `log-opts` for rotation (`max-size`, `max-file`), `default-address-pools` to avoid LAN subnet clashes, `live-restore: true` so containers survive a daemon restart (critical for production upgrades), `userland-proxy: false`, alternative `runtimes` (runsc/gVisor, kata), and the `features.containerd-snapshotter` opt-in on upgraded hosts. Validate the file before restart:

```bash
python3 -c "import json; json.load(open('/etc/docker/daemon.json'))"
```

Docker's run-time security knobs, operational level (the strategy is `container-security`):

```bash
# Drop all capabilities, add back only what is needed
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE myimage

# Read-only root filesystem with writable tmpfs
docker run --read-only --tmpfs /tmp --tmpfs /var/run myimage

# Custom seccomp profile
docker run --security-opt seccomp=/path/to/profile.json myimage
```

**Rootless mode** runs the daemon as a non-root user, removing the container-escape-to-host-root path:

```bash
dockerd-rootless-setuptool.sh install
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
```

Its limitations: no macvlan/ipvlan, no AppArmor by default, and ports below 1024 need `net.ipv4.ip_unprivileged_port_start=0`. **User-namespace remapping** (`"userns-remap": "default"` in `daemon.json`) maps container root to an unprivileged host UID as a middle ground when full rootless is impractical. Never mount `/var/run/docker.sock` into a container you do not fully trust; socket access is root-equivalent on the host.

**Docker Desktop vs Docker Engine**: Desktop runs on macOS, Windows, and Linux inside a managed VM with a GUI and optional built-in Kubernetes, and is paid for large organisations (over 250 employees or over 10M USD revenue). Docker Engine is Linux-only, native (no VM), Apache-2.0, and has no GUI or bundled Kubernetes.

## Version notes

Guidance defaults to the latest stable (29.x) when the version is unknown. Version boundaries that change behaviour:

- **v23**: BuildKit becomes the default build engine.
- **v25**: BuildKit fully default; API baseline for older-client compatibility.
- **v28**: nftables support lands as experimental.
- **v29** (February 2026, latest patch 29.3.1 March 2026, bundles containerd 2.2.2): the **containerd image store is the default for new installs**, replacing the legacy graphdriver; the **minimum API version is 1.44** (older clients and pinned CI tooling break); **nftables** is stabilised but still opt-in; devicemapper, aufs, and Schema 1 image pulls are **removed**; 29.3.1 adds HTTP keep-alive for registry connections.

Existing installs upgrading to v29 keep legacy storage unless they opt in with `features.containerd-snapshotter`, and images are not auto-migrated (a re-pull is needed on the switch). Migrate off devicemapper/aufs to overlay2 before upgrading, or the daemon fails to start. Full v29 change list, migration checklist, and post-migration validation are in `references/versions.md`.

## Cross-references

- `container-runtime-selection`: the vendor-neutral umbrella that decides Docker vs Podman vs containerd; this skill operates Docker once that choice is made. Reciprocal reference.
- `podman-ops`, `containerd-ops`: sibling runtime-operations skills for the other OCI runtimes in the family.
- `container-security`: the security strategy this skill's knobs serve, image scanning as a gate, admission control, supply-chain integrity, runtime protection. Cover the Docker-level rootless/seccomp/capabilities knobs here; take the programme from there.
- `container-orchestration-selection`: Kubernetes and orchestration design; Kubernetes dropped the dockershim in 1.24, so a node runs containerd, not the Docker daemon.
- `nginx-load-balancing`, `load-balancer-selection`: front a published container port with a reverse proxy or load balancer.
- `cert-manager`, `secrets-hygiene`, `hashicorp-vault-ops`: certificates, the handling discipline for registry credentials and build secrets, and operating the central secret store. Never bake a real literal into an image layer.
- `cicd-platforms-ops`, `gh-actions-ci`: the pipeline that runs `docker build` and the cache-export flags this skill defines.
- `prometheus-configuration`, `grafana-dashboards`: metrics and dashboards for the daemon and containers.
- `utc-timestamps`: container logs, `events`, and health-check history correlate on UTC; a skewed host clock corrupts the timeline.

## Red flags

- About to ship `:latest` to production instead of a pinned tag or digest.
- About to `COPY . .` before installing dependencies, busting the layer cache on every source change.
- About to run a container as root with no `USER` and no capability drop.
- About to build without a `.dockerignore`, pulling `.git`, `node_modules`, and `.env` into the context.
- About to bake a secret into a layer with `ENV SECRET=` or `COPY .env` instead of a BuildKit `--secret` mount or a runtime secret.
- About to rely on the default `docker0` bridge and lose name-based DNS between containers.
- About to run `--network host` routinely, discarding network isolation.
- About to mount `/var/run/docker.sock` into an untrusted container (root-equivalent on the host).
- About to enable nftables or the containerd image store on a host with tooling that inspects iptables rules or clients pinned below API 1.44, without checking the version notes.
- About to upgrade to v29 from a devicemapper or aufs host without migrating to overlay2 first (the daemon will not start).

## Bottom line

Docker is a CLI talking to `dockerd`, which delegates execution to containerd and runc; BuildKit is the build engine and Compose v2 is the CLI plugin. Build minimal images with multi-stage Dockerfiles, order layers by change frequency, keep secrets out of layers with `--secret` mounts, and pin tags. Give containers name-based DNS with a custom bridge, persist data in named volumes, and harden at run time with a non-root user, dropped capabilities, a read-only root filesystem, and rootless mode where its limits allow. Track the v29 boundaries (containerd image store, API 1.44, removed drivers) before an upgrade. Bring the runtime choice from `container-runtime-selection` and the security strategy from `container-security`; keep credentials and certificates in their proper homes.
