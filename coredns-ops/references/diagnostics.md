# CoreDNS diagnostics

## dig patterns for CoreDNS

### Query against the cluster DNS ClusterIP

```bash
# Find the kube-dns ClusterIP
kubectl get svc -n kube-system kube-dns

# Query CoreDNS directly (from a pod in the cluster)
dig @<kube-dns-clusterip> my-service.my-namespace.svc.cluster.local

# Query from a debug pod
kubectl run dnsutils --image=registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3 \
    --restart=Never -it --rm -- dig my-service.my-namespace.svc.cluster.local

# Full trace to see search domain expansion
kubectl exec -it <pod> -- dig +search my-service

# Bypass search domains with FQDN (trailing dot)
kubectl exec -it <pod> -- dig my-service.my-namespace.svc.cluster.local.
```

### Query from inside a running pod

```bash
# Check what DNS server the pod is using
kubectl exec -it <pod> -- cat /etc/resolv.conf

# Standard A record lookup
kubectl exec -it <pod> -- dig A my-service.default.svc.cluster.local

# Headless service (expect multiple A records)
kubectl exec -it <pod> -- dig A my-headless.default.svc.cluster.local

# SRV record for named port
kubectl exec -it <pod> -- dig SRV _http._tcp.my-service.default.svc.cluster.local

# Reverse lookup (PTR)
kubectl exec -it <pod> -- dig -x 10.96.0.10

# External name resolution (to verify forward plugin)
kubectl exec -it <pod> -- dig api.example.com
```

### Query NodeLocal DNSCache directly

```bash
# NodeLocal DNSCache binds to 169.254.20.10 on each node
# Run from a pod on the target node
dig @169.254.20.10 my-service.default.svc.cluster.local

# Check if NodeLocal DNSCache is running on the node
kubectl get pods -n kube-system -l k8s-app=node-local-dns -o wide
```

## kubectl log investigation

### CoreDNS pod logs

```bash
# Tail logs from all CoreDNS pods
kubectl logs -n kube-system -l k8s-app=kube-dns --follow

# Logs from a specific CoreDNS pod
kubectl logs -n kube-system <coredns-pod-name>

# Previous container logs (after a crash)
kubectl logs -n kube-system <coredns-pod-name> --previous

# Filter for errors only
kubectl logs -n kube-system -l k8s-app=kube-dns | grep -i error
```

### ConfigMap inspection

```bash
# View current CoreDNS Corefile
kubectl get configmap coredns -n kube-system -o yaml

# Edit the Corefile in place
kubectl edit configmap coredns -n kube-system

# Apply a modified Corefile from file
kubectl apply -f coredns-configmap.yaml
```

## Plugin-level debug

### Enable query logging temporarily

Add the `log` plugin to the server block in the ConfigMap. The `reload` plugin will pick up the change within 30 seconds:

```
.:53 {
    log
    errors
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf
    cache 30
}
```

Remove `log` after debugging. At cluster scale, per-query logging generates enormous volume and starves CoreDNS of CPU.

To reduce log volume while still capturing failures, use class filtering:

```
.:53 {
    log . {denial error}    # only log NXDOMAIN and errors
    ...
}
```

### Verify CoreDNS is reachable

```bash
# Check CoreDNS pod status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS endpoints
kubectl get endpoints -n kube-system kube-dns

# Describe a CoreDNS pod for events
kubectl describe pod -n kube-system <coredns-pod-name>
```

## Common failure modes

### NXDOMAIN for in-cluster services

**Symptom**: `dig my-service.default.svc.cluster.local` returns NXDOMAIN from inside the cluster.

**Investigation steps**:

1. Confirm the service exists: `kubectl get svc my-service -n default`
2. Confirm CoreDNS pods are running: `kubectl get pods -n kube-system -l k8s-app=kube-dns`
3. Confirm the kube-dns ClusterIP is correct in `/etc/resolv.conf` inside the pod.
4. Query CoreDNS directly: `dig @<kube-dns-clusterip> my-service.default.svc.cluster.local`
5. Enable the `log` plugin temporarily and watch for the query reaching CoreDNS.
6. Check the `kubernetes` plugin configuration in the ConfigMap: confirm `cluster.local` is in the zone list.
7. Confirm the namespace is not excluded by a `namespaces` restriction in the `kubernetes` plugin.

**Common cause**: the `kubernetes` plugin is configured with a different domain than the cluster's actual domain; or the service exists in a namespace not covered by the plugin configuration.

### Slow external name resolution

**Symptom**: external DNS queries (e.g., `api.example.com`) from pods take 1-2 seconds or more.

**Investigation steps**:

1. Measure the query time: `kubectl exec -it <pod> -- time dig api.example.com`
2. Check for ndots expansion: `kubectl exec -it <pod> -- cat /etc/resolv.conf` - if `ndots:5` and the name has fewer than 5 dots, four failed search-domain queries precede the real lookup.
3. Compare with FQDN: `kubectl exec -it <pod> -- time dig api.example.com.` (trailing dot bypasses ndots).
4. If ndots is the cause, set `dnsConfig.options.ndots: 1` on affected pods, or deploy NodeLocal DNSCache to absorb the extra queries efficiently.
5. Check the `forward` plugin upstream latency: `kubectl logs -n kube-system -l k8s-app=kube-dns | grep forward`
6. Verify upstream resolvers are reachable from the CoreDNS pod: `kubectl exec -it <coredns-pod> -- dig @8.8.8.8 api.example.com`

