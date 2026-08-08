# Unbound architecture and configuration

## unbound.conf structure

Unbound configuration is organised into named clauses. All clauses are optional except `server:`, which must be present. Clause order does not matter but the conventional order is: `server:`, `remote-control:`, `forward-zone:` / `stub-zone:` entries, `local-zone:` / `local-data:` entries.

### Clause summary

| Clause | Purpose |
|---|---|
| `server:` | Global settings: interfaces, ports, access-control, DNSSEC, cache, privacy, hardening, TLS |
| `remote-control:` | Enables the unbound-control Unix socket or TCP/TLS socket |
| `forward-zone:` | Forward queries for a name (or `.` for all) to specific upstream resolvers |
| `stub-zone:` | Send queries directly to the zone's authoritative servers; keeps DNSSEC validation |
| `local-zone:` | Declare a synthetic zone served locally |
| `local-data:` | Individual records within a local zone |
| `cachedb:` | External cache backend (Redis) configuration |
| `python:` | Python module script path |

### Minimal working configuration

```ini
server:
    interface: 127.0.0.1
    port: 53
    access-control: 127.0.0.0/8 allow
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    hide-identity: yes
    hide-version: yes

remote-control:
    control-enable: yes
    control-interface: /run/unbound.ctl
```

---

## Multi-threaded architecture

```
Client Query
    |
    v
Worker Thread (one per num-threads)
    |
    +-- Module Pipeline: [validator] -> [iterator]
    |
    +-- Shared caches (msg-cache, rrset-cache, infra-cache, key-cache)
```

### Threading model

- `num-threads`: number of worker threads; set to the number of CPU cores.
- Each thread runs an independent iterator state machine for recursive lookups.
- All caches are shared across threads; slabs reduce lock contention.
- `so-reuseport: yes` distributes incoming UDP/TCP sockets across threads for even load.

### Cache hierarchy

| Cache | Contents | Key setting |
|---|---|---|
| msg-cache | Complete DNS responses keyed by question (qname + qtype + qclass) | `msg-cache-size` |
| rrset-cache | Individual RRsets (A, AAAA, CNAME, DNSKEY, RRSIG, etc.) | `rrset-cache-size` (set to 2x msg-cache-size) |
| infra-cache | Per-server RTT, lame status, EDNS capability, historical performance | `infra-cache-numhosts` |
| key-cache | DNSSEC DNSKEY RRsets for validated zones | `key-cache-size` |

Slabs partition each cache to reduce mutex contention. Set slabs to a power of 2 close to `num-threads`:

```ini
msg-cache-slabs: 4
rrset-cache-slabs: 4
infra-cache-slabs: 4
key-cache-slabs: 4
```

### Iterator state machine

The iterator performs recursive resolution:
1. Query root servers for the TLD NS delegation.
2. Query the TLD servers for the domain NS delegation.
3. Query the authoritative server for the final answer.
4. Cache all intermediate results (NS records, glue).
5. Handle CNAME chains, DNAME redirects, and referrals.

Optimisations applied by the iterator:
- **Prefetch**: re-resolves popular entries before TTL expiry (`prefetch: yes`).
- **Qname minimisation**: sends only the minimal label set to each server (RFC 7816).
- **Aggressive NSEC**: uses cached NSEC/NSEC3 records to synthesise negative answers without additional upstream queries (`aggressive-nsec: yes`).

---

## Module pipeline

The module pipeline is configured via `module-config`. The default is `"validator iterator"`.

### validator module

- Verifies DNSSEC signatures (RRSIG) against DNSKEY records.
- Builds the chain of trust: root KSK -> root DNSKEY -> TLD DS -> TLD DNSKEY -> zone DS -> zone DNSKEY.
- Produces one of four results per query: SECURE (valid chain), INSECURE (zone not signed), BOGUS (validation failed), INDETERMINATE (cannot determine).
- Trust anchor: root zone KSK stored in `auto-trust-anchor-file` and updated via RFC 5011.

### iterator module

- Implements the recursive resolution state machine.
- Maintains infra-cache for server selection (lowest RTT, lame detection).
- Handles CNAME and DNAME resolution chains.
- Supports stub-zone and forward-zone overrides for partial recursion.

