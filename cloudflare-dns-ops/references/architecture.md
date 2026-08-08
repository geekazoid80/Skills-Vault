# Cloudflare DNS architecture

## Anycast network

Cloudflare operates 300+ points of presence (PoPs) worldwide. DNS queries are routed to the nearest PoP via BGP anycast automatically, with no TTL-based failover required at the DNS layer: failover happens at the network routing layer. Inline DDoS mitigation runs at every PoP, with documented capacity of 4+ Tbps absorbed without DNS impact.

## Proxied (orange cloud) vs DNS-only (grey cloud)

This is the single most consequential configuration decision for any Cloudflare DNS record.

### Proxied mode (orange cloud)

Traffic flows through Cloudflare's reverse-proxy infrastructure before reaching the origin.

- Origin IP is hidden; visitors see Cloudflare anycast IPs in responses.
- Enables WAF, CDN caching, DDoS L3/L4/L7 protection, Workers, Rate Limiting.
- Restricted to A, AAAA, and CNAME record types.
- HTTP and HTTPS traffic only (port 80, port 443, plus a limited set of alternative HTTP ports).
- DNS TTL appears as 300 to resolvers regardless of the configured value.
- Not suitable for MX targets, SMTP servers, SRV records, CAA, NS, TXT (these must be DNS-only), or any non-HTTP service.

### DNS-only mode (grey cloud)

Cloudflare serves authoritative DNS responses only; traffic flows directly from client to origin.

- Real origin IP is returned in DNS responses.
- No WAF/CDN/DDoS proxy benefit (the anycast DNS infrastructure still applies).
- Required for MX, TXT, SRV, CAA, and NS records; also required for any non-HTTP service.
- Custom TTL is respected (minimum 60 s for DNS-only records).
- Safe default when the protocol or port does not fit the proxy.

### TTL behaviour

| Mode | Effective TTL |
|---|---|
| Proxied | Always 300 s (platform override; configured value is ignored) |
| DNS-only | Configured value (minimum 60 s) |

### Origin IP leakage

Any DNS-only A or AAAA record that returns the real origin IP can be used to bypass proxy protections. Common leakage vectors: a `mail.` subdomain (SMTP server), a `ftp.` subdomain, or an old A record left over from before Cloudflare was adopted. Audit all grey-cloud records for unintended origin exposure. Subdomain enumeration tools and certificate transparency logs are the same methods attackers use.

## Zone setup options

### Full setup (primary authoritative, all plans)

Change the NS records at the domain registrar to Cloudflare's assigned nameservers. Cloudflare becomes the primary authoritative source for the zone. Supports all Cloudflare features. Recommended for new deployments.

Quick-scan import automatically detects existing DNS records during setup; review the imported set before activating to remove stale or incorrect records.

### CNAME / partial setup (Business / Enterprise)

Keep an existing authoritative DNS provider. Point specific subdomains to Cloudflare by creating CNAMEs to `cdn.cloudflare.net` at the existing provider. Only the CNAME-pointed hostnames are proxied through Cloudflare. Suitable for incremental migration or where the registrar or existing DNS setup cannot be changed.

### Secondary DNS: Cloudflare as secondary (Enterprise)

Cloudflare receives zone transfers from a customer-operated primary. Configuration:
- Add the primary nameserver IP and TSIG key (Zone:Secondary:Edit scope) in the Cloudflare dashboard.
- Configure the primary to allow AXFR/IXFR to Cloudflare's transfer endpoints; authorise with TSIG.
- Propagation SLA: edge propagation under 5 s end-to-end after transfer completion; zone transfer completion at P99 ~800 ms.
- Supports true multi-provider DNS: both Cloudflare nameservers and primary NS records can appear at the registrar.

### Secondary DNS: outgoing (Cloudflare as primary with external secondary)

Cloudflare acts as primary and sends zone transfers to external secondary nameservers. Configure outgoing zone transfer settings (peer IPs, TSIG) via the API (`/zones/{zone_id}/secondary_dns/outgoing`). The external secondary must allow AXFR from Cloudflare transfer IPs.

### Secondary DNS and proxied records

When using secondary DNS, proxy status on transferred records is controlled via Secondary DNS Override settings. Without the override, transferred records are DNS-only by default; configure override to apply proxy status as needed.

## CNAME flattening at apex

Standard DNS does not permit CNAME records at the zone apex (the root domain, `example.com`). Cloudflare automatically resolves CNAME chains at the apex and returns the resulting A/AAAA records in responses, making CNAME-at-apex work transparently. No registrar Alias record support required. This is particularly useful for pointing the apex to a CDN, load balancer hostname, or SaaS provider endpoint.

