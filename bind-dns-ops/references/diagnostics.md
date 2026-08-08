# BIND diagnostics and troubleshooting

## rndc command reference

`rndc` communicates with the running named process over the control channel (default `127.0.0.1:953`). Ensure the control channel and rndc key are configured before using these commands.

### Zone management

```bash
rndc reload                      # Reload named.conf and all zones
rndc reload example.com          # Reload a specific zone
rndc retransfer example.com      # Force zone transfer from primary (on secondary)
rndc freeze example.com          # Pause dynamic updates for a zone
rndc thaw example.com            # Resume dynamic updates for a zone
rndc sign example.com            # Re-sign a zone (manual DNSSEC)
```

### Cache management

```bash
rndc flush                       # Flush the entire DNS cache
rndc flushname example.com       # Flush a specific name from cache
rndc flushname example.com IN A  # Flush a specific RRset
```

### Diagnostics and status

```bash
rndc status                      # Check named process status and uptime
rndc stats                       # Dump statistics to named_stats.txt
rndc dumpdb -all                 # Dump the entire cache database to a file
rndc trace                       # Increase logging verbosity by one level
rndc notrace                     # Reset logging verbosity to configured level
rndc querylog on                 # Enable query logging at runtime
rndc querylog off                # Disable query logging at runtime
```

### DNSSEC key management

```bash
# Confirm DS record published at parent (required during KSK rollover)
rndc dnssec -checkds -key <keyid> published example.com

# Advance a manual-mode KASP rollover to the next state (9.20 only)
rndc dnssec -step example.com

# Show current DNSSEC key states for a zone
rndc dnssec -status example.com
```

## Validation tools

### named-checkconf

Validates named.conf syntax before applying the configuration. Always run before reloading.

```bash
named-checkconf /etc/named.conf           # Validate configuration syntax
named-checkconf -e /etc/named.conf        # Print effective config with defaults (9.20 only)
named-checkconf -k /etc/named.conf        # Check key-directory alignment with dnssec-policy (9.20 only)
named-checkconf -p /etc/named.conf        # Print parsed config (useful for debugging include files)
```

### named-checkzone

Validates zone file syntax. Run before reloading a zone after manual edits.

```bash
named-checkzone example.com /var/named/example.com.zone
named-checkzone -D example.com /var/named/example.com.zone  # Dump as canonical zone format
```

Common errors caught by named-checkzone:
- Missing trailing dots on fully-qualified names.
- SOA serial not incremented since last transfer.
- Duplicate records.
- CNAME at zone apex or coexisting with other records.

## Query logging

Enable query logging to diagnose what clients are querying and whether DNSSEC validation flags are set.

```
logging {
    channel querylog {
        file "/var/log/named/queries.log" versions 10 size 20m;
        print-time yes;
        print-severity yes;
        severity dynamic;
    };
    category queries { querylog; };
    category query-errors { querylog; };
};
```

Toggle at runtime without a config reload:

```bash
rndc querylog on
rndc querylog off
```

Query log line format:

```
15-Jun-2026 10:00:01.234 client @0x... 10.0.0.5#54321 (example.com): query: example.com IN A +E(0)DC (192.0.2.1)
```

Flags in the query log: `+` (recursion desired), `E` (EDNS), `D` (DNSSEC OK bit), `C` (checking disabled), `T` (TCP).

## Statistics

### File-based statistics

```bash
rndc stats
# Writes to /var/named/data/named_stats.txt by default
# Sections: incoming queries, outgoing queries, resolver stats, zone maintenance stats
```

### HTTP statistics channel

```
statistics-channels {
    inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
};
```

```bash
curl http://127.0.0.1:8053/json/v1        # Full JSON stats
curl http://127.0.0.1:8053/json/v1/zones  # Per-zone stats
```

### Prometheus integration

Use `prometheus-bind-exporter` to scrape the statistics channel and expose metrics in Prometheus format. Key metrics: `bind_resolver_queries_total`, `bind_cache_hits`, `bind_cache_misses`, `bind_dnssec_validation_success_total`. See `grafana-dashboards` and `prometheus-configuration` for dashboard and scrape configuration.

## dig diagnostic commands

