# BIND architecture and configuration

## named.conf top-level statements

```
options { ... };             # Global server settings
logging { ... };             # Log channels and categories
acl <name> { ... };          # Named address match lists
key <name> { ... };          # TSIG key definitions
zone <name> { ... };         # Zone definitions (outside views)
view <name> { ... };         # View definitions
controls { ... };            # rndc control channel
statistics-channels { ... }; # HTTP stats endpoint
server <ip> { ... };         # Per-server settings
```

ACLs and keys declared before any view are global and may be referenced inside views. Zone definitions at the top level are not permitted once any view exists; all zones must move inside views.

## Options block key settings

```
options {
    directory "/var/named";
    listen-on { 192.0.2.1; };      # Bind to specific interface(s)
    recursion yes;                  # Enable for recursive; disable for authoritative-only
    allow-recursion { internal; }; # Restrict recursion to trusted clients
    allow-query { any; };
    allow-transfer { none; };       # Default deny zone transfers
    forwarders { 9.9.9.9; };       # Upstream resolvers for forwarding
    forward only;                   # Only use forwarders, do not recurse
    dnssec-validation auto;         # Enable DNSSEC validation with managed root key
    max-cache-size 256m;
    minimal-responses yes;          # Reduce amplification risk
    version "not disclosed";        # Hide version string
};
```

Set `recursion no` on an authoritative-only server. Set `recursion yes` with a tight `allow-recursion` ACL on a recursive server; never expose recursion to the internet.

## ACLs

```
acl "internal" {
    10.0.0.0/8;
    192.168.0.0/16;
    172.16.0.0/12;
    localhost;
};
```

ACLs are named address match lists. They accept IPv4/IPv6 CIDRs, `localhost`, `localnets`, `any`, `none`, and nested ACL names. Reference them by name in `allow-query`, `allow-transfer`, `allow-recursion`, and `match-clients`.

## Views (split-horizon)

Views allow a single BIND instance to serve different DNS data to different clients based on source address or TSIG key.

```
view "internal" {
    match-clients { internal; };
    recursion yes;
    zone "example.com" {
        type primary;
        file "internal/example.com.zone";
    };
    zone "." {
        type hint;
        file "named.ca";
    };
};

view "external" {
    match-clients { any; };
    recursion no;
    zone "example.com" {
        type primary;
        file "external/example.com.zone";
    };
};
```

Rules:
- Once any view is defined, every zone (including root hints, localhost, loopback) must be inside a view or named will refuse to start.
- First match wins; place the most specific `match-clients` (internal clients, TSIG-authenticated transfers) before the catch-all `any`.
- TSIG keys may be used in `match-clients` to route signed queries (dynamic updates, secondary transfers) to the correct view.

## Zone file format

```
$ORIGIN example.com.
$TTL 3600
@   IN  SOA  ns1.example.com. hostmaster.example.com. (
                2024010101  ; Serial (YYYYMMDDnn) -- increment on every edit
                3600        ; Refresh: how often secondaries check for changes
                900         ; Retry: how often secondaries retry on failure
                604800      ; Expire: how long secondaries serve stale data
                300 )       ; Minimum: negative caching TTL (RFC 2308)
@   IN  NS   ns1.example.com.
@   IN  NS   ns2.example.com.
ns1 IN  A    192.0.2.1
ns2 IN  A    192.0.2.2
www IN  A    192.0.2.10
@   IN  MX   10 mail.example.com.
@   IN  TXT  "v=spf1 ip4:192.0.2.0/24 -all"
```

Key rules:
- Names not ending in `.` are relative to `$ORIGIN`. Always terminate fully-qualified names with a dot.
- The SOA serial must be incremented on every edit for secondaries to detect the change.
- Use `named-checkzone example.com /path/to/zone` to validate before reloading.
- SOA serial convention: `YYYYMMDDnn` (UTC date plus two-digit revision). Derive today's date from the live clock, not from memory; see `utc-timestamps`.

## Primary and secondary (master/slave) zone setup

```
# Primary named.conf
zone "example.com" {
    type primary;
    file "example.com.zone";
    allow-transfer { key "transfer-key"; };
    notify yes;
    also-notify { 192.0.2.2; };
};

# Secondary named.conf
zone "example.com" {
    type secondary;
    file "secondary/example.com.zone";
    primaries { 192.0.2.1 key "transfer-key"; };
};
```

The primary sends NOTIFY to secondaries when the zone changes. Secondaries check the SOA serial and initiate a transfer (IXFR first, falling back to AXFR) if the serial is higher. Protect transfers with TSIG keys and `allow-transfer` ACLs.

## DNSSEC with KASP

KASP (`dnssec-policy`) is the recommended method for automated DNSSEC signing. Manual key management with `dnssec-keygen` is still possible but adds operational complexity without benefit for most deployments.

### Built-in policies

