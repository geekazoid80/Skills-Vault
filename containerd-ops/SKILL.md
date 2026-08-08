---
name: containerd-ops
description: "containerd operations for Linux and Kubernetes nodes: CRI configuration for the kubelet (config.toml v3, sandbox_image, SystemdCgroup, runtime classes for runc, Kata, gVisor), snapshotters (overlayfs, stargz and nydus lazy pulling, btrfs, zfs), containerd namespaces (moby vs k8s.io vs default), the NRI plugin framework, registry mirror config via certs.d, garbage collection and leases, and the nerdctl, ctr, and crictl CLIs. WHEN: containerd, nerdctl, ctr, crictl, CRI, snapshotter, overlayfs, stargz, nydus, NRI, config.toml, SystemdCgroup, sandbox_image, containerd namespace, k8s.io namespace, registry mirror certs.d, containerd 2.x, dockershim removal, Kubernetes CRI node config. Do NOT use for: choosing a container runtime or comparing containerd vs Docker (container-runtime-selection); Docker or Podman engine operations (docker-ops, podman-ops); Kubernetes cluster operations and orchestrator-level CRI choice (container-orchestration-selection); container or Kubernetes security, image signing and supply chain (container-security); building images at scale or CI/CD pipelines (cicd-platforms-ops); metrics dashboards and alerting (prometheus-configuration, grafana-dashboards)."
license: MIT
metadata:
  version: 1.0.0
---

# containerd operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: containerd-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating containerd, the low-level container runtime that sits beneath Docker and is the standard Kubernetes CRI since dockershim was removed in Kubernetes 1.24. It covers node-level CRI configuration for the kubelet, snapshotter selection, containerd namespaces, the NRI plugin framework, registry mirrors, garbage collection, and the three CLIs (nerdctl, ctr, crictl). containerd is a daemon with a content store, a metadata store, snapshotters, and a shim-per-container runtime layer; it deliberately has no build tooling of its own, which is where external BuildKit comes in. This skill assumes the runtime choice is already made; for that decision see `container-runtime-selection`.

## When to use

- Configuring containerd as the Kubernetes CRI on a node: `config.toml` v3, `sandbox_image`, `SystemdCgroup`, and per-runtime classes (runc, Kata, gVisor) selected via Kubernetes RuntimeClass.
- Choosing and configuring a snapshotter: overlayfs by default, stargz or nydus for lazy pulling of large images, btrfs or zfs on those filesystems, native on old kernels.
- Working across containerd namespaces (`moby` for Docker, `k8s.io` for the kubelet, `default` for ctr), and understanding why a query returns empty against the wrong namespace.
- Adding NRI plugins for CPU pinning, NUMA topology, GPU or device injection, and OCI hook injection.
- Setting up registry mirrors and insecure registries via `/etc/containerd/certs.d/`.
- Driving containerd from a CLI: nerdctl for Docker-compatible workflows, ctr for low-level debugging, crictl for CRI-level pod and container inspection on a Kubernetes node.
- Migrating a node from containerd 1.7 to 2.x: config `version = 3`, shim v1 and AUFS removal, Schema 1 image removal, cgroup v2.
- Garbage collection, leases, and the content store when disk fills up.

## When not to use

- **Choosing a container runtime, or comparing containerd against Docker or CRI-O**: use `container-runtime-selection`, the sibling umbrella that owns the selection decision. This skill assumes containerd is already chosen and operates it. Reciprocal reference.
- **Docker or Podman engine operations**: use `docker-ops` or `podman-ops`. containerd sits beneath Docker's stack (dockerd is a containerd client in the `moby` namespace), so the two skills meet at that boundary; user-facing Docker and Podman workflows live in those sibling skills.
- **Kubernetes cluster operations and orchestrator-level CRI choice**: use `container-orchestration-selection`. containerd is the standard Kubernetes CRI, and this skill owns the node-level CRI config; cluster lifecycle, scheduling, and the fleet-wide runtime decision route out.
- **Container and Kubernetes security** (runtime protection, image scanning, signing and verification, supply-chain integrity, Pod Security Standards, sandbox runtime hardening): use `container-security`. Kata and gVisor are configured here as runtime classes; their security rationale lives there.
- **Building images at scale, or deep build pipelines**: containerd has no native builder; nerdctl shells out to external BuildKit for `nerdctl build`, and CI/CD build orchestration belongs in `cicd-platforms-ops`.
- **Metrics dashboards and alerting**: containerd exposes Prometheus metrics (covered here at the endpoint level), but dashboards and alert rules belong in `prometheus-configuration` and `grafana-dashboards`.