### Loop detection crash (CoreDNS exits at startup)

**Symptom**: CoreDNS enters a crash-loop; logs show `Loop from <addr> detected, see https://coredns.io/plugins/loop`.

**Cause**: the `forward` plugin is configured to forward to a resolver that eventually queries CoreDNS itself. The most common trigger is `forward . /etc/resolv.conf` when the node's `/etc/resolv.conf` points to `127.0.0.1` or the node's own IP where CoreDNS is also listening.

**Fix**:
1. Check the node's `/etc/resolv.conf`: `kubectl exec -it <coredns-pod> -- cat /etc/resolv.conf`
2. Replace `/etc/resolv.conf` with explicit upstream resolvers: `forward . 8.8.8.8 1.1.1.1`
3. Or use a stub-domain server block for cluster traffic and a separate external upstream block.

### Conntrack table exhaustion

**Symptom**: intermittent DNS failures across the cluster; no CoreDNS errors in logs; node-level `dmesg` or `conntrack -S` shows `conntrack: table full, dropping packet`.

**Cause**: DNS UDP queries through kube-proxy iptables DNAT consume conntrack entries. At scale (1000+ pods), the conntrack table saturates.

**Fix**: deploy NodeLocal DNSCache. This routes DNS queries to a per-node cache via direct routing (no DNAT), eliminating conntrack consumption for DNS.

**Interim mitigation** (not a permanent fix): increase the conntrack table size.

```bash
# Check current conntrack table usage on a node
conntrack -S
sysctl net.netfilter.nf_conntrack_count
sysctl net.netfilter.nf_conntrack_max

# Temporary increase (lost on reboot without sysctl persistence)
sysctl -w net.netfilter.nf_conntrack_max=524288
```

### ConfigMap YAML syntax errors

**Symptom**: CoreDNS enters a crash-loop after a ConfigMap edit; logs show `failed to parse Corefile` or similar.

**Prevention**: validate the Corefile locally before applying. CoreDNS ships a `coredns` binary that can validate a Corefile:

```bash
# Validate a local Corefile (requires a local CoreDNS binary)
coredns -conf Corefile -validate

# Or use kubectl dry-run before applying
kubectl apply -f coredns-configmap.yaml --dry-run=client
```

**Recovery**: if CoreDNS is already crash-looping, restore the previous ConfigMap from a backup or revert to a known-good Corefile via `kubectl edit configmap coredns -n kube-system`.

### Missing fallthrough on kubernetes plugin

**Symptom**: PTR lookups for node IPs or external addresses return NXDOMAIN; only Kubernetes pod and service PTR records resolve.

**Cause**: the `kubernetes` plugin handles `in-addr.arpa` and `ip6.arpa` zones but does not have `fallthrough` configured. Reverse queries for IPs outside the pod/service CIDR are answered with NXDOMAIN instead of being passed to the `forward` plugin.

**Fix**: add `fallthrough in-addr.arpa ip6.arpa` to the `kubernetes` plugin block:

```
kubernetes cluster.local in-addr.arpa ip6.arpa {
    pods insecure
    fallthrough in-addr.arpa ip6.arpa
    ttl 30
}
```

### Cache TTL issues

**Symptom**: updated service endpoints not visible to pods; pods continue to reach old endpoints after a deployment.

**Cause**: the cache TTL is too high for the workload's change rate. Default 30-second cache is fine for stable services but delays propagation for rapidly cycling endpoints (canary, blue-green, rolling deployments).

**Diagnosis**:
1. Check the cache plugin configuration in the ConfigMap.
2. Measure the actual observed propagation delay versus the configured TTL.
3. Check `coredns_cache_hits_total` vs `coredns_cache_misses_total` in Prometheus to confirm cache is being used.

**Fix**: lower the cache TTL for the affected zone or disable caching for that zone. For cluster-internal records, a TTL of 5-10 seconds balances freshness against CoreDNS load.

```
cluster.local:53 {
    kubernetes cluster.local {
        ttl 5
    }
    cache 5
}
```

## Prometheus-based triage

Use Prometheus metrics to identify the failure category before diving into logs:

| Symptom | Metric to check | Interpretation |
|---|---|---|
| General DNS failures | `coredns_dns_responses_total{rcode="SERVFAIL"}` | CoreDNS cannot get an answer (upstream down, loop, kubernetes API unreachable) |
| In-cluster NXDOMAIN spike | `coredns_dns_responses_total{rcode="NXDOMAIN"}` | Services not found; check kubernetes plugin config and service existence |
| High latency | `coredns_dns_request_duration_seconds` p99 | CPU throttling, upstream latency, or conntrack drops causing retries |
| Upstream failing | `coredns_forward_responses_total{rcode="SERVFAIL"}` | Upstream resolvers returning SERVFAIL |
| Low cache hit rate | `coredns_cache_hits_total / (coredns_cache_hits_total + coredns_cache_misses_total)` | Cache too small or TTL too low |
| Slow Kubernetes API | `coredns_kubernetes_dns_programming_duration` | Kubernetes API server slow to propagate endpoint changes |
