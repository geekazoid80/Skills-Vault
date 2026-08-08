# Unbound diagnostics and troubleshooting

## unbound-control command reference

unbound-control requires the remote-control socket or TCP/TLS endpoint to be enabled in unbound.conf. All commands block until the operation completes.

### Status and health

```bash
unbound-control status            # Unbound version, uptime, and thread count
unbound-control dump_requestlist  # Active queries (useful for diagnosing hangs)
```

### Configuration management

```bash
unbound-control reload            # Reload unbound.conf without restarting
                                  # Picks up: local-zone/data, access-control, forward-zone
                                  # Does NOT pick up: interface/port changes (needs restart)
unbound-control reconfig          # Alias for reload on some versions
```

### Cache operations

```bash
unbound-control stats             # Query statistics (resets counters)
unbound-control stats_noreset     # Query statistics without resetting counters
unbound-control dump_cache        # Dump full cache to stdout
unbound-control load_cache        # Load cache from stdin (useful for warm restart)
unbound-control flush example.com                # Flush all records for example.com (all types)
unbound-control flush_type example.com A         # Flush only A records for example.com
unbound-control flush_zone corp.internal.        # Flush all records for the zone and subdomains
unbound-control flush_bogus                      # Flush all BOGUS (validation-failed) entries
unbound-control flush_negative                   # Flush all negative cache entries
unbound-control lookup www.example.com           # Check if name is in cache and show TTL
```

### Forward and stub zone management

```bash
unbound-control list_forwards                    # List all configured forward zones
unbound-control list_stubs                       # List all configured stub zones
unbound-control forward corp.internal. 10.0.0.53 # Add a forward zone at runtime
unbound-control forward_remove corp.internal.    # Remove a forward zone at runtime
```

Runtime forward/stub changes are not persisted; they are lost on reload or restart. Add persistent entries to unbound.conf.

### Local zone management

```bash
unbound-control list_local_zones                 # List all local zones
unbound-control list_local_data                  # List all local data entries
unbound-control local_zone home.lab. static      # Add a local zone at runtime
unbound-control local_data "server1.home.lab. IN A 10.0.0.10"  # Add local data at runtime
unbound-control local_zone_remove home.lab.      # Remove a local zone
unbound-control local_data_remove server1.home.lab. # Remove a local data entry
```

### Trust anchor and DNSSEC

```bash
unbound-control get_option auto-trust-anchor-file  # Show configured trust anchor file path
unbound-anchor -v -a /var/lib/unbound/root.key     # Verify/update trust anchor (run as root)
```

### Configuration inspection

```bash
unbound-control get_option prefetch               # Show value of a running config option
unbound-control set_option prefetch: yes          # Change a config option at runtime (not all options support this)
```

---

## unbound-checkconf

Validates unbound.conf syntax and semantic correctness before applying changes. Always run before reload or restart.

```bash
unbound-checkconf                               # Check /etc/unbound/unbound.conf (default)
unbound-checkconf /etc/unbound/unbound.conf     # Explicit path
unbound-checkconf -f /etc/unbound/unbound.conf  # Show full resolved configuration
```

Common errors reported by unbound-checkconf:

| Error message | Cause |
|---|---|
| `cannot open root.key` | auto-trust-anchor-file path does not exist or is not readable by unbound |
| `unbound.conf:N: syntax error` | Typo in directive name or missing colon |
| `option not available` | Directive requires a module that is not in module-config |
| `cannot open /run/unbound.ctl` | Stale control socket from a previous crash |

---

## dig-based DNSSEC validation testing

### Verify the resolver is validating

```bash
# Expect: flags: qr rd ra ad; ANSWER SECTION with RRSIG records
dig @127.0.0.1 dnssec-deployment.org A +dnssec +short

# Signed zone must return AD flag in the flags line
dig @127.0.0.1 dnssec-deployment.org SOA +dnssec | grep flags
```

The `ad` (Authenticated Data) flag in the response means the resolver validated DNSSEC successfully.

### Test that BOGUS domains return SERVFAIL

```bash
# dnssec-failed.org has intentionally broken DNSSEC; expect SERVFAIL from a validating resolver
dig @127.0.0.1 dnssec-failed.org A
# Expected: status: SERVFAIL
```

If this returns an answer (non-SERVFAIL), DNSSEC validation is not active.

### Check a specific record

```bash
# Full DNSSEC chain with verbose output
dig @127.0.0.1 www.example.com A +dnssec +multiline

# Trace the delegation path (queries each level in turn)
dig @127.0.0.1 www.example.com A +trace
```

### Test a negative answer

```bash
# NXDOMAIN should include NSEC/NSEC3 record and ad flag
dig @127.0.0.1 nonexistent.dnssec-deployment.org A +dnssec
```

---

## Query statistics interpretation

`unbound-control stats_noreset` outputs key-value pairs. Important metrics:

| Key | Meaning |
|---|---|
| `total.num.queries` | Total queries received since last reset |
| `total.num.cachehits` | Queries answered from cache |
| `total.num.cachemiss` | Queries requiring upstream resolution |
| `total.num.recursivereplies` | Upstream recursive replies received |
| `total.requestlist.avg` | Average depth of query queue |
| `mem.cache.rrset` | RRset cache memory in use |
| `mem.cache.message` | Message cache memory in use |
| `num.query.type.A` | Count of A record queries |
| `num.answer.rcode.SERVFAIL` | SERVFAIL responses returned to clients |
| `num.answer.rcode.NXDOMAIN` | NXDOMAIN responses returned |
| `num.dnssec.bogus` | Queries that failed DNSSEC validation |
| `num.dnssec.secure` | Queries validated as SECURE |

A high `num.dnssec.bogus` count indicates a problem with one or more DNSSEC-signed zones (broken trust anchor, expired signatures, or misconfigured zone). Check `unbound-control dump_cache | grep BOGUS` to identify the affected zone.

Cache hit rate:
```
hit_rate = total.num.cachehits / total.num.queries
```

A hit rate below 70% on a warm cache may indicate oversized query diversity, too-small cache, or too-low `cache-min-ttl`.

---

## Common failure modes

### SERVFAIL from DNSSEC validation (BOGUS result)

**Symptom:** clients receive SERVFAIL for a specific domain; other domains resolve correctly.

**Diagnosis:**
```bash
# Check if the domain is in the cache as BOGUS
unbound-control dump_cache | grep -A5 "BOGUS"

# Query with +dnssec to see what the resolver returns
dig @127.0.0.1 example.com A +dnssec +cd   # +cd disables validation; if this works, it is a DNSSEC failure
```

**Causes and fixes:**

| Cause | Fix |
|---|---|
| Zone signed with unsupported algorithm | Add `domain-insecure: "example.com"` as a temporary workaround; notify zone operator |
| DS record in parent does not match zone's DNSKEY | Zone operator must publish correct DS; operator action required |
| Expired RRSIG (signatures not refreshed) | Zone operator must re-sign; operator action required |
| Unbound trust anchor stale | Run `unbound-anchor -v`; restart Unbound |
| Forwarding to upstream without proper DNSSEC support | Switch to full recursion or a validating upstream |

### Forward loop

**Symptom:** queries for a forwarded zone time out or return SERVFAIL; log shows repeated upstream queries with no answer.

**Diagnosis:**
```bash
# Enable verbosity temporarily
unbound-control set_option verbosity: 3
# Check logs for loops
journalctl -u unbound -f | grep "loop"
unbound-control set_option verbosity: 1
```

**Cause:** a forward-zone points to an upstream that itself forwards back to Unbound, or the upstream cannot resolve the zone.

**Fix:** verify the upstream resolves the zone independently; check that stub-zone (not forward-zone) is used when pointing at the zone's own authoritative servers.

### Cache poisoning protection

Unbound defends against DNS cache poisoning via:
- `use-caps-for-id: yes`: randomises query case (0x20 encoding); forged responses must match the case pattern.
- Port randomisation: Unbound uses a random source port for each outgoing query.
- `harden-glue: yes`: rejects out-of-zone glue records in referrals.
- DNSSEC validation: the strongest defence; a signed zone cannot be poisoned at the DNS layer.

If you suspect active cache poisoning, run `unbound-control flush_bogus` and `unbound-control flush_negative` to clear potentially poisoned entries, then check logs for anomalous NXDOMAIN or answer-spoofing patterns.

### Trust anchor stale after extended downtime

**Symptom:** after restarting Unbound (particularly after extended downtime), all DNSSEC-signed zones return BOGUS.

**Diagnosis:**
```bash
unbound-anchor -v -a /var/lib/unbound/root.key
# Look for: "success" or errors about key update failure
```

**Fix:**
```bash
systemctl stop unbound
unbound-anchor -a /var/lib/unbound/root.key    # re-bootstrap if update fails
chown unbound:unbound /var/lib/unbound/root.key
systemctl start unbound
```

RFC 5011 automatic rollover requires Unbound to be running at least once during the 30-day hold-down period. If it was offline for longer during a root KSK rollover, the trust anchor may need manual re-bootstrapping via `unbound-anchor`.

### Performance: high SERVFAIL rate

**Symptom:** elevated `num.answer.rcode.SERVFAIL` in stats; clients report resolution failures.

**Diagnosis:**
```bash
unbound-control stats_noreset | grep SERVFAIL
unbound-control dump_cache | grep BOGUS | head -20
```

If BOGUS entries are high, DNSSEC validation is failing for multiple zones. If BOGUS is low but SERVFAIL is high, the upstream or root servers may be unreachable. Check network connectivity and firewall rules for UDP/TCP port 53 outbound (and 853 if using DoT).

### Verbosity levels for debugging

```ini
server:
    verbosity: 1    # default: errors and warnings
    # verbosity: 2  # query-level logging
    # verbosity: 3  # detailed per-query debug
    # verbosity: 4  # very verbose (use only temporarily; fills logs quickly)
```

Change verbosity at runtime:
```bash
unbound-control set_option verbosity: 3
# ... observe logs ...
unbound-control set_option verbosity: 1
```

Log query destinations (useful for diagnosing forward-zone routing):
```ini
server:
    log-queries: yes      # log every query received
    log-replies: yes      # log every reply sent to client
    log-tag-queryreply: yes  # prefix log lines with "query" or "reply"
```

These increase log volume significantly; enable only for diagnosis, then disable.
