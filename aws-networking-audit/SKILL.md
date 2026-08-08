---
name: aws-networking-audit
description: "Use for any AWS VPC networking security audit, posture review, connectivity assessment, or compliance pass. Triggers include \"AWS VPC audit\", \"VPC security review\", \"VPC architecture review\", \"Security Group rule audit\", \"SG rule review\", \"NACL audit\", \"Network ACL review\", \"VPC Flow Log analysis\", \"Flow Log forensics\", \"Transit Gateway routing audit\", \"TGW route table review\", \"TGW propagation audit\", \"VPC peering audit\", \"VPC peering route validation\", \"VPC endpoint review\", \"PrivateLink audit\", \"S3 gateway endpoint check\", \"Route Table validation\", \"black-hole route detection\", \"NAT Gateway placement audit\", \"Internet Gateway exposure check\", \"AWS networking compliance\", \"AWS subnet tier review\", \"AWS public vs private subnet audit\", \"AWS read-only IAM policy for audit\", \"AWS cross-account VPC audit\", \"AWS Organizations VPC visibility\", \"ENI placement review\", \"EIP optimisation\", \"unattached EIP audit\", \"unused Security Group cleanup\", \"default Security Group exposure\", \"0.0.0.0/0 inbound rule audit\", \"SSH from internet audit\", \"RDP from internet audit\", \"VPC CIDR overlap check\", \"secondary CIDR planning\", \"subnet exhaustion check\", \"AZ distribution audit\", \"single-AZ VPC risk review\", \"DNS attribute audit (enableDnsSupport / enableDnsHostnames)\", \"cross-AZ traffic analysis\", \"VPC Flow Log reject rate review\", \"top-talker analysis from Flow Logs\", \"AWS PCI segmentation review\", \"AWS HIPAA networking audit\", \"AWS CIS Foundations VPC controls\", \"AWS NIST 800-53 VPC mapping\", \"AWS post-migration networking audit\". Six-step audit procedure (VPC inventory and design, Security Group and NACL analysis, Transit Gateway and connectivity, VPC Flow Log analysis, Route Table validation, report and resource optimisation). Three threshold tables (Security Group rule severity, VPC Flow Log reject rate, subnet utilisation). Three decision trees (Overly Permissive Security Group rule, VPC Best-Practice Design Review, Transit Gateway Routing Diagnosis). Inlines the VPC packet flow model (Security Group + NACL evaluation order, both directions), the Security Group vs NACL comparison, the Transit Gateway routing model (associations, propagation, static routes), and VPC peering constraints (non-transitive, no overlap, route required in both VPCs, no edge-to-edge routing). AWS-only single-vendor surface; no multi-cloud or vendor-tag splits. Diagnose-first; read-only `aws ec2 describe-*`, `aws logs filter-log-events`, `aws sts get-caller-identity`, `aws iam simulate-principal-policy` throughout. No state-changing commands. Out of scope: CloudFront, WAF, ALB content routing, Route 53. Reference `references/cli-reference.md` for read-only AWS CLI commands organised by audit step, and `references/design-and-cost.md` for VPC design rationale and networking cost optimisation (subnet tiers, CIDR planning, NAT Gateway cost reduction, VPC Endpoint cost framework, Transit Gateway vs peering selection). Maps onto `multi-vendor-network-ops` nine-element response contract for production-impacting recommendations. Pairs with `acl-rule-analysis` for Security Group + NACL rule pattern review, `secrets-hygiene` for IAM and access-key discipline (cross-account assume-role, SSO, `aws configure`), `network-log-analysis` for Flow Log REJECT triage and top-talker aggregation, `siem-log-analysis` for Flow Log to SIEM forwarding (CloudWatch Logs to Splunk / Sumo / Elastic), `incident-response-network` for black-hole route triage and post-incident posture review, `oncall-runbooks` for cross-account audit escalation, `systematic-debugging` for Step 3 connectivity diagnosis and Step 4 Flow Log triage (rule out one layer at a time: SG to NACL to Route Table to TGW propagation), `completion-gate` Layer 3 for production-audit sign-off cadence. Customised from vahagn-madatyan/netsec-skills-suite/aws-networking-audit (Apache-2.0); `references/vpc-architecture.md` fully folded into body (packet flow diagrams, SG vs NACL comparison, TGW routing model, VPC peering constraints, subnet routing patterns); `references/cli-reference.md` kept and cleaned (em-dash purge, US-to-UK spelling); upstream `safety` / `openclaw` / `metadata.author` frontmatter fields dropped per vault four-field House style."
license: Apache-2.0
metadata:
  version: 1.1.0
---

# AWS VPC networking audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: aws-networking-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Cloud resource audit for AWS Virtual Private Cloud (VPC) architecture, security posture, and connectivity. Evaluates provider-specific AWS networking constructs (VPC design, Security Groups, NACLs, Transit Gateway topologies, VPC Flow Logs, Route Tables, ENI placement) rather than generic cloud networking advice.

