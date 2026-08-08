# Podman architecture and internals

Daemonless execution, conmon and crun, Netavark and Aardvark-DNS, storage, the configuration files, podman machine internals, and the REST API. Read this for "how does X work" questions.

## Daemonless execution model

```
User runs: podman run myimage
  |
  podman (CLI process)
  |-- resolves image (containers/image library)
  |-- builds the OCI runtime spec
  |-- starts conmon
  |     |
  |     conmon (container monitor)
  |     |-- forks crun/runc
  |     |     |
  |     |     crun --> sets up namespaces, cgroups, seccomp --> exec container process
  |     |
  |     |-- monitors container stdout/stderr
  |     |-- captures the exit code
  |     |-- stays alive for the container's lifetime
  |
  podman CLI exits (the container keeps running under conmon)
```

Key insight: after `podman run -d`, the `podman` CLI process exits and the container runs under `conmon`, a small C monitor. This is fundamentally unlike Docker, where the container runs under the long-lived daemon. No daemon means no single point of failure and no root-owned control socket to defend.

### conmon (container monitor)

conmon is a minimal C program (around 1 MB) that:

- forks the OCI runtime (crun/runc) to create the container;
- holds the container's terminal pty when there is one;
- captures stdout/stderr to log files;
- monitors the container process and records exit status;
- serves `podman attach` and `podman logs` by reading those log files;
- stays alive as long as the container runs;
- lets the `podman` CLI exit without affecting the container.

### crun vs runc

| Aspect | crun | runc |
|---|---|---|
| Language | C | Go |
| Startup time | around 50ms | around 500ms |
| Memory use | around 1 MB | around 10 MB |
| cgroup v2 | first-class | supported |
| User namespace | full support | full support |
| Default in | Podman, CRI-O | Docker, containerd |
| OCI compliant | yes | yes (reference implementation) |

crun is Podman's default because of its faster container startup and lower resource use.

## Networking: Netavark and Aardvark-DNS

Netavark replaced CNI plugins in Podman 4.0. It is a Rust network stack purpose-built for Podman:

```
podman --> Netavark (network setup)
             |-- creates bridge networks (Linux bridge + veth pairs)
             |-- configures iptables/nftables rules for port mapping
             |-- manages macvlan/ipvlan networks
             |-- applies firewall rules per container
             |
             +-- Aardvark-DNS (DNS resolution)
                  |-- per-network DNS server
                  |-- resolves container names to IPs
                  |-- supports aliases and network-scoped DNS
```

Network creation:

```bash
podman network create mynet                              # default bridge
podman network create --subnet 172.20.0.0/16 --gateway 172.20.0.1 mynet
podman network create -d macvlan --subnet 192.168.1.0/24 \
  --gateway 192.168.1.1 -o parent=eth0 macvlan-net       # rootful only
```

### Rootless networking

Rootless mode cannot modify host iptables or create veth pairs directly, so it uses pasta (or legacy slirp4netns):

```
Rootless: podman --> pasta --> container network namespace
                      |
                  translates between host and container
                  using unprivileged network-namespace operations
```

- **pasta** (Podman 5.x+ default): uses Linux network namespaces for better performance than slirp4netns; supports TCP, UDP, and ICMP passthrough.
- **slirp4netns** (legacy): userspace TCP/IP stack; higher latency but works on older kernels.

## Storage architecture

Podman uses the `containers/storage` library for layered image and container storage:

```
Storage root:
  Rootful:  /var/lib/containers/storage/
  Rootless: ~/.local/share/containers/storage/

Directory structure:
  overlay-images/       image metadata (manifests, configs)
  overlay-layers/       layer metadata
  overlay/              actual layer filesystems
    <layer-id>/
      diff/             layer content
      merged/           union mount (while the container runs)
      upper/            writable layer (container)
      work/             overlayfs work directory
  volumes/              named volumes
```

### Storage drivers

