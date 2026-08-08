# Route 53 architecture reference

## Hosted zones

### Public hosted zones

Served from AWS anycast edge locations; four nameservers per zone assigned automatically by AWS (do not change them). Internet-accessible from anywhere. Delegate from your registrar by updating NS records to the four AWS nameservers. Supports DNSSEC signing.

### Private hosted zones

Accessible from associated VPCs only; not visible from the internet or from unassociated VPCs. Two VPC settings must be enabled on every associated VPC: `enableDnsHostNames` and `enableDnsSupport`. Associate additional VPCs via `aws route53 associate-vpc-with-hosted-zone` (same account) or cross-account via RAM sharing plus the same CLI call from the target account.

VPC peering, Transit Gateway attachment, and RAM sharing do NOT automatically propagate private hosted zone DNS. Each VPC must be explicitly associated. Private hosted zones do not support DNSSEC.

### Hosted zone pricing

Public and private hosted zones: USD 0.50/month per zone. First 25 hosted zones are USD 0.50 each; additional zones are USD 0.10 each. DNS queries are charged separately (standard vs Alias, policy type, and health-check evaluation affect per-query cost).

---

## Alias records

Alias records are a Route 53 extension that extends the DNS record model. Key properties:

- **Zone apex support**: an Alias record can sit at the zone apex (e.g., `example.com`), which a standard CNAME cannot (RFC 1034 prohibition).
- **Free queries to AWS resources**: queries to Alias records targeting AWS resources are not charged.
- **Auto-updating**: if the target resource's IP addresses change (e.g., an ALB adds nodes), Route 53 automatically updates the resolution; no TTL or record change required.
- **No custom TTL**: the TTL is inherited from the target resource; you cannot override it.

Supported Alias targets: Application Load Balancer (ALB), Network Load Balancer (NLB), Classic Load Balancer (CLB), CloudFront distribution, API Gateway (REST and HTTP), S3 website endpoint (static hosting only, not S3 object URLs), Elastic Beanstalk environment, VPC Interface Endpoint, Global Accelerator accelerator, another Route 53 record in the same hosted zone.

Alias records are type A or AAAA (or AAAA for IPv6-capable targets). Specify `evaluate_target_health = true` in Terraform to inherit the target's health status in failover and routing-policy scenarios.

---

## Routing policies

### Simple

Single resource; no health check; no routing logic. When multiple IP values are added to a simple record, Route 53 returns all values in random order and the client selects one. No health check can be attached to a simple routing record.

### Weighted

Assigns a weight (0-255) to each record for the same DNS name. Traffic proportion = record weight / sum of all weights. Weight 0 removes the record from rotation but keeps it defined. All records at weight 0 results in equal distribution across all.

Use cases: A/B testing, canary deploys, gradual traffic migration between endpoints.

### Latency

Routes queries to the AWS region with the lowest measured latency for the requesting client. Each record specifies an AWS region; Route 53 maintains a latency database keyed to edge locations and selects the region with the lowest historical latency. Latency can be combined with health checks to skip unhealthy regions.

### Failover (active/passive)

Two records for the same DNS name: PRIMARY and SECONDARY. Route 53 serves the PRIMARY record while its health check passes; on failure, it serves the SECONDARY. Health check on PRIMARY is mandatory; health check on SECONDARY is optional but recommended.

Alias failover: set `evaluate_target_health = true` on the Alias record to treat the target's health as the health check. Useful when the target is an ALB with its own health checking.

### Geolocation

Routes by the geographic origin of the DNS query: country, continent, or US state. Each record carries a geographic identifier. Route 53 matches the most specific identifier first (state beats country beats continent). A default record catches all unmatched locations; without a default, unmatched queries return NXDOMAIN.

### Geoproximity

Routes based on the geographic distance between the query origin and the resource location, with a bias modifier (-99 to +99). Positive bias expands the effective region (attracts more traffic); negative bias shrinks it (deflects traffic). Geoproximity requires Route 53 Traffic Flow (Traffic Policies); it is not available through standard record-set API calls.

### IP-based

Routes by the client's source IP CIDR block. Define CIDR collections (named groups of IP ranges) and map each collection to a location (a record). More specific CIDR blocks take precedence. Use cases: ISP-based routing, routing corporate office subnets to a dedicated endpoint.

### Multivalue answer

Returns up to 8 healthy records for a single query. Each record can have an optional health check; unhealthy records are excluded from the response. Clients receive the set and pick one (typically round-robin). Multivalue is not a true load balancer: it provides client-side load distribution only. For server-side load balancing use an ALB or NLB behind an Alias record.

---

## Health checks

### Endpoint health checks