Scope covers VPC-layer networking: CIDR planning, subnet tier layout, security filtering, inter-VPC connectivity, and traffic observability. Out of scope: CloudFront distributions, WAF rules, application-layer load balancing (ALB content routing), and DNS (Route 53) configuration.

Reference `references/cli-reference.md` for read-only AWS CLI commands organised by audit step.

## When to use

- VPC architecture design review: validating CIDR allocation, subnet tier layout, and AZ distribution before or after deployment.
- Post-migration networking audit: verifying VPC connectivity, Security Group rules, and Route Table entries after workload migration.
- Security assessment: identifying overly permissive Security Group rules, default NACL exposure, and missing VPC Flow Log coverage.
- Connectivity troubleshooting: diagnosing Transit Gateway route propagation failures, VPC peering asymmetric routing, or black-hole routes.
- Compliance preparation: documenting VPC segmentation, Security Group justification, and Flow Log retention for auditors (PCI DSS 4.0, HIPAA, CIS AWS Foundations, NIST 800-53).
- Cost optimisation review: identifying unused Elastic Network Interfaces (ENIs), unattached Elastic IPs (EIPs), and cross-AZ traffic patterns.

## Prerequisites

- **AWS CLI v2** configured with valid credentials (`aws sts get-caller-identity` succeeds).
- **IAM permissions**: minimum read-only policy covering `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`, `ec2:DescribeNetworkAcls`, `ec2:DescribeTransitGateways`, `ec2:DescribeTransitGatewayRouteTables`, `ec2:DescribeRouteTables`, `ec2:DescribeFlowLogs`, `ec2:DescribeNetworkInterfaces`, `ec2:DescribeVpcPeeringConnections`, `ec2:DescribeVpcEndpoints`, `ec2:DescribeAddresses`, `logs:FilterLogEvents`, `logs:DescribeLogGroups`.
- **Target scope identified**: specific VPC ID(s), AWS account, and region. Multi-account audits require cross-account IAM roles or AWS Organizations access.
- **VPC Flow Logs enabled**: Step 4 requires active Flow Logs publishing to CloudWatch Logs or S3. If Flow Logs are not enabled, document this as a Critical finding.
- **Credential handling**: never paste IAM keys or session tokens into the chat. Per `secrets-hygiene` "Probing the credential store" subsection, probe with `aws sts get-caller-identity > /dev/null 2>&1 && echo ok`; never `aws sts get-caller-identity | tee /dev/stderr` or any pattern that surfaces credentials in transcripts.

## Procedure

Six steps in sequence. Each builds on prior findings, moving from inventory through security analysis to optimisation.

### Step 1: VPC inventory and design assessment

Enumerate all VPCs in the target region and assess architectural design.

```
aws ec2 describe-vpcs --region <region> --output table
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --output table
```

For each VPC, evaluate:

- **CIDR block allocation**: primary and secondary CIDR blocks. Check for RFC 1918 compliance, overlapping CIDRs across VPCs (blocks peering), and sufficient address space for growth. VPCs support up to 5 CIDR blocks.
- **Subnet tier layout**: identify public subnets (Route Table routes to Internet Gateway), private subnets (Route Table routes to NAT Gateway), and isolated subnets (no internet route). Verify each tier exists and workloads are placed in the correct tier.
- **Availability Zone distribution**: subnets should span at least 2 AZs for resilience. Single-AZ VPC designs are a High finding.
- **DNS settings**: verify `enableDnsSupport` and `enableDnsHostnames` are enabled. Required for VPC endpoints and private DNS resolution.
- **Tenancy**: default vs dedicated. Dedicated tenancy has significant cost implications; verify it is intentional.

For the design rationale behind these checks (subnet-tier model, CIDR-planning discipline including the Docker 172.17.0.0/16 conflict, NAT Gateway cost-reduction strategies, the VPC Endpoint cost-decision framework, and Transit Gateway vs peering selection), see `references/design-and-cost.md`. Non-network AWS cost levers (compute, storage, database, Savings Plans) live in `aws-cloud-ops`.

### Step 2: Security Group and NACL analysis

Audit stateful Security Group rules and stateless NACL rules for overly permissive access. Before evaluating individual rules, review the VPC packet flow model below to understand the evaluation order: outbound packets traverse the Security Group first (stateful) then the NACL (stateless) then the Route Table; inbound packets traverse the NACL first then the Security Group.

#### VPC packet flow model

##### Outbound packet flow (instance to network)

