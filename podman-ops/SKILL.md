---
name: podman-ops
description: "Operate Podman, the daemonless, rootless-by-default container engine, across versions 5.x to 6.0: rootless setup with subuid/subgid and user namespaces, Quadlet systemd integration (.container/.pod/.network/.volume units), Kubernetes-compatible pods and YAML generation, podman machine on macOS and Windows, Buildah image builds, Netavark and Aardvark-DNS networking, pasta rootless networking, crun runtime, and SELinux :z/:Z volume labels. WHEN: \"Podman\", \"podman run\", \"rootless\", \"daemonless\", \"Quadlet\", \".container file\", \"podman machine\", \"podman generate kube\", \"podman kube play\", \"pod create\", \"Netavark\", \"Aardvark-DNS\", \"pasta\", \"slirp4netns\", \"conmon\", \"crun\", \"Buildah\", \"subuid\", \"subgid\", \"podman-compose\", \"podman.socket\". Do NOT use for: choosing a runtime, the Podman-vs-Docker comparison, or Docker-to-Podman migration strategy (container-runtime-selection); Docker or containerd operations (docker-ops, containerd-ops); container and Kubernetes security strategy (container-security); Kubernetes orchestration and CRI-O (container-orchestration-selection); in-cluster or service certificates (cert-manager); secret handling (secrets-hygiene, hashicorp-vault-ops); ingress and reverse proxy (nginx-load-balancing, load-balancer-selection); CI/CD (cicd-platforms-ops, gh-actions-ci); observability (prometheus-configuration, grafana-dashboards)."
license: MIT
metadata:
  version: 1.0.0
---

# Podman operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: podman-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating Podman: the daemonless, rootless-by-default container engine. It assumes the runtime choice is already made (Podman is what you are running); the depth here is how to set up and run it well. That means rootless user-namespace configuration, Quadlet as the production pattern for containers-as-systemd-units, Kubernetes-compatible pods and YAML round-tripping, podman machine on macOS and Windows, Buildah image builds, and the Netavark networking stack. It is scoped to Podman operations, not to comparing runtimes, securing a cluster, or hosting an application's ingress.

## When to use

- Standing up rootless Podman: subuid/subgid ranges, kernel and cgroup v2 prerequisites, lingering, and rootless networking (pasta, slirp4netns).
- Authoring Quadlet units (`.container`, `.pod`, `.network`, `.volume`) and driving them through `systemctl --user` with health checks and auto-update.
- Building and running Kubernetes-compatible pods, and round-tripping with `podman generate kube` / `podman kube play`.
- Running Podman on macOS or Windows through `podman machine` (VM backends, resource sizing, volume mounts).
- Building images with Buildah / `podman build`, and inspecting or copying them with Skopeo.
- Configuring Netavark and Aardvark-DNS networks, bridge and macvlan drivers, and DNS between containers.
- Fixing SELinux volume-label permission errors with `:z` / `:Z`, and rootless bind-mount ownership with `--userns=keep-id`.
- Enabling the Docker-compatible socket so `podman-compose` or Docker Compose can drive Podman day to day.

## When not to use