Route 53 health checkers are distributed globally across AWS regions. They probe the target on a configurable interval (10s or 30s) using HTTP, HTTPS, or TCP.

Key settings:

| Setting | Range / options | Notes |
|---|---|---|
| Protocol | HTTP, HTTPS, TCP | HTTPS validates the TLS certificate by default |
| Port | 1-65535 | Typically 80 (HTTP) or 443 (HTTPS) |
| Request interval | 10s or 30s | 10s = fast response, higher cost |
| Failure threshold | 1-10 | Consecutive failures before marking unhealthy |
| String match | Optional (HTTP/HTTPS only) | Route 53 checks the response body for the string |

Route 53 health checkers source from published IP ranges. These ranges must be permitted in Security Groups and NACLs for the health check to reach private-facing endpoints (via public IPs). For truly private resources, use the CloudWatch alarm pattern.

### Calculated health checks

Aggregates up to 256 child health checks using AND, OR, or NOT logic. A parent calculated health check is healthy when the configured minimum number of child checks pass. Use calculated checks to represent the health of a multi-component service without needing a single endpoint.

### CloudWatch alarm-based health checks

For resources that Route 53 health checkers cannot reach directly (e.g., resources in private VPC subnets, on-premises endpoints reachable only via VPN):

1. Deploy a CloudWatch metric or log-metric filter that reflects the resource's health.
2. Create a CloudWatch alarm on that metric.
3. Create a Route 53 health check of type CloudWatch Alarm, referencing the alarm.
4. Route 53 monitors the alarm state (OK = healthy, ALARM or INSUFFICIENT_DATA = unhealthy).

This pattern lets failover routing protect private endpoints without exposing them to the internet.

### ARC routing controls

Application Recovery Controller (ARC) routing controls provide manual and automated DR traffic switching via DNS:

- **Routing controls**: binary on/off switches that map to Route 53 health check states. Turning a control OFF marks the associated health check as unhealthy, pulling traffic away.
- **Safety rules**: enforce constraints across controls (e.g., "at least one region must remain ON").
- **Recovery clusters**: the ARC control plane; deployed across multiple AWS regions for resilience.
- **Use**: works with failover routing records. Flip a routing control to shift traffic between regions or availability zones during DR events.

---

## DNSSEC

Route 53 supports DNSSEC signing on public hosted zones only. The implementation uses a split KSK/ZSK model:

| Key | Owner | Rotation | Algorithm |
|---|---|---|---|
| KSK (Key Signing Key) | Customer, via AWS KMS | Manual | ECC_NIST_P256 (must use this key spec) |
| ZSK (Zone Signing Key) | Route 53 (auto-managed) | Automatic (~7 days) | Managed internally |

### Requirements

- The KMS key must be in **us-east-1**, regardless of where the hosted zone operates or where your workloads run.
- The KMS key spec must be **ECC_NIST_P256**.
- The IAM/KMS key policy must grant Route 53 the `kms:Sign`, `kms:GetPublicKey`, and `kms:DescribeKey` permissions.

### Enablement steps

1. Create a KMS key in us-east-1 with the correct key spec and key policy.
2. Create the KSK in Route 53: `aws route53 create-key-signing-key --hosted-zone-id Z123 --key-management-service-arn arn:aws:kms:us-east-1:... --name my-ksk --status ACTIVE`.
3. Enable DNSSEC on the zone: `aws route53 enable-hosted-zone-dnssec --hosted-zone-id Z123`.
4. Retrieve the DS record: `aws route53 get-dnssec --hosted-zone-id Z123` (returns the DS record value).
5. Publish the DS record at the domain registrar (or parent zone if Route 53 is both registrar and DNS provider, the console can do this automatically).

### KSK rotation (manual)

KSK does not auto-rotate. Rotation procedure:

1. Create a new KSK (new KMS key or same key, new KSK resource) with status ACTIVE.
2. Wait for the new DNSKEY to propagate (at least the zone's TTL).
3. Publish the new DS record at the registrar.
4. Wait for the old DS record to expire from caches (at least the parent zone's TTL).
5. Set the old KSK status to INACTIVE: `aws route53 update-key-signing-key --status INACTIVE`.
6. Delete the old KSK after confirming the new chain is validated end-to-end.

### Monitoring

Set CloudWatch alarms on:

- `DNSSECInternalFailure`: Route 53 encountered an internal error with DNSSEC signing. Requires immediate investigation.
- `DNSSECKeySigningKeysNeedingAction`: one or more KSKs need operator action (e.g., the KMS key was disabled, the KSK is approaching expiry, or the action flag is set after a failed rotation step).

---

## Route 53 Resolver

Route 53 Resolver provides hybrid DNS connectivity between AWS VPCs and on-premises networks.

### Inbound endpoints

An inbound endpoint creates Elastic Network Interfaces (ENIs) in specified VPC subnets. On-premises DNS resolvers forward queries for AWS-hosted domains (e.g., internal Route 53 private hosted zones, `amazonaws.com` service endpoints) to these ENI IPs.

- Capacity: 10,000 queries per second per IP address.
- Recommendation: deploy ENIs in at least two Availability Zones for resilience.
- On-premises conditional forwarding rules send the AWS domain to the inbound endpoint IPs via VPN or Direct Connect.

### Outbound endpoints

An outbound endpoint creates ENIs in VPC subnets that Route 53 uses as the source when forwarding DNS queries to on-premises resolvers.

- Used with FORWARD resolver rules that specify on-premises domain names and target DNS server IPs.
- Recommendation: deploy ENIs in at least two Availability Zones.

### Resolver rules

Three rule types:

| Rule type | Behaviour |
|---|---|
| FORWARD | Matches a domain and forwards queries to the specified IP(s) via the outbound endpoint |
| SYSTEM | Route 53 handles the query locally (default for Route 53-hosted zones and AWS service endpoints) |
| Recursive | Default catch-all; handled by Route 53 Resolver if no other rule matches |

Most specific match wins: a FORWARD rule for `internal.example.com` takes precedence over a FORWARD rule for `example.com`.

Resolver rules can be shared across accounts via AWS RAM (Resource Access Manager), enabling centralised DNS architecture in hub-and-spoke multi-account organisations.

### Common hybrid DNS architecture

```
On-premises client
  -> On-prem resolver (conditional forward: *.aws.internal -> inbound endpoint IPs)
       -> Route 53 inbound endpoint (ENIs in VPC)
            -> Private hosted zone resolution

AWS Lambda / EC2
  -> Route 53 Resolver (default)
       -> Matches FORWARD rule: *.corp.internal -> outbound endpoint
            -> On-premises resolver (resolves AD, legacy internal apps)
```

---

## DNS Firewall

Route 53 Resolver DNS Firewall filters outbound DNS queries made by resources within a VPC. It operates at the VPC level, not the instance level.

### Components

- **Domain lists**: named sets of domains to match against. Two types:
  - Managed domain lists: AWS-maintained threat intelligence feeds (malware domains, botnet C2, etc.).
  - Custom domain lists: operator-defined lists of allowed or blocked domains.
- **Rule groups**: ordered sets of rules, each with a priority (lower number = higher priority), a domain list reference, and an action.
- **Actions**: ALLOW (permit and stop rule processing), ALERT (log the match, then allow), BLOCK (deny; response is NXDOMAIN, NODATA, or a custom override CNAME).
- **VPC association**: each VPC must be explicitly associated with one or more rule groups.

### Multi-account management

Use AWS Firewall Manager to centrally manage DNS Firewall rule groups across accounts in an AWS Organisation. Firewall Manager can enforce mandatory rule groups on every VPC in selected accounts/OUs.

### Logging

Enable DNS Firewall query logging via Route 53 Resolver query logging to CloudWatch Logs, S3, or Kinesis Firehose. Match events appear in the log with the rule group, rule priority, and action taken.

---

## Traffic Flow

Traffic Flow (Traffic Policies) is the Route 53 visual/API editor for complex routing policy combinations. It enables:

- **Geoproximity routing**: the only way to configure geoproximity; not available in standard record-set API.
- **Chained policies**: e.g., route by geolocation first, then apply weighted routing within each geographic group.
- **Policy versioning**: traffic policies are versioned; roll back by associating a previous version.
- **Policy records**: a traffic policy is instantiated as a policy record against a DNS name; one policy can apply to multiple hosted zones and DNS names.

---

## Application Recovery Controller (ARC)

ARC provides DNS-based DR traffic control with operational safeguards:

- **Readiness checks**: validate that a recovery environment (alternate region, alternate AZ) meets defined criteria (resource counts, configuration parity) before failover.
- **Routing controls**: binary on/off switches. Each control maps to a Route 53 health check state; flipping a control OFF marks the health check unhealthy and pulls traffic away via failover routing.
- **Safety rules**: guard rails applied to routing controls (e.g., `ATLEAST(1, [us-east-1, us-west-2])` prevents both regions from being turned OFF simultaneously).
- **Recovery clusters**: the ARC control plane, deployed across 5 AWS regions for resilience. Accessible via a cluster endpoint even during a regional outage.

ARC is appropriate for production DR scenarios where human or automated control over DNS-based traffic switching is needed with safety guardrails, rather than purely health-check-driven failover.

---

## Pricing notes

| Resource | Pricing indicator |
|---|---|
| Hosted zone | USD 0.50/month (first 25); USD 0.10/month (additional) |
| Standard DNS queries | USD 0.40/million (first 1 billion/month) |
| Alias queries to AWS resources | Free (no per-query charge) |
| Health checks (basic endpoint) | USD 0.50/month per check (10s interval: USD 1.00/month) |
| Route 53 Resolver endpoints | USD 0.125/hour per endpoint + USD 0.01/million queries |
| DNS Firewall | USD 0.60/million DNS queries inspected |
| Traffic Flow policy records | USD 50/month per policy record |

Alias records to AWS resources are a meaningful cost optimisation for high-query-rate zones: pointing `example.com` at an ALB via Alias rather than a CNAME or A record eliminates per-query charges for those lookups.

---

## Terraform resource reference

```hcl
# Public hosted zone
resource "aws_route53_zone" "public" {
  name = "example.com"
}

# Private hosted zone
resource "aws_route53_zone" "private" {
  name = "internal.example.com"
  vpc {
    vpc_id = aws_vpc.main.id
  }
}

# Alias record at zone apex (ALB)
resource "aws_route53_record" "apex_alias" {
  zone_id = aws_route53_zone.public.zone_id
  name    = ""
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Weighted routing
resource "aws_route53_record" "weighted_blue" {
  zone_id        = aws_route53_zone.public.zone_id
  name           = "api.example.com"
  type           = "A"
  set_identifier = "blue"
  weighted_routing_policy {
    weight = 90
  }
  ttl     = 60
  records = ["192.0.2.10"]
}

# Failover routing (primary)
resource "aws_route53_record" "failover_primary" {
  zone_id        = aws_route53_zone.public.zone_id
  name           = "service.example.com"
  type           = "A"
  set_identifier = "primary"
  failover_routing_policy {
    type = "PRIMARY"
  }
  health_check_id = aws_route53_health_check.primary.id
  ttl             = 60
  records         = ["192.0.2.10"]
}

# Endpoint health check
resource "aws_route53_health_check" "primary" {
  fqdn              = "www.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
}

# DNSSEC KSK
resource "aws_route53_key_signing_key" "main" {
  hosted_zone_id             = aws_route53_zone.public.id
  key_management_service_arn = aws_kms_key.dnssec.arn  # must be us-east-1, ECC_NIST_P256
  name                       = "main-ksk"
  status                     = "ACTIVE"
}

resource "aws_route53_hosted_zone_dnssec" "main" {
  hosted_zone_id = aws_route53_zone.public.id
  depends_on     = [aws_route53_key_signing_key.main]
}

# Resolver inbound endpoint
resource "aws_route53_resolver_endpoint" "inbound" {
  name      = "inbound-resolver"
  direction = "INBOUND"
  security_group_ids = [aws_security_group.resolver.id]
  ip_address {
    subnet_id = aws_subnet.a.id
  }
  ip_address {
    subnet_id = aws_subnet.b.id
  }
}

# Resolver outbound endpoint + forward rule
resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "outbound-resolver"
  direction = "OUTBOUND"
  security_group_ids = [aws_security_group.resolver.id]
  ip_address {
    subnet_id = aws_subnet.a.id
  }
  ip_address {
    subnet_id = aws_subnet.b.id
  }
}

resource "aws_route53_resolver_rule" "forward_onprem" {
  domain_name          = "corp.internal"
  name                 = "forward-to-onprem"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id
  target_ip {
    ip   = "10.0.0.53"
    port = 53
  }
}

# DNS Firewall rule group
resource "aws_route53_resolver_firewall_rule_group" "main" {
  name = "main-firewall"
}

resource "aws_route53_resolver_firewall_rule_group_association" "vpc" {
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.main.id
  vpc_id                 = aws_vpc.main.id
  priority               = 100
  name                   = "main-vpc-association"
}
```

---

## AWS CLI reference

```bash
# List hosted zones
aws route53 list-hosted-zones

# List records in a zone
aws route53 list-resource-record-sets --hosted-zone-id Z123

# Create or update records via change batch
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123 \
  --change-batch file://changes.json

# Check DNSSEC status
aws route53 get-dnssec --hosted-zone-id Z123

# List health checks
aws route53 list-health-checks

# Get health check status
aws route53 get-health-check-status --health-check-id abc123

# List Resolver endpoints
aws route53resolver list-resolver-endpoints

# List Resolver rules
aws route53resolver list-resolver-rules

# List DNS Firewall rule groups
aws route53resolver list-firewall-rule-groups

# Associate a VPC with a private hosted zone (cross-account: run from target account)
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id Z123 \
  --vpc VPCRegion=ap-southeast-1,VPCId=vpc-abc123
```
