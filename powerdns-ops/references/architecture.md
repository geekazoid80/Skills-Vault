# PowerDNS architecture

## Suite overview

PowerDNS consists of three separate products with distinct roles. Never run them as a combined process; each is a separate binary with its own configuration file.

```
                                    +----------------------+
                                    |  PowerDNS Auth 5.0   |
                                    |  (Authoritative)     |
                     +----------->  |  gmysql/gpgsql/...   |
                     |              +----------------------+
+----------------+   |
|  DNSdist 2.0   |---+
|  (Frontend LB) |   |              +----------------------+
|  DoH/DoT/DoQ   |   +----------->  |  PowerDNS Recursor   |
+----------------+                  |  5.4 (Recursive)     |
                                    |  DNSSEC/RPZ/Lua      |
                                    +----------------------+
```

| Product | Binary | Config file | Role |
|---|---|---|---|
| Authoritative Server 5.0 | `pdns_server` | `pdns.conf` | Answers queries for hosted zones; never recurses |
| Recursor 5.4 | `pdns_recursor` | `recursor.conf` or YAML | Performs recursive resolution; never hosts zones |
| DNSdist 2.0 | `dnsdist` | Lua or YAML | Frontend load balancer; protocol termination (DoH/DoT/DoQ); DDoS protection |

DNSdist routes queries by zone ownership: queries for zones hosted on the Auth Server go to Auth; all other queries go to the Recursor. This is the standard single-IP deployment pattern.

## Authoritative Server 5.0

### Internal architecture

```
Query -> Receiver threads -> Distributor threads -> Backend worker -> Packet cache -> Response
                                                         |
                              +--------------------------+
                              |
                    +---------+----------+
                    |                    |
               [gmysql]             [gpgsql]
               MariaDB/MySQL        PostgreSQL
```

- **Receivers**: packet I/O threads; handle incoming UDP/TCP query distribution.
- **Distributors**: route queries to backend worker threads.
- **Packet cache**: per-answer cache keyed on the full question section; serves repeated identical queries without backend round-trips.
- **Query cache**: caches backend query results (zone lookups); separate from the packet cache.

### Backend details

#### gmysql (MySQL / MariaDB)

Most commonly used production backend.

Schema tables: `domains`, `records`, `domainmetadata`, `cryptokeys`.

Key config options:

```ini
launch=gmysql
gmysql-host=127.0.0.1
gmysql-port=3306
gmysql-dbname=pdns
gmysql-user=pdns
gmysql-password=secret                    # use secrets-hygiene; never plaintext in conf
gmysql-max-connections=5
```

Replication-aware usage: configure a read replica for query-time record lookups and the primary for writes via the REST API or pdnsutil. The `records` table is the hot path; index on `(domain_id, name, type)` is critical for performance.

Schema migration from Auth 4.x to 5.0 is required; run the bundled migration script before starting the 5.0 daemon.

#### gpgsql (PostgreSQL)

Same schema concept as gmysql with PostgreSQL syntax.

Notable: gpgsql supports `LISTEN/NOTIFY` for instant zone-change propagation between PowerDNS instances without polling. When the primary writes a record change, PostgreSQL broadcasts a notification; secondary Auth instances reload the affected zone immediately.

```ini
launch=gpgsql
gpgsql-host=127.0.0.1
gpgsql-dbname=pdns
gpgsql-user=pdns
gpgsql-password=secret
```

#### gsqlite3 (SQLite3)

Single-file database; no daemon required. Suitable for development, CI testing, or small low-traffic deployments. Not recommended for production under significant query load (file locking under concurrent writers is a bottleneck).

```ini
launch=gsqlite3
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
```

#### gldap (LDAP)

Maps DNS records to LDAP directory entries. Used in ISP and hosting environments with existing LDAP infrastructure where DNS records are managed as directory objects alongside user and host records.

#### bind (zone files)

Reads RFC-compliant zone files and a `named.conf`-style zone declaration file. Used for legacy compatibility when migrating from BIND or when zone files are managed by an external toolchain.

```ini
launch=bind
bind-config=/etc/powerdns/named.conf
```

