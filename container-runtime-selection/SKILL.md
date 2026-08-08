---
name: container-runtime-selection
description: "Vendor-neutral container runtime selection, comparison, and migration reasoning: Docker vs Podman vs containerd execution models, daemon vs daemonless, rootless design, and the low-level OCI runtime layer (runc, crun, youki, gVisor, Kata) plus the cgroup and namespace fundamentals that underlie them. Owns which runtime earns a given dev, CI, or production deployment, not how to operate one. WHEN: \"container runtime\", \"Docker vs Podman\", \"which container runtime\", \"containerd vs Docker\", \"daemonless\", \"rootless containers\", \"container engine\", \"runtime comparison\", \"crun vs runc\", \"OCI runtime\", \"gVisor\", \"Kata Containers\", \"migrate Docker to Podman\", \"dockershim removal\", \"cgroup v2 container\". Do NOT use for: deep per-runtime implementation (Dockerfile, Compose, BuildKit, Quadlet, CRI config), which routes to docker-ops, podman-ops, or containerd-ops; container and Kubernetes SECURITY (image scanning, rootless hardening as a control, runtime protection, supply chain), which routes to container-security; Kubernetes orchestration and cluster-level CRI choice, which routes to container-orchestration-selection; observability of running containers, which routes to prometheus-configuration and grafana-dashboards."
license: MIT
metadata:
  version: 1.0.0
---

# Container runtime selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: container-runtime-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for choosing a container runtime. It owns the reasoning that survives any one product: which execution model fits (daemon versus daemonless), whether rootless is a requirement, which engine earns a dev, CI, or production deployment, which low-level OCI runtime the engine should call, and how to migrate between engines without breaking images. Engine-specific configuration and operations (Dockerfile optimisation, Compose, BuildKit, Quadlet, CRI settings) live in the per-vendor sibling skills; the depth here is the selection and migration logic that outlasts a runtime change.

## When to use

- Comparing runtimes (Docker versus Podman versus containerd) for a new project or an existing estate.
- Selecting a runtime given a deployment target (dev workstation, CI pipeline, production server), an OS (RHEL, Ubuntu, macOS, Windows), and a security posture.
- Deciding whether daemonless or rootless operation is a hard requirement, and what it costs.
- Choosing the low-level OCI runtime (runc, crun, youki, gVisor, Kata) beneath the engine.
- Planning a migration: Docker to Podman on a server estate, or Docker to containerd for Kubernetes nodes after dockershim removal.
- Understanding how OCI standards keep images and runtimes portable across engines.

## When not to use

- **Deep per-runtime implementation and operations**: the exact Dockerfile, Compose file, BuildKit flag, Podman Quadlet unit, rootless setup, `podman machine`, containerd CRI config, snapshotter, or NRI plugin. Use the sibling vendor skills `docker-ops`, `podman-ops`, or `containerd-ops`. This umbrella decides which engine fits; those build and run it.
- **Container and Kubernetes security**: image scanning and CI gate policy, rootless and capability hardening as a security control, admission control, runtime protection, seccomp/AppArmor profiles, supply-chain integrity (SLSA, cosign, SBOM). Use `container-security`. Sandbox runtimes (gVisor, Kata) are named here as a selection option; their use as an isolation control is that skill's ground.
- **Kubernetes orchestration and cluster-level CRI choice**: how the cluster schedules, and which CRI implementation (containerd versus CRI-O) a node runs at the orchestration layer. Use `container-orchestration-selection` (sibling umbrella). This skill compares the runtimes themselves; that one places them under an orchestrator.
- **Observability of running containers**: metrics, dashboards, and alerting on container and host resource use. Use `prometheus-configuration` and `grafana-dashboards`.

## Classify the request first

Every request resolves to one of these, which determines whether the concept reference is needed:

| Class | Examples | Where the depth lives |
|---|---|---|
| Runtime comparison and selection | Docker vs Podman vs containerd, daemon vs daemonless, rootless requirement, which engine for dev/CI/production, license and OS constraints | this SKILL.md, "Core model" below |
| OCI runtime layer | runc vs crun vs youki, gVisor and Kata for isolation, which runtime the engine calls | this SKILL.md, "OCI runtime selection" below |
| Migration | Docker to Podman, Docker to containerd after dockershim removal, cross-engine image portability | this SKILL.md, "Migration patterns" below |
| Fundamentals: how containers work | OCI spec, Linux namespaces, cgroups v1 vs v2, union filesystems, image format, registries, container networking basics | `references/concepts.md` |

