# Podman setup and operations

Rootless setup and troubleshooting, Quadlet patterns, pods, Buildah builds, systemd integration, and hardening. Read this for design and operations questions.

## Rootless setup

### Prerequisites checklist

```bash
# 1. Kernel supports user namespaces
sysctl user.max_user_namespaces   # want a non-zero value (mainline, RHEL, Fedora)
cat /proc/sys/kernel/unprivileged_userns_clone   # want 1 (Debian/Ubuntu only; absent elsewhere)
# if disabled: sysctl -w user.max_user_namespaces=28633 (plus kernel.unprivileged_userns_clone=1
# on Debian/Ubuntu), persisted in /etc/sysctl.d/

# 2. sub-UID / sub-GID configured
cat /etc/subuid    # username:100000:65536
cat /etc/subgid    # username:100000:65536
# if missing: usermod --add-subuids 100000-165535 --add-subgids 100000-165535 username

# 3. cgroup v2 with user delegation
cat /sys/fs/cgroup/cgroup.controllers     # want cpu memory io pids
ls  /sys/fs/cgroup/user.slice/            # should exist

# 4. Lingering (keeps user systemd running after logout)
loginctl enable-linger "$USER"

# 5. Confirm rootless
podman info --format '{{.Host.Security.Rootless}}'   # true
```

### Rootless troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `cannot find UID/GID for user` | missing sub-UID/GID | `usermod --add-subuids 100000-165535 username` |
| `cannot setup namespace` | kernel rejects user namespaces | set `kernel.unprivileged_userns_clone=1` |
| container exits with permission denied | SELinux or file ownership | `:z`/`:Z` volume label or `--userns=keep-id` |
| cannot bind port 80/443 | privileged port | set `net.ipv4.ip_unprivileged_port_start=0` |
| slow networking | using slirp4netns | switch to pasta (default in 5.x+) |
| `XDG_RUNTIME_DIR not set` | no systemd user session | `loginctl enable-linger $USER` and re-login |

### Rootless volume permissions

The container runs as UID 0, which maps to host UID 100000, so files owned by your host UID (1000) are inaccessible. Three fixes:

```bash
# 1. keep-id: map the host UID into the container
podman run --userns=keep-id -v /home/user/data:/data myimage

# 2. change ownership inside the namespace
podman unshare chown -R 0:0 /home/user/data

# 3. named volume: let Podman manage permissions
podman volume create mydata
podman run -v mydata:/data myimage
```

## Quadlet patterns

### Single service

```ini
# ~/.config/containers/systemd/webapp.container
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
HealthRetries=3
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

### Multi-container application (pod)

```ini
# webapp.pod
[Pod]
PodName=webapp
PublishPort=8080:80
PublishPort=5432:5432
Network=webapp.network

# webapp-nginx.container
[Unit]
Description=Nginx Frontend
After=webapp-api.service

[Container]
Pod=webapp.pod
Image=nginx:1.27-alpine
ContainerName=webapp-nginx
Volume=./nginx.conf:/etc/nginx/nginx.conf:ro,z

[Service]
Restart=on-failure

# webapp-api.container
[Unit]
Description=API Backend
After=webapp-db.service

[Container]
Pod=webapp.pod
Image=registry.example.com/api:v2.0
ContainerName=webapp-api
Environment=DATABASE_URL=postgresql://localhost:5432/myapp
HealthCmd=wget -qO- http://localhost:3000/health
HealthInterval=15s

[Service]
Restart=on-failure

# webapp-db.container
[Container]
Pod=webapp.pod
Image=postgres:16-alpine
ContainerName=webapp-db
Environment=POSTGRES_DB=myapp
EnvironmentFile=%h/.config/webapp/db.env
Volume=webapp-pgdata.volume:/var/lib/postgresql/data:Z

[Service]
Restart=on-failure
```

### Supporting resources

```ini
# webapp.network
[Network]
Driver=bridge
Subnet=172.20.0.0/16
Gateway=172.20.0.1
DNS=true

# webapp-data.volume
[Volume]
Driver=local
Label=app=webapp

# webapp-pgdata.volume
[Volume]
Driver=local
Label=app=webapp
Label=component=database
```

### Quadlet lifecycle commands

```bash
# after creating or changing Quadlet files
systemctl --user daemon-reload

# enable and start
systemctl --user enable --now webapp-nginx
systemctl --user enable --now webapp-api
systemctl --user enable --now webapp-db

# for pods, start the pod service
systemctl --user start webapp-pod

# inspect the generated unit
systemctl --user cat webapp-nginx.service