### Optional modules

```ini
# External Redis cache shared across multiple Unbound instances
module-config: "validator cachedb iterator"

# Response IP policy (block/redirect by answer IP range)
module-config: "respip validator iterator"

# Python-based custom query or response manipulation
module-config: "validator python iterator"
```

#### cachedb module (Redis backend)

```ini
cachedb:
    backend: "redis"
    redis-server-host: 127.0.0.1
    redis-server-port: 6379
    redis-timeout: 100
```

Useful when multiple Unbound instances run behind a load balancer and must share a warm cache. The Redis instance must be secured and co-located or reachable over a trusted network only.

---

## DNSSEC validation

### Trust anchor management

```ini
server:
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
```

- The file holds the IANA root zone KSK.
- RFC 5011 automatic updates are applied while Unbound is running; the hold-down timer is 30 days.
- Bootstrap the initial file before the first start:

```bash
unbound-anchor -a /var/lib/unbound/root.key
chown unbound:unbound /var/lib/unbound/root.key
```

- Verify trust anchor health:

```bash
unbound-anchor -v -a /var/lib/unbound/root.key
```

### Validation process

1. Receive answer from authoritative server (with RRSIG and DNSKEY records via DO-bit query).
2. Retrieve the DNSKEY for the zone (if not already in key-cache).
3. Verify each RRSIG signature covers the answer RRset.
4. Walk the chain of trust from root KSK to the target zone.
5. Mark result as SECURE, INSECURE, BOGUS, or INDETERMINATE.

A BOGUS result causes Unbound to return SERVFAIL to the client. This is the correct behaviour: Unbound refuses to serve data that fails validation rather than pass it through silently.

### Negative trust anchors

Disable validation for a specific zone with known-broken DNSSEC:

```ini
server:
    domain-insecure: "broken-dnssec.example.com"
```

Use sparingly. A negative trust anchor is a permanent exception that bypasses security for the named zone. Document every instance and review periodically.

### Key DNSSEC settings

```ini
server:
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    harden-dnssec-stripped: yes      # reject answers lacking DNSSEC for signed zones
    aggressive-nsec: yes             # synthesise NXDOMAIN from cached NSEC without upstream query
    val-clean-additional: yes        # strip unsigned additional section records
```

---

## Forward zones and stub zones

### forward-zone

Sends queries for the named zone to the listed upstream resolvers instead of recursing from root. Unbound does NOT iterate for forwarded zones; it trusts the upstream's response.

```ini
# Forward all queries to Cloudflare via DoT
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com
    forward-addr: 9.9.9.9@853#dns.quad9.net

# Forward internal domain to corporate DNS (plain DNS)
forward-zone:
    name: "corp.internal."
    forward-addr: 10.0.0.53
    forward-addr: 10.0.0.54

# Forward reverse lookups to internal DNS
forward-zone:
    name: "10.in-addr.arpa."
    forward-addr: 10.0.0.53
```

The `@853#hostname` syntax sets the TLS port and the SNI/certificate verification hostname. Without the `#hostname` part, Unbound cannot verify the upstream TLS certificate.

DNSSEC caveat: when forwarding (not recursing), Unbound cannot independently validate DNSSEC unless the upstream returns signed responses and sets the AD bit. For strict DNSSEC, use full recursion (no root forward-zone) or `forward-tls-upstream` to a validating upstream you control.

### stub-zone

Sends queries directly to the zone's authoritative servers. Unbound DOES recurse and validate DNSSEC for stub zones. Use for internal authoritative servers in a split-horizon deployment.

```ini
stub-zone:
    name: "internal.example.com."
    stub-addr: 10.0.0.10
    stub-addr: 10.0.0.11
    stub-no-cache: no    # cache answers (default)
```

Forward zone vs stub zone decision:
- `forward-zone`: trust the upstream; delegation to a trusted forwarder or DoT provider.
- `stub-zone`: go direct to the zone's authoritative servers; keep DNSSEC validation; use for split-horizon internal zones.

---

## access-control

Defines which clients may submit queries. The default is to deny all. List permits before the implicit final deny.