```
EC2 instance sends packet
        |
        v
+---------------------------+
| Security Group (SG)       |  Stateful. Outbound rules evaluated.
| Outbound rules            |  If denied, packet dropped. SG drops are
|                           |  silent in v2 Flow Logs (no REJECT entry).
+---------------------------+
        | Permitted
        v
+---------------------------+
| Network ACL (NACL)        |  Stateless. Outbound rules evaluated.
| Outbound rules            |  Rules evaluated by number (lowest first).
|                           |  First match wins; default deny at end.
+---------------------------+
        | Permitted
        v
+---------------------------+
| Route Table               |  Longest prefix match determines next hop.
| Route selection           |  Local route handles intra-VPC.
|                           |  Other targets: IGW, NAT GW, TGW, VPC peering,
|                           |  VPC endpoint, etc.
+---------------------------+
        |
        v
   Packet exits subnet
```

##### Inbound packet flow (network to instance)

```
Packet arrives at subnet
        |
        v
+---------------------------+
| Network ACL (NACL)        |  Stateless. Inbound rules evaluated.
| Inbound rules             |  Must explicitly permit return traffic
|                           |  (unlike stateful SG).
+---------------------------+
        | Permitted
        v
+---------------------------+
| Security Group (SG)       |  Stateful. If outbound was allowed,
| Inbound rules             |  return traffic auto-permitted. New
|                           |  connections: inbound rules evaluated.
+---------------------------+
        | Permitted
        v
   Packet delivered to instance ENI
```

**Key audit implication.** Security Groups and NACLs are evaluated independently. A packet can be permitted by the Security Group but denied by the NACL (or vice versa). When troubleshooting connectivity, check both. VPC Flow Logs record the final ACCEPT / REJECT decision after both layers evaluate.

#### Security Group vs NACL comparison

| Property | Security Group | Network ACL |
|----------|---------------|-------------|
| Statefulness | Stateful. Return traffic auto-allowed. | Stateless. Both directions require rules. |
| Scope | ENI-level (attached to instances, ALBs, etc.). | Subnet-level (applies to all traffic in / out of subnet). |
| Rule evaluation | All rules evaluated; permit if any rule matches. | Rules evaluated by number; first match wins. |
| Default behaviour | Default SG: allow all inbound from self, all outbound. | Default NACL: allow all inbound and outbound. |
| Deny rules | Not supported. Rules are permit-only. | Supported. Explicit deny rules by number. |
| Rule limit | 60 inbound + 60 outbound per SG (adjustable). | 20 inbound + 20 outbound per NACL (adjustable). |

##### Audit implications

- **Security Groups alone are usually sufficient** for instance-level access control. NACLs add subnet-level defence-in-depth.
- **NACL deny rules** can block traffic that Security Groups permit. Use NACLs for broad subnet-level blocks (e.g. known malicious CIDRs).
- **Stateless NACL pitfall**: permitting inbound TCP 443 in the NACL without permitting outbound ephemeral ports (1024 to 65535) breaks HTTPS connections. Security Groups handle this automatically via statefulness.

#### Security Group analysis

```
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
```

For each Security Group, evaluate inbound and outbound rules:

- **0.0.0.0/0 inbound rules**: any Security Group rule permitting inbound from `0.0.0.0/0` (or `::/0`) is a finding. Severity depends on port: SSH / RDP from 0.0.0.0/0 is Critical; HTTPS from 0.0.0.0/0 on a public ALB may be acceptable.
- **SG-to-ENI mapping on public subnets**: cross-reference Security Groups with ENIs on public subnets. An overly permissive Security Group attached to an ENI in a public subnet with a public IP is higher risk than the same Security Group on a private subnet.
- **Default Security Group**: the VPC default Security Group allows all inbound from itself and all outbound. If any ENI uses the default Security Group, flag as Medium; workloads should use purpose-specific Security Groups.
- **Unused Security Groups**: Security Groups with no associated ENIs are cleanup candidates.

#### NACL analysis

```
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=<vpc-id>"
```

NACLs are stateless. Evaluate both inbound and outbound rule sets:

- **Rule ordering**: NACLs evaluate rules by rule number (lowest first). A broad permit at rule 100 cannot be overridden by a deny at rule 200. Verify deny rules are numbered lower than corresponding permits.
- **Default NACL**: allows all inbound and outbound traffic. Subnets using the default NACL have no network-layer filtering beyond Security Groups. Flag as Medium if used on production subnets.
- **Ephemeral port range**: outbound NACLs must permit ephemeral ports (1024 to 65535) for return traffic. Missing ephemeral port rules break TCP connections.

### Step 3: Transit Gateway and connectivity assessment

Evaluate inter-VPC and hybrid connectivity through Transit Gateway (TGW), VPC peering, and VPC endpoints.

#### Transit Gateway routing model

Each TGW has one or more route tables. Each attachment (VPC, VPN, peering) is **associated** with exactly one route table and can **propagate** routes to one or more route tables.

```
        VPC-A ---- TGW Attachment ----+
                                      |
        VPC-B ---- TGW Attachment ----+---- Transit Gateway
                                      |       |
        VPC-C ---- TGW Attachment ----+       |
                                              |
        VPN Connection -- TGW Attachment -----+
```