Note: the `bind` backend in PowerDNS is read-only for zone files by default. Zone modifications via pdnsutil or the REST API require a read-write backend (gmysql, gpgsql, etc.).

#### pipe (external process)

Pipes DNS queries to an external process via stdin/stdout using a tab-separated question/answer protocol. Enables custom resolution logic in any language. Suitable for highly dynamic or computed records.

#### remote (JSON over HTTP or Unix socket)

Sends queries to an external HTTP service or Unix socket as JSON. Use for integration with external databases, APIs, or custom resolvers that do not fit the SQL schema.

### DNSSEC implementation

PowerDNS uses online signing: zone data is stored unsigned in the backend; the Auth Server signs records at query time using key material from the `cryptokeys` table.

#### pdnsutil key management commands

```bash
pdnsutil secure-zone example.com              # generate KSK + ZSK, enable signing
pdnsutil set-nsec3 example.com '1 0 1 -' optout  # switch to NSEC3 (opt-out mode)
pdnsutil unset-nsec3 example.com              # revert to NSEC (enumeratable; smaller zone)
pdnsutil show-zone example.com                # display DNSKEY records and DS hashes
pdnsutil add-zone-key example.com ksk 256 active ecdsa256  # add explicit key
pdnsutil activate-zone-key example.com <id>   # activate a key by ID
pdnsutil deactivate-zone-key example.com <id> # deactivate without removing
pdnsutil remove-zone-key example.com <id>     # permanently delete key
pdnsutil rectify-zone example.com             # rebuild NSEC/NSEC3 chain after bulk edits
```

#### Algorithm support

| Algorithm | Identifier | Notes |
|---|---|---|
| ED25519 | ecdsa256-equivalent label | Recommended; fast, small signatures |
| ED448 | | Larger signatures; niche use |
| ECDSA P-256 | ecdsa256 | Widely supported; good default |
| ECDSA P-384 | ecdsa384 | Stronger; larger signatures |
| RSA 2048+ | | Legacy; avoid for new deployments |

#### Key rollover

- **ZSK rollover**: automated by the Auth Server based on configured timing; no operator intervention required.
- **KSK rollover**: semi-automated. The operator runs `pdnsutil add-zone-key example.com ksk active ecdsa256` to generate a new KSK, then submits the new DS hash (from `pdnsutil show-zone`) to the parent registrar, then retires the old KSK after the DS propagates. Monitor parent DS synchronisation before retiring.

#### NSEC vs NSEC3

- **NSEC**: authenticated denial of existence; enumerates zone contents (zone walking possible).
- **NSEC3**: hashes owner names; prevents zone walking. Use for public-facing zones where enumeration is a concern. The opt-out flag skips signing of unsigned delegations (common in large TLD-style zones).

### REST API

Base URL: `http://<server>:8081/api/v1/servers/localhost/`

Authentication: `X-API-Key: <key>` header. Enable in `pdns.conf` with `api=yes` and `api-key=<secret>`.

| Method | Endpoint | Action |
|---|---|---|
| GET | `/zones` | List all zones |
| POST | `/zones` | Create zone |
| GET | `/zones/{zone}` | Get zone details and all records |
| PATCH | `/zones/{zone}` | Add, modify, or delete record sets |
| DELETE | `/zones/{zone}` | Delete zone |
| PUT | `/zones/{zone}/notify` | Send NOTIFY to all configured secondaries |
| PUT | `/zones/{zone}/axfr-retrieve` | Retrieve zone via AXFR (slave/secondary mode) |
| GET | `/zones/{zone}/cryptokeys` | List DNSSEC keys for zone |
| POST | `/zones/{zone}/cryptokeys` | Add DNSSEC key |
| DELETE | `/zones/{zone}/cryptokeys/{id}` | Remove DNSSEC key |

The PATCH endpoint uses `rrsets` with `changetype: REPLACE` or `DELETE`. A REPLACE on an existing rrset overwrites all records of that type at that name; it is not an additive update.

### Lua scripting hooks (Auth)

