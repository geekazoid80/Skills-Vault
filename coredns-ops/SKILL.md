---
name: coredns-ops
description: "Use for CoreDNS implementation, Corefile configuration, plugin chain management, and Kubernetes service discovery operations. Covers Corefile server block structure, plugin execution order (compile-time plugin.cfg), key plugins (kubernetes, forward, cache, hosts, file, auto, etcd, rewrite, loadbalance, health, ready, prometheus, errors, log, loop, reload), Kubernetes DNS (cluster.local, ClusterIP/headless/ExternalName/pod resolution, SRV records, autopath, search domains, ndots), NodeLocal DNSCache for large-cluster performance, ConfigMap hot-reload, conditional forwarding for hybrid DNS, Prometheus metrics, health/readiness probes, and common failure diagnostics. References: architecture.md, diagnostics.md. Triggers include \"CoreDNS\", \"Corefile\", \"CoreDNS plugin\", \"kubernetes plugin\", \"cluster.local\", \"CoreDNS forward\", \"CoreDNS cache\", \"ndots\", \"autopath\", \"CoreDNS kubernetes service discovery\", \"kube-dns\", \"CoreDNS ConfigMap\", \"CoreDNS Prometheus\", \"NodeLocal DNSCache\", \"plugin chain\", \"CoreDNS rewrite\", \"CoreDNS loop\", \"CoreDNS health\", \"CoreDNS ready\", \"CoreDNS forward plugin\", \"CoreDNS headless service\", \"CoreDNS ExternalName\", \"CoreDNS SRV\", \"coredns-ops\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops."
license: MIT
metadata:
  version: 1.0.0
---

# CoreDNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: coredns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers CoreDNS-specific implementation: writing and validating Corefiles, understanding the plugin chain and compile-time execution order, configuring Kubernetes service discovery, tuning cache and forwarding, deploying NodeLocal DNSCache for large clusters, and diagnosing CoreDNS failures. The conceptual layer (DNS resolution flow, DNSSEC design, platform selection, cross-platform comparison) lives in `dns-network-ops`.

## When to use

- Writing or reviewing a Corefile: server blocks, plugin selection, zone matching.
- Configuring the Kubernetes `kubernetes` plugin for service and pod resolution.
- Setting up conditional forwarding for hybrid DNS (Kubernetes plus corporate internal DNS).
- Tuning the `cache`, `forward`, or `rewrite` plugins.
- Deploying or diagnosing NodeLocal DNSCache on large Kubernetes clusters.
- Managing CoreDNS via Kubernetes ConfigMap and hot-reload.
- Diagnosing NXDOMAIN for in-cluster services, slow external resolution, conntrack exhaustion, or cache anomalies.
- Setting up Prometheus metrics and health/readiness probes for CoreDNS.

## When not to use

- **DNS architecture, DNSSEC design, or cross-platform selection**: use `dns-network-ops`.
- **BIND (named.conf, views, RPZ, KASP, catalog zones)**: use `bind-dns-ops`.
- **Validating caching recursive resolver hardening, DNSSEC validation, or privacy features**: use `unbound-dns-ops`.
- **Secrets handling for TLS certificates or upstream DoT credentials**: apply `secrets-hygiene` alongside this skill.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and configuration | Corefile structure; server blocks; plugin chain and compile-time execution order; key plugins (kubernetes, forward, cache, rewrite, hosts, file, auto, etcd, loadbalance, health, ready, prometheus, errors, log, loop, reload); Kubernetes DNS record types (ClusterIP, headless, ExternalName, pod, SRV); search domains and ndots; NodeLocal DNSCache architecture and Corefile; conditional forwarding; Prometheus metrics; health and readiness probes; Corefile patterns | `references/architecture.md` |
| Diagnostics and troubleshooting | dig against ClusterIP and pod DNS; kubectl logs and crash-loop investigation; plugin-level debug (log plugin, errors plugin); common failure modes: NXDOMAIN for services, slow external resolution, loop detection crash, conntrack exhaustion, ConfigMap YAML syntax errors, missing fallthrough, cache TTL issues; ndots problem and mitigation | `references/diagnostics.md` |

## Core concepts

### Classify first

Before writing any Corefile, identify two things:

1. **Deployment context**: Kubernetes cluster DNS (most common), standalone CoreDNS, or NodeLocal DNSCache DaemonSet. Each has a different Corefile shape and operational model.
2. **Cluster scale**: small (fewer than 100 pods) vs large (1000+ pods). Scale determines whether NodeLocal DNSCache is needed and how cache sizes should be tuned.

### Plugin chain and execution order

The order plugins execute within a server block is **not** determined by Corefile order. It is fixed at compile time by `plugin.cfg`. The Corefile determines only which plugins are activated for each server block. A plugin either handles the query and returns a response, or calls `plugin.NextOrFailure()` to pass the query to the next plugin in the chain. See `references/architecture.md` for the default `plugin.cfg` order.