- **Association**: determines which route table is used to route traffic originating from the attachment. A VPC attachment associated with Route Table A uses Table A's routes for outbound traffic.
- **Propagation**: when enabled, the attachment's CIDR is automatically added to the target route table. VPC-A's CIDR propagated to Table B means Table B has a route directing VPC-A traffic to VPC-A's attachment.
- **Static routes**: manually added routes. Override propagated routes if more specific. Used for default routes (0.0.0.0/0 to VPN) or aggregation.

#### TGW audit commands

```
aws ec2 describe-transit-gateways
aws ec2 describe-transit-gateway-route-tables --transit-gateway-id <tgw-id>
aws ec2 search-transit-gateway-routes --transit-gateway-route-table-id <tgw-rt-id> --filters "Name=state,Values=active"
```

- **TGW route table associations**: each VPC attachment should be associated with the correct TGW Route Table. Misassociations cause traffic to route to wrong VPCs.
- **Route propagation**: verify propagation is enabled for VPC attachments that need dynamic routing. Disabled propagation requires manual static routes; check for stale entries.
- **TGW peering**: for multi-region Transit Gateway peering, verify routes are propagated across regions and CIDR blocks don't overlap.
- **Overlapping CIDRs**: two VPCs with overlapping CIDRs attached to the same TGW cause ambiguous routing. TGW uses longest prefix match but overlapping /16 CIDRs result in unpredictable behaviour.
- **Black-hole routes**: TGW routes become black holes when the target attachment is deleted. Check route status = "active" vs "blackhole".
- **Multi-region TGW peering**: routes do not auto-propagate across TGW peering connections. Static routes are required in each region's TGW route table pointing to the peering attachment.

#### VPC peering

```
aws ec2 describe-vpc-peering-connections --filters "Name=status-code,Values=active"
```

##### VPC peering constraints

| Constraint | Detail |
|------------|--------|
| Non-transitive | VPC-A to VPC-B and VPC-B to VPC-C does NOT allow VPC-A to VPC-C. |
| No overlapping CIDRs | Peering fails if VPC CIDRs overlap. |
| Cross-region supported | Inter-region peering incurs data transfer charges. |
| Route required in both VPCs | Each VPC needs a Route Table entry pointing to the peering connection for the peer's CIDR. |
| No edge-to-edge routing | Cannot route through a peer VPC to access its IGW, NAT GW, or VPN. |
| DNS resolution opt-in | `AllowDnsResolutionFromRemoteVpc` must be enabled for cross-VPC private DNS. |

##### Peering vs Transit Gateway

| Criterion | VPC peering | Transit Gateway |
|-----------|------------|-----------------|
| Topology | Point-to-point (N x (N-1)/2 connections for N VPCs). | Hub-and-spoke (N connections for N VPCs). |
| Transitivity | Non-transitive. | Transitive via route tables. |
| Cost | Data transfer only. | Hourly per attachment + data transfer. |
| Scale | Up to 125 peering connections per VPC. | Up to 5,000 attachments per TGW. |
| Use case | Few VPCs, direct low-latency links. | Many VPCs, centralised routing, VPN integration. |

#### VPC endpoints

```
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=<vpc-id>"
```

- **Gateway endpoints**: S3 and DynamoDB. Verify Route Table entries exist for gateway endpoint prefix lists.
- **Interface endpoints (PrivateLink)**: verify ENI placement in appropriate subnets and Security Group rules permit traffic from workloads.

### Step 4: VPC Flow Log analysis

Analyse VPC Flow Logs for security events and traffic patterns. Cross-refs `network-log-analysis` for REJECT pattern triage methodology and `siem-log-analysis` when Flow Logs are forwarded to SIEM (CloudWatch Logs to Kinesis to Splunk / Sumo / Elastic).

```
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=<vpc-id>"
```

Verify Flow Logs are enabled at the VPC level (not just subnet or ENI level) with REJECT and ACCEPT capture. If Flow Logs are not enabled, document as Critical and recommend enabling before further analysis.

For active Flow Logs, query CloudWatch Logs:

```
aws logs filter-log-events --log-group-name <flow-log-group> --filter-pattern "REJECT"
```

Analyse patterns:

- **Reject patterns**: high-volume REJECTs from external IPs suggest scanning or attack traffic. REJECTs between internal subnets indicate Security Group or NACL misconfigurations.
- **Cross-AZ traffic volume**: Flow Logs show source / destination AZ. Significant cross-AZ traffic incurs data transfer costs; identify top cross-AZ flows.
- **Top talkers**: aggregate by source / destination ENI to find highest-volume flows. Unexpected top talkers may indicate compromised instances or data exfiltration.
- **SG deny correlation**: Flow Log REJECTs from specific ENIs should correlate with Security Group rules. If an ENI shows REJECTs for traffic that its Security Group should permit, investigate NACL interference.

### Step 5: Route Table validation

