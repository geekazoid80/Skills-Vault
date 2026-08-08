# AWS VPC design and cost reference

Design-time and cost-optimisation depth that complements the audit procedure in the skill body. The audit steps assess an existing VPC against best practice; this reference is the design rationale and the networking cost levers behind those checks. Prices are US East (N. Virginia) on-demand and drift; treat them as anchors and verify at the AWS pricing page.

Scope note: Route 53, CloudFront, and the ALB/NLB/GLB load balancers are deliberately out of scope here. They belong to the DNS and load-balancer skill families; this reference stays on VPC structure, NAT, endpoints, and inter-VPC connectivity.

## VPC architecture

### Foundational design

Multi-AZ is mandatory. Deploy across 2 or more AZs (3 preferred). Cross-AZ data transfer (around $0.01/GB each direction) is minor next to the risk of a single-AZ outage.

### Standard subnet architecture

```
VPC (e.g. 10.0.0.0/16, 65,536 IPs)
  Public subnets (one per AZ)
    Internet Gateway route
    ALB/NLB, NAT Gateway, bastion hosts
    Small CIDR (e.g. /24 = 251 usable IPs)
  Private app subnets (one per AZ)
    Route to NAT Gateway for outbound internet
    EC2, ECS tasks, VPC-attached Lambda
    Larger CIDR (e.g. /20 = 4,091 IPs)
  Private data subnets (one per AZ)
    No internet route
    RDS, ElastiCache, OpenSearch
    Medium CIDR (e.g. /22 = 1,019 IPs)
  Optional isolated subnets: no route table entries except local
```

### CIDR planning

Plan CIDRs before deployment. Overlapping CIDRs block both VPC peering and Transit Gateway attachment.

- Use RFC 1918 space: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.
- Allocate a master range and carve sub-ranges per VPC.
- Roughly /16 per VPC for production, /20 or /22 for dev and staging.
- Document allocations in an IPAM tool (AWS VPC IPAM or a spreadsheet).
- Leave room for secondary CIDRs (up to 5 per VPC).
- Never use 172.17.0.0/16: Docker uses it by default, so it causes container routing conflicts on instances running Docker.

## NAT Gateway cost awareness

NAT Gateway is one of the most surprisingly expensive AWS services.

- Hourly charge: around $0.045/hr times 730 hours, about $32.40/month per NAT Gateway.
- Data processing: around $0.045/GB processed.
- HA pattern: one per AZ (recommended), so 3 times $32.40, about $97.20/month before data transfer.

### Cost-reduction strategies

| Strategy | Saving | Trade-off |
|---|---|---|
| Single NAT Gateway (dev/staging only) | Around 66 per cent of the hourly charge | Single point of failure |
| VPC Endpoints for AWS services | Removes NAT data charges for S3, DynamoDB, ECR, CloudWatch | Small hourly cost for Interface endpoints |
| NAT instance (t4g.nano) | Around $3/mo vs around $32/mo | Lower throughput; you manage HA and patching |
| IPv6 with egress-only Internet Gateway | Free outbound | Requires IPv6 adoption |

Key insight: if private subnets mostly reach AWS services (S3, DynamoDB, SQS, ECR, CloudWatch), VPC Endpoints remove most NAT Gateway data charges. A single Interface endpoint costs around $7.20/month per AZ, cheaper than NAT data charges at moderate traffic.

## VPC Endpoints

### Gateway endpoints (free)

Available for S3 and DynamoDB only. No hourly charge and no data-processing charge; implemented as route table entries. Always create these. There is no reason not to.

### Interface endpoints (PrivateLink)

- Available for 100+ AWS services (ECR, CloudWatch, SQS, SNS, KMS, Secrets Manager, SSM, STS).
- Cost: around $0.01/hr per AZ (about $7.20/month per AZ) plus around $0.01/GB processed.
- Prioritise by traffic volume: ECR (image pulls), CloudWatch (logs and metrics), SSM.

Decision framework: calculate the monthly NAT Gateway data charge for each AWS service. If that charge exceeds the Interface endpoint cost (about $7.20/month/AZ), create the endpoint. Added benefit: the traffic stays on the AWS network.

## Transit Gateway vs VPC Peering

| Factor | VPC Peering | Transit Gateway |
|---|---|---|
| Cost | Free (data transfer only: around $0.01/GB cross-AZ) | Around $0.05/hr per attachment plus around $0.02/GB processed |
| Topology | 1:1, non-transitive | Hub-and-spoke, transitive routing |
| Scale | Up to 125 peerings per VPC | Up to 5,000 attachments |
| Cross-region | Supported | Supported |

Decision rule:

- 1 to 5 VPCs: VPC Peering. Simple and cost-effective.
- 5 to 10 VPCs with mesh needs: evaluate Transit Gateway.
- 10+ VPCs or a hub-and-spoke requirement: Transit Gateway. Centralised management outweighs the cost.

## How this maps to the audit

- Step 1 (VPC inventory and design assessment): the subnet-tier model and CIDR-planning discipline above are the yardstick for the design checks.
- Step 3 (Transit Gateway and connectivity assessment): the TGW-vs-Peering selection table explains why a given topology was chosen, which informs whether the current connectivity is appropriate.
- Cost optimisation findings: NAT Gateway placement, missing Gateway endpoints, and over-provisioned NAT in non-production are the highest-value networking cost levers. Non-network AWS cost levers (compute, storage, database, Savings Plans) live in `aws-cloud-ops` (`references/cost.md`).
