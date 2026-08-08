---
name: unbound-dns-ops
description: "Use for Unbound validating recursive resolver operations: unbound.conf structure, DNSSEC validation (trust anchors, auto-trust-anchor-file, aggressive-nsec), forward zones and stub zones, conditional forwarding, access-control, cache settings (msg-cache, rrset-cache, prefetch, serve-expired), DNS over TLS and DNS over HTTPS (tls-service, https-port), local-zone and local-data blocking, threads and performance tuning, remote-control via unbound-control, and privacy hardening (qname-minimisation, hide-identity). References: architecture.md, diagnostics.md. Triggers include \"Unbound\", \"unbound.conf\", \"unbound-control\", \"unbound-checkconf\", \"validating resolver\", \"DNSSEC validation\", \"trust anchor\", \"qname minimisation\", \"qname-minimisation\", \"prefetch\", \"serve-expired\", \"forward-zone\", \"stub-zone\", \"local-zone\", \"local-data\", \"msg-cache\", \"rrset-cache\", \"aggressive-nsec\", \"unbound-anchor\", \"pfSense DNS resolver\", \"OPNsense DNS resolver\", \"Pi-hole upstream\", \"DoT upstream\", \"DoH server\", \"module-config validator iterator\", \"infra-cache\", \"key-cache\", \"domain-insecure\", \"harden-dnssec-stripped\", \"use-caps-for-id\", \"so-reuseport\", \"cachedb Redis\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops; for authoritative BIND see bind-dns-ops; for authoritative PowerDNS see powerdns-ops."
license: MIT
metadata:
  version: 1.0.0
---

# Unbound DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: unbound-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Unbound-specific implementation: writing and validating unbound.conf, configuring DNSSEC validation, forward and stub zones, local-zone blocking, encrypted DNS (DoT/DoH), performance tuning, and operating Unbound via unbound-control. The conceptual layer (resolution flow, DNSSEC design, platform selection, cross-platform comparison) lives in `dns-network-ops`. Authoritative serving belongs in `bind-dns-ops` or `powerdns-ops`.

## When to use

- Writing or reviewing unbound.conf: server block, access-control, forward-zone, stub-zone, local-zone.
- Configuring DNSSEC validation: auto-trust-anchor-file, unbound-anchor bootstrap, negative trust anchors (domain-insecure), aggressive-nsec.
- Setting up conditional forwarding: forward particular domains to internal DNS while recursing everything else.
- Hardening privacy: qname-minimisation, hide-identity, hide-version, use-caps-for-id.
- Configuring DoT upstream forwarding or enabling Unbound as a DoH/DoT server for clients.
- Tuning performance: thread count, cache sizes and slabs, prefetch, serve-expired, so-reuseport.
- Operating Unbound: unbound-control (reload, stats, dump_cache, flush, lookup), unbound-checkconf.
- Diagnosing failures: SERVFAIL from DNSSEC validation, forward loops, cache poisoning, stale records.
- Integrating Unbound with pfSense, OPNsense, or Pi-hole.

## When not to use

- **DNS architecture, DNSSEC design, or cross-platform selection**: use `dns-network-ops`. Unbound is a recursive/validating resolver; it does not serve authoritative zones to the internet.
- **Authoritative zone serving (named.conf, zone files, KASP, RPZ on BIND)**: use `bind-dns-ops`.
- **Authoritative serving via database backend or REST API (PowerDNS Authoritative)**: use `powerdns-ops`. Note: the PowerDNS Recursor is a separate product conceptually similar to Unbound; route PowerDNS Recursor questions there.
- **Kubernetes cluster DNS (CoreDNS plugin chain, Corefile)**: use `coredns-ops`.
- **TSIG/DNSSEC key generation and secret handling**: apply `secrets-hygiene` alongside this skill.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and configuration | unbound.conf structure; multi-threaded model; module pipeline (validator, iterator, respip, cachedb, python); cache hierarchy (msg-cache, rrset-cache, infra-cache, key-cache); DNSSEC validation and trust anchors; forward-zone and stub-zone; conditional forwarding; local-zone and local-data; access-control; DoT upstream; DoH server; performance tuning table; deployment patterns (standalone recursive, forwarder, Pi-hole stack, pfSense/OPNsense, clustered Redis) | `references/architecture.md` |
| Diagnostics and troubleshooting | unbound-control command reference; unbound-checkconf; dig +dnssec validation testing; common failure modes (SERVFAIL from validation, BOGUS, forward loop, cache poisoning, stale trust anchor); performance diagnosis (cache hit rate, query latency) | `references/diagnostics.md` |

## Core concepts

### Classify the deployment first

Before writing any configuration, identify three things:

1. **Resolution mode**: full recursion (queries root servers directly) or forwarding (delegates to a trusted upstream via DoT or plain DNS). Full recursion is the privacy-preserving choice and the correct one for strict DNSSEC validation. Forwarding is simpler but DNSSEC validation is weakened unless the upstream also validates and you trust it.
2. **Scale**: home or small office (1-100 clients), campus (hundreds to low thousands), or ISP-scale (100k+). Scale drives thread count, cache sizes, and whether cachedb with Redis is worthwhile.
3. **Encrypted transport**: plain DNS on port 53 for clients, DoT or DoH for clients, DoT upstream to a trusted forwarder, or a full encrypted path (clients via DoH to Unbound, Unbound upstream via DoT).

### unbound.conf structure

unbound.conf is divided into named clauses. The most important:

- `server:` -- all global settings live here: interfaces, ports, access-control, DNSSEC, cache, privacy, hardening, threads, TLS certificates.
- `forward-zone:` -- forward queries for a given zone to specific upstream resolvers (plain DNS or DoT).
- `stub-zone:` -- send queries for a zone directly to its authoritative servers (bypasses the resolver's normal iteration for that zone, but still validates).
- `local-zone:` / `local-data:` -- serve synthetic answers locally without querying upstream; used for internal hostnames, blocking, and split-horizon.
- `remote-control:` -- enable unbound-control socket and TLS credentials.

### DNSSEC validation and trust anchors

Unbound validates DNSSEC by default when `auto-trust-anchor-file` is set. The auto-trust-anchor-file holds the root KSK and is updated via RFC 5011 automatic rollover. Bootstrap the initial file with `unbound-anchor` before starting Unbound the first time. Use `domain-insecure: "example.com"` to disable validation for specific zones with known-broken DNSSEC. Never leave trust anchor files stale; monitor expiry.

### Forward zones vs stub zones

| Directive | Behaviour | When to use |
|---|---|---|
| `forward-zone:` | Sends queries to the listed upstream resolvers; Unbound does NOT recurse from root | Forwarding all or selected queries to a trusted upstream (internal DNS, DoT provider) |
| `stub-zone:` | Sends queries directly to the zone's authoritative servers; Unbound DOES validate DNSSEC | Reaching an internal authoritative server for a split-horizon zone while retaining validation |

A common mistake is using `forward-zone` for an internal zone pointing at an authoritative server that does not validate DNSSEC, then wondering why DNSSEC fails. Use `stub-zone` for internal authoritative servers you want validated.

### local-zone types

| Type | Behaviour | Typical use |
|---|---|---|
| `static` | Returns NXDOMAIN for names not in local-data | Internal hostnames; precise split-horizon |
| `refuse` | Returns REFUSED | Block domains (ad blocking, RPZ-style) |
| `redirect` | Returns the local-data answer for all names under the zone | Redirect entire domain to a landing IP |
| `transparent` | Serves local-data but also recurses for names not matched | Supplement public DNS with private overrides |
| `always_nxdomain` | NXDOMAIN regardless of any match | Unconditional blocking |

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC design, platform selection, and the broader DNS family. The conceptual layer always lives there; this skill is the implementation layer.
- `bind-dns-ops`: BIND as authoritative server; use alongside Unbound in a split authoritative/recursive deployment.
- `powerdns-ops`: PowerDNS Authoritative for database-backed zones; PowerDNS Recursor as an alternative to Unbound.
- `coredns-ops`: CoreDNS for Kubernetes service discovery; a different recursive/forwarding model.
- `multi-vendor-network-ops`: production-change contract (assumptions, pre-checks, execution, post-checks, rollback, escalation). Apply to every unbound.conf change in production, especially trust anchor changes and DoT upstream switchovers.
- `secrets-hygiene`: unbound-control TLS private keys, DoT/DoH certificate private keys, and any TSIG secrets used with stub zones must never be committed to version control or inlined in scripts.
- `utc-timestamps`: trust anchor key timing, serve-expired TTL windows, and DNS query log analysis must be reasoned in UTC.
- `systematic-debugging`: structured fault-isolation for complex Unbound failures (BOGUS DNSSEC from a misbehaving zone, forward loop, validation chain break, cachedb Redis connectivity).

## Red flags

- **Open recursive resolver on the internet.** `access-control: 0.0.0.0/0 allow` turns Unbound into a DNS amplification weapon. Always restrict to internal subnets (`access-control: 10.0.0.0/8 allow`, etc.) and deny everything else.
- **qname-minimisation tradeoffs.** `qname-minimisation: yes` is the correct default for privacy, but some legacy authoritative servers mishandle minimised queries and return SERVFAIL. The safe default, `qname-minimisation-strict: no`, falls back gracefully. Switching to strict mode on a resolver serving production traffic needs validation against the zone population first.
- **Trust-anchor staleness.** The root KSK is updated via RFC 5011 but requires Unbound to be running periodically to track the rollover hold-down timer. An Unbound instance that is shut down for more than 30 days during a root KSK rollover may lose the ability to update its trust anchor automatically. Monitor `unbound-control get_option auto-trust-anchor-file` and run `unbound-anchor -v` to verify trust anchor health.
- **Forwarding with DNSSEC validation mismatch.** When using `forward-zone: name "."` without `forward-tls-upstream`, Unbound forwards in plain DNS and cannot independently validate DNSSEC (it trusts the upstream's DO-bit answers). If DNSSEC is a hard requirement, use full recursion or `forward-tls-upstream` with a validating upstream.
- **rrset-cache-size less than 2x msg-cache-size.** Under-sizing the rrset cache relative to the message cache causes premature RRset evictions, which in turn causes message cache misses and query amplification. Always set `rrset-cache-size` to at least twice `msg-cache-size`.
- **serve-expired without a TTL limit.** `serve-expired: yes` without `serve-expired-ttl` can return arbitrarily stale records indefinitely during upstream outages. Always set `serve-expired-ttl` (86400 seconds is a reasonable ceiling).
- **Pi-hole port conflict.** Pi-hole and Unbound both default to port 53. When co-located, run Unbound on a non-standard port (5335 is conventional) and point Pi-hole upstream to `127.0.0.1#5335`.

## Bottom line

Classify the resolution mode (full recursion vs forwarding), scale, and encrypted-transport requirements before writing any configuration. Load `references/architecture.md` for unbound.conf structure, module pipeline, DNSSEC, forward/stub zones, local-zone, DoT/DoH, and deployment patterns. Load `references/diagnostics.md` for unbound-control, unbound-checkconf, dig-based validation testing, and failure-mode diagnosis. Route all architecture and DNSSEC design decisions to `dns-network-ops`. Treat every production unbound.conf change as a change-controlled operation under the `multi-vendor-network-ops` contract.