## Core model (condensed)

**A container is a host process, not a virtual machine.** It is isolated by Linux namespaces and constrained by cgroups, sharing the host kernel rather than sitting behind hardware isolation. That fact underlies the whole runtime landscape: the engine and its OCI runtime are the machinery that sets up those namespaces, cgroups, and mounts around a process.

**Docker, Podman, and containerd are not equivalent layers.** They differ most in the execution model:

```
Docker:      CLI -> dockerd (daemon) -> containerd -> shim -> runc
Podman:      CLI -> conmon -> crun/runc (no daemon)
containerd:  client (kubelet/nerdctl) -> containerd -> shim -> runc
```

- **Docker Engine** is a client-server design with a long-running daemon (`dockerd`) that itself delegates to containerd. Its strengths are the largest ecosystem, BuildKit for builds, Compose, Docker Desktop, and the deepest documentation. Its weaknesses are that the daemon is a single point of failure and runs as root by default, and Docker Desktop is a paid subscription for large organisations. Best for development workflows, CI/CD pipelines, and teams already invested in Docker tooling.
- **Podman** is daemonless: each invocation forks and execs the container process directly, supervised by `conmon`. It is rootless by design, integrates natively with systemd (Quadlet), can generate Kubernetes YAML, and has no daemon single point of failure, under an Apache 2.0 license. Its weaknesses are a smaller ecosystem, some Compose compatibility gaps, and a required Linux VM (`podman machine`) on macOS and Windows. Best for RHEL and Fedora production servers, security-sensitive environments, and systemd-managed services.
- **containerd** is a minimal daemon focused on container execution and image management, with no build tooling of its own. It is CNCF graduated, the native Kubernetes CRI backend, lightweight, and extensible through its snapshotter and NRI plugin systems. Its weaknesses are no built-in build capability (BuildKit is separate), a low-level CLI (`ctr`), and a need for nerdctl for a Docker-compatible experience. Best for Kubernetes nodes, a minimal runtime footprint, and custom container platforms.

**Decision matrix.**

| Requirement | Docker | Podman | containerd |
|---|---|---|---|
| Development workflow | Best | Good | Fair (nerdctl) |
| CI/CD builds | Best (BuildKit) | Good | Fair (external BuildKit) |
| Kubernetes CRI backend | Not directly (uses containerd) | Not directly (use CRI-O) | Best |
| Rootless production | Supported | Best | Supported |
| systemd integration | Restart policies | Best (Quadlet) | Unit files |
| RHEL/Fedora default | Available | Default | Available |
| macOS/Windows dev | Docker Desktop | podman machine | nerdctl + Lima |
| Image building | BuildKit (built-in) | Buildah (integrated) | External BuildKit |
| Multi-arch builds | `docker buildx` | `podman build --platform` | BuildKit |
| License | Engine Apache 2.0, Desktop paid for large orgs | Apache 2.0 | Apache 2.0 |
| Pod support | No (Compose only) | Yes (Kubernetes-compatible) | Via CRI |

**Gather the deciding context before recommending.** The right answer turns on the deployment target (dev, CI, production), the OS (RHEL/Fedora favours Podman as the default; Ubuntu carries all three; macOS and Windows need a Linux VM whichever way), whether Kubernetes is in the picture (the node runs containerd or CRI-O, not Docker), the security posture (rootless and daemonless raise the floor), team expertise, and the Docker Desktop license threshold for the organisation.

**Anti-patterns:** treating "Docker" as a synonym for "containers" when OCI standards make images and runtimes portable across every engine; ignoring cgroup v2, now the default on modern distros; assuming rootless has the same reach as rootful (it cannot bind ports below 1024, use macvlan/ipvlan, or reach host devices without extra configuration); overlooking the Docker Desktop license for organisations above the free-tier threshold; and mixing CRI implementations (containerd and CRI-O) on the same Kubernetes node.

## OCI runtime selection

The OCI runtime is the low-level component that actually creates the container from an unpacked filesystem bundle. All three engines can swap it, so the engine choice and the OCI-runtime choice are separable decisions.

| Runtime | Language | Strengths | Use case |
|---|---|---|---|
| runc | Go | OCI reference implementation, widest compatibility | Default for Docker and containerd |
| crun | C | Faster startup, lower memory footprint | Default for Podman, performance-critical paths |
| youki | Rust | Memory safety, growing ecosystem | Experimental alternative |
| gVisor (runsc) | Go | Application-kernel sandbox, syscall interception | Multi-tenant and untrusted workloads |
| Kata Containers | Go | VM-isolated containers, hardware-level isolation | Strict isolation requirements |

