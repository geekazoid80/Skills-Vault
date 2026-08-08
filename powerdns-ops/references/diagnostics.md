# PowerDNS diagnostics

## pdns_control (Authoritative Server)

`pdns_control` communicates with a running `pdns_server` via a Unix control socket. All commands run as the OS user that owns the socket (typically `pdns` or `root`).

### Status and statistics

```bash
pdns_control show *                       # dump all statistics (query counters, cache hits, etc.)
pdns_control show cache-size              # number of entries in the packet cache
pdns_control show query-cache-size        # number of entries in the query cache
pdns_control show backend-queries         # total backend queries since startup
pdns_control show latency                 # average query latency in microseconds
pdns_control list                         # list all available pdns_control commands
```

### Cache management

```bash
pdns_control ccounts                      # show cache entry counts
pdns_control purge                        # flush the entire packet cache
pdns_control purge example.com            # flush cache for a specific zone
pdns_control purge www.example.com A      # flush a specific name/type combination
```

Use `purge` after a record change that did not propagate because the old answer is still cached.

### Zone and backend operations

```bash
pdns_control bind-reload-now example.com  # reload a zone from the bind backend immediately
pdns_control notify example.com           # send NOTIFY to all secondaries for a zone
pdns_control retrieve example.com         # trigger AXFR retrieval (when acting as secondary)
pdns_control rediscover                   # rediscover all zones from the backend
pdns_control reload                       # reload all backend zones (gentle restart)
```

### Process and configuration

```bash
pdns_control version                      # print running version
pdns_control uptime                       # seconds since daemon start
pdns_control quit                         # graceful shutdown
pdns_control quit-nicely                  # wait for in-flight queries to finish, then quit
```

## pdnsutil diagnostics

`pdnsutil` is the offline zone-management and DNSSEC-operations tool. It connects directly to the configured backend, not to the running daemon.

### Zone inspection

```bash
pdnsutil list-all-zones                   # list all zones in the backend
pdnsutil list-zone example.com            # dump all records in a zone
pdnsutil show-zone example.com            # show DNSSEC key info and DS records for parent
pdnsutil check-zone example.com           # validate zone data for common errors
pdnsutil check-all-zones                  # validate all zones (run after bulk imports)
```

### DNSSEC inspection and repair

```bash
pdnsutil show-zone example.com            # display active keys, algorithms, DS hashes
pdnsutil rectify-zone example.com         # rebuild NSEC/NSEC3 ordering (required after bulk record edits)
pdnsutil secure-zone example.com          # enable DNSSEC, generate KSK + ZSK
pdnsutil disable-dnssec example.com       # remove all DNSSEC keys and disable signing
```

`check-zone` and `check-all-zones` report:
- Duplicate records
- Missing glue records
- SOA record issues (missing MNAME, bad serial format)
- DNSSEC ordering errors (requires `rectify-zone` if NSEC/NSEC3 order is wrong)

### TSIG key management

```bash
pdnsutil generate-tsig-key transfer-key hmac-sha256  # generate a new TSIG key
pdnsutil list-tsig-keys                               # list all TSIG keys
pdnsutil set-meta example.com TSIG-ALLOW-AXFR transfer-key  # allow AXFR with this key
pdnsutil set-meta example.com TSIG-ALLOW-DNSUPDATE transfer-key  # allow dynamic updates
```

TSIG key material is stored in the `tsigkeys` table. Protect via `secrets-hygiene`; rotate on personnel change.

### Zone serial management

```bash
pdnsutil increase-serial example.com      # increment SOA serial (triggers NOTIFY to secondaries)
pdnsutil set-kind example.com Native      # set zone type: Native, Primary, Secondary
pdnsutil set-meta example.com ALSO-NOTIFY 10.0.0.100  # add extra NOTIFY target
```

## rec_control (Recursor)

`rec_control` communicates with a running `pdns_recursor` via its control socket.

### Status and statistics

```bash
rec_control get-all                       # dump all statistics (cache hit rate, query counts, etc.)
rec_control get cache-hits                # number of cache hits
rec_control get cache-misses              # number of cache misses
rec_control get cache-entries             # current cache size (entries)
rec_control get questions                 # total questions answered
rec_control get servfails                 # total SERVFAIL responses
rec_control get nxdomains                 # total NXDOMAIN responses
rec_control get negcache-entries          # negative cache size
```

### Cache management

```bash
rec_control wipe-cache example.com        # flush all cached records for a domain
rec_control wipe-cache-typed example.com A  # flush specific type
rec_control dump-cache /tmp/cache.txt     # dump cache contents to file (for debugging)
```

### RPZ and security