| Policy | Key type | Algorithm | Lifetime |
|---|---|---|---|
| `default` | CSK (combined signing key) | ECDSAP256SHA256 | 1 year |
| `insecure` | None | n/a | Removes signing |

### Custom policy

```
dnssec-policy "my-policy" {
    keys {
        ksk lifetime P1Y algorithm ecdsap256sha256;
        zsk lifetime P90D algorithm ecdsap256sha256;
    };
    nsec3param iterations 0 optout no salt-length 0; # Per RFC 9276
    signatures-validity 14d;
    signatures-validity-dnskey 14d;
};
```

Apply to a zone:

```
zone "example.com" {
    type primary;
    file "example.com.zone";
    dnssec-policy "my-policy";
    inline-signing yes; # Required in 9.18; default in 9.20 when dnssec-policy is set
};
```

### Inline signing

Inline signing keeps the unsigned zone file editable by the operator; BIND maintains a separate in-memory (and on-disk) signed version. This avoids accidental corruption of DNSSEC records during manual zone edits.

### KSK rollover

KASP automates ZSK rollovers fully. KSK rollovers are semi-automated:

1. KASP generates the new KSK and begins the rollover at the scheduled time.
2. Operator submits the new DS record to the parent zone (registrar or parent nameserver).
3. Operator confirms DS publication: `rndc dnssec -checkds -key <keyid> published example.com`
4. KASP retires the old KSK after the DS TTL has expired.

Never retire the old KSK before confirming DS publication at the parent. DS desynchronisation causes total zone validation failure from resolvers that trust the old DS.

### Manual-mode KASP (9.20 only)

```
dnssec-policy "manual-rollover" {
    manual-mode yes;
};
```

KASP pauses at each key state transition and waits for operator confirmation. Advance with `rndc dnssec -step example.com`. Useful for audited environments where automated key transitions require a change-control approval.

## RPZ (Response Policy Zones)

RPZ intercepts DNS responses and applies a rewrite policy, enabling local DNS threat blocking without changes to upstream authoritative data.

```
options {
    response-policy {
        zone "rpz.example.com" policy NXDOMAIN;
    } servfail-until-ready yes; # Prevent unprotected queries during zone load (9.20)
};

zone "rpz.example.com" {
    type primary;
    file "rpz.example.com.zone";
};
```

### Triggers

| Trigger | Matches on |
|---|---|
| `qname` | The queried domain name |
| `client-ip` | The client's source IP address |
| `response-ip` | The IP address in the DNS answer |
| `nsdname` | The nameserver name for the answer |
| `nsip` | The nameserver IP for the answer |

### Actions

| Action | Effect |
|---|---|
| `NXDOMAIN` | Returns NXDOMAIN (domain does not exist) |
| `NODATA` | Returns NODATA (no records of the queried type) |
| `PASSTHRU` | Bypasses RPZ for this entry (whitelist) |
| `DROP` | Drops the query silently (no response) |
| `CNAME <target>` | Redirects to a sinkhole or block page |

Enable `servfail-until-ready yes` in production to prevent unfiltered responses during the RPZ zone load window at startup. Without it, BIND serves unprotected responses until the RPZ zone is fully loaded.

Threat feed providers: Spamhaus, SURBL, Infoblox; or self-managed blocklists in zone file format.

## TSIG

TSIG provides HMAC-based authentication for zone transfers, dynamic updates, and `rndc` control channel communications.

```
key "transfer-key" {
    algorithm hmac-sha256;
    secret "base64-encoded-secret=="; # Never commit this to a repository
};

zone "example.com" {
    allow-transfer { key "transfer-key"; };
};
```

Generate a new key:

```bash
tsig-keygen -a hmac-sha256 transfer-key
```

For Active Directory integration (GSS-TSIG), configure a Kerberos keytab:

```
tkey-gssapi-keytab "/etc/named.keytab";
```

Store the base64 secret outside version control; inject via an environment variable, HashiCorp Vault, or a secrets manager. See `secrets-hygiene`.

## Catalog zones

Catalog zones automate secondary zone provisioning. The primary maintains a list of zones as DNS records (TXT/PTR records in a special catalog zone). Secondaries that subscribe to the catalog zone automatically add and remove zones as the catalog changes, eliminating manual zone stanza management on secondaries.

```
# Primary: add to options
catalog-zones {
    zone "catalog.example.com" default-primaries { 192.0.2.1; };
};

zone "catalog.example.com" {
    type primary;
    file "catalog.example.com.zone";
};
```

BIND 9.20 adds `notify-defer` and automatic detection and restart of stalled catalog zone transfers.

## Forwarders and recursion controls

```
options {
    forwarders {
        9.9.9.9;
        149.112.112.112;
    };
    forward only;         # Only use forwarders; do not recurse if forwarders fail
    # forward first;      # Try forwarders first; recurse if they return SERVFAIL
};
```

Use `forward only` when all external resolution must go through a specific upstream (e.g. a corporate DNS proxy or firewall policy). Use `forward first` when forwarders are best-effort and fallback to full recursion is acceptable.

