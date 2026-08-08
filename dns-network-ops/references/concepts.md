# DNS fundamentals

## DNS resolution flow

### Full resolution path

```
Client (stub resolver)
  -> Recursive resolver (ISP, enterprise, 1.1.1.1, 8.8.8.8)
       -> Root nameservers (. zone, 13 root server clusters)
            -> TLD nameservers (.com, .net, .org, etc.)
                 -> Authoritative nameservers (example.com)
                      -> Response returned to client
```

1. The **stub resolver** (client OS) checks local cache, the hosts file, then queries the configured recursive resolver.
2. The **recursive resolver** checks its cache. On a miss it performs iterative resolution:
   a. Queries a root nameserver for `.`, gets a referral to the TLD nameserver.
   b. Queries the TLD nameserver for `.com`, gets a referral to the domain's authoritative nameservers.
   c. Queries the authoritative nameserver for `example.com`, gets the answer.
3. The recursive resolver caches the answer for the TTL duration.
4. The response returns to the stub resolver, which caches it locally.

### Key concepts

- **Recursive query**: the client expects a complete answer (the recursive resolver does the work).
- **Iterative query**: the server returns the best answer it has (a referral or an answer); the resolver follows referrals.
- **Caching**: every resolver in the chain caches results per TTL, reducing query load.
- **Negative caching**: NXDOMAIN and NODATA responses are also cached (per the SOA minimum TTL, RFC 2308).

## Record types

### Address records

| Type | Purpose | Example |
|---|---|---|
| A | IPv4 address | `www IN A 192.0.2.10` |
| AAAA | IPv6 address | `www IN AAAA 2001:db8::10` |

### Alias and delegation

| Type | Purpose | Notes |
|---|---|---|
| CNAME | Canonical name (alias) | Cannot coexist with other records at the same name; cannot sit at the zone apex (use Alias/ANAME) |
| NS | Nameserver delegation | Delegates a zone or subdomain to the specified nameservers |
| SOA | Start of Authority | Required; defines zone parameters (serial, refresh, retry, expire, minimum TTL) |

### Mail

| Type | Purpose | Example |
|---|---|---|
| MX | Mail exchange | `@ IN MX 10 mail.example.com.` (priority plus target) |
| TXT (SPF) | Sender Policy Framework | `"v=spf1 ip4:192.0.2.0/24 -all"` |
| TXT (DKIM) | DomainKeys Identified Mail | Public key for email signature verification |
| TXT (DMARC) | Domain-based Message Authentication | `"v=DMARC1; p=reject; rua=mailto:dmarc@example.com"` |

### Service and security

| Type | Purpose | Example |
|---|---|---|
| SRV | Service locator | `_sip._tcp IN SRV 10 20 5060 sipserver.example.com.` |
| CAA | Certificate Authority Authorization | Restricts which CAs may issue certificates for the domain |
| TLSA | TLS authentication (DANE) | Associates a TLS certificate with a DNS name |
| PTR | Reverse lookup (IP to name) | In `in-addr.arpa` or `ip6.arpa` zones |
| DS | Delegation Signer (DNSSEC) | Links the parent zone to the child zone trust chain |
| DNSKEY | Public key (DNSSEC) | KSK or ZSK for signature verification |
| RRSIG | Record signature (DNSSEC) | Digital signature for a DNS record set |
| NSEC/NSEC3 | Authenticated denial of existence | Proves a name does not exist (NSEC3 prevents zone walking) |

## Zone transfers

### AXFR (full zone transfer)

- Transfers the entire zone from primary to secondary.
- TCP-based; the secondary initiates the transfer.
- Used for initial synchronisation or when IXFR fails.
- Protect with ACLs and TSIG authentication.

### IXFR (incremental zone transfer)

- Transfers only the changes since a specified serial number.
- More efficient than AXFR for large zones with small changes.
- Falls back to AXFR if incremental data is unavailable.
- Requires serial-number tracking (the SOA serial).

### NOTIFY

- The primary sends a NOTIFY message to secondaries when the zone changes.
- Secondaries immediately check the SOA serial and initiate a transfer if needed.
- Faster than waiting for the SOA refresh interval.

### TSIG authentication

- Cryptographic authentication for zone transfers and dynamic updates.
- HMAC-based (SHA-256 recommended); a shared secret between primary and secondary.
- Prevents unauthorised zone transfers and spoofed updates.

## Caching and TTL

### TTL (time to live)

- Defines how long a record may be cached, in seconds.
- Set per record or per zone (the `$TTL` directive).
- Lower TTL means faster propagation of changes but more queries to the authoritative servers.
- Higher TTL means fewer queries but slower change propagation.

### TTL guidelines

| Scenario | Recommended TTL | Notes |
|---|---|---|
| Stable records (MX, NS) | 86400 (24h) | Rarely change |
| Standard A/AAAA records | 3600 (1h) | Balance of freshness and efficiency |
| Pre-migration | 300 (5m) | Lower the TTL before changes, raise it after |
| Dynamic / failover | 60 (1m) | Quick failover response |
| CDN/proxy records | Auto or 300 | The CDN controls effective caching |

### Negative caching (RFC 2308)

NXDOMAIN and NODATA responses are cached for the SOA minimum-field duration. A typical value is 300s (5 minutes). A negative TTL that is too high delays recovery when records are later added.

## Split-horizon DNS

Split-horizon (split-brain) DNS returns different answers depending on the source of the query.

### Implementation approaches

1. **Separate servers**: internal DNS servers for internal clients, external DNS for the public.
2. **Views (BIND)**: a single server with `view "internal"` and `view "external"` matching on a client ACL.
3. **DNS policies plus zone scopes (Windows)**: a single server with zone scopes returning different records per client subnet.
4. **Separate zones (cloud)**: a private hosted zone (Route 53) plus a public hosted zone.

### Design rules

- The internal view should resolve both internal and external names.
- The external view should resolve public names only.
- Consistency: records accessed from both sides must resolve correctly in both views.
- Management: changes must be applied to the correct view or scope.