```bash
rec_control reload-zones                  # reload all RPZ zones and forwarding config
rec_control dump-rpz <name> /tmp/rpz.txt  # dump an RPZ zone's contents (debugging)
rec_control get-ntas                      # list negative trust anchors
rec_control add-nta example.com "reason"  # add a negative trust anchor (bypass DNSSEC for domain)
rec_control clear-nta example.com         # remove a negative trust anchor
```

`reload-zones` picks up changes to `recursor.conf` (YAML) without a full daemon restart. Use after updating RPZ feed URLs or forwarding zones.

### Lua script management

```bash
rec_control reload-lua-script             # hot-reload the Lua script without restarting
rec_control reload-lua-config             # reload Lua configuration entries
```

### Process management

```bash
rec_control version                       # print running version
rec_control uptime                        # seconds since start
rec_control current-queries               # show in-flight queries
rec_control top-queries                   # most frequently queried names
rec_control top-remotes                   # clients sending the most queries (DDoS indicator)
```

`top-remotes` is the first check during a query-flood event; it identifies the source IPs generating excessive load.

## DNSdist console

DNSdist exposes a Lua console for runtime inspection and control.

Connect:

```bash
dnsdist -c                                # connect to local control socket
```

Or via network socket (if configured):

```lua
controlSocket("127.0.0.1:5199")
setKey("yourbase64key==")
```

Common console commands:

```lua
showServers()                             -- list backends and their health status
showRules()                               -- list all rules in evaluation order
getPool("pdns-auth"):getServers()         -- inspect backends in a specific pool
dumpStats()                               -- full statistics dump
showStats()                               -- summary statistics
topClients(10)                            -- top 10 clients by query volume
topQueries(10)                            -- top 10 queried names
topSlow(10)                               -- top 10 slowest queries
```

### Backend management at runtime

```lua
getServer(0):setDown()                    -- force a backend offline (by index)
getServer(0):setUp()                      -- force a backend back online
getServer(0):setAuto()                    -- return to automatic health-check control
getServer(0):getLatency()                 -- average latency for this backend (ms)
```

Forcing a backend down is useful during planned maintenance; forcing it back to auto resumes health-check-driven state.

## Metrics and monitoring

### Prometheus endpoints

| Product | Default endpoint |
|---|---|
| Authoritative Server | `http://<host>:8081/api/v1/servers/localhost/statistics` (JSON) |
| Recursor | `http://<host>:8082/metrics` (Prometheus format) |
| DNSdist | `http://<host>:8083/metrics` (Prometheus format, if `webserver` enabled) |

Key metrics to alert on:

| Metric | Threshold / alert condition |
|---|---|
| `auth-4-errors` (Auth) | Non-zero sustained; indicates backend or DNSSEC errors returning SERVFAIL |
| `cache-hit-ratio` (Recursor) | Below 80% sustained; check cache size and TTL settings |
| `servfails` (Recursor) | Spike above baseline; upstream reachability or DNSSEC validation failure |
| `rpz-applied` (Recursor) | Sustained zero when feeds are loaded; RPZ may not be functioning |
| `servfail-responses` (DNSdist) | Spike; backend pool may be unhealthy |
| `latency` (Auth, microseconds) | Backend query latency; spikes indicate database or network issues |

### Carbon / Graphite export

```ini
# pdns.conf
carbon-server=10.0.0.50:2003
carbon-interval=30
carbon-ourname=pdns01
```

The same setting pattern applies to `recursor.conf`. DNSdist uses `carbonServer("10.0.0.50:2003", "dnsdist01")` in its Lua config.

## Common failure patterns

### Auth: backend connection failure

Symptoms: all queries return SERVFAIL; `pdns_control show backend-queries` shows a flat counter (no increase); syslog shows "gmysql Connection failed" or similar.

Diagnosis:

```bash
pdns_control show backend-queries          # compare with previous value; flat = no successful queries
journalctl -u pdns -n 50                   # check backend connection errors
mysql -h 127.0.0.1 -u pdns -p pdns -e "SELECT 1"  # verify database reachability
```

Resolution: restore database connectivity. If using a replica for reads, check replica lag (`SHOW SLAVE STATUS`); if the replica is too far behind, the Auth Server may read stale or missing records.

### Auth: DNSSEC not validated by external resolvers

Symptoms: `dig +dnssec example.com @8.8.8.8` shows no RRSIG or shows AD=0 from a validating resolver.

Diagnosis:

```bash
pdnsutil show-zone example.com             # confirm keys are present and active
dig DS example.com @<parent-nameserver>    # check DS record at parent
dig DNSKEY example.com @<auth-server>      # confirm DNSKEY served
pdnsutil check-zone example.com            # look for DNSSEC ordering or key errors
```