```ini
server:
    access-control: 127.0.0.0/8 allow
    access-control: 10.0.0.0/8 allow
    access-control: 192.168.0.0/16 allow
    access-control: 172.16.0.0/12 allow
    access-control: 0.0.0.0/0 deny
```

Never set `access-control: 0.0.0.0/0 allow` on a resolver reachable from the internet. Open resolvers are abused for DNS amplification attacks.

---

## Cache settings: prefetch, serve-expired, TTL floors and ceilings

```ini
server:
    # Cache sizes (rrset should be 2x msg)
    msg-cache-size: 128m
    rrset-cache-size: 256m

    # TTL controls
    cache-min-ttl: 60          # floor: never cache for less than 60 seconds
    cache-max-ttl: 86400       # ceiling: never cache for more than 24 hours

    # Prefetch: re-resolve popular entries before TTL expiry to prevent cache misses
    prefetch: yes
    prefetch-key: yes          # prefetch DNSKEY records for DNSSEC-signed zones

    # Serve expired: return stale records during upstream outages
    serve-expired: yes
    serve-expired-ttl: 86400   # max stale age; always set this
    serve-expired-ttl-reset: yes  # reset stale TTL when a fresh answer is received
```

`prefetch: yes` reduces cache-miss latency at the cost of slightly increased query volume to authoritative servers. Enable it on resolvers with a warm cache (campus scale and above).

`serve-expired: yes` keeps DNS resolution functional during upstream outages by returning cached-but-expired records. Without `serve-expired-ttl`, records can be served stale indefinitely; always cap stale age.

---

## Encrypted DNS (DoT and DoH)

### DoT incoming server (clients connect to Unbound via TLS on port 853)

```ini
server:
    interface: 0.0.0.0@853
    tls-port: 853
    tls-service-key: "/etc/unbound/server.key"
    tls-service-pem: "/etc/unbound/server.pem"
```

Protect the private key file per `secrets-hygiene`: mode 0600, owner unbound, not committed to version control.

### DoH incoming server (clients connect to Unbound via HTTPS on port 443, Unbound 1.17+)

```ini
server:
    interface: 0.0.0.0@443
    https-port: 443
    tls-service-key: "/etc/unbound/server.key"
    tls-service-pem: "/etc/unbound/server.pem"
    http-endpoint: "/dns-query"
    http-notls-downstream: no    # require TLS (default; do not disable in production)
```

Full encrypted path: clients query Unbound via DoH on port 443; Unbound forwards upstream via DoT with `forward-tls-upstream: yes`.

### DoT upstream forwarding

```ini
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com
    forward-addr: 9.9.9.9@853#dns.quad9.net
```

---

## local-zone and local-data

local-zone declares a synthetic DNS zone served by Unbound directly, without querying upstream. local-data adds individual records within that zone.

### local-zone types

| Type | Behaviour | Typical use |
|---|---|---|
| `static` | Returns NXDOMAIN for names not matched by local-data | Internal hostnames; split-horizon precision |
| `refuse` | Returns REFUSED (policy rejection) | Block domains; ad blocking |
| `redirect` | Returns local-data answer for ANY name under the zone | Redirect entire domain (NXDOMAIN redirect, landing page) |
| `transparent` | Serves local-data; recurses for names without a local match | Private overrides layered on public DNS |
| `always_nxdomain` | Returns NXDOMAIN unconditionally | Unconditional blocking regardless of local-data |
| `nodefault` | Removes the built-in private-address reverse zones | Use with caution; needed when serving custom reverse zones |

### Examples

```ini
# Internal hostname resolution
local-zone: "home.lab." static
local-data: "server1.home.lab. IN A 10.0.0.10"
local-data: "server1.home.lab. IN AAAA fd00::10"
local-data: "10.0.0.10.in-addr.arpa. IN PTR server1.home.lab."

# Block an ad or tracking domain
local-zone: "ads.example.com." refuse

# Redirect entire domain to a block page
local-zone: "malware.example.net." redirect
local-data: "malware.example.net. IN A 10.0.0.1"

# Override a single name while recursing for the rest of the zone
local-zone: "example.com." transparent
local-data: "internal.example.com. IN A 10.0.1.50"
```