Per-zone forwarding overrides global forwarders:

```
zone "internal.corp" {
    type forward;
    forwarders { 10.0.0.53; };
    forward only;
};
```

## RRL (Response Rate Limiting)

RRL reduces the effectiveness of DNS amplification attacks by limiting the response rate to any single client IP.

```
rate-limit {
    responses-per-second 10;
    slip 2;    # Every 1-in-N responses is truncated (TC=1) rather than dropped
    window 15; # Sliding window in seconds
};
```

The `slip` value causes BIND to send a truncated response instead of silently dropping, prompting legitimate clients to retry over TCP.

## Zone templates (9.20 only)

Zone templates allow reusable configuration blocks applied to multiple zones:

```
template "signed-zone" {
    dnssec-policy default;
    inline-signing yes;
    also-notify { 192.0.2.100; };
};

zone "example.com" {
    type primary;
    file "example.com.zone";
    use-template "signed-zone";
};

zone "example.net" {
    type primary;
    file "example.net.zone";
    use-template "signed-zone";
};
```

Template changes apply at zone definition time; a zone reload (`rndc reload <zone>`) is required after a template change.

## Version notes (9.18 / 9.20)

### BIND 9.18 (ESV)

9.18 is the Extended Support Version: long-term security patches, recommended for stability-focused deployments.

Key characteristics:
- DNSSEC via KASP (`dnssec-policy`) is available and recommended.
- `auto-dnssec` is still functional but deprecated; do not start new deployments with it.
- `trusted-keys` and `managed-keys` are still functional (removed in 9.20); migrate to `trust-anchors`.
- RBTDB (Red-Black-Tree Database) is the default storage engine.
- `inline-signing` must be explicitly set when using KASP.
- DNS over TLS (DoT) server-side support introduced in 9.18.
- RPZ and catalog zones fully supported.
- `servfail-until-ready` for RPZ is a 9.20 feature; not available on 9.18.
- Zone templates are a 9.20 feature; not available on 9.18.

Features removed in 9.18 relative to older releases:
- `glue-cache`, `sortlist`, `delegation-only` zone type removed.
- DNSRPS (DNS Response Policy Service) removed; use native RPZ instead.

Migration planning before upgrading 9.18 to 9.20:
1. Replace every `auto-dnssec` with `dnssec-policy`; named will refuse to start in 9.20 if `auto-dnssec` is present.
2. Replace `trusted-keys`/`managed-keys` with `trust-anchors`.
3. Remove `glue-cache` and `sortlist` if present.
4. Verify RSASHA1 usage: 9.20 emits deprecation warnings; plan algorithm migration to ECDSAP256SHA256.
5. Test with QP-trie (9.20 default): zone loading, query performance, memory profile may differ from RBTDB.

### BIND 9.20 (current stable)

9.20 is the current stable release with significant architectural changes.

Key characteristics:
- QP-trie database replaces RBTDB as default: 4 to 7% authoritative performance improvement; SIEVE LRU cache expiration for better recursive performance near `max-cache-size`. RBTDB will be removed entirely in 9.22.
- `inline-signing` is the default when `dnssec-policy` is set; no need to specify it explicitly.
- Manual-mode KASP (`manual-mode yes` in `dnssec-policy`) allows change-controlled key rollovers.
- Zone templates (`use-template`) for reusable zone configuration.
- `named-checkconf -e` prints the effective configuration including all built-in defaults.
- `named-checkconf -k` checks `key-directory` alignment with `dnssec-policy`.
- `servfail-until-ready yes` in the `response-policy` block prevents unprotected RPZ startup queries.
- DSYNC record type support for generalised parent-child delegation management.
- PROXYv2 protocol support.
- DoH and DoT transport support.
- DNAME records and extraneous NS records in the AUTHORITY section are rejected unless delivered over a spoofing-resistant transport (TCP, DNS cookies, or TSIG).

Breaking changes from 9.18 (named will refuse to start if these are present):
- `auto-dnssec`: use `dnssec-policy` instead.
- `trusted-keys`: use `trust-anchors` instead.
- `managed-keys`: use `trust-anchors` instead.
- `glue-cache`, `sortlist`, `delegation-only`: remove from config.
- DNSRPS: use native RPZ instead.

Deprecation warnings (still function but will be removed in a future release):
- RSASHA1 algorithm (code 5) and RSASHA1-NSEC3SHA1 (code 7).
- DS digest type SHA1.
- Weak algorithm names in `allow-transfer`, `server`, and similar blocks.

Common 9.20 pitfalls:
- `auto-dnssec` causes a startup failure; must be removed before upgrading.
- QP-trie memory profile differs from RBTDB; monitor memory after upgrade and adjust `max-cache-size` if needed.
- RSASHA1 deprecation warnings may flood logs if zones are still signed with RSASHA1.
- Zone template changes require a zone reload to take effect.