Resolution: if DS is missing at parent, submit the DS hash from `pdnsutil show-zone` to the registrar. If DS is present but BOGUS, run `pdnsutil rectify-zone example.com` to rebuild NSEC/NSEC3 chain, then check algorithm consistency.

### Auth: zone changes not propagating to secondaries

Symptoms: secondary nameservers serve stale records after an update.

Diagnosis:

```bash
pdns_control show serial example.com       # confirm serial incremented
pdns_control notify example.com            # trigger manual NOTIFY
dig SOA example.com @<secondary-ns>        # check serial on secondary
```

Resolution: if SOA serial did not increment after editing via API, use `pdnsutil increase-serial example.com` manually. If NOTIFY is not reaching secondaries, check `only-notify` config and firewall rules for UDP/TCP port 53.

### Recursor: RPZ feed not loading

Symptoms: `rec_control get rpz-applied` shows 0; blocked domains resolve normally.

Diagnosis:

```bash
rec_control get-all | grep rpz             # check rpz-related counters
journalctl -u pdns-recursor -n 100         # look for RPZ fetch errors
curl -I https://rpz.provider.com/feed.zone  # test feed URL reachability
```

Resolution: verify URL reachability and TLS certificate validity. Check `servfail-until-ready` behaviour: if this is set and RPZ is still loading, clients will receive SERVFAIL. After resolving the feed issue, run `rec_control reload-zones` to trigger a fresh load.

### Recursor: DNSSEC validation failures (SERVFAIL to clients)

Symptoms: clients receive SERVFAIL for specific domains; `rec_control get servfails` increasing.

Diagnosis:

```bash
rec_control get-all | grep dnssec
dig +dnssec example.com @127.0.0.1        # observe AD flag and RRSIG presence
rec_control dump-cache /tmp/cache.txt && grep example.com /tmp/cache.txt  # check cache state
```

Resolution options:
- If the domain has a known DNSSEC breakage: add a negative trust anchor temporarily with `rec_control add-nta example.com "Known breakage, ticket #123"`.
- If the breakage is in a PDNS zone: run `pdnsutil rectify-zone` on the Auth Server and verify DS at parent.

### DNSdist: all backends marked down

Symptoms: DNSdist returns SERVFAIL for all queries; `showServers()` in the console shows all backends `down`.

Diagnosis:

```lua
-- in dnsdist console
showServers()                             -- confirm backends are marked down
getServer(0):getLatency()                 -- check if any responses are coming through
```

```bash
dig @192.168.1.10 example.com            # test backend directly (bypass DNSdist)
```

Resolution: if backends are reachable directly, the health-check query may be failing. Verify the health-check query name and expected response. Temporarily force a backend up with `getServer(0):setUp()` in the DNSdist console to restore service while investigating. Restore to auto with `getServer(0):setAuto()` once the health-check configuration is corrected.

### Schema migration failure (Auth 4.x to 5.0)

Symptoms: `pdns_server` starts but returns SERVFAIL or fails to load zones; syslog shows schema column errors.

Diagnosis:

```bash
pdns_server --version                     # confirm 5.0 binary
mysql -u pdns -p pdns -e "DESCRIBE records;"  # check schema; 5.0 adds columns
```

Resolution: run the schema migration script from the PowerDNS 5.0 documentation (`/usr/share/doc/pdns-backend-mysql/schema.mysql.sql` upgrade path). Take a database backup before running. Test with `pdnsutil check-all-zones` after migration.

## Log reference

### Auth syslog patterns

| Log fragment | Meaning |
|---|---|
| `Backend reported permanent error` | Backend (database) query failed; check connectivity |
| `Unable to launch, can't connect to database` | Startup failure; database unreachable |
| `Signing with key` | DNSSEC online signing occurring; expected |
| `Zone ... is stale` | SOA serial on secondary is older than primary; NOTIFY may not have reached secondary |
| `AXFR of domain ... initiated` | Inbound zone transfer starting (secondary mode) |

### Recursor syslog patterns

| Log fragment | Meaning |
|---|---|
| `Validation of ... failed` | DNSSEC validation failure; check key and DS at parent |
| `RPZ ... loaded` | RPZ feed successfully loaded; note the record count |
| `Failed to load RPZ` | Feed unreachable or parse error; check URL and format |
| `Sending SERVFAIL` | Query failed; correlated with DNSSEC or upstream reachability events |
| `Negcache hit` | Negative cache served; expected for NXDOMAIN responses |

### DNSdist log patterns

| Log fragment | Meaning |
|---|---|
| `Backend ... down` | Health check failed; backend removed from pool |
| `Backend ... up` | Backend recovered; returned to pool |
| `Dropped query` | A `DropAction` rule matched; expected if rate limiting is active |
| `No backends available` | All backends in pool down; clients receive SERVFAIL |