## DNSSEC

### One-click enablement

1. Enable DNSSEC in the dashboard (DNS -> Settings) or via the API (`PATCH /zones/{zone_id}/dnssec`).
2. Cloudflare generates and manages KSK and ZSK automatically (ECDSA P-256 / SHA-256).
3. The DS record is displayed in the dashboard; add it at the registrar.
4. For domains registered via Cloudflare Registrar, the DS record is published automatically.

ZSK rotation is fully automatic. KSK rotation is managed by Cloudflare; no operator action is required for standard zones.

Verify DS publication with:
```bash
dig DS example.com @8.8.8.8 +short
```

### Multi-signer DNSSEC (RFC 8901)

For multi-provider DNS deployments where both providers are authoritative: each provider signs with its own keys; both DNSKEY sets appear in the zone simultaneously. Clients validating against either provider's keys succeed. This is the standard approach for DNSSEC in a multi-CDN or multi-DNS-provider architecture.

After migrating from pre-signed DNSSEC (where the primary sends a pre-signed zone to Cloudflare via secondary DNS) to Cloudflare-managed DNSSEC, disable pre-signed mode on the primary. Leaving it active causes Cloudflare nameservers to return REFUSED.

### Foundation DNS: per-account DNSSEC keys (Enterprise)

Foundation DNS provides per-account (and optionally per-zone) KSK/ZSK rotation instead of Cloudflare's globally shared key rotation. Required for compliance regimes that mandate key segregation.

## Foundation DNS (Enterprise)

Foundation DNS is a premium authoritative DNS tier included in Enterprise contracts.

| Feature | Standard | Foundation DNS |
|---|---|---|
| Anycast groups | Shared pool | Three separate groups (geographically distinct data centres) |
| Nameservers | Shared with other customers | Dedicated, not shared |
| Nameserver TLDs | Varies | Span .com, .net, .org for registry resilience |
| DNSSEC keys | Shared rotation | Per-account / per-zone rotation |
| GraphQL analytics | 7-day window | 31-day window, sourceIP dimension, percentile metrics |
| Software soak | Standard rollout | Two-week soak period before upgrades reach Foundation DNS nameservers |

Foundation DNS is the correct choice when compliance requires dedicated infrastructure, when registry-level resilience across multiple TLD operators is required, or when longer analytics windows are needed.

## 1.1.1.1 public resolver

Cloudflare operates a public recursive resolver at 1.1.1.1, independent of the authoritative service.

| Service | IPv4 | IPv6 |
|---|---|---|
| Standard | 1.1.1.1, 1.0.0.1 | 2606:4700:4700::1111, 2606:4700:4700::1001 |
| Families (malware blocking) | 1.1.1.2, 1.0.0.2 | 2606:4700:4700::1112, 2606:4700:4700::1002 |
| Families (malware + adult content) | 1.1.1.3, 1.0.0.3 | 2606:4700:4700::1113, 2606:4700:4700::1003 |

### Encrypted transport options

| Protocol | Endpoint |
|---|---|
| DNS-over-HTTPS (DoH) | `https://cloudflare-dns.com/dns-query` (GET and POST) |
| DNS-over-TLS (DoT) | `1dot1dot1dot1.cloudflare-dns.com` port 853 |
| DNS-over-QUIC (DoQ) | `1.1.1.1` QUIC port 853 (0-RTT, lowest latency) |
| Tor | Hidden service available for anonymous queries |

Privacy commitments: no query data sold; logs wiped within 24 hours; independently audited by KPMG annually.

The 1.1.1.1 resolver is separate from the authoritative service. Use it as a benchmark resolver during troubleshooting (`dig @1.1.1.1`), as an encrypted resolver endpoint for client devices, or as the Families-filtered resolver for networks requiring content blocking without deploying on-premises DNS filtering.

## DNS Firewall (Enterprise)

DNS Firewall protects an existing authoritative DNS infrastructure by proxying inbound DNS queries through Cloudflare before they reach the operator's nameservers.

- DDoS mitigation at Cloudflare edge before queries reach origin nameservers.
- Per-IP and aggregate rate limiting.
- Configurable TTL overrides and response caching.
- Stale record serving if origin nameservers are unreachable.
- No changes to nameserver software required; point the zone's NS records to Cloudflare-provided DNS Firewall cluster IPs.

DNS Firewall is distinct from the authoritative DNS product: the operator retains their own nameservers; Cloudflare fronts them. Contrast with the full zone-hosting product where Cloudflare is the primary.

## Load Balancing and health checks