- **Choosing a runtime, the Podman-vs-Docker comparison, or a Docker-to-Podman migration strategy**: use `container-runtime-selection`. That umbrella owns the selection reasoning and the phased migration plan; this skill covers running Podman once chosen.
- **Docker or containerd operations**: use `docker-ops` or `containerd-ops`. Podman's daemonless model changes how containers are managed, so the operations do not transfer one-for-one.
- **Container and Kubernetes security strategy** (image scanning gates, admission control, Pod Security Standards, supply-chain integrity): use `container-security`. This skill covers Podman's own rootless and user-namespace knobs; the security strategy lives there.
- **Kubernetes orchestration and CRI-O** (cluster lifecycle, scheduling, the in-cluster runtime): use `container-orchestration-selection`. Podman generates and consumes Kubernetes YAML, but it is not a cluster orchestrator.
- **In-cluster or service certificates**: use `cert-manager`. **Secret handling**: use `secrets-hygiene` for the discipline and `hashicorp-vault-ops` for the store.
- **Ingress or reverse proxy** in front of a Podman workload: use `nginx-load-balancing` or `load-balancer-selection`.
- **CI/CD pipelines** that build or push images: use `cicd-platforms-ops` or `gh-actions-ci`. **Observability**: use `prometheus-configuration` or `grafana-dashboards`.
- **The RHEL host layer** (subscription-manager, dnf modules, distro packaging of Podman) is out of scope; keep the Podman operations here and treat the OS-integration layer as a separate concern.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture and internals | daemonless fork/exec, conmon, crun vs runc, Netavark and Aardvark-DNS, storage drivers and layout, `containers.conf` / `storage.conf` / `registries.conf`, podman machine internals, the REST API | `references/architecture.md` |
| Setup and operations | rootless prerequisites and troubleshooting, Quadlet unit patterns, pods and Kubernetes YAML, Buildah builds, systemd integration, hardening, Docker-socket compatibility | `references/best-practices.md` |

## Core model (condensed)

**Daemonless, fork/exec.** Each `podman` invocation directly forks and execs; there is no central daemon. The chain is `podman CLI -> conmon -> crun -> kernel`. After `podman run -d` the CLI exits and the container keeps running under `conmon` (a small C monitor that holds the pty, captures stdout/stderr and the exit code, and serves `podman logs`/`attach`). Consequences that shape everything else: no single daemon whose crash takes down every container; no root-owned `/var/run/docker.sock` to defend; containers are child processes owned by the user or by systemd, which is why systemd (via Quadlet) is the native lifecycle manager.