Audit Route Tables for correctness, efficiency, and security.

```
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"
```

#### Subnet types and routing patterns

AWS does not formally label subnets as "public" or "private"; the distinction is determined by Route Table entries.

- **Public subnet**: Route Table contains `0.0.0.0/0 to Internet Gateway (igw-xxx)`. Instances can have public IPs or Elastic IPs. Use for load balancers, bastion hosts, NAT Gateways.
- **Private subnet**: Route Table contains `0.0.0.0/0 to NAT Gateway (nat-xxx)`. Instances reach internet through NAT Gateway (outbound only). Use for application servers, databases, backend services.
- **Isolated subnet**: Route Table contains NO route to `0.0.0.0/0`. No internet access in either direction. May have routes to VPC endpoints (S3, DynamoDB gateway endpoints). Use for sensitive databases, compliance-restricted workloads.

```
For each subnet in VPC:
  1. Find associated Route Table (or main RT if no explicit association).
  2. Check for 0.0.0.0/0 route:
     - Target = igw-xxx     -> Public subnet.
     - Target = nat-xxx     -> Private subnet.
     - No 0.0.0.0/0 route   -> Isolated subnet.
  3. Verify subnet type matches workload requirements.
  4. Check for black-hole routes (deleted targets).
```

For each Route Table, evaluate:

- **Main vs custom Route Tables**: the VPC main Route Table is the default for subnets without explicit association. Verify the main Route Table has restrictive routes; an overly permissive main Route Table affects all unassociated subnets.
- **Most-specific route precedence**: AWS Route Tables use longest prefix match. Verify that more-specific routes take precedence as intended and don't create unintended traffic paths.
- **Black-hole routes**: routes with status "blackhole" indicate the target (NAT Gateway, VPC peering, TGW attachment) was deleted. Black-hole routes silently drop traffic. Remove or replace.
- **NAT Gateway routing**: private subnets should route `0.0.0.0/0` to a NAT Gateway for outbound internet access. Verify NAT Gateway is in a public subnet with an EIP. Multi-AZ deployments should have one NAT Gateway per AZ to avoid cross-AZ traffic and single-AZ failure.
- **VPC endpoint routes**: gateway endpoint routes (S3, DynamoDB prefix lists) should exist in Route Tables for subnets that access those services.

### Step 6: Report and optimisation

Compile findings and identify resource optimisation opportunities.

#### Unused resource cleanup

```
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=<vpc-id>" "Name=status,Values=available"
aws ec2 describe-addresses --filters "Name=domain,Values=vpc"
```

- **Unused ENIs**: ENIs in "available" status are not attached to instances. Identify orphaned ENIs from terminated instances or failed deployments.
- **Unattached EIPs**: Elastic IPs not associated with an ENI incur hourly charges. Release or associate.
- **NAT Gateway optimisation**: consolidate NAT Gateways if traffic volume doesn't justify per-AZ deployment, or deploy per-AZ if cross-AZ data transfer costs exceed NAT Gateway costs.

Compile the findings report using the Report Template section below.

## Threshold tables

### Security Group rule severity

| Finding | Severity | Rationale |
|---------|----------|-----------|
| SG allows SSH (22) from 0.0.0.0/0 | Critical | Direct shell access from internet. |
| SG allows RDP (3389) from 0.0.0.0/0 | Critical | Remote desktop open to internet. |
| SG allows all ports from 0.0.0.0/0 | Critical | No port restriction on internet access. |
| ENI on public subnet using default SG | High | Default SG permits all inbound from group members. |
| SG with >50 inbound rules | High | Excessive complexity; likely over-permissive. |
| SG allows database ports from non-app subnets | High | Database access not restricted to application tier. |
| SG with no description on rules | Medium | Limits auditability and rule justification. |
| SG with 0 associated ENIs | Medium | Unused; cleanup candidate. |

### VPC Flow Log reject rate

| Reject rate (per minute) | Severity | Action |
|---------------------------|----------|--------|
| >1000 external-source REJECTs | High | Active scanning or DDoS; review source IPs. |
| >100 internal-to-internal REJECTs | High | Misconfigured SG or NACL; investigate rules. |
| 10 to 100 external REJECTs | Medium | Background noise; monitor trend. |
| <10 external REJECTs | Low | Normal background scanning. |

### Subnet utilisation

| Available IPs (% of CIDR) | Severity | Action |
|----------------------------|----------|--------|
| <10% remaining | High | Subnet exhaustion risk; plan CIDR expansion. |
| 10 to 25% remaining | Medium | Monitor growth; plan expansion proactively. |
| >75% unused | Low | Over-provisioned; consider smaller CIDR next time. |

## Decision trees

### Is this Security Group rule overly permissive?

