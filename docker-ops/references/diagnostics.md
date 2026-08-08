# Docker diagnostics and troubleshooting

## Container inspection

### Logs

```bash
docker logs -f --tail 100 <container>              # follow with tail
docker logs --since 2024-01-01T00:00:00Z <container>
docker logs --since 30m <container>
docker logs -t <container>                          # timestamps
docker logs <dead-container-id>                     # works if not removed
```

`docker logs` only works with the `json-file` and `journald` logging drivers. With fluentd, syslog, or others, query the backend directly.

### Inspect

```bash
docker inspect <container>                                            # full JSON metadata

docker inspect --format '{{.State.Status}}' <container>
docker inspect --format '{{.NetworkSettings.IPAddress}}' <container>
docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' <container>
docker inspect --format '{{json .Mounts}}' <container> | jq .
docker inspect --format '{{.Config.Healthcheck}}' <container>

docker inspect --format '{{.State.ExitCode}}' <container>
# 0 = normal, 1 = app error, 137 = SIGKILL (OOM or docker stop timeout),
# 139 = SIGSEGV, 143 = SIGTERM

docker inspect --format '{{.State.OOMKilled}}' <container>            # OOM killed?
docker inspect --format '{{.RestartCount}}' <container>               # restart count
```

### Stats (live resource usage)

```bash
docker stats                                        # all containers, streaming
docker stats --no-stream <container1> <container2>  # snapshot
docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
```

Key metrics:

- **CPU %**: may exceed 100% on multi-core (200% = 2 cores fully used).
- **MEM USAGE / LIMIT**: current RSS / cgroup memory limit.
- **NET I/O**: network bytes received / sent.
- **BLOCK I/O**: disk bytes read / written.
- **PIDs**: number of processes in the container.

### Events

```bash
docker events                                       # stream real-time events
docker events --filter container=<name>
docker events --filter event=die
docker events --filter event=oom
docker events --filter event=health_status
docker events --since 1h --until 30m
docker events --format '{{json .}}'
```

Event types: `create`, `start`, `stop`, `die`, `kill`, `oom`, `pause`, `unpause`, `health_status`, `exec_create`, `exec_start`, `attach`, `detach`, `resize`.

### Top and diff

```bash
docker top <container>                              # processes in the container
docker top <container> -eo pid,ppid,user,stat,args

docker diff <container>                             # files changed in the writable layer
# A = added, C = changed, D = deleted
```

## System-level diagnostics

### System info

```bash
docker info
```

Key fields to check: Server Version, Storage Driver (overlay2, fuse-overlayfs), Logging Driver, Cgroup Driver (systemd vs cgroupfs), Cgroup Version (1 vs 2), Kernel Version, Operating System, Security Options (seccomp, apparmor, rootless), Runtimes (runc plus any alternatives), containerd version, runc version.

### Disk usage

```bash
docker system df                                    # summary
docker system df -v                                 # detailed breakdown
```

Shows images (total size, shared layers, reclaimable), containers (writable layer and log size), volumes (size, in-use), and BuildKit build cache size.

### Cleanup

```bash
docker system prune                                 # stopped containers, unused networks,
                                                    # dangling images, build cache
docker system prune -a --volumes                    # also unused images and volumes

docker container prune                              # stopped containers
docker image prune -a                               # all unused images
docker volume prune                                 # unused volumes
docker builder prune                                # BuildKit cache
docker network prune                                # unused networks

docker image prune -a --filter "until=24h"          # images older than 24h
```

## Troubleshooting workflows

### Container will not start

1. Check the exit code: `docker inspect --format '{{.State.ExitCode}}' <container>`.
2. Read logs: `docker logs <container>`.
3. Check events: `docker events --filter container=<name> --since 1h`.
4. Inspect the health check: `docker inspect --format '{{json .State.Health}}' <container> | jq .`.
5. Run interactively: `docker run -it --entrypoint /bin/sh <image>`.
6. Check resource limits: `docker inspect --format '{{json .HostConfig.Resources}}' <container> | jq .`.

