# Docker Engine architecture

## Daemon architecture

### dockerd process model

```
dockerd (Docker Daemon)
  |-- API Server (REST over Unix socket / TCP)
  |     |-- /var/run/docker.sock (default)
  |     |-- tcp://0.0.0.0:2376 (TLS, remote access)
  |
  |-- Image Service
  |     |-- BuildKit (build engine)
  |     |-- Content Store (containerd-managed in v29+)
  |     |-- Distribution (pull/push to registries)
  |
  |-- Container Service
  |     |-- Lifecycle management (create, start, stop, remove)
  |     |-- Exec management
  |     |-- Logging drivers (json-file, journald, syslog, fluentd, gelf, etc.)
  |
  |-- Network Controller
  |     |-- Bridge driver (libnetwork)
  |     |-- Overlay driver (VXLAN)
  |     |-- Macvlan / IPvlan drivers
  |     |-- Embedded DNS server (127.0.0.11)
  |
  |-- Volume Manager
  |     |-- Local driver
  |     |-- Plugin drivers (NFS, GlusterFS, etc.)
  |
  +-- containerd client (gRPC)
        |
        containerd
          |-- Content store (content-addressable blobs)
          |-- Metadata store (BoltDB)
          |-- Snapshotter (overlayfs default)
          |-- Runtime service
                |
                containerd-shim-runc-v2
                  |
                  runc --> Linux kernel
```

### Daemon configuration

```json
// /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-address-pools": [
    { "base": "172.80.0.0/16", "size": 24 }
  ],
  "dns": ["8.8.8.8"],
  "live-restore": true,
  "userland-proxy": false,
  "features": {
    "containerd-snapshotter": true
  },
  "default-runtime": "runc",
  "runtimes": {
    "runsc": { "path": "/usr/local/bin/runsc" },
    "kata": { "path": "/usr/local/bin/kata-runtime" }
  }
}
```

### Live restore

With `"live-restore": true`, containers keep running if the daemon restarts. This is critical in production to avoid container downtime during daemon upgrades; the shim process keeps containers alive independently of the daemon.

### Contexts

Docker contexts switch between multiple Docker endpoints:

```bash
docker context create remote --docker "host=ssh://user@remote-host"
docker context use remote
docker context ls
```

Contexts store connection info in `~/.docker/contexts/`.

## BuildKit architecture

BuildKit is a concurrent, cache-efficient build engine:

```
Dockerfile --> Frontend (dockerfile.v0) --> LLB (Low-Level Build)
LLB --> Solver (DAG execution) --> Snapshotter --> Image Export
```

### LLB (Low-Level Build)

BuildKit compiles Dockerfiles into LLB, a directed acyclic graph of build operations. This enables:

- **Parallel execution**: independent instructions run concurrently.
- **Content-addressable caching**: cache keyed on instruction plus input content, not instruction order.
- **Lazy evaluation**: only builds what is needed for the requested output.

### Builder instances

```bash
docker buildx ls                              # list builders
docker buildx create --name mybuilder --use   # create and activate
docker buildx inspect --bootstrap             # ensure builder is running
```

Builder drivers:

- `docker`: uses dockerd's bundled BuildKit (single-platform only).
- `docker-container`: runs BuildKit in a container (multi-platform, remote cache).
- `kubernetes`: runs BuildKit pods in Kubernetes.
- `remote`: connects to a remote BuildKit instance.

### Supply-chain attestations

```bash
# Build with provenance attestation (SLSA) and SBOM
docker buildx build --provenance=true --sbom=true --push -t myapp:v1.0 .

# Inspect attestations
docker buildx imagetools inspect myapp:v1.0 --format '{{json .Provenance}}'
```

Provenance records the build environment, source, and steps; the SBOM records all packages in the image. Both are stored as OCI referrer artifacts. The strategy for consuming these (signature verification, admission gating) is `container-security`; the flags that produce them are here.

## Networking internals

### Bridge network architecture

```
Host Network Namespace:
  eth0 (physical) --> Internet
  docker0 (bridge, 172.17.0.0/16) --> default network
  br-abc123 (bridge, 172.20.0.0/16) --> custom network
    |
    veth-pair <--> container network namespace
    veth-pair <--> container network namespace

Per Container:
  eth0@if5 (veth pair, inside container NS)
  lo (loopback)
```

### iptables / nftables rules

Docker creates iptables rules for:

- **MASQUERADE**: NAT for outbound container traffic (POSTROUTING chain).
- **DNAT**: port publishing (`-p 8080:80`) via the DOCKER chain in the nat table.
- **FORWARD**: allow inter-container traffic on the same bridge.
- **DROP**: isolate containers on different bridges (and on the same bridge with `--icc=false`).

Docker Engine v29 experimental nftables support generates nftables rules directly, avoiding the iptables-nft translation layer.

### Embedded DNS

On custom bridge networks (not the default `docker0`), Docker runs an embedded DNS server at `127.0.0.11`:

- Resolves container names to their IPs on the same network.
- Resolves service names in Compose to the container(s) implementing that service.
- Falls through to host DNS for external resolution.
- The container `/etc/resolv.conf` points to `127.0.0.11`.

### Overlay network (Swarm)

Overlay uses VXLAN encapsulation (UDP port 4789):

- Each overlay network gets a unique VXLAN Network Identifier (VNI).
- `docker_gwbridge` connects the overlay to the host network for external access.
- Control-plane encryption (`--opt encrypted`) uses IPsec ESP for the data plane.

## Storage architecture

### containerd image store (Docker Engine v29 default)

The containerd image store replaces Docker's legacy graphdriver-based storage:

```
containerd content store:
  /var/lib/containerd/io.containerd.content.v1.content/
    blobs/sha256/     <-- compressed layers, manifests, configs

containerd snapshotter:
  /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/
    snapshots/        <-- unpacked layer filesystems
```

Benefits over the legacy storage:

- Shared store between Docker and Kubernetes (if the same containerd instance).
- Native multi-platform image support (image index handling).
- Lazy pulling with stargz/nydus snapshotters.
- Better garbage collection.

### Volume internals

Named volumes are stored at `/var/lib/docker/volumes/<name>/_data/`.

Volume mount propagation controls how mounts propagate between host and container:

- `rprivate` (default): no propagation.
- `rshared`: bidirectional propagation.
- `rslave`: host-to-container propagation only.

```bash
docker run -v mydata:/app/data:rshared myimage   # bidirectional
```

### Logging architecture

Docker supports pluggable logging drivers:

| Driver | Output | Notes |
|---|---|---|
| json-file | `/var/lib/docker/containers/<id>/<id>-json.log` | Default; supports `max-size`, `max-file` |
| journald | systemd journal | Queryable via `journalctl` |
| syslog | syslog daemon | RFC 5424 |
| fluentd | Fluentd collector | Structured logging |
| gelf | Graylog | UDP/TCP to GELF endpoint |
| awslogs | CloudWatch | AWS native |
| gcplogs | Cloud Logging | GCP native |
| local | Compressed binary format | More efficient than json-file |

Only `json-file` and `journald` support `docker logs`. Other drivers require querying the backend directly.
