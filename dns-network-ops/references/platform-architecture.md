# Platform comparison and architecture patterns

## Cross-platform feature matrix

| Feature | Windows DNS | BIND | Route 53 | Cloudflare |
|---|---|---|---|---|
| Authoritative | Yes | Yes | Yes | Yes |
| Recursive | Yes | Yes | Resolver (VPC) | 1.1.1.1 (public) |
| DNSSEC signing | Yes (GUI plus PowerShell) | Yes (KASP) | Yes (KMS-based KSK) | Yes (one-click) |
| Split-horizon | DNS policies / scopes | Views | Private plus public zones | CNAME setup (partial) |
| RPZ / DNS firewall | Policies (limited) | RPZ (full) | DNS Firewall | Gateway DNS filtering |
| Dynamic updates | Secure (AD) | TSIG / GSS-TSIG | API / CLI only | API only |
| Zone transfers | AXFR / IXFR | AXFR / IXFR plus TSIG | N/A (API-managed) | Secondary DNS (Enterprise) |
| IaC support | PowerShell / DSC | Ansible / config files | Terraform / CloudFormation | Terraform |
| DoH / DoT | DoH server (2025 preview) | DoT server (9.18+) | N/A (resolver only) | 1.1.1.1 (DoH/DoT/DoQ) |

The PowerDNS, CoreDNS, Unbound, and Azure DNS platforms extend this picture: PowerDNS adds database-backed zones with a REST API, CoreDNS adds a plugin chain for Kubernetes service discovery, Unbound is a dedicated validating recursive resolver, and Azure DNS mirrors the Route 53 managed model within Azure (public zones, private zones, and the Azure DNS Private Resolver). Route to the vendor skill for each platform's specifics.

## DNS architecture patterns

### Internal-only (on-premises)

```
AD domain controllers (Windows DNS)
  -> AD-integrated zones for internal domains
  -> Conditional forwarders for partner and cloud domains
  -> Global forwarders for internet resolution
```

### Split-horizon (internal plus external)

```
Internal DNS (Windows DNS or a BIND internal view)
  -> Internal records (private IPs, AD zones)
External DNS (Cloudflare, Route 53, or a BIND external view)
  -> Public records (web servers, MX, SPF)
```

### Hybrid cloud

```
On-premises DNS (Windows DNS / BIND)
  -> Forward Azure private zones to the Azure DNS Private Resolver
  -> Forward AWS private zones via Route 53 Resolver inbound endpoints
  -> Conditional forwarders for cloud-hosted services

AWS Route 53 Resolver
  -> Outbound endpoints forward corp.example.com to on-prem DNS
  -> Private hosted zones for VPC resources
```

### Multi-provider (resilience)

```
Primary: Cloudflare DNS (anycast authoritative)
Secondary: Route 53 (secondary via zone transfer)
  -> Both sets of NS records published at the registrar
  -> The zone is served even if one provider has an outage
```

Multi-provider authoritative DNS is the strongest defence against a single-provider outage. The October 2016 Dyn outage is the canonical lesson: domains with only one DNS provider went dark. Secondary DNS via zone transfer (AXFR/IXFR with TSIG) keeps the second provider in sync.

## DNS security layers by platform

| Layer | Technology | Platform |
|---|---|---|
| Cache poisoning protection | DNSSEC validation | All platforms |
| Zone data integrity | DNSSEC signing | All platforms |
| Malware domain blocking | RPZ / DNS firewall | BIND (RPZ), Route 53 (DNS Firewall), Windows (policies) |
| Data exfiltration prevention | DNS firewall / RPZ | Route 53 DNS Firewall, BIND RPZ |
| Encrypted transport | DoH / DoT / DoQ | BIND (DoT), Windows 2025 (DoH preview), Cloudflare 1.1.1.1 |
| Zone-transfer security | TSIG / ACLs | BIND, Cloudflare Secondary DNS |

## Platform routing summary

| Request pattern | Route to |
|---|---|
| AD-integrated zones, DNS policies, PowerShell DNS | `windows-dns-ops` |
| named.conf, zone files, RPZ, KASP, views | `bind-dns-ops` |
| Database-backed authoritative, REST API | `powerdns-ops` |
| Kubernetes service discovery, Corefile plugins | `coredns-ops` |
| Validating recursive resolver, forward zones | `unbound-dns-ops` |
| Route 53 hosted zones, routing policies, health checks, DNS Firewall | `route53-dns-ops` |
| Azure public/private zones, Private Resolver | `azure-dns-ops` |
| Cloudflare proxy vs DNS-only, Foundation DNS, 1.1.1.1, secondary DNS | `cloudflare-dns-ops` |