### Kubernetes plugin

The `kubernetes` plugin is the core of Kubernetes DNS. It reads services, endpoints, and pods from the Kubernetes API and answers DNS queries for `cluster.local`, `in-addr.arpa`, and `ip6.arpa`. Key settings: `pods insecure` (or `pods verified` for stricter verification), `fallthrough in-addr.arpa ip6.arpa` (to pass unresolved reverse queries upstream), and `ttl 30` (default; lower for rapidly changing endpoints).

### Server blocks and zone matching

Each server block binds to an address:port and one or more zones. Zone matching uses longest-suffix-first: a `cluster.local:53` block wins over `.:53` for queries under `cluster.local`. Multiple server blocks on the same port are supported and are the correct way to implement conditional forwarding.

### ConfigMap hot-reload

In Kubernetes, CoreDNS configuration lives in the `coredns` ConfigMap in `kube-system`. The `reload` plugin watches for changes and applies them without a pod restart, typically within 30 seconds. YAML syntax errors in the ConfigMap cause CoreDNS to crash-loop; validate before applying.

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC design, cross-platform selection, and the broader DNS family skill set.
- `unbound-dns-ops`: validating, caching recursive resolver; use alongside CoreDNS when a separate upstream validating resolver is needed (e.g., CoreDNS forwards to an internal Unbound instance for DNSSEC validation).
- `multi-vendor-network-ops`: production-change contract (assumptions, pre-checks, execution, post-checks, rollback). Apply to every production CoreDNS ConfigMap change and NodeLocal DNSCache deployment.
- `secrets-hygiene`: TLS certificates, DoT upstream credentials, and any API tokens used in CoreDNS integrations must never be inlined in Corefiles or ConfigMaps committed to version control.
- `utc-timestamps`: CoreDNS query logs and Prometheus metrics must be reasoned in UTC; cache TTL decisions are time-sensitive and depend on accurate clock reasoning.
- `systematic-debugging`: structured fault-isolation approach for complex CoreDNS failures (loop detection, view mis-matching, plugin interaction, conntrack exhaustion at scale).

## Red flags

- **Loop detection crash.** The `loop` plugin sends a test query at startup. If the `forward` plugin points at a resolver that ultimately queries CoreDNS (e.g., `/etc/resolv.conf` pointing to localhost), CoreDNS detects the loop and shuts down. Always ensure `forward . <upstream>` points to a resolver outside the current CoreDNS instance.
- **Missing `fallthrough` on the kubernetes plugin.** Without `fallthrough in-addr.arpa ip6.arpa`, reverse DNS queries for non-Kubernetes IPs return NXDOMAIN instead of being forwarded upstream. This breaks PTR lookups for node IPs and external addresses.
- **ConfigMap YAML syntax errors.** Indentation errors or invalid Corefile syntax in the ConfigMap cause CoreDNS to crash-loop. Validate Corefile syntax before applying; check with `kubectl logs -n kube-system -l k8s-app=kube-dns`.
- **Conntrack exhaustion without NodeLocal DNSCache.** In clusters with 1000+ pods, UDP DNS queries through kube-proxy iptables DNAT consume conntrack entries. Conntrack table exhaustion causes silent DNS failures with no obvious error. Deploy NodeLocal DNSCache to eliminate conntrack for DNS.
- **Cache TTL too high for dynamic workloads.** The default 30-second cache is appropriate for stable services. For canary deployments, blue-green switches, or rapidly cycling endpoints, reduce or disable cache for the affected zone to prevent stale endpoint resolution.
- **ndots=5 causing external DNS latency.** The default `ndots: 5` Kubernetes pod DNS config causes external queries (e.g., `api.example.com`) to try four search domain expansions before the real lookup. For pods making heavy external DNS calls, set `dnsConfig.options.ndots: 1` or use FQDNs with trailing dots.
- **log plugin left enabled in production.** The `log` plugin emits one line per query. At cluster scale this generates enormous log volume and can starve the CoreDNS pod of CPU. Enable it only for targeted debugging, then remove.
- **Single CoreDNS replica.** A single CoreDNS pod is a critical DNS single point of failure for the entire cluster. Run at least two replicas with pod anti-affinity to spread them across nodes.

## Bottom line

Classify the deployment context (cluster DNS, standalone, or NodeLocal DNSCache) and cluster scale before writing any Corefile. Load `references/architecture.md` for plugin chain detail, Kubernetes DNS record types, server block patterns, and NodeLocal DNSCache configuration. Load `references/diagnostics.md` for dig patterns, kubectl log analysis, and common failure diagnosis. Route architecture and design decisions to `dns-network-ops`. Treat every production ConfigMap change as a change-controlled operation under the `multi-vendor-network-ops` contract.
