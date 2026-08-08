# DNS security and encrypted transport

## Encrypted DNS protocols

### DNS over HTTPS (DoH)

- DNS queries and responses over HTTPS (port 443).
- Blends with regular HTTPS traffic, which makes it difficult to block or filter.
- Standard: RFC 8484.
- Used by browsers (Firefox, Chrome) and OS resolvers.

### DNS over TLS (DoT)

- DNS queries and responses over TLS (port 853).
- A dedicated port makes it visible to network monitoring.
- Standard: RFC 7858.
- Easier to detect and manage than DoH.

### DNS over QUIC (DoQ)

- DNS over the QUIC transport (port 853).
- 0-RTT connection establishment, so lower latency than DoT.
- Standard: RFC 9250.
- Emerging; supported by Cloudflare 1.1.1.1.

### Comparison

| Feature | DoH | DoT | DoQ |
|---|---|---|---|
| Port | 443 | 853 | 853 (UDP) |
| Visibility | Blends with HTTPS | Dedicated port | Dedicated port |
| Blockable | Hard to block | Easy to block | Easy to block |
| Performance | Good | Good | Best (0-RTT) |
| Browser support | Wide | Limited | Emerging |

The operational tension: DoH is good for client privacy but undermines enterprise DNS-based filtering and monitoring, because queries no longer traverse the inspectable resolver. Enterprises typically push managed DoH/DoT to an approved resolver and block unsanctioned public DoH endpoints.

## DNS security patterns

### RPZ (Response Policy Zones)

RPZ intercepts DNS responses and substitutes custom answers:

- **NXDOMAIN**: return "domain does not exist" for blocked domains.
- **CNAME redirect**: redirect to a sinkhole or warning page.
- **DROP**: silently drop the query.
- **PASSTHRU**: explicitly allow through despite other RPZ policies.

Trigger types: qname (query name), client-ip, response-ip, nsdname, nsip.

Providers: Spamhaus, SURBL, Infoblox threat feeds, and custom internal lists.

### DNS sinkholing

Redirect known-malicious domains to a controlled sinkhole server:

- The sinkhole logs connection attempts for incident response.
- It prevents malware command-and-control communication.
- Implemented via an RPZ CNAME redirect or a DNS policy.

### DNS firewall (cloud)

Cloud DNS firewalls filter outbound DNS queries:

- Route 53 DNS Firewall: per-VPC, managed plus custom domain lists, ALLOW/ALERT/BLOCK actions.
- Cloudflare Gateway: per-user or per-device policy, integrated with Zero Trust.
- The primary defence against DNS-based data exfiltration.

### Rate limiting (RRL)

Response Rate Limiting caps the DNS response rate per source to mitigate amplification attacks:

- `responses-per-second`: a cap per source IP.
- `slip`: the fraction of responses sent truncated (TC bit set) instead of dropped, so legitimate clients retry over TCP.
- Prevents authoritative servers from being used as DDoS amplifiers.

## Security layers in combination

A defence-in-depth DNS posture layers these controls:

| Layer | Control | Where it lives |
|---|---|---|
| Cache poisoning protection | DNSSEC validation | Recursive resolvers |
| Zone data integrity | DNSSEC signing | Authoritative servers |
| Malware domain blocking | RPZ / DNS firewall | Recursive resolvers, cloud DNS firewall |
| Data exfiltration prevention | DNS firewall / RPZ | Egress resolvers, cloud DNS firewall |
| Encrypted transport | DoH / DoT / DoQ | Client-to-resolver path |
| Zone-transfer security | TSIG / ACLs | Authoritative primaries and secondaries |
| Amplification mitigation | RRL, recursion ACLs | Authoritative and recursive servers |