For large blocking lists, consider the `rpz` module (available in Unbound 1.16+) or a dedicated RPZ feed rather than hundreds of individual `local-zone` / `local-data` lines.

---

## Privacy hardening

```ini
server:
    # Identity and version disclosure
    hide-identity: yes
    hide-version: yes
    identity: ""

    # Qname minimisation (RFC 7816): send only the minimum required labels to each server
    qname-minimisation: yes
    # Set to "no" to allow fallback for legacy authoritative servers that reject minimised queries
    # The default "no" (non-strict) is correct for general use
    qname-minimisation-strict: no

    # 0x20 encoding: randomise case in outgoing queries to defend against cache poisoning
    use-caps-for-id: yes

    # Harden against out-of-zone data in additional sections
    harden-glue: yes
    harden-below-nxdomain: yes
    harden-dnssec-stripped: yes

    # Disable EDNS Client Subnet by default (do not leak client subnet to upstream)
    send-client-subnet: 0.0.0.0/0
    client-subnet-always-forward: no
```

---

## Performance tuning

### Thread and cache sizing by scale

| Deployment | Clients | num-threads | msg-cache-size | rrset-cache-size |
|---|---|---|---|---|
| Home / lab | 1-10 | 1-2 | 8m | 16m |
| Small office | 10-100 | 2-4 | 32m | 64m |
| Campus | 100-1000 | 4-8 | 128m | 256m |
| ISP-scale | 1000+ | 8-16 | 512m | 1g |

### Key performance parameters

| Parameter | Default | Recommendation |
|---|---|---|
| `num-threads` | 1 | Set to CPU core count |
| `so-reuseport` | no | Enable; distributes sockets across threads |
| `outgoing-range` | 4096 | Increase for high-query-rate deployments (8192+) |
| `num-queries-per-thread` | 1024 | Increase proportionally with outgoing-range |
| `msg-cache-slabs` | 4 | Power of 2, close to num-threads |
| `rrset-cache-slabs` | 4 | Match msg-cache-slabs |
| `infra-cache-slabs` | 4 | Match msg-cache-slabs |
| `key-cache-slabs` | 4 | Match msg-cache-slabs |
| `prefetch` | no | Enable for campus scale and above |
| `cache-min-ttl` | 0 | 60s prevents excessive query amplification for low-TTL records |

### Complete performance block (campus scale)

```ini
server:
    num-threads: 4
    so-reuseport: yes
    outgoing-range: 8192
    num-queries-per-thread: 4096

    msg-cache-size: 128m
    rrset-cache-size: 256m
    msg-cache-slabs: 4
    rrset-cache-slabs: 4
    infra-cache-slabs: 4
    key-cache-slabs: 4

    prefetch: yes
    prefetch-key: yes
    cache-min-ttl: 60
    cache-max-ttl: 86400
    serve-expired: yes
    serve-expired-ttl: 86400
```

---

## remote-control (unbound-control)

### Configuration

```ini
remote-control:
    control-enable: yes
    control-interface: /run/unbound.ctl   # Unix socket (preferred; no TLS overhead)
    # For TCP/TLS remote control:
    # control-interface: 127.0.0.1
    # control-port: 8953
    # control-use-cert: yes
    # server-key-file: "/etc/unbound/unbound_server.key"
    # server-cert-file: "/etc/unbound/unbound_server.pem"
    # control-key-file: "/etc/unbound/unbound_control.key"
    # control-cert-file: "/etc/unbound/unbound_control.pem"
```

Protect the control socket: set mode 0660, owned by root:unbound, so only the unbound group can access it. Never expose TCP/TLS remote control to untrusted networks.

### Key unbound-control commands

```bash
unbound-control status            # Unbound version and uptime
unbound-control reload            # Reload configuration (no restart needed)
unbound-control stats_noreset     # Query statistics (counters not cleared)
unbound-control stats             # Query statistics (clears counters)
unbound-control dump_cache        # Dump entire cache to stdout
unbound-control flush example.com # Remove example.com from cache (all types)
unbound-control flush_zone corp.internal. # Remove all records for zone
unbound-control lookup www.example.com    # Look up a name in the cache
unbound-control list_forwards     # List configured forward zones
unbound-control list_stubs        # List configured stub zones
unbound-control list_local_zones  # List local zones
unbound-control list_local_data   # List local data entries
unbound-control get_option prefetch       # Query a running option
```