### Container OOM killed

1. Confirm OOM: `docker inspect --format '{{.State.OOMKilled}}' <container>` (true = OOM).
2. Check the memory limit: `docker inspect --format '{{.HostConfig.Memory}}' <container>`.
3. Check current usage: `docker stats --no-stream <container>`.
4. Check kernel OOM events: `dmesg | grep -i oom`.
5. Increase the limit or optimise application memory.
6. Exit code 137 without `OOMKilled=true` usually means `docker stop` timed out and sent SIGKILL.

### Networking issues

```bash
docker inspect --format '{{json .NetworkSettings.Networks}}' <container> | jq .

docker exec <container> nslookup <other-container-name>
docker exec <container> cat /etc/resolv.conf        # 127.0.0.11 on a custom bridge
docker exec <container> ping <target>
docker exec <container> wget -qO- http://<target>:<port>/

docker port <container>                             # published ports
docker network inspect <network-name>

iptables -t nat -L DOCKER -n -v                     # host NAT rules
iptables -L DOCKER-USER -n -v
```

### Storage issues

```bash
docker info | grep "Storage Driver"
docker ps -s                                        # writable layer size
docker exec <container> du -sh /* 2>/dev/null | sort -rh | head -20
docker inspect --format '{{json .Mounts}}' <container> | jq .
mount | grep overlay
xfs_info /var/lib/docker | grep ftype               # ftype=1 required for overlay2
```

### Build issues

```bash
docker buildx build --no-cache --progress=plain .   # verbose, no cache
docker run -it <last-successful-layer-sha> /bin/sh  # debug a failed step
docker buildx du                                    # BuildKit cache size
docker builder prune -a                             # prune build cache
tar -cf - . | wc -c                                 # build context size, check .dockerignore
docker buildx build --platform linux/amd64 --load . # load single-platform locally
```

### Daemon issues

```bash
systemctl status docker
journalctl -u docker.service -f
journalctl -u docker.service --since "1 hour ago"

python3 -c "import json; json.load(open('/etc/docker/daemon.json'))"   # validate config

systemctl status containerd
journalctl -u containerd.service -f

curl --unix-socket /var/run/docker.sock http://localhost/version       # test the socket
```

## Performance analysis

### Container CPU throttling

```bash
cat /sys/fs/cgroup/docker/<container-id>/cpu.stat   # cgroup v2; nr_throttled, throttled_usec

docker inspect --format '{{.HostConfig.NanoCpus}}' <container>   # --cpus
docker inspect --format '{{.HostConfig.CpuQuota}}' <container>   # --cpu-quota
docker inspect --format '{{.HostConfig.CpuPeriod}}' <container>  # --cpu-period
```

### Network performance

```bash
docker run --rm --network mynet nicolaka/netshoot iperf3 -c <target-container>
docker exec <container> ip link show eth0           # MTU
# userland proxy overhead: disable with "userland-proxy": false in daemon.json
```

### I/O performance

```bash
docker inspect --format '{{json .HostConfig.BlkioDeviceReadBps}}' <container>
docker stats --format "{{.Name}}: {{.BlockIO}}"
```

## Health-check debugging

```bash
docker inspect --format '{{json .Config.Healthcheck}}' <container> | jq .   # configuration
docker inspect --format '{{json .State.Health}}' <container> | jq .         # last 5 results
docker inspect --format '{{.State.Health.Status}}' <container>              # starting/healthy/unhealthy
docker exec <container> curl -f http://localhost:8080/health               # run manually
```

## Compose diagnostics

```bash
docker compose ps                                   # running services
docker compose logs -f                              # all services
docker compose logs -f api                          # one service
docker compose config                               # resolved (merged) YAML
docker compose events
docker compose exec api bash
docker compose top                                  # per-service resource usage
```
