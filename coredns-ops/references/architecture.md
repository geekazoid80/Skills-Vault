# CoreDNS architecture

## Corefile structure

A Corefile is the CoreDNS configuration file. It consists of one or more server blocks. Each server block declares a zone (or set of zones) and an optional address:port binding, then lists the plugins active for that block.

```
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

Multiple server blocks are the correct way to implement conditional forwarding, split-horizon, or zone-specific plugin chains:

```
cluster.local:53 {
    kubernetes cluster.local
    cache 30
}

corp.internal:53 {
    forward . 10.0.0.53 10.0.0.54
    cache 60
}

.:53 {
    forward . 8.8.8.8 1.1.1.1
    cache 30
}
```

Zone matching uses longest-suffix-first: `cluster.local:53` matches `foo.cluster.local` before `.:53`.

## Plugin chain and execution order

Plugins are compiled into the CoreDNS binary at build time. Their execution order within a server block is determined by `plugin.cfg` at compile time, not by the order they appear in the Corefile. The Corefile controls only which plugins are activated for each server block.

Each query traverses the ordered chain. A plugin either:
- Handles the query and writes a response (stops the chain).
- Calls `plugin.NextOrFailure()` to pass the query to the next plugin.

### Default plugin.cfg order (abridged)

The following is the default compile-time execution order for commonly used plugins. Plugins higher in the list execute first:

```
metadata
cancel
tls
reload
nsid
bufsize
root
bind
debug
trace
ready
health
pprof
prometheus
errors
log
dnstap
local
dns64
acl
any
chaos
loadbalance
cache
rewrite
dnssec
autopath
template
transfer
hosts
route53
clouddns
k8s_external
kubernetes
file
auto
secondary
etcd
loop
forward
grpc
```

Practical implication: `cache` executes before `kubernetes` and `forward` in the default build. A cache hit returns without ever reaching the kubernetes or forward plugin. `rewrite` executes before `kubernetes`, so rewrites apply before service lookup.

## Key plugins

| Plugin | Purpose | Key options |
|---|---|---|
| `kubernetes` | Kubernetes service and pod resolution | Zone, pod mode (disabled/insecure/verified), fallthrough, ttl, endpoint_pod_names, namespaces |
| `forward` | Upstream forwarding | Servers, max_concurrent, policy (round_robin/random/sequential), health_check, tls_servername, force_tcp, expire |
| `cache` | Response caching | TTL in seconds, max size, success/denial bucket sizes |
| `rewrite` | Name/type/class rewriting | name exact, name suffix (with answer auto), type rewriting |
| `hosts` | Zone from hosts-file format | Inline entries, fallthrough |
| `file` | Authoritative zone from RFC 1035 zone file | Zone file path, transfer |
| `auto` | Authoritative zone auto-reload from directory | Directory, zone pattern |
| `etcd` | SkyDNS v1 etcd-backed resolution | etcd endpoints, zone |
| `loadbalance` | Round-robin shuffling of A/AAAA records | Automatic |
| `health` | HTTP health probe at :8080/health | lameduck duration |
| `ready` | HTTP readiness probe at :8181/ready | Per-plugin readiness hooks |
| `prometheus` | Prometheus metrics at :9153/metrics | Bind address |
| `errors` | Error logging with consolidation | Consolidation period |
| `log` | Per-query logging | Response class filter (default logs all; use class denial/error to reduce volume) |
| `loop` | Forwarding loop detection | Automatic; shuts CoreDNS down on loop detection |
| `reload` | ConfigMap/Corefile hot-reload | Interval (default 30s) |
| `dnssec` | Inline DNSSEC signing | Key file, zones |
| `autopath` | Optimised search-domain resolution for pods | @kubernetes |
| `transfer` | AXFR/IXFR zone transfer serving | to/from configuration |

### forward plugin options

```
forward . 8.8.8.8 1.1.1.1 {
    max_concurrent 1000       # concurrent queries per upstream
    policy round_robin        # round_robin | random | sequential
    health_check 5s           # upstream health check interval
    tls_servername dns.google # for DNS over TLS (DoT)
    force_tcp                 # force TCP transport
    expire 10s                # connection expiry
}
```

### rewrite plugin examples

```
# Exact name rewrite
rewrite name exact old.example.com new.example.com

# Suffix rewrite (with answer rewriting for CNAME responses)
rewrite name suffix .old-cluster.local .cluster.local answer auto

