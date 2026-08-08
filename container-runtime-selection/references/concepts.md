# Container runtime concepts

The fundamentals a runtime-selection decision rests on: the OCI specifications, Linux namespaces, cgroups, union filesystems, the image format, registries, and container networking basics. These are engine-agnostic; every runtime implements the same standards, which is why images and runtimes stay portable.

## OCI specifications

The Open Container Initiative (OCI) defines three specifications that ensure portability across container runtimes.

### Runtime specification (runtime-spec)

Defines how to run a container from an unpacked filesystem bundle:

- **config.json**: process to run, environment variables, working directory, user and group, capabilities, rlimits.
- **Linux namespaces**: which namespaces to create (pid, net, mnt, uts, ipc, user, cgroup).
- **Mounts**: filesystem mount points (bind, tmpfs, proc, sysfs, devpts).
- **Cgroups**: resource limits (CPU, memory, I/O, PIDs).
- **Seccomp**: syscall filtering profile.
- **Hooks**: prestart, createRuntime, createContainer, startContainer, poststart, poststop.

### Image specification (image-spec)

Defines the container image format:

- **Image manifest**: references the config and layer descriptors.
- **Image index** (fat manifest): references multiple manifests for multi-platform images (linux/amd64, linux/arm64).
- **Image config**: default runtime parameters (Env, Cmd, Entrypoint, ExposedPorts, Volumes, Labels).
- **Layers**: an ordered set of filesystem changesets (tarballs), each with a content-addressable digest (sha256).
- **Media types**: `application/vnd.oci.image.manifest.v1+json`, `application/vnd.oci.image.layer.v1.tar+gzip`.

### Distribution specification (distribution-spec)

Defines how registries store and distribute images:

- **Pull**: `GET /v2/<name>/manifests/<reference>` and `GET /v2/<name>/blobs/<digest>`.
- **Push**: `POST /v2/<name>/blobs/uploads/`, then `PUT` with content, then `PUT /v2/<name>/manifests/<reference>`.
- **Tags listing**: `GET /v2/<name>/tags/list`.
- **Content negotiation**: the client specifies accepted media types to select OCI versus Docker manifest formats.
- **Referrers API**: links artifacts (signatures, SBOMs, attestations) to an image via the `subject` field.

## Linux namespaces

Namespaces provide process-level isolation. Each container typically gets its own set.

| Namespace | Flag | Isolates |
|---|---|---|
| PID | `CLONE_NEWPID` | Process IDs; PID 1 inside the container is not PID 1 on the host |
| Network | `CLONE_NEWNET` | Network interfaces, routing tables, iptables rules, sockets |
| Mount | `CLONE_NEWNS` | Filesystem mount points; the container sees its own root filesystem |
| UTS | `CLONE_NEWUTS` | Hostname and NIS domain name |
| IPC | `CLONE_NEWIPC` | System V IPC, POSIX message queues, shared memory |
| User | `CLONE_NEWUSER` | UID/GID mapping; root (0) inside maps to an unprivileged UID outside |
| Cgroup | `CLONE_NEWCGROUP` | Cgroup root view; the container sees only its own cgroup hierarchy |
| Time | `CLONE_NEWTIME` | System clocks (CLOCK_MONOTONIC, CLOCK_BOOTTIME); kernel 5.6 and later |

**User namespaces** are the foundation of rootless containers. They let a process hold UID 0 inside the namespace while running as an unprivileged user on the host. Sub-UID and sub-GID mappings (`/etc/subuid`, `/etc/subgid`) define the range of host UIDs available for mapping.

## Control groups (cgroups)

Cgroups limit, account for, and isolate the resource usage of process groups.

### cgroup v1 versus v2

| Aspect | cgroup v1 | cgroup v2 |
|---|---|---|
| Hierarchy | Multiple hierarchies, one per controller | Single unified hierarchy |
| Controllers | CPU, memory, blkio, devices, freezer, and so on as separate trees | All controllers in one tree |
| Memory tracking | Per-cgroup only | Per-cgroup with PSI (Pressure Stall Information) |
| eBPF | Limited | Full eBPF device controller support |
| Delegation | Complex (requires multiple mount points) | Simple (single subtree delegation) |
| Default (2026) | Legacy distros | RHEL 9+, Ubuntu 22.04+, Fedora 31+, Debian 12+ |

### Key controllers

- **cpu**: CPU time allocation (`cpu.max`, `cpu.weight`); maps to `--cpus` and `--cpu-shares`.
- **memory**: memory limits (`memory.max`, `memory.high`, `memory.swap.max`); maps to `--memory`, `--memory-swap`.
- **io**: block I/O limits (`io.max`, `io.weight`); maps to `--device-read-bps`, `--device-write-bps`.
- **pids**: maximum number of processes (`pids.max`); maps to `--pids-limit`.
- **cpuset**: pin to specific CPUs or memory nodes; maps to `--cpuset-cpus`.

### Resource-limit good practice

- Always set memory limits to prevent an OOM kill of other workloads.
- Set CPU limits for multi-tenant environments; use CPU shares for priority-based scheduling.
- PID limits stop fork bombs (`--pids-limit 256` is a reasonable default).
- In Kubernetes, `requests` map to cpu.weight and memory.min (guaranteed), while `limits` map to cpu.max and memory.max (a ceiling).

## Union filesystems and layers

