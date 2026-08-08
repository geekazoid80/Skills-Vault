# Docker Engine version notes

Guidance defaults to the latest stable (29.x) when the version is unknown. Determine the running version with `docker version` and `docker info`.

## Version boundaries

- **v23**: BuildKit becomes the default build engine.
- **v25**: BuildKit fully default; API baseline for older-client compatibility.
- **v28**: nftables support lands as experimental.
- **v29**: containerd image store default (new installs), nftables stabilised (opt-in), API minimum 1.44, legacy storage drivers removed.

## Docker Engine 29.x

Covers 29.0 through 29.3.1 (current latest stable).

- **Initial release**: February 2026
- **Latest patch**: 29.3.1 (March 2026)
- **Bundled containerd**: 2.2.2
- **Bundled runc**: latest stable

### containerd image store (default)

The containerd image store is the **default for all new installations**, replacing Docker's legacy graphdriver-based image management. This is the most significant architectural change.

What changed:

- Image pull, push, and storage are handled by containerd's content store and snapshotter.
- Images are stored at `/var/lib/containerd/io.containerd.content.v1.content/` instead of `/var/lib/docker/image/`.
- containerd's overlayfs snapshotter replaces Docker's overlay2 storage driver for image layers.
- Multi-platform image support is native (image index handling built into containerd).

Impact on existing installations:

- Upgrades from v28 retain legacy storage unless explicitly migrated.
- New installations get the containerd image store by default.
- `docker images`, `docker pull`, `docker push` work identically from the user's perspective.
- Images from legacy storage are not auto-migrated; a re-pull is required when switching.

Verify which store is active:

```bash
docker info | grep "Storage Driver"
docker info | grep "containerd-snapshotter"
```

Opt in on upgraded installations:

```json
{
  "features": {
    "containerd-snapshotter": true
  }
}
```

### Minimum API version raised to 1.44

Docker Engine 29 requires API version 1.44 or newer; older clients that negotiate a lower version receive errors.

Affected clients: Docker CLI versions before 25.0 (`docker version`), third-party tools using the Docker API, and CI/CD pipelines with pinned Docker client versions.

```bash
# Upgrade the CLI to match the engine
apt-get install docker-ce-cli=5:29.3.1-1~ubuntu.24.04~noble

# Or set the API version explicitly (if the client supports it)
export DOCKER_API_VERSION=1.44
```

### nftables (experimental, stabilised)

Docker Engine 29 can generate nftables rules directly instead of routing through the iptables-nft translation layer. This was experimental in v28 and is now stable-experimental.

```json
{
  "iptables": true,
  "ip6tables": true,
  "experimental": true
}
```

Benefits: direct rule generation eliminates translation overhead, better compatibility with distributions deprecating iptables, cleaner rule sets for debugging (`nft list ruleset`).

Do not enable it yet if you depend on tools that inspect iptables rules (fail2ban, some monitoring agents), or if the host has complex existing nftables rules that may conflict.

### HTTP keep-alive for registry connections

Docker Engine 29.3.1 enables HTTP keep-alive for registry connections, reusing TCP/TLS connections across blob transfers during pull and push. This gives faster multi-layer pulls (no repeated TLS handshakes per layer) and is most visible on images with many small layers.

### Removed features

| Feature | Status | Migration |
|---|---|---|
| devicemapper storage driver | Removed | Migrate to overlay2 before upgrading |
| aufs storage driver | Removed (via containerd 2.0) | Migrate to overlay2 |
| Schema 1 image pull | Removed (containerd 2.1) | Re-push images as OCI or Docker schema 2 |
| API versions < 1.44 | Rejected | Upgrade clients |

### Security fixes in 29.x

- **Plugin installation hardening**: stricter validation of plugin manifests.
- **Git URL validation in BuildKit**: prevents SSRF via malicious Git URLs in build contexts.
- **Untrusted frontend protection**: BuildKit validates frontend images before execution.

## Migration from Docker Engine 28.x

### Pre-migration checklist

1. **Check the storage driver**: `docker info | grep "Storage Driver"`. If devicemapper or aufs, migrate to overlay2 first.
2. **Check API clients**: verify all tools support API 1.44+ (`docker version` on all clients).
3. **Check Schema 1 images**: `docker inspect <image> | grep SchemaVersion`; re-push Schema 1 images.
4. **Back up**: `/var/lib/docker/`, `/etc/docker/daemon.json`, volume data.

### Migration steps

```bash
# 1. Stop containers (or use live-restore)
docker compose down  # for each project

# 2. Back up
cp -r /etc/docker/daemon.json /etc/docker/daemon.json.bak
tar czf /backup/docker-data.tar.gz /var/lib/docker/

# 3. Update packages
apt-get update
apt-get install docker-ce=5:29.3.1-1~ubuntu.24.04~noble \
  docker-ce-cli=5:29.3.1-1~ubuntu.24.04~noble \
  containerd.io

# 4. Verify
docker version
docker info
docker ps -a

# 5. Opt into the containerd image store (optional for upgrades)
# Add to /etc/docker/daemon.json: "features": {"containerd-snapshotter": true}
# Then: systemctl restart docker
# Then re-pull images: docker pull <image>
```

### Post-migration validation

```bash
docker info | grep containerd
docker ps --format '{{.Names}}: {{.Status}}'
journalctl -u docker.service --since "10 min ago" | grep -i warn
docker exec <container> wget -qO- http://other-container:port/health
```

## Version boundaries in 29.x

Features not available in Docker Engine 29.x:

- nftables is stable-experimental but not the default networking backend (iptables remains default).
- No built-in Kubernetes integration (use Docker Desktop or a separate Kubernetes deployment).

Features introduced in Docker Engine 29.x:

- containerd image store as default (new installs).
- nftables stabilised (experimental flag).
- API minimum 1.44.
- HTTP keep-alive for registries (29.3.1).
- containerd 2.2.2 bundled.

## Common v29 pitfalls

1. **Upgrading without checking API clients**: CI/CD pipelines or monitoring tools using API < 1.44 break immediately.
2. **Expecting automatic image migration**: switching to the containerd image store requires re-pulling images; they are not migrated from the legacy store.
3. **devicemapper/aufs users**: these drivers are completely removed, not just deprecated; upgrading without migrating to overlay2 first fails to start the daemon.
4. **Schema 1 images**: very old images (pre-2017) in Schema 1 format cannot be pulled; re-push them in OCI or Docker schema 2 format.
5. **Mixing containerd configs**: Docker's containerd instance uses `/etc/docker/containerd/` config, not `/etc/containerd/config.toml`; do not conflate the two if running standalone containerd alongside Docker.