Cloudflare Load Balancing (a separate add-on) integrates with DNS by replacing static A/AAAA records with dynamically routed responses based on health-check status, geographic steering, or latency-based routing. Health checks run from Cloudflare PoPs; unhealthy origins are removed from the pool, and the DNS response is updated automatically. Load Balancing records can be proxied or DNS-only.

Failover at the DNS layer (low-TTL approach) is an alternative: set DNS-only A records with a short TTL and update them via API when an origin fails. This is simpler but slower: clients that have already cached the TTL see the old answer until the TTL expires.

## Page rules and redirect interaction with DNS

Page rules and redirect rules (Cloudflare Rules) apply only to proxied records. A DNS-only record bypasses Cloudflare entirely; no page rule, WAF rule, or redirect rule fires for traffic reaching the origin directly. When diagnosing a redirect or rule that "isn't firing", verify that the relevant hostname is proxied (orange cloud), not DNS-only.

## API v4 REST reference

Base URL: `https://api.cloudflare.com/client/v4/`

Authentication: `Authorization: Bearer $CLOUDFLARE_API_TOKEN` header. Use a scoped token (Zone:DNS:Edit for record management, Zone:Read for analytics-only).

Key endpoints:

```bash
# List zones
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones"

# Create a proxied A record
curl -X POST \
  "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"A","name":"www","content":"192.0.2.1","proxied":true}'

# Enable DNSSEC
curl -X PATCH \
  "https://api.cloudflare.com/client/v4/zones/{zone_id}/dnssec" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"status":"active"}'

# Query secondary DNS zone transfer status (incoming)
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/{zone_id}/secondary_dns/incoming"
```

Resources relevant to DNS: `zones`, `dns_records`, `dnssec`, `secondary_dns/incoming`, `secondary_dns/outgoing`, `load_balancers`.

## Terraform provider

Provider: `cloudflare/cloudflare`. Key resources:

```hcl
# DNS-only A record
resource "cloudflare_record" "mail" {
  zone_id = var.zone_id
  name    = "mail"
  value   = "192.0.2.10"
  type    = "A"
  proxied = false
  ttl     = 300
}

# Proxied A record (TTL is ignored by Cloudflare but set for clarity)
resource "cloudflare_record" "www" {
  zone_id = var.zone_id
  name    = "www"
  value   = "192.0.2.1"
  type    = "A"
  proxied = true
}

# Enable DNSSEC
resource "cloudflare_zone_dnssec" "example" {
  zone_id = var.zone_id
}

# Zone-level settings override (e.g. minimum TTL)
resource "cloudflare_zone_settings_override" "example" {
  zone_id = var.zone_id
  settings {
    min_ttl = 60
  }
}
```

Use `CLOUDFLARE_API_TOKEN` environment variable for provider authentication; never hardcode tokens in Terraform files or state. Store state remotely (Terraform Cloud, S3 + state locking) to avoid credential leakage via local state files. See `secrets-hygiene` for the full token handling protocol.

## Troubleshooting commands

```bash
# Query a specific Cloudflare authoritative nameserver
dig @ns1.cloudflare.com example.com A

# Query via 1.1.1.1 resolver
dig @1.1.1.1 example.com A

# Identify the serving PoP (NSID option)
dig +nsid example.com @1.1.1.1

# Verify DNSSEC DS record at parent
dig DS example.com @8.8.8.8 +short

# Check DNSSEC chain validation
dig +dnssec example.com @1.1.1.1

# Check secondary DNS transfer status via API
curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/{zone_id}/secondary_dns/incoming"
```

Common failure modes:

| Symptom | Likely cause | Check |
|---|---|---|
| SERVFAIL for all DNSSEC-validating resolvers | DS record mismatch or not yet propagated at registrar | `dig DS example.com @8.8.8.8` vs Cloudflare dashboard DS value |
| Mail not delivered; MX record proxied | Orange cloud on MX target hostname | Switch MX target to DNS-only (grey cloud) |
| Redirect rule not firing | Target hostname is DNS-only | Enable proxy (orange cloud) on the hostname |
| Custom TTL not taking effect | Record is proxied | Proxied records always return TTL 300; switch to DNS-only to honour custom TTL |
| Secondary zone transfer failing | TSIG key mismatch or firewall blocking Cloudflare transfer IPs | Verify TSIG on both sides; allow Cloudflare transfer IP ranges in primary ACL |
| REFUSED from Cloudflare nameservers after secondary DNSSEC migration | Pre-signed mode still active on primary | Disable pre-signed DNSSEC on primary after enabling Cloudflare-managed DNSSEC |