Hook functions are defined in a Lua script referenced from `pdns.conf` via `lua-prequery-script=`.

| Hook | Timing | Use case |
|---|---|---|
| `preresolve` | Before backend lookup | Intercept, redirect, or short-circuit queries |
| `postresolve` | After backend, before response | Modify or filter answer records |
| `preaxfr` | Before outbound AXFR transfer | Filter zone transfer content per secondary |
| `nodata` | Backend returned no records for name | Synthesise NODATA responses |
| `nxdomain` | Zone or name not found | Custom NXDOMAIN handling (walled garden, logging) |

Example: geo-based A record response:

```lua
function preresolve(dq)
    if dq.qname:equal(newDN("geo.example.com")) then
        if dq.remoteaddr:isPartOf(newNMG({"10.0.0.0/8"})) then
            dq:addAnswer(pdns.A, "10.1.1.1", 60)
        else
            dq:addAnswer(pdns.A, "203.0.113.1", 60)
        end
        return true
    end
    return false
end
```

### Views (Auth 5.0)

Views enable split-horizon DNS on the Authoritative Server: different responses for different client source networks, backed by different databases or different records in the same database.

```yaml
views:
  internal:
    networks: [10.0.0.0/8, 192.168.0.0/16]
    zones:
      - name: example.com
        backend: gmysql
        database: internal_db
  external:
    networks: [0.0.0.0/0]
    zones:
      - name: example.com
        backend: gmysql
        database: external_db
```

Views are evaluated in order; first match wins. Each view can specify a different backend instance, a different database within the same backend type, or different zone metadata.

### Zone transfer (AXFR/IXFR and supermaster/autoprimary)

For secondary zones, the Authoritative Server can retrieve zones via AXFR/IXFR from a primary. The supermaster/autoprimary feature automates secondary provisioning: when the primary notifies a secondary about a new zone, the secondary queries the primary's NS records, matches against a configured supermaster entry, and provisions the zone automatically.

```ini
# pdns.conf on secondary
autosecondary=yes

# Add the primary as a supermaster in the database
# INSERT INTO supermasters VALUES ('10.0.0.100', 'ns1.example.com', 'admin');
```

Restrict inbound AXFR with `allow-axfr-ips`; restrict outbound NOTIFY with `only-notify`.

## Recursor 5.4

### Internal architecture

```
Query -> Receiver threads -> MTasker (cooperative threads) -> Iterator (recursive resolution)
                                      |                             |
                                 [Cache]                       [RPZ engine]
                                 (DNSSEC-aware                 (policy feeds)
                                  response cache)
```

- **MTasker**: cooperative multithreading; each in-flight query is a lightweight task.
- **Iterator**: recursive resolution state machine; follows referrals from root to TLD to authoritative.
- **Cache**: stores resolved answers with DNSSEC status flags; serves repeated queries without re-resolution.
- **RPZ engine**: evaluates each query and response against loaded policy feeds.

### YAML configuration (Recursor 5.2+ recommended)

```yaml
incoming:
  listen: ["0.0.0.0:53", "[::]:53"]
  allow_from: ["127.0.0.0/8", "10.0.0.0/8"]   # never expose to internet

outgoing:
  source_address: ["0.0.0.0"]

dnssec:
  validate: validate                             # off | process | log-fail | validate

forwarding:
  zones:
    - zone: "."                                  # forward everything (resolver-as-forwarder)
      forwarders: ["8.8.8.8", "1.1.1.1"]
    - zone: internal.corp
      recurse: false
      forwarders: ["10.0.0.53"]

cache:
  max_cache_entries: 1000000
  max_negative_ttl: 3600
  serve_expired: true
  serve_expired_ttl: 86400                       # serve stale cache during upstream outages

rpz:
  - name: threat-feed
    url: https://rpz.provider.com/feed.zone
    defpol: Policy.NXDOMAIN
    refresh: 300

logging:
  loglevel: 4                                    # 0=none ... 6=debug
```

### DNSSEC validation

Modes, from least to most strict:

| Mode | Behaviour |
|---|---|
| `off` | No validation; DNSSEC records ignored |
| `process` | Validate if possible; log failures; return answer regardless |
| `log-fail` | Same as process but failures are logged prominently |
| `validate` | Strict; BOGUS responses returned as SERVFAIL to clients |

Built-in root zone trust anchors (IANA root KSK) with automatic RFC 5011 sentinel updates. Negative trust anchors can disable validation per-domain for known-broken DNSSEC deployments.

### RPZ implementation

Multiple RPZ feeds load simultaneously in priority order. Feed sources: AXFR/IXFR from a primary nameserver, HTTP/HTTPS download, or local zone file.

Actions per match:

| Action | Behaviour |
|---|---|
| NXDOMAIN | Return NXDOMAIN (blocked domain does not exist) |
| NODATA | Return NODATA (name exists but no records) |
| DROP | Silently discard query (no response to client) |
| PASSTHRU | Explicitly bypass RPZ for this match (whitelist) |
| CNAME redirect | Redirect to a walled-garden IP or page |

Trigger types: `qname` (query name), `client-ip` (source IP), `response-ip` (IP in answer), `nsdname` (nameserver name), `nsip` (nameserver IP).

`servfail-until-ready=yes`: returns SERVFAIL for all queries until all RPZ feeds have loaded. Use when RPZ is a security control, not just a service enhancement.

### Serve-stale / serve-expired

When upstream nameservers are unreachable, the Recursor can serve expired cache entries rather than returning SERVFAIL. `serve_expired: true` with `serve_expired_ttl: 86400` provides up to 24 hours of resilience during upstream outages.

### Lua scripting (Recursor)

```lua
-- preresolve: block or redirect before resolution
function preresolve(dq)
    if dq.qname:equal(newDN("blocked.example.com")) then
        dq.rcode = pdns.NXDOMAIN
        return true
    end
    return false
end

-- postresolve: inspect or modify after resolution
function postresolve(dq)
    if dq.qtype == pdns.A then
        for i, rec in ipairs(dq:getRecords()) do
            pdnslog("A response: " .. rec:getContent())
        end
    end
    return false
end
```

Available hooks: `preresolve`, `postresolve`, `nxdomain`, `nodata`, `preoutquery` (before sending upstream query), `ipfilter` (filter by client IP at the earliest point).

## DNSdist 2.0

### Load balancing policies

| Policy | Description |
|---|---|
| `leastOutstanding` | Route to backend with fewest pending queries (default) |
| `wrandom` | Weighted random; assign weights per backend |
| `roundrobin` | Sequential rotation across all healthy backends |
| `firstAvailable` | Always route to first healthy backend |
| `chashed` | Consistent hash on query name; same name always goes to same backend |

### DoH / DoT / DoQ frontend

| Protocol | Port | Notes |
|---|---|---|
| DoT (DNS over TLS) | 853 | Standard TLS termination; widely supported |
| DoH (DNS over HTTPS) | 443 | HTTP/2 with `/dns-query` path; browser-compatible |
| DoQ (DNS over QUIC) | 853 (QUIC) | 0-RTT; lowest latency; DNSdist 2.0 |

TLS certificates are configured centrally in DNSdist and reused across DoT and DoH frontends. Certificate rotation requires a DNSdist reload (`dnsdist -c` or `reload-certs` console command).

### Rules engine

Rules are evaluated in order; the first matching rule's action applies.

Selectors:

| Selector | Matches on |
|---|---|
| `QTypeRule` | DNS query type (A, AAAA, MX, etc.) |
| `QNameRule` | Exact query name |
| `SuffixMatchNodeRule` | Query name suffix (zone delegation) |
| `NetmaskGroupRule` | Client source IP/CIDR |
| `MaxQPSIPRule` | Per-source-IP query rate |
| `RegexRule` | Regular expression on query name |
| `TagRule` | Tags set by earlier rules |

Actions:

| Action | Effect |
|---|---|
| `PoolAction` | Route to a named backend pool |
| `DropAction` | Silently discard query |
| `RCodeAction` | Return a specific RCODE (REFUSED, SERVFAIL, etc.) |
| `SpoofAction` | Return a synthesised answer |
| `DelayAction` | Introduce artificial latency (rate-limiting defence) |
| `LogAction` | Log and continue to next rule |
| `TeeAction` | Duplicate query to a secondary backend (observability) |

Example: route internal zones to the Auth pool, block ANY queries, rate-limit per IP:

```lua
addAction(MaxQPSIPRule(100), DropAction())
addAction(QTypeRule(dnsdist.ANY), RCodeAction(dnsdist.REFUSED))
addAction(SuffixMatchNodeRule(newSuffixMatchNode({"example.com.", "example.net."})),
          PoolAction("pdns-auth"))
```

### Health checks

- TCP connect check to backend port (default).
- DNS query-based check: send a configured query, expect a valid answer.
- Lazy health checking: only check a backend when it starts failing queries, not continuously.
- Auto-recovery: backend returns to the pool when health checks pass again.

Configuration:

```yaml
backends:
  - address: "192.168.1.10:53"
    name: "pdns-auth"
    healthcheck: true
    check_interval: 5
    check_timeout: 1
```

### DNSdist Defender

Advanced threat mitigation features in DNSdist 2.0:

- **DNS tunneling detection**: entropy analysis and query-pattern matching to identify covert channel traffic.
- **PRSD mitigation**: pseudo-random subdomain (PRSD) attack detection; blocks clients generating high volumes of unique subdomains (used to overwhelm authoritative servers).
- **Amplification prevention**: detects and blocks large responses to spoofed sources.
- **SIEM integration**: CEF and syslog export of threat events to external SIEM platforms.

### Deployment patterns

#### Standard: Auth and Recursor behind DNSdist

```
Internet -> DNSdist (port 53, DoT 853, DoH 443)
                |
       +--------+--------+
       |                 |
  Auth Server       Recursor
  (example.com)     (everything else)
```

DNSdist routes queries for hosted zones to the Auth pool and all other queries to the Recursor pool. Both pools can have multiple backends for redundancy.

#### Auth with database high availability

```
DNSdist -> Auth Server 1 -> MySQL Primary
               |                  |
           Auth Server 2 -> MySQL Replica (read)
```

Multiple Auth instances load-balanced by DNSdist; MySQL replication for zone data redundancy. Auth instances use read-replica for lookups and primary for writes (API/pdnsutil). Native AXFR/IXFR between Auth instances is also supported for multi-site replication.

#### Recursor with RPZ threat blocking

```
Internal clients -> Recursor
                       |
                  +----+----+
                  |         |
              RPZ feed 1  RPZ feed 2
              (Spamhaus)  (Custom)
```

Multiple RPZ feeds loaded in priority order; blocked domains return NXDOMAIN or redirect to walled garden. The Recursor cache absorbs repeated queries for the same blocked domains.

#### High-availability DNSdist with anycast

```
Anycast VIP -> DNSdist Active (keepalived)
                    |
               DNSdist Standby
                    |
            +-------+-------+
            |               |
       Recursor 1      Recursor 2
```

DNSdist HA via keepalived with a shared anycast VIP. Backend pools span both Recursor instances; DNSdist health checks drive automatic failover per backend.

### pdns.conf core settings reference

```ini
# Backend (choose one)
launch=gmysql
gmysql-host=127.0.0.1
gmysql-dbname=pdns
gmysql-user=pdns
gmysql-password=secret                    # secrets-hygiene: use env var or vault reference

# REST API
api=yes
api-key=changeme                          # secrets-hygiene: rotate regularly
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=10.0.0.0/8

# Performance
receiver-threads=4
distributor-threads=4
cache-ttl=60
query-cache-ttl=60
negquery-cache-ttl=60

# Zone transfer security
allow-axfr-ips=10.0.0.0/8
disable-axfr=no
only-notify=10.0.0.100,10.0.0.101

# TSIG for zone transfers
# Create TSIG key: pdnsutil generate-tsig-key transfer-key hmac-sha256
# Assign to zone:  pdnsutil set-meta example.com TSIG-ALLOW-AXFR transfer-key
```