```
Security Group rule under review
|-- Source is 0.0.0.0/0 (or ::/0)?
|   |-- Yes
|   |   |-- Port = 22 (SSH) or 3389 (RDP)?
|   |   |   |-- Yes -> CRITICAL: management ports open to internet.
|   |   |   |        Restrict to known IP ranges or use SSM / bastion.
|   |   |   |-- No
|   |   |       |-- Port = 443 (HTTPS) on public-facing ALB / NLB?
|   |   |       |   |-- Yes -> Acceptable for public services.
|   |   |       |   |-- No  -> HIGH: review necessity of open port.
|   |   |       |-- Port = ALL?
|   |   |           |-- CRITICAL: all ports open to internet.
|   |   |-- ENI attached to public subnet instance?
|   |       |-- Yes -> Risk amplified; instance directly reachable.
|   |       |-- No (private subnet) -> Lower risk but still flag.
|   |-- No (specific source CIDR or SG reference)
|       |-- SG self-reference?
|       |   |-- Acceptable for cluster communication.
|       |-- Cross-VPC or broad CIDR (/8, /16)?
|           |-- Medium: verify least-privilege intent.
```

### Is this VPC design following AWS best practices?

```
VPC design under review
|-- Multiple AZs used?
|   |-- No  -> HIGH: single point of failure.
|   |-- Yes
|       |-- Subnet tiers defined (public / private / isolated)?
|       |   |-- No  -> HIGH: flat network; no segmentation.
|       |   |-- Yes
|       |       |-- Public subnets have IGW route?
|       |       |   |-- Verify only intended subnets are public.
|       |       |-- Private subnets route to NAT GW?
|       |       |   |-- Per-AZ NAT GW? -> Best practice.
|       |       |   |-- Single NAT GW  -> Cost-optimised but AZ risk.
|       |       |-- Isolated subnets have no internet route?
|       |           |-- Verify; should only reach VPC endpoints.
|       |-- VPC Flow Logs enabled?
|       |   |-- No  -> CRITICAL: no traffic visibility.
|       |   |-- Yes -> Check retention and capture scope.
|       |-- CIDR planning?
|           |-- Overlaps with peered VPCs? -> Blocks connectivity.
|           |-- Sufficient for growth?     -> Plan secondary CIDRs.
```

### Transit Gateway routing diagnosis

```
TGW connectivity issue (e.g. VPC-A cannot reach VPC-B)
|-- Both VPCs attached to TGW?
|   |-- No -> Attach the missing VPC.
|   |-- Yes
|       |-- VPC-A attachment associated with which RT?
|       |   |-- Note: this RT governs outbound from VPC-A.
|       |-- Does that RT contain a route to VPC-B's CIDR?
|       |   |-- No
|       |   |   |-- Is VPC-B's CIDR propagated to that RT?
|       |   |   |   |-- No -> Enable propagation OR add static route.
|       |   |   |   |-- Yes but route missing -> Check VPC-B's attachment state.
|       |   |-- Yes
|       |       |-- Route state = active or blackhole?
|       |           |-- blackhole -> VPC-B attachment was deleted; replace.
|       |           |-- active    -> Check Security Group + NACL on VPC-B side.
|       |-- VPC-A Route Table contains route to VPC-B's CIDR via TGW?
|           |-- No -> Add route in VPC-A's subnet Route Table (target = TGW attachment).
|           |-- Yes -> Diagnosis points to SG / NACL / instance-level issue.
```

## Report template

```
AWS VPC NETWORKING AUDIT REPORT
==================================
Account: [account-id] ([account-alias])
Region: [region]
VPC: [vpc-id] ([Name tag])
CIDR Blocks: [primary] [secondary if any]
Audit Date: [timestamp]
Performed By: [operator / agent]

VPC ARCHITECTURE:
Subnets: [total] (public:[n] private:[n] isolated:[n])
AZs: [list]
DNS: enableDnsSupport=[yes/no] enableDnsHostnames=[yes/no]
Tenancy: [default / dedicated]

SECURITY GROUPS:
Total: [n] | With 0.0.0.0/0 inbound: [n] | Unused (0 ENIs): [n]
Default SG in use: [yes / no - ENI count]
Rules total: [n] inbound / [n] outbound

NACLs:
Total: [n] | Using default NACL: [n subnets]
Custom NACLs: [n] | Stateless rules reviewed: [n]

CONNECTIVITY:
Transit Gateway: [tgw-id or N/A] | Attachments: [n]
VPC Peering: [n active] | Route validation: [pass / issues]
VPC Endpoints: [n] (gateway:[n] interface:[n])

FLOW LOGS:
Status: [enabled / disabled] | Capture: [ALL / ACCEPT / REJECT]
Log destination: [CloudWatch / S3] | Retention: [days]
Reject rate: [n/min avg] | Top reject sources: [list]

ROUTE TABLES:
Total: [n] | Main RT associations: [n subnets]
Black-hole routes: [n] | NAT GW routes: [n]

RESOURCE OPTIMISATION:
Unused ENIs: [n] | Unattached EIPs: [n]
Cross-AZ traffic: [high / moderate / low]
NAT GW count: [n] across [n] AZs

FINDINGS:
1. [Severity] [Category] - [Description]
   Resource: [sg-xxx / rtb-xxx / nacl-xxx]
   Issue: [detail] -> Recommendation: [action]

RECOMMENDATIONS: [prioritised by severity]
NEXT AUDIT: [CRITICAL findings: 30d, HIGH: 90d, clean: 180d]
```