| Driver | Mechanism | Notes |
|---|---|---|
| overlay | OverlayFS (kernel) | default; needs kernel 4.0+ |
| fuse-overlayfs | FUSE OverlayFS | needed for rootless on kernel < 5.11 |
| btrfs | Btrfs subvolumes | native copy-on-write |
| zfs | ZFS datasets | enterprise features |
| vfs | simple copy | no copy-on-write, slow, works everywhere |

Configuration:

```toml
# /etc/containers/storage.conf (rootful)
# ~/.config/containers/storage.conf (rootless)

[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"   # only for rootless on old kernels
mountopt = "nodev,metacopy=on"
```

## containers.conf

Global engine configuration:

```toml
# /etc/containers/containers.conf (system)
# ~/.config/containers/containers.conf (user)

[containers]
default_capabilities = [
  "CHOWN", "DAC_OVERRIDE", "FOWNER", "FSETID",
  "KILL", "NET_BIND_SERVICE", "SETFCAP", "SETGID",
  "SETPCAP", "SETUID"
]
log_driver = "k8s-file"          # or journald
pids_limit = 2048
userns = "host"                   # or "auto" for rootless
ipcns = "private"
seccomp_profile = "/usr/share/containers/seccomp.json"

[engine]
runtime = "crun"                  # or "runc"
cgroup_manager = "systemd"        # or "cgroupfs"
events_logger = "journald"

[network]
network_backend = "netavark"      # or "cni" (legacy)
dns_bind_port = 53
```

## registries.conf

```toml
# /etc/containers/registries.conf

# search registries (used when the image name omits a registry)
unqualified-search-registries = ["docker.io", "quay.io"]

# registry mirror
[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "mirror.internal.example.com"

# insecure registry (no TLS)
[[registry]]
location = "registry.internal:5000"
insecure = true

# blocked registry
[[registry]]
location = "untrusted.registry.io"
blocked = true
```

## podman machine (macOS / Windows)

On macOS and Windows, containers need a Linux kernel, so Podman runs a lightweight Linux VM (Fedora CoreOS) and the CLI talks to it:

```
macOS/Windows:
  podman CLI --> gRPC API --> podman machine VM (Fedora CoreOS)
                                |
                                podman (inside VM) --> crun --> containers
```

### VM backends

| Platform | Backend | Notes |
|---|---|---|
| macOS (M-series) | Apple Virtualization.framework | default since 5.x, supports VirtioFS |
| macOS (Intel) | QEMU | legacy backend |
| macOS (M3+) | VZ with nested virtualisation | 5.6+, enables running VMs inside containers |
| Windows | WSL2 | Windows Subsystem for Linux 2 |

### Machine management

```bash
podman machine init --cpus 4 --memory 8192 --disk-size 100
podman machine start
podman machine stop
podman machine ssh                    # SSH into the VM
podman machine set --rootful          # enable rootful access
podman machine ls
podman machine inspect
```

Volume mounts between host and VM use VirtioFS (macOS VZ) or 9p (QEMU/WSL2); host paths are available inside the VM automatically:

```bash
podman run -v /Users/myuser/data:/data myimage
```

## Podman REST API

Podman exposes a REST API compatible with Docker's API plus Podman-native extensions:

```bash
# enable the socket (rootless)
systemctl --user enable --now podman.socket
# socket at: $XDG_RUNTIME_DIR/podman/podman.sock

# enable the socket (rootful)
systemctl enable --now podman.socket
# socket at: /run/podman/podman.sock

# query
curl --unix-socket "$XDG_RUNTIME_DIR/podman/podman.sock" \
  http://localhost/v5.0.0/libpod/containers/json
```

Two endpoint namespaces:

- `/vX.Y.Z/libpod/`: Podman-native endpoints (pods, Quadlet, and more). These carry the breaking changes in the Podman 6.0 API revision.
- `/vX.Y.Z/`: Docker-compatible endpoints (containers, images, networks). These stay stable for client compatibility.