## Classify the request first

Every request resolves to one of these; the operational depth lives in the reference, the condensed model lives below.

| Class | Examples | Where the depth lives |
|---|---|---|
| Daemon and CRI architecture | plugin model, gRPC services, content and metadata stores, shim-per-container, CRI call flow (RunPodSandbox to RemoveContainer), RuntimeClass wiring | `references/architecture.md` |
| Node CRI configuration | full `config.toml` v3, CNI wiring, registry `certs.d`, NRI block, proxy-plugin snapshotters, `containerd config dump` validation | `references/architecture.md` |
| Snapshotter internals | overlayfs mount layout, stargz eStargz TOC and on-demand fetch, nydus RAFS v6, lazy-pull trade-offs | `references/architecture.md` |
| Plugins and lifecycle | NRI plugin lifecycle and ContainerAdjustment, Sandbox API for VM runtimes, Transfer Service, garbage collection with leases | `references/architecture.md` |

## Core model (condensed)

**containerd is a low-level daemon, not a user-facing tool.** A single daemon exposes a gRPC socket at `/run/containerd/containerd.sock`. Everything is a plugin: the content store (content-addressable, immutable blobs), the metadata store (BoltDB for images, containers, leases, snapshots), snapshotters, the runtime service (a shim per container calling runc, Kata, or gVisor), and the CRI plugin the kubelet talks to. It has no image builder of its own by design.

**The CRI plugin is how Kubernetes runs containers.** Since dockershim was removed in Kubernetes 1.24, the kubelet talks to containerd's built-in CRI plugin over gRPC. Two settings break nodes when wrong: the config must declare `version = 3` on containerd 2.x (an old header silently falls back to defaults), and `SystemdCgroup = true` is required on cgroup v2 systems with systemd, or container creation fails.

**containerd namespaces are not Linux namespaces.** They isolate resources between clients sharing one daemon: `moby` holds Docker's containers and images, `k8s.io` holds the kubelet's, `default` is for ctr. Querying the wrong namespace returns empty results and misleads. Content in the store is shared across all namespaces; leases keep it from being garbage collected while referenced.

**Snapshotters manage the layered filesystem.** overlayfs is the default and general-purpose choice; native uses copy-based bind mounts for old kernels without OverlayFS; btrfs and zfs use the respective filesystem features. stargz and nydus enable lazy pulling: the container starts on a table of contents and fetches file content on demand, so a multi-GB image starts in seconds at the cost of first-access latency and a hard dependency on the registry staying reachable.

**Use the right CLI for the job.** nerdctl is the Docker-compatible, user-facing CLI (compose, build via BuildKit, rootless). ctr is the low-level, unstable debug CLI shipped with containerd, not meant for scripting. crictl is the CRI-level tool for inspecting pods and containers on a Kubernetes node, talking straight to the CRI endpoint.

**Anti-patterns:** an old `config.toml` header on containerd 2.x (silent fallback to defaults); missing `SystemdCgroup = true` on a systemd cgroup v2 host; querying the wrong containerd namespace and concluding nothing is running; treating ctr as a stable scripting interface; putting registry mirror config inline in `config.toml` on 2.x instead of `certs.d`; expecting Schema 1 images to pull on 2.1+; enabling stargz or nydus without accepting the registry-availability trade-off.

## CRI configuration for the kubelet

The kubelet reaches containerd over the CRI gRPC socket. The CRI plugin block in `/etc/containerd/config.toml` sets the pause image, the default snapshotter and runtime, and the per-runtime handlers Kubernetes selects with RuntimeClass:

```toml
# /etc/containerd/config.toml (containerd 2.x)
version = 3

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.10"

  [plugins."io.containerd.grpc.v1.cri".containerd]
    snapshotter = "overlayfs"
    default_runtime_name = "runc"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        SystemdCgroup = true    # required on cgroup v2 + systemd hosts

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
      runtime_type = "io.containerd.kata.v2"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.gvisor]
      runtime_type = "io.containerd.runsc.v1"

  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
```

A Kubernetes RuntimeClass whose `handler` matches a runtime name here lets a Pod pick Kata or gVisor per workload:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata
handler: kata    # matches runtimes.kata in config.toml
```

After any edit, validate with `containerd config dump` (effective config) and restart the daemon. The full annotated `config.toml` (global settings, CNI, NRI, metrics, proxy plugins) and the RunPodSandbox-to-RemoveContainer CRI call flow live in `references/architecture.md`.

## Registry mirrors and insecure registries

On containerd 2.x, registry configuration lives in `certs.d`, not inline in `config.toml`. One directory per registry host, each with a `hosts.toml`:

```
/etc/containerd/certs.d/
  docker.io/hosts.toml:
    server = "https://registry-1.docker.io"
    [host."https://mirror.internal.example.com"]
      capabilities = ["pull", "resolve"]
  registry.internal:5000/hosts.toml:
    server = "http://registry.internal:5000"
    [host."http://registry.internal:5000"]
      capabilities = ["pull", "push", "resolve"]
      skip_verify = true    # insecure registry, lab only
```

## Snapshotters

overlayfs is the default. Reach for a different snapshotter only for a concrete reason:

| Snapshotter | Mechanism | Use case | Lazy pull |
|---|---|---|---|
| overlayfs | Kernel OverlayFS | Default, general purpose | No |
| native | Copy-based bind mounts | Old kernels without OverlayFS | No |
| btrfs | Btrfs subvolumes | Btrfs root filesystem | No |
| zfs | ZFS datasets | ZFS root filesystem | No |
| stargz | eStargz, on-demand fetch | Large images, faster start | Yes |
| nydus | RAFS v6, block dedup | Large images, better compression | Yes |

Lazy pulling (stargz, nydus) mounts a remote image on its table of contents and downloads file content on first access, so start time no longer scales with image size. The trade-off is first-access latency and a runtime dependency on the registry remaining reachable. stargz and nydus are wired as proxy-plugin snapshotters; the mount layout and eStargz TOC internals are in `references/architecture.md`.

```bash
# Run against the stargz snapshotter
nerdctl run --snapshotter stargz -d nginx:latest
```

## containerd namespaces

Namespaces partition one daemon between clients. Always name the namespace explicitly with ctr; the default is `default`, which is rarely where the containers you want to see live:

```bash
ctr --namespace moby   containers ls   # Docker's containers
ctr --namespace k8s.io containers ls   # kubelet's containers
ctr --namespace k8s.io images ls       # kubelet's images

# Sweep every namespace
for ns in $(ctr namespaces ls -q); do
  echo "=== $ns ==="
  ctr -n "$ns" containers ls
done
```

An empty result is almost always the wrong namespace, not an empty node.

## NRI plugins

NRI (Node Resource Interface) lets domain-specific plugins react to container lifecycle events and return adjustments to the OCI spec: CPU affinity and pinning, NUMA-aware memory, GPU and device injection, OCI hook injection, and resource rebalancing. It is enabled by default from containerd 2.0.

```toml
[plugins."io.containerd.nri.v1.nri"]
  disable = false
  socket_path = "/var/run/nri/nri.sock"
  plugin_path = "/opt/nri/plugins"