**Rootless by design.** Podman runs entirely inside a user's namespace with no root anywhere in the stack. Container UID 0 maps to an unprivileged host UID from the user's `/etc/subuid` range (for example container 0 to host 100000). Rootless and rootful keep separate image and container stores (`~/.local/share/containers/storage/` vs `/var/lib/containers/storage/`), so `sudo podman images` and `podman images` show different sets. `crun` is the default OCI runtime (C, far faster startup and lower memory than Go's `runc`).

**Quadlet is the production pattern.** Do not hand-run `podman run` for anything long-lived. Declare `.container` / `.pod` / `.network` / `.volume` files in a watched directory; the Quadlet generator turns them into systemd `.service` units on `daemon-reload`, and systemd owns the lifecycle, restarts, health, and auto-update.

**Pods mirror Kubernetes.** Containers in a pod share a network namespace (and optionally PID) through an infra/pause container; published ports live on the pod, not the members. `podman generate kube` and `podman kube play` round-trip with Kubernetes YAML.

**Anti-patterns:** confusing rootful and rootless stores and wondering where an image went; running long-lived containers by hand instead of via Quadlet; forgetting `/etc/subuid` and `/etc/subgid` entries so rootless fails cryptically; binding a port below 1024 rootless without `net.ipv4.ip_unprivileged_port_start=0`; omitting `:z`/`:Z` on SELinux hosts and hitting permission denied; expecting `--privileged` or macvlan to behave rootless; skipping `loginctl enable-linger` so user services die at logout.

## Rootless setup (subuid / subgid and user namespaces)

Rootless is the flagship capability and the usual default. Container UIDs map to a delegated range of unprivileged host UIDs, so nothing in the stack needs root.

Prerequisites, checked in order:

```bash
# 1. User namespaces enabled (some distros ship this disabled)
sysctl user.max_user_namespaces   # want a non-zero value (mainline, RHEL, Fedora)
# Debian / Ubuntu also gate on a downstream sysctl:
cat /proc/sys/kernel/unprivileged_userns_clone   # want 1 (Debian/Ubuntu only; absent elsewhere)
# if disabled: sysctl -w user.max_user_namespaces=28633 (and, on Debian/Ubuntu,
# sysctl -w kernel.unprivileged_userns_clone=1), persisted in /etc/sysctl.d/

# 2. subuid / subgid ranges for the user
cat /etc/subuid   # username:100000:65536
cat /etc/subgid   # username:100000:65536
# if missing: usermod --add-subuids 100000-165535 --add-subgids 100000-165535 username

# 3. cgroup v2 with user delegation
cat /sys/fs/cgroup/cgroup.controllers   # want cpu memory io pids
ls  /sys/fs/cgroup/user.slice/          # should exist

# 4. Keep the user's systemd running after logout (Quadlet needs this)
loginctl enable-linger "$USER"

# 5. Confirm rootless
podman info --format '{{.Host.Security.Rootless}}'   # true
```

UID-mapping modes select how host and container users line up:

```bash
podman run --userns=keep-id myimage   # map the current user in as the same UID (bind mounts to host-owned files)
podman run --userns=auto   myimage    # auto-assign a subuid sub-range
podman run --userns=host   myimage    # no user namespace (rootful behaviour)
```

`--userns=keep-id` is the fix for the common rootless bind-mount trap: the container runs as UID 0 which maps to host 100000, so files owned by your own UID (1000) are unreadable until you either keep-id, `podman unshare chown` the tree, or switch to a named volume that Podman owns. Full prerequisite checklist, the symptom-to-fix table, and volume-permission recipes are in `references/best-practices.md`; the namespace and storage internals are in `references/architecture.md`.

## Quadlet and systemd integration

Quadlet converts declarative unit files into systemd services, giving containers first-class lifecycle, restart, health, and logging.

File locations: system (rootful) `/etc/containers/systemd/`; user (rootless) `~/.config/containers/systemd/`. A minimal `.container`:

```ini
[Unit]
Description=Web Application
After=network-online.target

[Container]
Image=registry.example.com/webapp:v3.0
ContainerName=webapp
PublishPort=8080:8080
Environment=NODE_ENV=production
Volume=webapp-data.volume:/app/data:z
Network=webapp.network
HealthCmd=curl -f http://localhost:8080/health
HealthInterval=30s
ReadOnly=true
RunInit=true
AutoUpdate=registry
UserNS=keep-id

[Service]
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
```

Lifecycle:

```bash
systemctl --user daemon-reload          # pick up new or changed Quadlet files
systemctl --user enable --now webapp    # start now and at login
systemctl --user status webapp
journalctl --user -u webapp -f          # logs go to journald by default
```

Auto-update needs `AutoUpdate=registry` on the container plus the timer: `systemctl --user enable --now podman-auto-update.timer` (daily; edit `OnCalendar` to retime). Validate generation with `systemd-analyze verify` or by running the user generator against a temp dir. Multi-container pod bundles, the `.network`/`.volume` resource files, and health-driven dependency ordering are in `references/best-practices.md`.

## Pods and Kubernetes YAML

A Podman pod mirrors a Kubernetes Pod: members share a network namespace (and optionally PID) via an infra/pause container, and published ports sit on the pod.

```bash
podman pod create --name webapp -p 8080:80          # ports on the pod
podman run -d --pod webapp --name nginx nginx:latest
podman run -d --pod webapp --name sidecar my-sidecar:latest
# nginx and sidecar reach each other over localhost, as in Kubernetes

podman generate kube webapp > pod.yaml              # export running pod to K8s YAML
podman kube play pod.yaml                            # deploy from YAML (also Deployments, Services)
podman kube down pod.yaml                            # teardown
```

This round-trip is how a single-host Podman workload becomes a starting-point manifest for a cluster. Cluster orchestration itself (scheduling, controllers, CRI-O as the in-cluster runtime) is out of scope here; route that to `container-orchestration-selection`.

## podman machine (macOS and Windows)

Containers need a Linux kernel, so on macOS and Windows Podman runs a lightweight Linux VM (Fedora CoreOS) and the CLI talks to it over gRPC.

| Platform | Backend | Notes |
|---|---|---|
| macOS (M-series) | Apple Virtualization.framework | Default since 5.x, VirtioFS mounts |
| macOS (Intel) | QEMU | Legacy backend |
| macOS (M3+) | VZ with nested virtualisation | 5.6+, lets VMs run inside containers |
| Windows | WSL2 | Windows Subsystem for Linux 2 |

```bash
podman machine init --cpus 4 --memory 8192 --disk-size 100   # defaults are small; size up front
podman machine start
podman machine ssh                       # into the VM
podman machine set --rootful             # enable rootful access in the VM
podman machine ls
```

Host paths mount into the VM automatically over VirtioFS (macOS VZ) or 9p (QEMU/WSL2), so `podman run -v /Users/me/data:/data ...` works. The default VM is deliberately small; raise CPU and memory at `init` rather than fighting resource limits later.

## Buildah and image builds

`podman build` is Buildah under the covers, so a `Containerfile` (or `Dockerfile`, both are honoured) builds with the same daemonless, rootless model as running. Buildah also exposes finer-grained scripted builds when you want to assemble a layer without a full Containerfile, and Skopeo inspects or copies images between transports without pulling them.

```bash
podman build -t registry.example.com/myapp:v2.0 .        # Buildah-backed; reads Containerfile or Dockerfile
podman build --build-arg VERSION=2.0 --layers -t myapp .  # cache intermediate layers
skopeo inspect docker://registry.example.com/myapp:v2.0   # metadata without pulling
skopeo copy docker://src/img:tag docker://dst/img:tag     # registry-to-registry, no local store
```

The build ignore-file is `.containerignore`, falling back to `.dockerignore`. Buildah builds are rootless too, so image assembly in CI needs no privileged daemon. BuildKit-specific Dockerfile syntax is not guaranteed; Podman uses Buildah, not BuildKit.

## Netavark networking

Netavark (Rust) replaced CNI plugins in Podman 4.0 and is the default stack; Aardvark-DNS gives per-network name resolution so containers reach each other by name.

```bash
podman network create mynet                              # default bridge
podman network create --subnet 172.20.0.0/16 --gateway 172.20.0.1 mynet
podman network create -d macvlan --subnet 192.168.1.0/24 \
  --gateway 192.168.1.1 -o parent=eth0 macvlan-net       # rootful only
```

Rootless networking cannot touch host iptables or create veth pairs directly, so it goes through **pasta** (default in 5.x+, network-namespace based, TCP/UDP/ICMP passthrough) or legacy **slirp4netns** (userspace TCP/IP, higher latency, older kernels). `--network host` shares the host namespace for best performance. Rootless cannot use macvlan or ipvlan, and cannot bind ports below 1024 without `net.ipv4.ip_unprivileged_port_start=0`. The Netavark and Aardvark-DNS internals and the `network_backend` config live in `references/architecture.md`.

## SELinux volume labels

On SELinux-enforcing hosts (RHEL, Fedora) a bind mount is denied until it is relabelled for container access:

```bash
podman run -v /host/path:/ctr/path:z myimage   # shared label: multiple containers may use the mount
podman run -v /host/path:/ctr/path:Z myimage   # private label: exactly one container
```

Omitting `:z`/`:Z` on these hosts is the classic "Permission denied" on an otherwise-correct mount. Use `:z` when several containers share the data, `:Z` when the mount belongs to one container. In Quadlet the same suffix goes on the `Volume=` line. Rootless bind-mount ownership (a separate problem from labelling) is solved with `--userns=keep-id`, not with a label.

## Docker-compatible socket (day-to-day compatibility)

Most Docker CLI verbs work unchanged (`alias docker=podman`), and Podman can expose a Docker-API socket so existing Compose tooling drives it:

```bash
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
docker compose up -d          # or: podman-compose up -d
```

This is an operational convenience for running Compose stacks against Podman. The strategic question of whether and how to migrate a Docker estate to Podman is a selection decision; route it to `container-runtime-selection`.

## Version notes

Podman guidance here spans 5.x through 6.0. When a question is version-specific, pin behaviour to the release; when the version is unknown, guide from the latest stable and ask if it matters.

Feature boundaries worth knowing:

- **4.0**: Netavark replaces CNI as the network backend. **4.4**: `AutoUpdate` in Quadlet.
- **5.0**: rewritten networking with **pasta** as the rootless default; Apple Virtualization.framework for podman machine on macOS.
- **5.6**: Quadlet command suite; nested virtualisation on M3+ Macs. **5.8**: multi-file Quadlet bundles.
- **6.0** (major release): a **major libpod REST API revision** with breaking changes to Podman-native `/libpod/` endpoints; Docker-compatible endpoints stay stable, so `podman-compose` and Compose-over-socket keep working, but custom scripts hitting libpod directly and Podman Desktop / remote clients must be tested and updated. Also enhanced Quadlet (better dependency resolution, native secret injection, build-from-Containerfile before run, improved `podman quadlet install` bundles), pasta and Aardvark-DNS reliability gains, and bundled newer crun.

6.0 migration essentials: inventory anything using the libpod API, review Quadlet files for deprecated directives, back up `/etc/containers/` and `~/.config/containers/` and volume data (`podman volume export`), then upgrade and re-verify with `podman info`, `systemctl --user daemon-reload`, and a container round-trip. Podman does not implement Docker Swarm (use Kubernetes) and does not use BuildKit (it uses Buildah), in any version.

## Cross-references

- `container-runtime-selection`: the vendor-neutral umbrella that decides Podman vs Docker vs containerd and owns the Docker-to-Podman migration strategy; this skill runs Podman once chosen. Reciprocal reference.
- `docker-ops`, `containerd-ops`: sibling runtime-operations skills; the daemonless model here does not carry over to a daemon-based or CRI runtime.
- `container-security`: container and Kubernetes security strategy; this skill exposes Podman's rootless and user-namespace ops knobs, the security posture and gates live there.
- `container-orchestration-selection`: Kubernetes orchestration and CRI-O; Podman generates and plays Kubernetes YAML but is not a cluster orchestrator.
- `cert-manager`: in-cluster and service certificates for workloads Podman runs.
- `secrets-hygiene`, `hashicorp-vault-ops`: secret discipline and the secret store; Quadlet secret injection consumes them, never inline a credential in a unit file.
- `nginx-load-balancing`, `load-balancer-selection`: ingress and reverse proxy in front of a Podman workload.
- `cicd-platforms-ops`, `gh-actions-ci`: pipelines that build (Buildah) and push images.
- `prometheus-configuration`, `grafana-dashboards`: observability for the containers Podman runs.
- `utc-timestamps`: container events, health transitions, and journald correlation depend on NTP-synchronised UTC clocks.

## Red flags

- About to run a long-lived service with a bare `podman run` instead of a Quadlet unit under systemd.
- About to debug a "missing" image without checking whether you are rootful or rootless (separate stores).
- About to deploy rootless without `/etc/subuid` and `/etc/subgid` entries, or without `loginctl enable-linger`.
- About to bind a port below 1024 rootless without setting `net.ipv4.ip_unprivileged_port_start=0`.
- About to bind-mount on an SELinux host without `:z`/`:Z`, then blame the image for "Permission denied".
- About to reach for `--userns=keep-id` and `:Z` interchangeably; one fixes ownership, the other fixes SELinux labelling.
- About to expect `--privileged`, macvlan, or ipvlan to work rootless.
- About to size a podman machine at defaults and then fight CPU or memory limits; set them at `init`.
- About to upgrade to Podman 6.0 with scripts hitting the libpod API and no test pass against the revised endpoints.
- About to inline a secret into a Quadlet unit instead of using native secret injection or an external store.

## Bottom line

Podman is daemonless (`podman -> conmon -> crun`, no central daemon) and rootless by design (container UIDs map through subuid/subgid into an unprivileged host range, with separate stores from rootful). Run long-lived workloads as Quadlet systemd units, not by hand; build pods that mirror Kubernetes and round-trip their YAML with `generate kube` / `kube play`; on macOS and Windows the work happens inside a `podman machine` VM you should size up front. Get rootless right first (namespaces, subuid/subgid, lingering, pasta), remember `:z`/`:Z` on SELinux and `--userns=keep-id` for host-owned bind mounts, and on 6.0 test anything touching the revised libpod API. Bring the runtime choice and any Docker migration from `container-runtime-selection`; hand security, orchestration, certificates, secrets, ingress, CI/CD, and observability to the skills that own them.