## Troubleshooting

### VPC Flow Logs not enabled

If `aws ec2 describe-flow-logs` returns empty for the target VPC, Flow Logs are not configured. Document as a Critical finding; no traffic visibility. Flow Logs require an IAM role with `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` permissions. Enabling Flow Logs is a non-disruptive operation.

### Security Group not attached to expected ENI

Use `aws ec2 describe-network-interfaces --filters "Name=group-id,Values=<sg-id>"` to find all ENIs associated with a Security Group. If the expected ENI is missing, check whether the instance was replaced (Auto Scaling) or the SG was modified.

### Transit Gateway route propagation disabled

If TGW routes are missing, verify propagation is enabled on the TGW Route Table for the relevant VPC attachment. Use `aws ec2 get-transit-gateway-route-table-propagations` to check. Disabled propagation requires manual static route entries.

### Black-hole routes in Route Tables

Routes with status "blackhole" occur when the target resource (NAT Gateway, VPC Peering Connection, TGW Attachment) is deleted but the route entry remains. Identify affected subnets and either remove the route or create a replacement target.

### Cross-account VPC audit

For multi-account environments using AWS Organizations, use `aws sts assume-role` to obtain temporary credentials for each account. Alternatively, use AWS Config aggregator or AWS RAM (Resource Access Manager) shared resources for centralised visibility. Per `secrets-hygiene` "Probing the credential store", never persist assumed-role credentials in shell history; pipe them through a subshell capture or use `aws --profile <role-profile>`.

## Nine-element response contract (production-impacting recommendations)

Per `multi-vendor-network-ops`, any recommendation that would alter production AWS networking state MUST include all nine elements. This is the iron rule for production audits; missing any element is a deferral signal, not a green light.

1. **Account**: `<account-id>` (`<account-alias>`).
2. **Region**: `<region>`.
3. **VPC scope**: `<vpc-id>` and any peered / TGW-attached VPCs that share the blast radius.
4. **IAM principal**: which role / user / SSO session will execute the change; verify least-privilege.
5. **Safety tier**: read-only audit (no risk) vs targeted change (defined blast radius) vs broad change (multi-VPC, multi-AZ).
6. **Blast radius**: ENIs / subnets / cross-AZ traffic / inter-VPC connectivity affected.
7. **Rollback path**: explicit `aws` command(s) to reverse the change, OR the AWS Backup / snapshot ID to restore from.
8. **Approval**: who signed off (named human + timestamp), referenced from the audit ticket.
9. **Evidence**: pre-change `aws ec2 describe-*` output, post-change `describe-*` output, Flow Log diff window.

## Cross-link surface

Live cross-refs (vault skills that pair with this one):

- **`multi-vendor-network-ops`**: umbrella; nine-element response contract above.
- **`acl-rule-analysis`**: Security Group + NACL rule pattern catalogue; overly-permissive-rule decision logic carries across to AWS.
- **`secrets-hygiene`**: IAM credentials, access keys, `aws sts assume-role` discipline; "Probing the credential store" pattern applies to every credential probe in this skill.
- **`network-log-analysis`**: VPC Flow Log REJECT triage, top-talker aggregation, cross-AZ accounting (Step 4).
- **`siem-log-analysis`**: Flow Log to SIEM forwarding playbooks (CloudWatch Logs to Kinesis to Splunk / Sumo / Elastic).
- **`incident-response-network`**: black-hole route triage, scanning-pattern response, post-incident SG / NACL review.
- **`oncall-runbooks`**: cross-account audit procedure, severity classification, escalation.
- **`systematic-debugging`**: rule out one layer at a time during connectivity diagnosis (SG -> NACL -> Route Table -> TGW propagation).
- **`completion-gate`** Layer 3: production-audit cadence; sign-off on findings ledger.
- **`plan-time-tooling`**: enumerate this skill plus `secrets-hygiene` + `acl-rule-analysis` + `humanise-comms` + `cite-sources` at any AWS-audit chunk plan-mode entry.
- **`subagent-delegation`**: blast-radius grep before any state-changing follow-on PR.
- **`humanise-comms`**: em-dash purge + spelling cleanup for any audit report or follow-on doc text.
- **`cloud-platform-selection`**: family-level cross-cloud strategy (AWS vs Azure vs GCP selection criteria, Well-Architected principles cross-cloud, migration 7 Rs framework, FinOps practice). Pair when an AWS VPC audit raises strategic questions beyond the VPC layer (should this workload be on AWS at all, multi-cloud egress cost analysis, vendor lock-in considerations, post-migration cost optimisation).
- **`aws-cloud-ops`**: vendor-specific AWS operations (compute, serverless, storage, database, messaging, cost, security, observability). This audit skill owns AWS networking; `aws-cloud-ops` owns the rest of the AWS surface and cross-refers here for VPC depth. Its `references/design-and-cost.md` here is the shared home for VPC design and networking cost; non-network cost levers live in `aws-cloud-ops/references/cost.md`.