Container images use a layered filesystem model, where each instruction in a build creates a new layer.

### How layers work

1. **Base layer**: the root filesystem from the base image (for example `FROM debian:bookworm-slim`).
2. **Intermediate layers**: each `RUN`, `COPY`, or `ADD` instruction creates a layer of filesystem changes (added, modified, deleted files).
3. **Container layer**: a thin writable layer created when the container starts; all runtime writes go here.
4. **Content-addressable**: each layer is identified by a SHA-256 digest of its content, so identical layers are stored and transferred once.

### Union filesystem drivers

| Driver | Mechanism | Performance | Notes |
|---|---|---|---|
| OverlayFS (overlay2) | Kernel-native (3.18+), upper/lower/merged dirs | Best for most workloads | Default for Docker, Podman, containerd |
| fuse-overlayfs | FUSE-based OverlayFS | Moderate | Required for rootless on kernels below 5.11 |
| Btrfs | Btrfs subvolumes per layer | Good with Btrfs | Copy-on-write at block level |
| ZFS | ZFS datasets per layer | Good with ZFS | Enterprise features (compression, dedup) |
| VirtioFS | Hypervisor filesystem passthrough | Good | Used by Docker Desktop and podman machine |

### OverlayFS internals

```
Container view (merged):  /merged/
                           |
           +---------------+----------------+
           |                                |
    Upper (writable):  /upper/       Lower (read-only):  /lower1/:/lower2/
    - New files go here              - Image layers stacked
    - Modified files copy-up         - Immutable
    - Deleted files get whiteout     - Shared across containers
```

- **Copy-up**: when a file in a lower layer is modified, it is copied to the upper layer first. The whole file is copied, not just the changed blocks.
- **Whiteout files**: deleting a file in a lower layer creates a character device (whiteout) in the upper layer to mask it.
- **Opaque directories**: deleting a directory creates an opaque whiteout that hides all lower-layer contents.

## Image format details

### Manifest structure

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:abc123...",
    "size": 1234
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:def456...",
      "size": 50000000
    }
  ]
}
```

### Multi-platform images (image index)

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:amd64digest...",
      "platform": { "architecture": "amd64", "os": "linux" }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:arm64digest...",
      "platform": { "architecture": "arm64", "os": "linux" }
    }
  ]
}
```

The runtime selects the manifest matching the host architecture automatically.

## Container registries

Registries store and distribute OCI images, implementing the OCI distribution specification.

### Registry types

| Registry | Type | Key features |
|---|---|---|
| Docker Hub | Public/private | Default registry, rate-limited free tier, official images |
| GitHub Container Registry (ghcr.io) | Public/private | GitHub Actions integration, free for public images |
| Amazon ECR | Private | IAM auth, cross-region replication, image scanning |
| Azure ACR | Private | Entra ID auth, geo-replication, ACR Tasks for builds |
| Google Artifact Registry | Private | IAM auth, multi-format (Docker, Maven, npm) |
| Harbor | Self-hosted | CNCF graduated, vulnerability scanning, RBAC, replication |
| Quay.io | Public/private | Red Hat, Clair scanning, geo-replication |
| Zot | Self-hosted | OCI-native, minimal, single binary |

### Image references

```
[registry/][namespace/]repository[:tag][@digest]

docker.io/library/nginx:1.27-alpine           # Docker Hub official
ghcr.io/myorg/myapp:v2.0                       # GitHub Container Registry
registry.example.com/team/api:v1.0@sha256:...  # Private with digest pin
```

- **Tag**: a mutable pointer to a manifest. `:latest` is the default if omitted.
- **Digest**: an immutable, content-addressable reference. Use it in production for reproducibility.
- **Tag plus digest**: pins exact content while keeping a human-readable tag.

### Image signing and verification

Signing is a supply-chain security control; it is noted here only as part of the image lifecycle. For the signing and verification discipline, use `container-security`.

- **cosign** (Sigstore): keyless signing with OIDC identity and a transparency log (Rekor).
- **Notary v2**: OCI-native signing, attached as referrer artifacts.
- **Docker Content Trust**: legacy, uses Notary v1, superseded by cosign.

## Container networking fundamentals

### Network namespace mechanics

Each container gets its own network namespace with:

- Separate network interfaces, routing tables, and iptables/nftables rules.
- A virtual ethernet pair (veth): one end in the container namespace, the other on a bridge or the host.
- A loopback interface (lo) isolated from the host loopback.

### Common network models

| Model | Mechanism | Use case |
|---|---|---|
| Bridge | veth pairs connected to a Linux bridge (docker0 or custom) | Default for single-host |
| Host | Container shares the host network namespace | Performance-sensitive, no isolation |
| Macvlan | Container gets its own MAC and IP on the physical network | Direct LAN access |
| IPvlan | Container shares the host MAC, gets its own IP (L2 or L3) | Similar to macvlan, no promiscuous mode |
| Overlay (VXLAN) | Encapsulated L2 over L3 between hosts | Multi-host (Swarm, Kubernetes) |
| CNI plugins | Standardised networking for Kubernetes | Calico, Cilium, Flannel |

### DNS resolution

- Docker: an embedded DNS server at 127.0.0.11 for custom bridge networks.
- Podman: Aardvark-DNS provides DNS for Podman networks.
- Kubernetes: CoreDNS for service discovery (`<svc>.<ns>.svc.cluster.local`).