# Query type rewrite
rewrite type AAAA A
```

### kubernetes plugin options

```
kubernetes cluster.local in-addr.arpa ip6.arpa {
    pods insecure                    # pod record mode: disabled | insecure | verified
    fallthrough in-addr.arpa ip6.arpa  # pass unresolved reverse queries to next plugin
    ttl 30                           # TTL for DNS records served by this plugin
    endpoint_pod_names               # use pod names in endpoint A record responses
    namespaces default staging       # restrict to specific namespaces
}
```

Pod modes:
- `disabled`: no pod records served.
- `insecure`: return a pod IP for any query matching the pod IP dash format (default; no API verification).
- `verified`: verify the pod exists in the Kubernetes API before returning a record (more accurate, higher API load).

## Kubernetes service discovery

### DNS record types

| Query pattern | Record type | Resolves to |
|---|---|---|
| `<svc>.<ns>.svc.cluster.local` | A/AAAA | ClusterIP address |
| `<svc>.<ns>.svc.cluster.local` (headless) | A | All pod IPs (multiple records) |
| `<svc>.<ns>.svc.cluster.local` (ExternalName) | CNAME | External FQDN |
| `<pod-ip-dashes>.<ns>.pod.cluster.local` | A | Pod IP (requires pods insecure or verified) |
| `_<port>._<proto>.<svc>.<ns>.svc.cluster.local` | SRV | Named port: priority, weight, port, target hostname |

### Search domains and ndots

Kubernetes configures each pod's `/etc/resolv.conf` with search domains and ndots:

```
search <namespace>.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

With ndots=5, a query with fewer than 5 dots triggers search domain expansion before a global lookup. For `api.example.com` (2 dots), this generates:
1. `api.example.com.<namespace>.svc.cluster.local` - NXDOMAIN
2. `api.example.com.svc.cluster.local` - NXDOMAIN
3. `api.example.com.cluster.local` - NXDOMAIN
4. `api.example.com.` - the real lookup (succeeds)

Mitigation options:
- Set `dnsConfig.options.ndots: 1` on pods that make heavy external DNS calls.
- Use FQDNs with trailing dot: `api.example.com.` bypasses search domain expansion entirely.
- Use `autopath` plugin with `@kubernetes` to short-circuit search-domain expansion using Kubernetes-aware resolution.
- Deploy NodeLocal DNSCache to absorb the extra queries efficiently at scale.

### autopath

The `autopath` plugin optimises search-domain resolution. When a pod sends `my-service.<namespace>.svc.cluster.local`, autopath resolves it directly, bypassing the client-side ndots expansion. This reduces the number of queries sent from the pod for in-cluster lookups.

## Server blocks as deployment unit

### Cluster DNS (standard Kubernetes deployment)

```
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}
```

### Conditional forwarding for hybrid DNS

Separate server blocks per domain; zone matching routes queries to the correct block:

```
# In-cluster service discovery
cluster.local:53 {
    kubernetes cluster.local
    cache 30
}

# Corporate Active Directory / internal DNS
corp.contoso.com:53 {
    forward . 10.0.0.53 10.0.0.54
    cache 60
}

# AWS VPC resolver
aws.internal:53 {
    forward . 10.0.0.2
    cache 30
}

# Everything else (public internet)
.:53 {
    forward . 8.8.8.8 1.1.1.1 {
        max_concurrent 1000
    }
    cache 30
    loop
    loadbalance
}
```

### Custom static hosts

```
.:53 {
    hosts {
        10.0.0.1  gateway.local
        10.0.0.10 db.local
        fallthrough
    }
    forward . 8.8.8.8
    cache 30
}
```

`fallthrough` in the `hosts` block passes queries for names not found in the hosts list to the next plugin.

## ConfigMap hot-reload

In Kubernetes, the Corefile lives in the `coredns` ConfigMap in the `kube-system` namespace. The `reload` plugin watches for changes and applies them without a pod restart.

```bash
kubectl edit configmap coredns -n kube-system
```

Changes take effect within the reload interval (default 30 seconds). YAML indentation errors or Corefile syntax errors prevent reload and cause CoreDNS to crash-loop. Always validate Corefile syntax before applying.

## NodeLocal DNSCache

### Why it exists

In standard Kubernetes DNS, every pod DNS query:
1. Is sent to the kube-dns ClusterIP.
2. Is DNAT-rewritten by kube-proxy iptables rules to a CoreDNS pod IP.
3. Consumes a conntrack entry for the NAT mapping.

At scale (1000+ pods), two problems emerge:
- **Conntrack table exhaustion**: DNS queries dominate the conntrack table; when the table fills, DNS queries are silently dropped.
- **UDP conntrack race conditions**: simultaneous queries to the same ClusterIP cause conntrack entry collisions and dropped responses.