---

## Deployment patterns

### Standalone recursive resolver (maximum privacy and DNSSEC integrity)

Full recursion from root servers. No forward-zone for `.`. Unbound validates DNSSEC independently.

```ini
server:
    interface: 0.0.0.0
    port: 53
    access-control: 10.0.0.0/8 allow
    access-control: 192.168.0.0/16 allow
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    harden-dnssec-stripped: yes
    prefetch: yes
    serve-expired: yes
    serve-expired-ttl: 86400

remote-control:
    control-enable: yes
    control-interface: /run/unbound.ctl
```

No `forward-zone:` clause means Unbound iterates from root for all queries.

### Forwarder to trusted upstream via DoT

Simple forwarding model. DNSSEC validation relies on upstream's AD-bit assertion unless `forward-tls-upstream` is used with a validating provider.

```ini
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 9.9.9.9@853#dns.quad9.net
```

### Pi-hole + Unbound stack

Pi-hole handles ad and tracker blocking. Unbound performs full recursive resolution with DNSSEC. No external forwarding needed.

```
Client -> Pi-hole (port 53, ad filtering) -> Unbound (port 5335, full recursion + DNSSEC)
                                                  |
                                              Root -> TLD -> Authoritative
```

Unbound configuration for Pi-hole upstream:

```ini
server:
    interface: 127.0.0.1
    port: 5335
    do-not-query-localhost: no        # allow forwarding back to localhost
    access-control: 127.0.0.0/8 allow
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    # Do NOT add forward-zone for "."; full recursion only
```

Pi-hole custom upstream: `127.0.0.1#5335`.

### OPNsense and pfSense

Unbound is the default DNS resolver on both platforms since OPNsense 17.7.

- OPNsense: Services > Unbound DNS > General (enable, interfaces, access networks). DoT upstream via Services > Unbound DNS > DNS over TLS. Advanced settings via the "Custom options" text box.
- pfSense: Services > DNS Resolver. Host overrides map to local-data. Advanced options for custom directives.
- Custom options written in the GUI "Custom options" field persist across upgrades. Direct edits to the generated unbound.conf may be overwritten on upgrade; use the GUI field instead.

### Clustered with Redis cache

Multiple Unbound instances behind a load balancer sharing a Redis cache via the cachedb module. Improves cache hit rate across instances. Requires a secured and co-located Redis instance.

```ini
module-config: "validator cachedb iterator"

cachedb:
    backend: "redis"
    redis-server-host: 127.0.0.1
    redis-server-port: 6379
    redis-timeout: 100
```

---

## Common pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| rrset-cache-size less than 2x msg-cache-size | Cache evictions, query amplification, lower hit rate | Set rrset-cache-size to at least 2x msg-cache-size |
| Forwarding without full DNSSEC validation | DNSSEC-signed zones resolve but AD bit not set or validation fails | Use full recursion or forward-tls-upstream to a validating upstream you trust |
| serve-expired without serve-expired-ttl | Arbitrarily stale records returned indefinitely during outages | Always set serve-expired-ttl (86400 is a reasonable ceiling) |
| Pi-hole and Unbound both on port 53 | Port conflict; one service fails to start | Run Unbound on port 5335; point Pi-hole upstream to 127.0.0.1#5335 |
| qname-minimisation-strict: yes on production | Some old authoritative servers return SERVFAIL for minimised queries | Keep qname-minimisation-strict: no (the default), which falls back gracefully |
| OPNsense custom options overwritten on upgrade | Custom resolver settings lost after upgrade | Use the GUI "Custom options" field, not direct edits to the generated file |
| Trust anchor file stale after extended downtime | BOGUS results for all DNSSEC-signed zones | Run unbound-anchor -v to re-bootstrap; restart Unbound |
| Open access-control | Resolver used as amplification weapon | Restrict to internal subnets; explicit deny for 0.0.0.0/0 |