```

The plugin lifecycle (Synchronize, the per-event callbacks, ContainerAdjustment) and worked topology and device-injection examples are in `references/architecture.md`.

## nerdctl vs ctr vs crictl

| CLI | Layer | Use it for | Avoid it for |
|---|---|---|---|
| nerdctl | High, Docker-compatible | Dev and CI, compose, build (via BuildKit), rootless, edge (K3s) | Nothing; it is the user-facing default |
| ctr | Low, containerd-native | Debugging daemon internals: content store, leases, plugins, namespaces | Scripting; the surface is unstable by design |
| crictl | CRI endpoint | Inspecting pods and containers on a Kubernetes node | General container work; it is CRI-scoped |

```bash
# nerdctl: Docker-compatible
nerdctl run -d --name web nginx:latest
nerdctl --namespace k8s.io ps        # view kubelet containers
nerdctl compose up -d

# ctr: low-level debug
ctr plugins ls
ctr -n k8s.io images ls
ctr leases ls

# crictl: CRI-level, Kubernetes node
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
crictl pods
crictl ps
crictl logs <container-id>
```

## External BuildKit

containerd has no built-in image builder. `nerdctl build` shells out to BuildKit (`buildkitd`), which must be installed and running separately. Keep build orchestration and CI pipelines in `cicd-platforms-ops`; this skill covers only that the build path is external and that BuildKit, not containerd, does the building.

## Garbage collection and the content store

The content store is content-addressable and shared across namespaces; leases keep referenced content alive. When disk fills, GC removes unreferenced blobs and unused snapshotter data:

```bash
ctr leases ls        # what is holding content
ctr content gc       # collect unreferenced content
```

Content lives under `/var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/`. Never hand-delete blobs; drop the lease and let GC reclaim them.

## Cross-references

- `container-runtime-selection`: the vendor-neutral selection umbrella that decides containerd vs Docker vs CRI-O; this skill operates containerd once chosen. Reciprocal reference.
- `docker-ops`, `podman-ops`: sibling engine skills. containerd sits beneath Docker's stack (dockerd is a containerd client in the `moby` namespace); user-facing Docker and Podman workflows live there.
- `container-orchestration-selection`: the orchestrator umbrella and fleet-wide CRI decision; this skill owns node-level CRI config, cluster lifecycle routes there.
- `container-security`: runtime protection, image scanning and signing, supply-chain integrity, and the security rationale for Kata and gVisor sandbox runtimes configured here as runtime classes.
- `cicd-platforms-ops`: the external BuildKit build path and CI/CD pipelines; containerd has no native builder.
- `prometheus-configuration`, `grafana-dashboards`: scraping and visualising the containerd Prometheus metrics endpoint exposed on the node.
- `utc-timestamps`: node clock skew corrupts container event and CRI audit correlation; keep NTP-synchronised UTC.

## Red flags

- About to deploy a containerd 2.x node with an old `config.toml` header instead of `version = 3`: it silently falls back to defaults.
- About to run on a systemd cgroup v2 host without `SystemdCgroup = true`: container creation fails.
- About to conclude a node is idle from an empty `ctr containers ls` run against the `default` namespace instead of `k8s.io` or `moby`.
- About to script against ctr as if it were a stable interface: it is a debug tool, use nerdctl or the API.
- About to configure a registry mirror inline in `config.toml` on 2.x instead of `certs.d`.
- About to enable stargz or nydus lazy pulling without accepting the first-access latency and the hard registry-availability dependency.
- About to expect a very old Schema 1 image to pull on containerd 2.1+: re-push it in OCI or Docker schema 2.
- About to hand-delete content-store blobs instead of dropping the lease and running GC.

## Bottom line

containerd is a low-level, plugin-based daemon with a content store, a metadata store, snapshotters, and a shim per container; it is the standard Kubernetes CRI and has no builder of its own. On a node, get `version = 3` and `SystemdCgroup = true` right or the node fails, keep registry mirrors in `certs.d`, and always name the containerd namespace so you are not fooled by empty results. Pick overlayfs unless a filesystem or a lazy-pull need says otherwise, and pick the CLI by layer: nerdctl for people, ctr for debugging, crictl for the CRI. Bring the runtime choice from `container-runtime-selection`, send builds to external BuildKit, and route security, orchestration, and dashboards to the siblings that own them.
