---
name: powerdns-ops
description: "Use for PowerDNS implementation, configuration, and operations: PowerDNS Authoritative Server (backends gmysql/gpgsql/gsqlite3/gldap/bind/pipe/remote, REST API zone management, DNSSEC with pdnsutil, views for split-horizon, Lua scripting hooks), PowerDNS Recursor (YAML configuration, DNSSEC validation, RPZ threat blocking, serve-stale, conditional forwarding, rec_control), and DNSdist (load balancing, DoH/DoT/DoQ termination, rules engine, DDoS protection, dnsdist Defender). References: architecture.md, diagnostics.md. Triggers include \"PowerDNS\", \"pdns\", \"pdnsutil\", \"pdns_control\", \"PowerDNS Recursor\", \"rec_control\", \"gmysql backend\", \"gpgsql\", \"gsqlite3\", \"PowerDNS API\", \"dnsdist\", \"supermaster\", \"autoprimary\", \"pdns.conf\", \"PowerDNS backend\", \"PowerDNS DNSSEC\", \"pdnsutil secure-zone\", \"PowerDNS Authoritative\", \"PowerDNS views\", \"PowerDNS Lua\", \"DNSdist rules\", \"DNSdist Defender\", \"RPZ PowerDNS\". For DNS architecture, DNSSEC design, zone-transfer concepts, and cross-platform comparison see dns-network-ops."
license: MIT
metadata:
  version: 1.0.0
---

# PowerDNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: powerdns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

PowerDNS is a suite of three separate products with distinct roles: the Authoritative Server (answers queries for zones it hosts), the Recursor (performs recursive resolution for clients), and DNSdist (load balancer and protocol frontend). Never combine authoritative and recursive concerns in the same PowerDNS instance; use DNSdist to present both behind a single IP. This skill covers implementation, configuration, and operations for all three. For DNS architecture, DNSSEC design, and cross-platform comparison use `dns-network-ops`.

## When to use

- Configuring or troubleshooting the PowerDNS Authoritative Server: backend selection (gmysql, gpgsql, gsqlite3, gldap, bind, pipe, remote), zone management via pdnsutil or the REST API, DNSSEC operations, views, Lua hooks.
- Configuring or troubleshooting PowerDNS Recursor: YAML config, DNSSEC validation, RPZ threat feeds, serve-stale, conditional forwarding, Lua scripting.
- Deploying or tuning DNSdist: load balancing policies, DoH/DoT/DoQ termination, rules engine, rate limiting, DDoS protection, health checks, metrics.
- Investigating PowerDNS-specific failures: wrong backend responding, DNSSEC signing not applied, RPZ feed not loaded, DNSdist health-check false negatives.
- Automating zone management via the PowerDNS REST API or pdnsutil in scripts or pipelines.

## When not to use

- **DNS architecture, DNSSEC chain-of-trust design, zone-transfer concepts, cross-platform comparison**: use `dns-network-ops`.
- **Pure recursive-resolver tuning on non-PowerDNS software (Unbound, systemd-resolved, dnsmasq)**: use `unbound-dns-ops` or the relevant skill.
- **BIND named.conf, views in BIND, KASP DNSSEC in BIND**: use `bind-dns-ops`.
- **SQL backend schema design, query performance, replication beyond DNS**: use `postgres-best-practices` or `mysql-best-practices`.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Product architecture and configuration | Suite overview (Auth/Recursor/DNSdist roles), backend details (gmysql/gpgsql/gsqlite3/gldap/bind/pipe/remote), DNSSEC implementation (pdnsutil, key storage, algorithms, NSEC3), REST API endpoints, Lua hooks, views, Recursor YAML config, RPZ implementation, DNSdist load-balancing policies, DoH/DoT/DoQ frontend, rules engine, deployment patterns | `references/architecture.md` |
| Operations and diagnostics | pdns_control commands, pdnsutil diagnostics, rec_control commands, dnsdist console, metrics and monitoring (Prometheus, Carbon/Graphite), common failure patterns with diagnosis and resolution, health-check tuning | `references/diagnostics.md` |