**How to reason about it.** Default to runc for the broadest compatibility, or crun where startup latency and memory density matter (it is Podman's default). Reach for gVisor or Kata only when the workload trust boundary demands stronger isolation than shared-kernel namespaces provide; both trade performance and some compatibility for that isolation, and both belong to a security conversation. When the driver is a security control rather than a runtime-fit choice, route the sandbox-runtime decision to `container-security`.

## Migration patterns

### Docker to Podman

- The CLI is nearly identical; `alias docker=podman` covers most commands.
- Dockerfiles build unchanged with `podman build`; Compose files run via `podman-compose` or the Podman-provided Docker socket.
- Key differences: no daemon socket, rootless by default, and Quadlet (systemd units) replaces Docker restart policies.
- Watch for: volume SELinux labels (`:z` and `:Z`), and the different networking stack (Netavark and Aardvark-DNS rather than the Docker bridge and embedded DNS).

### Docker to containerd (Kubernetes)

- Kubernetes removed dockershim in 1.24; containerd is the standard CRI backend for a node.
- Images are fully compatible, since both use the OCI image format.
- CLI migration: `docker` commands map to `nerdctl` for a Docker-like experience, or `crictl` for CRI-level debugging.
- containerd namespaces keep Docker (`moby`) and Kubernetes (`k8s.io`) workloads separate when both coexist on one host.

**Migration invariant:** OCI image portability is what makes these migrations safe. Images built by one engine run under any other, so a migration is a change of engine and workflow, not a rebuild of every image.

## Cross-references

- `docker-ops`: Docker Engine operations, Dockerfile and multi-stage builds, Compose, BuildKit, `buildx` multi-arch. This umbrella decides whether Docker fits; that skill builds and runs it.
- `podman-ops`: Podman operations, rootless setup, Quadlet and systemd integration, pods, `podman machine`, Buildah. Reciprocal sibling.
- `containerd-ops`: containerd operations, `ctr` and `nerdctl`, CRI configuration, snapshotters, NRI plugins. Reciprocal sibling.
- `container-orchestration-selection`: the Kubernetes-and-orchestration umbrella; it owns cluster-level scheduling and the containerd-versus-CRI-O choice at the node under an orchestrator. This skill compares the runtimes; that one places them under a cluster.
- `container-security`: image scanning and CI gates, admission control, rootless and capability hardening as a control, runtime protection, sandbox runtimes as an isolation boundary, supply-chain integrity. This skill selects a runtime; that one secures it.
- `prometheus-configuration`, `grafana-dashboards`: metrics and dashboards for running containers and their host resource use.
- `terraform-iac-ops`: provisioning the hosts and managed container platforms a chosen runtime runs on.
- `utc-timestamps`: container and image event correlation depends on UTC, NTP-synchronised clocks; skewed time corrupts the timeline across a fleet.

## Red flags

- About to treat Docker as the only way to run containers when the target is a Kubernetes node, where the runtime is containerd or CRI-O and Docker is not in the data path.
- About to recommend Docker Desktop for a large organisation without accounting for the paid-subscription threshold.
- About to assume rootless containers have rootful reach (binding low ports, macvlan/ipvlan, host devices) without the extra configuration those need.
- About to plan a migration as an image rebuild when OCI portability means the images already move unchanged.
- About to mix containerd and CRI-O on the same Kubernetes node.
- About to ignore cgroup v2 on a modern distro, or a rootless requirement on a kernel too old for native OverlayFS (which then needs fuse-overlayfs).
- About to reach for gVisor or Kata for a workload whose trust boundary does not need VM-grade or sandboxed isolation, paying the performance cost for nothing, or the reverse: leaving an untrusted multi-tenant workload on shared-kernel namespaces.
- About to pick an engine from familiarity before the deployment target, OS, Kubernetes involvement, and security posture are known.

## Bottom line

Choose the runtime from the execution model the deployment needs, not from habit. Docker earns dev workstations and CI where its ecosystem and BuildKit pay off; Podman earns RHEL/Fedora and security-sensitive servers with its daemonless, rootless, systemd-native design; containerd earns Kubernetes nodes and minimal-footprint platforms. Treat the low-level OCI runtime as a separate, swappable decision, and reach for gVisor or Kata only when the trust boundary demands it. Lean on OCI portability so migrations move workflows, not images. When the question turns to operating a specific engine, securing the workload, orchestrating a cluster, or watching it run, hand off to the sibling skill that owns it.