```bash
# Basic query against a specific server
dig @192.0.2.1 example.com A

# Check SOA serial on both primary and secondary
dig @ns1.example.com example.com SOA
dig @ns2.example.com example.com SOA

# Attempt a zone transfer (tests allow-transfer ACL)
dig @ns1.example.com example.com AXFR

# Query with DNSSEC: look for AD (authenticated data) flag
dig @192.0.2.1 +dnssec example.com A

# Full resolution trace from root
dig +trace example.com A

# Detailed DNSSEC validation (more verbose than dig)
delv @192.0.2.1 example.com A

# Compact output for scripting
dig +short example.com A

# Reverse lookup
dig -x 192.0.2.10

# Query with NSID to identify which anycast node responded
dig @1.1.1.1 example.com A +nsid
```

## Common failure modes and fixes

### Zone not loading

Symptoms: zone queries return SERVFAIL; named log shows zone load error.

Diagnosis:
1. `named-checkzone example.com /path/to/zone` to identify syntax errors.
2. Check named log: `journalctl -u named -n 100` or `/var/log/named/named.log`.
3. Verify file permissions: the named user must be able to read zone files.
4. Check `$ORIGIN` directive and trailing dots on fully-qualified names.
5. Verify the zone stanza is inside a view if views are configured.

### DNSSEC validation failures

Symptoms: resolvers return SERVFAIL for the zone; `dig +dnssec` shows no AD flag.

Diagnosis:
1. `dig +dnssec example.com A` from an external resolver: check for RRSIG records and the AD flag.
2. `delv @localhost example.com A` for detailed DNSSEC chain validation output.
3. Check that the DS record at the parent matches the current KSK: `dig example.com DS` at the parent nameserver.
4. Verify key state files in the `key-directory` exist and are readable by named.
5. Check `rndc dnssec -status example.com` for the current key state machine position.
6. If KSK has rolled without DS confirmation at parent: use `rndc dnssec -checkds -key <keyid> published example.com` to synchronise.

### Zone transfer failures

Symptoms: secondary is stale; `rndc status` shows zone transfer errors; secondary log shows REFUSED or NOTAUTH.

Diagnosis:
1. Confirm the secondary IP is in `allow-transfer` on the primary.
2. Confirm the TSIG key name and secret match exactly on both primary and secondary.
3. Verify TCP port 53 is permitted between primary and secondary (zone transfers use TCP).
4. Force a retry from the secondary: `rndc retransfer example.com`.
5. Attempt a manual AXFR with a TSIG key: `dig @primary -k /path/to/tsig.key example.com AXFR`.

### View mis-matching

Symptoms: internal clients receive external zone data (or vice versa); split-horizon not working.

Diagnosis:
1. Confirm `match-clients` ACLs are correct and non-overlapping.
2. Remember first-match wins: the more specific view must come first in named.conf.
3. Confirm the internal zone file is referenced inside the internal view, not the external one.
4. Check for a catch-all view without an explicit zone definition for the queried name.
5. Use `rndc querylog on` and check which view is selected in the query log.

### Recursion misconfiguration

Symptoms: external clients are able to use the server as a recursive resolver; amplification risk.

Diagnosis:
1. Confirm `recursion no` is set for authoritative-only servers.
2. If recursion is needed, confirm `allow-recursion` is restricted to trusted ACLs.
3. Test from an external IP: `dig @<public-ip> google.com A`; a response confirms open recursion.
4. Block at the network level immediately; fix named.conf in parallel.

### Named process failing to start (9.20 upgrade)

Symptoms: named refuses to start after upgrade to 9.20; log shows configuration error.

Diagnosis:
1. `named-checkconf /etc/named.conf` to identify the offending directive.
2. Most common cause: `auto-dnssec` still present in named.conf or an included file. Replace with `dnssec-policy`.
3. Second most common: `trusted-keys` or `managed-keys` blocks. Replace with `trust-anchors`.
4. Remove `glue-cache`, `sortlist`, and `delegation-only` zone type if present.
5. Check for DNSRPS configuration; replace with native RPZ.

## Performance troubleshooting

- **High query latency on recursive resolver**: check `max-cache-size`; if the cache is thrashing, increase the limit or investigate query patterns. On 9.20, SIEVE LRU cache expiration improves behaviour near the limit.
- **Memory spike after 9.20 upgrade**: QP-trie has a different memory profile from RBTDB. Monitor `rndc stats` output for memory usage and adjust `max-cache-size` accordingly.
- **Zone reload taking too long**: large zones with many records take time to reload. Consider `rndc reload example.com` (zone-only) rather than `rndc reload` (all zones) during maintenance windows.
- **TSIG authentication errors under load**: clock skew between primary and secondary causes TSIG authentication failures (default window is 5 minutes). Ensure NTP is synchronised on both servers; verify UTC alignment per `utc-timestamps`.