### Architecture

NodeLocal DNSCache runs CoreDNS as a DaemonSet on every node, bound to the link-local IP `169.254.20.10`. Pods are configured with `--cluster-dns=169.254.20.10` (kubelet flag), directing all DNS queries to the local node cache.

```
Pod (resolv.conf: 169.254.20.10)
  -> NodeLocal DNSCache DaemonSet (per-node, 169.254.20.10)
       -> Local cache (hit: return immediately)
       -> Cache miss: forward via TCP to kube-dns ClusterIP (CoreDNS)
```

TCP to the upstream eliminates UDP conntrack issues entirely. Local cache eliminates cross-node query latency for cached entries. Measured improvement at scale: 5-10x reduction in p99 DNS latency.

### NodeLocal DNSCache Corefile

```
cluster.local:53 {
    errors
    cache {
        success 9984 30
        denial  9984 5
    }
    reload
    loop
    bind 169.254.20.10
    forward . __PILLAR__CLUSTER__DNS__ {
        force_tcp
    }
    prometheus :9253
    health 169.254.20.10:8080
}

in-addr.arpa:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10
    forward . __PILLAR__CLUSTER__DNS__ {
        force_tcp
    }
    prometheus :9253
}

.:53 {
    errors
    cache 30
    reload
    loop
    bind 169.254.20.10
    forward . __PILLAR__UPSTREAM__SERVERS__
    prometheus :9253
}
```

`__PILLAR__CLUSTER__DNS__` and `__PILLAR__UPSTREAM__SERVERS__` are replaced with the actual kube-dns ClusterIP and external resolvers at deployment time.

### Deployment

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/nodelocaldns/nodelocaldns.yaml
```

Requires kubelet flag `--cluster-dns=169.254.20.10` to direct pod DNS to the local cache.

## Scaling and HA

- Run at least two CoreDNS replicas with pod anti-affinity across nodes. A single CoreDNS pod is a critical single point of failure for the entire cluster.
- Use a `PodDisruptionBudget` to ensure at least one replica remains available during node maintenance.
- Size the cache (`cache <max_size_entries>`) for the cluster's service count. Default (10000 entries) is adequate for clusters with fewer than 5000 services.
- For large clusters, deploy NodeLocal DNSCache. The per-node cache absorbs the majority of queries; the central CoreDNS deployment sees only cache misses.
- Set resource requests and limits on the CoreDNS Deployment. DNS is latency-sensitive; CPU throttling causes significant p99 latency spikes. Typical starting point: 100m CPU request, 500m CPU limit, 70Mi memory request.

## Prometheus metrics

The `prometheus` plugin exposes metrics at `:9153/metrics` by default.

| Metric | Description |
|---|---|
| `coredns_dns_requests_total` | Total queries by server, zone, and query type |
| `coredns_dns_responses_total` | Total responses by rcode (NOERROR, NXDOMAIN, SERVFAIL, etc.) |
| `coredns_dns_request_duration_seconds` | Query latency histogram |
| `coredns_cache_hits_total` | Cache hits |
| `coredns_cache_misses_total` | Cache misses |
| `coredns_cache_size` | Current number of cached entries |
| `coredns_forward_requests_total` | Queries forwarded to upstream resolvers |
| `coredns_forward_responses_total` | Responses received from upstream resolvers |
| `coredns_kubernetes_dns_programming_duration` | Time taken to update DNS after a Kubernetes API event |

Key alert signals: rising `coredns_dns_responses_total{rcode="SERVFAIL"}`, rising `coredns_forward_responses_total{rcode="SERVFAIL"}` (upstream unreachable), low cache hit ratio (cache too small or TTL too low), and elevated `coredns_dns_request_duration_seconds` p99 (upstream latency or CPU throttling).

## Health and readiness probes

```
health {
    lameduck 5s
}
ready
```

- `health` serves `:8080/health`. Returns HTTP 200 when CoreDNS is running. The `lameduck` option makes CoreDNS delay shutdown by 5 seconds to allow in-flight queries to complete.
- `ready` serves `:8181/ready`. Returns HTTP 200 only when all plugins report ready. The `kubernetes` plugin is not ready until it has completed the initial sync with the Kubernetes API. Using `/ready` as the readiness probe prevents traffic from reaching CoreDNS before it can answer Kubernetes DNS queries.

Kubernetes probe configuration:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 60
  timeoutSeconds: 5
readinessProbe:
  httpGet:
    path: /ready
    port: 8181
```