# verify Quadlet generation into a temp dir
/usr/lib/systemd/user-generators/podman-user-generator /tmp/quadlet-test
ls /tmp/quadlet-test/
```

## Pods and Kubernetes YAML

```bash
# create a pod with published ports (ports live on the pod, not the members)
podman pod create --name webapp -p 8080:80

# add containers
podman run -d --pod webapp --name nginx nginx:latest
podman run -d --pod webapp --name sidecar my-sidecar:latest
# members share localhost within the pod, like Kubernetes

# export a running pod to Kubernetes YAML
podman generate kube webapp > pod.yaml

# deploy from Kubernetes YAML (supports Deployments, Services)
podman kube play pod.yaml
podman kube down pod.yaml           # teardown
```

The infra (pause) container holds the pod's network namespace, identical to Kubernetes behaviour.

## Buildah and image builds

`podman build` is Buildah under the covers, and builds are rootless like everything else.

```bash
podman build -t registry.example.com/myapp:v2.0 .        # reads Containerfile or Dockerfile
podman build --build-arg VERSION=2.0 --layers -t myapp .  # cache intermediate layers
skopeo inspect docker://registry.example.com/myapp:v2.0   # metadata without pulling
skopeo copy docker://src/img:tag docker://dst/img:tag     # registry-to-registry, no local store
```

The ignore-file is `.containerignore`, falling back to `.dockerignore`. Podman uses Buildah, not BuildKit, so some BuildKit-specific Dockerfile syntax may differ.

## Docker-compatible socket

Most Docker CLI verbs work unchanged, and Podman can serve a Docker-API socket so Compose tooling drives it:

```bash
alias docker=podman        # works for most commands

systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
docker compose up -d       # or: pip3 install podman-compose && podman-compose up -d
```

This is a day-to-day compatibility facility. The strategic decision of whether and how to move a Docker estate onto Podman belongs to the `container-runtime-selection` umbrella.

## systemd integration

### Enable lingering

```bash
loginctl enable-linger "$USER"
```

Without lingering, all user systemd services (including Quadlet containers) stop when the user logs out.

### Auto-update

```ini
# in the .container file:
[Container]
AutoUpdate=registry        # check for a new image tag
# or
AutoUpdate=local           # use locally built images
```

```bash
systemctl --user enable --now podman-auto-update.timer   # daily by default
systemctl --user edit podman-auto-update.timer
# [Timer]
# OnCalendar=*-*-* 03:00:00     # run at 03:00 daily
```

### Logging

```bash
journalctl --user -u myapp -f     # Quadlet containers log to journald by default
podman logs -f myapp              # or read container logs directly
```

```ini
[Container]
LogDriver=journald
```

### Health checks feed dependency management

```ini
[Container]
HealthCmd=curl -f http://localhost:8080/health
HealthInterval=10s
HealthRetries=3
HealthStartPeriod=30s

[Service]
Restart=on-failure
```

## Hardening

### Least-privilege runtime

```bash
podman run --cap-drop ALL --cap-add NET_BIND_SERVICE myimage
podman run --read-only --tmpfs /tmp myimage
podman run --security-opt no-new-privileges myimage
podman run --security-opt seccomp=/path/to/profile.json myimage
```

For defence-in-depth container and Kubernetes security strategy (image scanning gates, admission control, Pod Security Standards, supply-chain integrity), route to `container-security`. The knobs above are Podman's own runtime controls.

### Image trust

```json
// /etc/containers/policy.json
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "registry.example.com": [{"type": "sigstoreSigned", "keyPath": "/etc/containers/sigstore/myorg.pub"}],
      "docker.io/library": [{"type": "insecureAcceptAnything"}]
    }
  }
}
```

```bash
skopeo inspect docker://registry.example.com/myapp:v2.0   # inspect without pulling
```

### Resource limits

```bash
podman run --cpus 1.5 myimage
podman run --memory 512m --memory-swap 1g myimage
podman run --pids-limit 256 myimage        # guard against fork bombs
```

```ini
# in Quadlet:
[Container]
PodmanArgs=--cpus 1.5 --memory 512m --pids-limit 256
```

## Common pitfalls

1. **Rootful vs rootless stores**: images, containers, and volumes are stored separately; `sudo podman images` shows a different set than `podman images`.
2. **Missing sub-UID/GID entries**: rootless fails silently or cryptically without `/etc/subuid` and `/etc/subgid`.
3. **Port below 1024 rootless**: needs `net.ipv4.ip_unprivileged_port_start=0`.
4. **SELinux labels**: omitting `:z`/`:Z` on RHEL/Fedora causes permission-denied on bind mounts.
5. **podman machine defaults**: the VM ships small; set `--cpus`/`--memory`/`--disk-size` at `init`.
6. **Quadlet file location**: units must sit in the exact watched directory or systemd never generates them; verify with `systemd-analyze verify`.