Related vault skills:

- `cloud-security-posture`: CSPM control-catalogue cross-mapping (CIS AWS Foundations, NIST 800-53).
- `sase-sse`: ZTA and zero-trust pillar mapping (the network pillar maps to VPC microsegmentation).

- `azure-networking-audit`: multi-cloud parity sibling for Azure VNet audits.
- `gcp-networking-audit`: multi-cloud parity sibling for GCP VPC audits.
- `cloud-network-design`: the vendor-neutral cloud-network design umbrella. This skill audits the running AWS network; that skill owns the cross-cloud design decisions (topology, CIDR, transit, connectivity) and routes per-cloud audit here.

## Out of scope

- **CloudFront distributions** (CDN edge; separate audit surface).
- **WAF rules** (web application firewall; separate audit surface).
- **ALB content routing** (L7 routing; covered by application-layer audits).
- **Route 53 / DNS** (separate audit; covers public DNS, private hosted zones, DNSSEC).
- **State-changing AWS commands**: this skill is read-only. All commands are `describe-*`, `get-*`, `list-*`, `search-*`, `filter-*`, `simulate-*`. Any remediation step a finding implies is surfaced as a recommendation, not executed.
- **General AWS troubleshooting unrelated to VPC networking**: use vendor docs or service-specific skills.

## Provenance

Customised from `https://github.com/vahagn-madatyan/netsec-skills-suite/tree/main/skills/aws-networking-audit` (Apache-2.0). Vault customisations:

- **Frontmatter**: 4-field House style (`name` + `description` + `license: Apache-2.0` + `metadata: { version: 1.0.0 }`). Upstream `safety: read-only`, `openclaw: {...}`, `metadata.author`, `metadata.safety` fields dropped (vault tooling does not consume them).
- **Description**: rewritten for vault Claude-Search-Optimisation discipline; trigger-phrase dense; covers 60+ surface forms across all six step domains plus compliance and cost-optimisation framings.
- **`references/vpc-architecture.md` fully folded into body**: packet flow diagrams (Step 2), Security Group vs NACL comparison (Step 2), Transit Gateway routing model (Step 3), VPC peering constraints (Step 3), subnet types and routing patterns (Step 5). Upstream file deleted; vault keeps only `references/cli-reference.md`.
- **`references/cli-reference.md` kept**: em-dash purged, US-to-UK spelling cleaned, header rewritten to point back at vault SKILL.md.
- **Em-dash purge**: zero em-dashes anywhere in SKILL.md or cli-reference.md (upstream had 31 + 2). Vault `humanise-comms` discipline.
- **US-to-UK spelling**: `optimi[sz]ation`, `behavio[u]r`, `organi[sz]e`, `analy[sz]e`, `centrali[sz]e`, `defen[cs]e` etc. normalised to UK forms throughout (the `z` variants converted to `s`; the `or` variants gain `u`).
- **Skill marker block**: added at top of body per vault convention.
- **Nine-element response contract**: added to map onto `multi-vendor-network-ops` (vault umbrella iron rule for production-impacting recommendations).
- **Cross-link surface**: extended beyond upstream to cover the live vault skills above; the cloud-network family (`cloud-network-design`, `azure-networking-audit`, `gcp-networking-audit`) has since landed, so those placeholders are now live cross-refs.
- **Secrets-hygiene cross-link**: added at Prerequisites + Step 6 troubleshooting; "Probing the credential store" pattern (PR #100 in Skills-Vault) applies to every credential probe.
- **`references/design-and-cost.md` added (Chunk C PR3)**: VPC design rationale and networking cost-optimisation depth folded from `chrishuffman5/domain-expert/skills/cloud-platforms/aws/references/networking.md` (MIT). Only the additive VPC-centric design and cost material was taken (subnet-tier model, CIDR planning including the Docker 172.17.0.0/16 conflict, NAT Gateway cost reduction, VPC Endpoint cost framework, Transit Gateway vs peering selection); the source's Route 53, CloudFront, and ALB/NLB/GLB sections were deferred to the DNS and load-balancer families rather than duplicated here. Em-dash purge and British / Pacific English applied. `metadata.version` bumped 1.0.0 to 1.1.0 for the fold. This is a permissive MIT fold into an Apache-2.0 skill; both licences are compatible and the source is attributed here and in `merged-skills-registry`.

See `merged-skills-registry/SKILL.md` for the full registry row and audit history.