## Key concepts (quick orientation)

**Three products, three binaries, three configs.** The Authoritative Server (`pdns_server`, config `pdns.conf`) and the Recursor (`pdns_recursor`, config `recursor.conf` or YAML) are separate packages that must not be mixed. DNSdist sits in front of both, routing queries by zone ownership.

**Backends are pluggable.** The Authoritative Server stores zone data in the configured backend; it does not use zone files by default (the `bind` backend enables file-based storage for legacy compatibility). The gmysql and gpgsql backends use a fixed schema (`domains`, `records`, `domainmetadata`, `cryptokeys` tables).

**DNSSEC is online signing.** Zone data is stored unsigned; the Authoritative Server signs at query time using key material from the `cryptokeys` table. `pdnsutil secure-zone` generates the keys; the DS record must then be published at the parent registrar separately.

**The REST API enables full automation.** All zone and record CRUD is available via HTTP on port 8081 (default) with an `X-API-Key` header. This is the preferred path for Infrastructure-as-Code and pipeline-driven DNS management.

## Authoritative Server: core tasks

### Enable the API

```ini
# pdns.conf
api=yes
api-key=changeme                         # store in vault, never plaintext
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=10.0.0.0/8
```

Protect the API key with `secrets-hygiene`; it grants full zone write access.

### Zone management via pdnsutil

```bash
pdnsutil create-zone example.com ns1.example.com
pdnsutil add-record example.com www A 300 10.1.1.1
pdnsutil list-zone example.com
pdnsutil secure-zone example.com          # enables DNSSEC; then publish DS at parent
pdnsutil show-zone example.com            # shows DS hash to submit to registrar
pdnsutil rectify-zone example.com         # fixes NSEC/NSEC3 ordering after bulk edits
pdnsutil increase-serial example.com      # bump SOA serial to trigger NOTIFY
```

### Zone management via the REST API

```bash
# Create zone
curl -X POST http://localhost:8081/api/v1/servers/localhost/zones \
  -H "X-API-Key: $PDNS_API_KEY" \
  -d '{"name":"example.com.","kind":"Native","nameservers":["ns1.example.com."]}'

# Replace an A record
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: $PDNS_API_KEY" \
  -d '{"rrsets":[{"name":"www.example.com.","type":"A","ttl":300,
       "changetype":"REPLACE","records":[{"content":"10.1.1.1","disabled":false}]}]}'

# Trigger NOTIFY to secondaries
curl -X PUT http://localhost:8081/api/v1/servers/localhost/zones/example.com./notify \
  -H "X-API-Key: $PDNS_API_KEY"
```

## Recursor: core tasks

### YAML configuration (Recursor 5.2+)

```yaml
incoming:
  listen: ["0.0.0.0:53", "[::]:53"]
  allow_from: ["127.0.0.0/8", "10.0.0.0/8"]   # never open to internet

dnssec:
  validate: validate                             # strict; BOGUS = SERVFAIL

forwarding:
  zones:
    - zone: internal.corp
      recurse: false
      forwarders: ["10.0.0.53"]

rpz:
  - name: threat-feed
    url: https://rpz.provider.com/feed.zone
    defpol: Policy.NXDOMAIN
    refresh: 300

cache:
  serve_expired: true
  serve_expired_ttl: 86400
```

### RPZ threat blocking

Multiple feeds load in priority order. Actions per match: NXDOMAIN, NODATA, DROP, PASSTHRU, CNAME redirect. Enable `servfail-until-ready` to block unprotected queries while feeds load on startup.

## DNSdist: core tasks

DNSdist 2.0 supports YAML configuration alongside the traditional Lua config; choose one format per deployment and do not mix them. Load-balancing policies include `leastOutstanding` (default), `wrandom`, `roundrobin`, `firstAvailable`, and `chashed` (consistent hash on query name).

```yaml
# dnsdist.yml (2.0)
listen_addresses: ["0.0.0.0:53", "0.0.0.0:853", "0.0.0.0:443"]

backends:
  - address: "192.168.1.10:53"
    name: "pdns-auth"
  - address: "192.168.1.20:53"
    name: "pdns-recursor"

policy: "leastOutstanding"

tls:
  certificates:
    - cert: "/etc/ssl/dns.pem"
      key: "/etc/ssl/dns.key"

doh:
  paths: ["/dns-query"]
```

Route internal-zone queries to Auth and all other queries to Recursor using `SuffixMatchNodeRule` and `PoolAction` in the rules engine.

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC chain-of-trust design, zone-transfer concepts (AXFR/IXFR/NOTIFY/TSIG), cross-platform comparison, and platform selection.
- `multi-vendor-network-ops`: production-change contract (assumptions, risk, evidence, pre-checks, execution, post-checks, rollback, escalation) applies to zone-schema migrations, DNSSEC key rollovers, and TTL changes.
- `secrets-hygiene`: the PowerDNS API key (`X-API-Key`), DNSSEC private keys in the `cryptokeys` table, TSIG keys for zone transfers, and RPZ feed authentication credentials must all follow vault hygiene; never commit to source control.
- `postgres-best-practices`: gpgsql backend schema management, connection pooling, replication-aware read/write routing, index tuning for the `records` table.
- `mysql-best-practices`: gmysql backend schema management, replication setup, connection pool sizing, schema migration scripts (Auth 5.0 requires a schema update from 4.x).
- `utc-timestamps`: SOA serials (YYYYMMDDnn convention), DNSSEC key timing (publish/activate/retire), and query log timestamps must be reasoned about in UTC.
- `systematic-debugging`: structured fault isolation when PowerDNS behaves unexpectedly; start with `pdns_control show *` or `rec_control get-all` to establish a baseline before changing config.
- `oncall-runbooks`: DNS incident response; DNSSEC rollover failure, RPZ feed outage, backend connectivity loss, and DNSdist backend-pool exhaustion are runbook-grade events.

## Red flags

- **Open Recursor on the internet.** The `allow_from` ACL in the Recursor MUST restrict query sources to internal networks. An open resolver becomes a DNS amplification weapon; there is no valid exception.
- **DNSSEC without DS at parent.** `pdnsutil secure-zone` signs the zone locally. Until the DS record is published at the parent registrar, external resolvers see the zone as unsigned. The signed zone then becomes BOGUS when a resolver validates.
- **Mixing Auth and Recursor on the same port.** The Authoritative Server and Recursor are separate binaries. Configuring recursion on the Auth server or hosting authoritative zones on the Recursor is unsupported and produces unpredictable query behaviour.
- **gmysql/gpgsql schema migration skipped.** Auth 5.0 requires schema changes from 4.x. Running a 5.0 binary against a 4.x schema produces silent data errors; always run the migration script before upgrading the daemon.
- **RPZ startup race.** Recursor may serve unprotected queries before RPZ feeds finish loading. Enable `servfail-until-ready` when RPZ enforcement is security-critical.
- **DNSdist YAML and Lua config mixed.** DNSdist 2.0 supports both formats; choose one per deployment. A mixed deployment produces configuration parse errors or silently ignores one layer.
- **DNSSEC key rollover without monitoring.** Auto ZSK rollover handles timing, but KSK rollover requires manual DS publication at the parent. Monitor key validity and parent DS synchronisation; desynchronisation causes total zone DNSSEC validation failure.

## Bottom line

Classify the request by product first (Authoritative, Recursor, or DNSdist), then by concern (backend, DNSSEC, API, Lua, monitoring). Load `references/architecture.md` for configuration depth and deployment patterns; load `references/diagnostics.md` for command references, metrics interpretation, and failure diagnosis. Treat DNSSEC key rollovers, backend schema migrations, and TTL changes as change-controlled operations under the `multi-vendor-network-ops` contract. Keep the API key and all DNSSEC private key material out of source control under `secrets-hygiene`.
