---
name: gcp-networking-audit
description: "Use for any GCP VPC networking security audit, posture review, connectivity assessment, or compliance pass. Triggers include \"GCP VPC audit\", \"GCP VPC Network audit\", \"VPC Network security review\", \"global VPC review\", \"GCP subnet tier review\", \"auto-mode vs custom-mode VPC audit\", \"GCP firewall rule audit\", \"firewall priority\", \"firewall priority evaluation audit\", \"hierarchical firewall policy audit\", \"org-level firewall policy review\", \"goto_next vs deny audit\", \"target tag vs service account firewall audit\", \"default-allow rules audit\", \"0.0.0.0/0 ingress firewall\", \"SSH/RDP from internet GCP\", \"Cloud NAT egress audit\", \"Cloud NAT port exhaustion\", \"Cloud NAT port allocation review\", \"Dynamic Port Allocation audit\", \"Cloud NAT logging audit\", \"Cloud Interconnect audit\", \"VLAN attachment state review\", \"Cloud VPN tunnel audit\", \"HA VPN review\", \"Shared VPC audit\", \"host/service project model audit\", \"compute.networkUser subnet IAM review\", \"Cloud Router BGP audit\", \"dynamic routing mode audit\", \"regional vs global routing\", \"VPC peering audit GCP\", \"VPC Network Peering constraints\", \"Private Google Access audit\", \"VPC Flow Log enablement audit GCP\", \"unused external IP audit\", \"reserved static IP cleanup\", \"GCP subnet exhaustion check\", \"GCP CIS networking\", \"GCP CIS Foundations network controls\", \"GCP NIST/PCI/HIPAA networking\", \"GCP post-migration networking audit\". Six-step audit procedure (VPC Network inventory and design, firewall rule and hierarchical policy analysis, Cloud NAT and egress, connectivity via Cloud Interconnect / Cloud VPN / Shared VPC, Cloud Router and routing validation, report and resource optimisation). Three threshold tables (firewall rule severity, Cloud Interconnect health, Cloud NAT port utilisation). Two decision trees (overly permissive firewall rule, GCP VPC Network best-practice design review). Inlines the GCP global-VPC-with-regional-subnets model (global VPC vs AWS/Azure regional comparison, auto-mode vs custom-mode), the firewall rule priority and hierarchical firewall policy evaluation order (org then folder then VPC priority 0-65534 then implied deny-ingress/allow-egress at 65535), Cloud NAT egress and port allocation, the Shared VPC host/service-project model and subnet-level IAM, Cloud Router BGP and dynamic routing mode, and GCP VPC Network Peering constraints (non-transitive, no overlapping subnet ranges, both sides must peer, subnet routes auto-exchanged, no firewall tag propagation). GCP-only single-vendor surface; no multi-cloud or vendor-tag splits. Diagnose-first; read-only `gcloud compute networks`, `gcloud compute firewall-rules`, `gcloud compute routers`, `gcloud compute interconnects`, `gcloud auth list` throughout. No state-changing commands. Out of scope: Cloud CDN, Cloud Armor WAF, load balancer URL maps, Cloud DNS. Reference `references/cli-reference.md` for read-only gcloud commands organised by audit step. Maps onto `multi-vendor-network-ops` nine-element response contract for production-impacting recommendations. Routes cross-cloud design decisions up to `cloud-network-design`; parity siblings `aws-networking-audit` and `azure-networking-audit`. Pairs with `acl-rule-analysis` for firewall rule pattern review, `secrets-hygiene` for GCP credential / service-account / `gcloud auth` discipline, `network-log-analysis` for VPC Flow Log REJECT triage and top-talker aggregation, `cloud-security-posture` for the CSPM control-catalogue boundary, `siem-log-analysis`, `incident-response-network`, `oncall-runbooks`, `systematic-debugging` for layer-by-layer connectivity diagnosis, `completion-gate` for production-audit sign-off, `utc-timestamps` for audit-timestamp discipline. Customised from vahagn-madatyan/netsec-skills-suite/gcp-networking-audit (Apache-2.0); `references/vpc-architecture.md` folded into body; `references/cli-reference.md` kept and cleaned; upstream safety/openclaw/author frontmatter dropped per vault four-field house style."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# GCP VPC networking audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: gcp-networking-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Cloud resource audit for Google Cloud Platform VPC Network architecture, firewall posture, and connectivity. Evaluates provider-specific GCP networking constructs (global VPC Network design, firewall rule priority evaluation, hierarchical firewall policies, Cloud NAT egress control, Cloud Interconnect VLAN attachments, Shared VPC host / service project topology, Cloud Router BGP sessions) rather than generic cloud networking advice.

Scope covers VPC-layer networking: auto-mode versus custom-mode VPC Networks, subnet IP ranges and secondary (alias IP) ranges, firewall rules with target tags and service accounts, Cloud NAT port allocation, Cloud Interconnect and Cloud VPN connectivity, Shared VPC cross-project networking, and Cloud Router dynamic routing. Out of scope: Cloud CDN, Cloud Armor WAF, load balancer URL maps, and Cloud DNS.

Reference `references/cli-reference.md` for read-only gcloud commands organised by audit step.

## When to use

- VPC Network architecture design review: validating auto-mode versus custom-mode selection, subnet IP ranges, secondary ranges for GKE, and Private Google Access before or after deployment.
- Post-migration networking audit: verifying firewall rules, Cloud NAT egress, and Cloud Router routes after workload migration.
- Security assessment: identifying permissive firewall rules using target tags, missing hierarchical firewall policies, `0.0.0.0/0` ingress, and disabled VPC Flow Logs.
- Connectivity troubleshooting: diagnosing Cloud Interconnect VLAN attachment failures, Cloud VPN tunnel errors, Cloud Router BGP session flapping, or Shared VPC permission issues.
- Compliance preparation: documenting VPC Network segmentation, firewall rule justification, and VPC Flow Log retention for auditors (PCI DSS 4.0, HIPAA, CIS GCP Foundations, NIST 800-53).
- Cost optimisation review: identifying unused reserved external IPs, over-provisioned Cloud NAT gateways, and idle Cloud Interconnect attachments.

## Prerequisites

- **gcloud CLI** authenticated (`gcloud auth list` shows an active account).
- **IAM permissions**: Viewer role on the target project, or granular read: `compute.networks.get`, `compute.firewalls.list`, `compute.routers.get`, `compute.interconnects.get`, `compute.subnetworks.list`, `compute.addresses.list`. Shared VPC audits require Viewer on both host and service projects. Hierarchical firewall policies require `compute.firewallPolicies.get` at the organisation or folder level.
- **Target scope identified**: project ID, organisation ID (for hierarchical firewall policies), and the Shared VPC host project if applicable.
- **VPC Flow Logs**: Step 1 checks subnet-level enablement. VPC Flow Logs in GCP are per-subnet, not VPC-level. If no production subnets have Flow Logs enabled, document this as a Critical finding.
- **Credential handling**: never paste service-account keys or access tokens into the chat. Per `secrets-hygiene` "Probing the credential store" subsection, probe with `gcloud auth list --filter="status:ACTIVE" --format="value(account)" > /dev/null 2>&1 && echo ok`; never a pattern that surfaces credentials or key material in transcripts.

## Procedure

Six steps in sequence. Each builds on prior findings, moving from inventory through security analysis to optimisation.

### Step 1: VPC Network inventory and design assessment

Enumerate all VPC Networks in the target project and assess architectural design. Before evaluating individual networks, review the GCP global VPC Network model below: unlike AWS (VPC is regional) and Azure (VNet is regional), a GCP VPC Network is a global resource, and its subnets are regional members of that one global network.

#### GCP global VPC Network model

A single GCP VPC Network spans all GCP regions. Subnets are regional but belong to the global VPC Network, so cross-region traffic within one VPC Network needs no peering or transit construct. This is the single most important structural difference an auditor carries over from AWS or Azure.

| Property | GCP | AWS | Azure |
|----------|-----|-----|-------|
| VPC / VNet scope | Global | Regional | Regional |
| Subnet scope | Regional | AZ-specific | Regional |
| Cross-region within VPC | Native (one VPC Network) | Requires Transit Gateway or peering | Requires VNet Peering |
| Firewall scope | VPC Network-wide (rules select by tag / service account) | Security Group per ENI | NSG per subnet or NIC |
| Default network | Created automatically (deletable) | Created per region (deletable) | None |

##### Auto-mode versus custom-mode VPC Networks

- **Auto-mode**: automatically creates one subnet per GCP region using predetermined /20 ranges from `10.128.0.0/9`, and new regions gain subnets automatically. Problematic in production: the predetermined ranges may conflict with on-premises or peer networks, the region set cannot be controlled, and the /20 sizing may not match capacity. Auto-mode can be converted to custom-mode (one-way, irreversible).
- **Custom-mode**: no automatic subnets; every subnet is explicitly defined with a chosen IP range in a chosen region. Required for production: full control over IP allocation (avoids conflicts with Cloud Interconnect or Cloud VPN peer networks), subnets sized to workload, and regions selected intentionally.

For each VPC Network, evaluate:

- **Auto-mode vs custom-mode**: production environments should use custom-mode. Auto-mode in production is a High finding when connected to on-premises (IP conflicts likely), Medium otherwise (uncontrolled IP allocation).
- **Global scope**: verify subnet distribution matches workload regions. A single VPC Network hosts subnets in every region without peering.
- **Subnet IP ranges**: primary ranges serve VMs; secondary ranges serve GKE Pod and Service CIDRs (alias IP ranges). Check for overlapping ranges across networks that must peer, and sufficient growth space.
- **Private Google Access**: enables VMs without external IPs to reach Google APIs. Disabled Private Google Access on internal-only subnets is a Medium finding.
- **VPC Flow Logs**: enablement is per-subnet in GCP, not VPC-level as in AWS. Subnets without Flow Logs lack traffic visibility; flag as High for production subnets.

```
gcloud compute networks list --project <project-id>
gcloud compute networks describe <network-name> --project <project-id>
gcloud compute networks subnets list --network <network-name>
```

### Step 2: Firewall rule and hierarchical policy analysis

Audit VPC Network firewall rules using GCP's priority-based evaluation, then the hierarchical firewall policies that evaluate before them. Before evaluating individual rules, review the evaluation order below: a rule at a higher level (organisation, then folder) can override rules at lower levels (VPC priority-numbered rules, then the implied rules).

#### Firewall rule evaluation order

```
Packet arrives at VM
        |
        v
+------------------------------+
| Hierarchical firewall policy |  Organisation-level policies
| (org level)                  |  evaluated first.
|                              |  Actions: allow, deny, goto_next.
+------------------------------+
        | goto_next (or no match)
        v
+------------------------------+
| Hierarchical firewall policy |  Folder-level policies
| (folder level)               |  evaluated second.
|                              |  Actions: allow, deny, goto_next.
+------------------------------+
        | goto_next (or no match)
        v
+------------------------------+
| VPC Network firewall rules   |  Project-level rules evaluated by
| (priority 0 to 65534)        |  priority number. Lowest number =
|                              |  highest priority. First match wins.
+------------------------------+
        | No match in custom rules
        v
+------------------------------+
| Implied rules                |  Deny all ingress (priority 65535).
| (priority 65535)             |  Allow all egress (priority 65535).
+------------------------------+
```

##### Hierarchical firewall policy actions

| Action | Effect |
|--------|--------|
| `allow` | Permit traffic; skips VPC-level rules entirely. |
| `deny` | Block traffic; skips VPC-level rules entirely. |
| `goto_next` | Delegate the decision to the next level (folder, then VPC rules). |
| No match | Implicitly delegates to the next level (same as `goto_next`). |

**Key audit implications.**

- A `deny` in an org-level hierarchical firewall policy overrides any VPC-level `allow`. Use it for organisation-wide blocks (for example, block SSH from the internet globally).
- A `goto_next` at org level delegates to folder level, then to VPC rules. This is the typical pattern for rules that project teams should be able to override.
- VPC firewall rules with priority 0 override all other VPC-level rules but cannot override a hierarchical policy `deny`.
- Implied rules (priority 65535) are the final fallback: deny ingress, allow egress. Any custom VPC rule at any priority overrides the implied rules.

#### VPC Network firewall rule analysis

GCP firewall rules evaluate by priority (0 to 65535, lowest number = highest priority). First match wins.

```
gcloud compute firewall-rules list --filter="network:<network-name>"
gcloud compute firewall-rules describe <rule-name>
```

For each firewall rule, evaluate:

- **Implied rules**: every VPC Network has an implied deny-all-ingress and allow-all-egress at priority 65535. These are not shown by `gcloud compute firewall-rules list` but are active; custom rules at 0 to 65534 override them.
- **Priority conflicts**: an allow at priority 1000 overrides a deny at priority 2000. Verify deny rules have lower priority numbers than any conflicting allow.
- **Target tags vs service accounts**: target tags are mutable labels, so any project editor can change VM tags to bypass a rule. Service account targets are IAM-controlled and more secure. Flag tag-based rules on sensitive workloads as Medium.
- **Source ranges**: any rule permitting ingress from `0.0.0.0/0`. SSH (22) or RDP (3389) from `0.0.0.0/0` is Critical. Verify broad ranges are justified.
- **Disabled rules**: GCP firewall rules can be disabled without deletion. A disabled deny rule leaves a security gap; an undocumented disabled rule is audit confusion.
- **Default network rules**: the `default` VPC Network ships with pre-created rules allowing ICMP, SSH, RDP, and internal traffic. Audit these permissive rules explicitly.

#### Hierarchical firewall policies

```
gcloud compute firewall-policies list --organization <org-id>
gcloud compute firewall-policies describe <policy-name>
gcloud compute firewall-policies rules list --firewall-policy <policy-name>
```

Hierarchical firewall policies apply at the organisation or folder level and evaluate before VPC Network firewall rules. Verify they enforce org-wide baselines (for example, block SSH from the internet) and that `goto_next` is used only where project-level override is intended.

### Step 3: Cloud NAT and egress analysis

Audit Cloud NAT gateways for egress capacity, port allocation, and logging. Cloud NAT provides outbound internet access for VMs without external IPs and is configured on a Cloud Router.

```
gcloud compute routers nats list --router <router-name> --region <region>
gcloud compute routers nats describe <nat-name> --router <router-name> --region <region>
```

For each Cloud NAT gateway, evaluate:

- **IP allocation method**: automatic (GCP assigns IPs) or manual (reserved IPs). Manual provides predictable egress IPs for third-party allowlisting.
- **Port allocation**: the default minimum is 64 ports per VM. Port exhaustion silently drops connections. Check `minPortsPerVm` and `maxPortsPerVm`. High-connection workloads need increased allocations; enable Dynamic Port Allocation for bursty workloads.
- **Endpoint-Independent Mapping**: when enabled, Cloud NAT uses consistent IP:port mappings, improving protocol compatibility. Disabled by default.
- **Cloud NAT logging**: verify `logConfig.enable`. Options: `ERRORS_ONLY`, `TRANSLATIONS_AND_ERRORS` (recommended), `ALL`. Missing NAT logging reduces egress visibility.
- **Subnet coverage**: Cloud NAT applies to all subnets or specific subnets. Verify production subnets are covered.

In a Shared VPC, Cloud NAT is configured in the host project's Cloud Router; verify it there, not in the service projects.

### Step 4: Connectivity analysis

Evaluate hybrid and cross-project connectivity via Cloud Interconnect, Cloud VPN, Shared VPC, and VPC Network Peering.

#### Cloud Interconnect

Cloud Interconnect provides dedicated physical connectivity between on-premises networks and GCP VPC Networks. A customer router peers over a cross-connect at a colocation facility to a Google Edge POP, which terminates a VLAN attachment that in turn peers with a Cloud Router over BGP into the VPC Network.

```
gcloud compute interconnects list
gcloud compute interconnects describe <interconnect-name>
gcloud compute interconnects attachments list --region <region>
gcloud compute interconnects attachments describe <attachment-name> --region <region>
```

- **VLAN attachment state**: verify `state: ACTIVE` and `operationalStatus: OS_ACTIVE`. `UNPROVISIONED_ATTACHMENT` means partner provisioning is incomplete; `PENDING_PARTNER` waits for partner-side configuration; `OS_LACP_DOWN` indicates a link-aggregation (Layer 2) failure; `DEFUNCT` means the attachment is no longer functional.
- **BGP session health**: each VLAN attachment peers with a Cloud Router via BGP. `UP` is healthy; `DOWN` indicates an ASN mismatch, authentication failure, or network issue. Verify both primary and redundant sessions.
- **MED values**: the Multi-Exit Discriminator influences route preference across multiple attachments. Lower MED is preferred; verify values match the active / standby design.
- **Redundancy**: production requires connections in two edge availability domains. A single-connection topology is a High finding.

##### Cloud Interconnect redundancy model

| Topology | SLA | Use case |
|----------|-----|----------|
| Single connection, single domain | No SLA | Development or test only. |
| Dual connections, two domains | 99.9% | Standard production. |
| Four connections, two domains | 99.99% | Mission-critical. |

#### Cloud VPN

```
gcloud compute vpn-tunnels list
gcloud compute vpn-tunnels describe <tunnel-name> --region <region>
gcloud compute vpn-gateways list
```

- **Tunnel status**: should show `status: ESTABLISHED`. `FIRST_HANDSHAKE` indicates IKE negotiation in progress; `NO_INCOMING_PACKETS` suggests an on-premises misconfiguration.
- **HA VPN**: High Availability VPN provides two tunnels for a 99.99% SLA. Use HA VPN for production; Classic VPN offers no redundancy SLA.

#### Shared VPC

Shared VPC enables centralised network management: a host project owns the VPC Network and service projects deploy workloads into shared subnets.

```
gcloud compute shared-vpc get-host-project <service-project-id>
gcloud compute shared-vpc list-associated-resources <host-project-id>
gcloud compute networks subnets get-iam-policy <subnet> --region <region> --project <host-project>
```

##### Shared VPC IAM model

- **Host project admin**: `compute.xpnAdmin` can share subnets and manage the host project designation.
- **Service project users**: `compute.networkUser` on specific subnets can deploy resources into those shared subnets.
- **Scoping**: grant `compute.networkUser` at the subnet level, not the project level, for least-privilege access.

##### Shared VPC audit checks

| Check | How |
|-------|-----|
| Host project designation correct | `gcloud compute shared-vpc get-host-project <service-project>` |
| Service projects associated | `gcloud compute shared-vpc list-associated-resources <host-project>` |
| Subnet IAM not over-broad | `get-iam-policy` per subnet; verify no wildcard principals hold `compute.networkUser`. |
| Firewall rules in host project | Firewall rules live in the host project, not the service projects. |
| Cloud NAT in host project | Cloud NAT must be configured on the host project's Cloud Router. |
| Private Google Access inheritance | Service projects inherit the host project subnet setting; verify enablement. |

#### VPC Network Peering

VPC Network Peering connects two VPC Networks (same or different projects or organisations) so they exchange internal traffic using internal IPs.

```
gcloud compute networks peerings list --network <network-name>
```

##### VPC Network Peering constraints

| Constraint | Detail |
|------------|--------|
| Non-transitive | Network-A peered with Network-B and Network-B peered with Network-C does NOT allow Network-A to reach Network-C. |
| No overlapping subnet ranges | Peering is rejected if primary or secondary subnet ranges overlap between the two networks. |
| Both sides must peer | Each network must independently create the peering; the connection is active only when both configurations match. |
| Subnet routes auto-exchanged | Subnet and secondary (alias) routes are exchanged automatically; static and dynamic routes are not exchanged by default. |
| No firewall tag / service account propagation | Target tags and service accounts do not cross a peering; firewall rules in one network cannot select instances in the peer by tag or service account. |
| No Private Google Access transit | A peer cannot reach Google APIs through the other network's Private Google Access. |

### Step 5: Cloud Router and routing validation

Audit Cloud Router configuration for route advertisements, BGP settings, and dynamic routing mode. Cloud Router provides BGP-based dynamic routing for Cloud Interconnect, Cloud VPN, and router appliances.

```
gcloud compute routers list --project <project-id>
gcloud compute routers describe <router-name> --region <region>
gcloud compute routers get-status <router-name> --region <region>
```

`get-status` returns learned routes, advertised routes, and BGP peer state in one call; it is the most comprehensive routing view.

- **Dynamic routing mode**: `regional` or `global`. Regional Cloud Routers advertise and learn routes only within their region; global mode propagates routes across all regions. Multi-region workloads reaching on-premises via a single-region Cloud Interconnect require global mode.
- **Custom route advertisements**: the default advertises all subnets. Custom mode overrides this. Verify that custom advertisements do not accidentally exclude required subnets.
- **Graceful restart**: preserves forwarding during Cloud Router updates. Enable it for production routers.
- **AS path analysis**: review `get-status` learned routes and AS paths. Unexpected paths indicate route leaks or suboptimal selection.
- **Route priorities**: custom routes use priority 0 to 65535 (default 1000); lower is preferred. Verify priorities create the intended active / standby or ECMP behaviour.
- **Learned route limits**: Cloud Router has per-region learned-route limits. Approaching a limit causes route drops; check `get-status` for count versus limit.

#### Cloud Router routing model

##### Routing mode impact

| Mode | Subnet advertisement | Learned route scope |
|------|----------------------|---------------------|
| Regional | Subnets in the same region only | Applied to the same region only. |
| Global | All subnets in the VPC Network | Applied to all regions. |

##### Route selection precedence

GCP selects routes in this order:

1. **Most specific prefix**: a /24 beats a /16 for matching traffic.
2. **Route type**: subnet routes, then peering routes, then Cloud Router (dynamic) routes, then static routes, then the default internet route.
3. **Priority value**: lower number preferred (0 to 65535, default 1000).
4. **ECMP**: equal-priority, equal-prefix routes are load-balanced.

##### BGP session states

| State | Meaning |
|-------|---------|
| UP | BGP session established, routes exchanged. |
| DOWN | No BGP session; check configuration. |
| MD5_AUTH_INTERNAL_PROBLEM | Authentication key mismatch. |

A route whose `nextHopIp` points to a stopped VM silently drops packets, the GCP analogue of an AWS black-hole route. Check for these during routing validation.

### Step 6: Report and optimisation

Compile findings and identify resource optimisation opportunities.

```
gcloud compute addresses list --filter="status=RESERVED" --project <project-id>
gcloud compute instances list --filter="networkInterfaces[].accessConfigs[].natIP:*"
gcloud compute firewall-rules list --filter="disabled=true"
```

- **Unused static IPs**: reserved external IPs not associated with a resource incur charges. Release unused addresses.
- **Disabled firewall rules**: create audit confusion. Delete or document a justification.
- **Over-permissive tag-based rules**: firewall rules targeting broad tags on high-privilege workloads should migrate to service account targets.
- **IP address utilisation**: GCP reserves 4 addresses per subnet. Subnets with under 10% available are exhaustion risks; over-provisioned subnets waste space, which matters most in Shared VPC.
- **Cloud NAT consolidation**: multiple gateways per region are unnecessary unless subnets need different configurations.

Compile the findings report using the Report template section below.

## Threshold tables

### Firewall rule severity

| Finding | Severity | Rationale |
|---------|----------|-----------|
| Firewall rule allows SSH (22) from 0.0.0.0/0 | Critical | Shell access from the internet. |
| Firewall rule allows RDP (3389) from 0.0.0.0/0 | Critical | Remote desktop from the internet. |
| Firewall rule allows all ports from 0.0.0.0/0 | Critical | No port restriction on ingress. |
| Target tag on sensitive workload instead of service account | High | Tags are mutable by project editors. |
| Hierarchical firewall policy missing at org level | High | No organisation-wide baseline. |
| VPC Flow Logs disabled on production subnet | High | No traffic visibility. |
| Firewall rule with priority 0 | High | Audit for broad scope; overrides all other VPC rules. |
| Disabled firewall rule undocumented | Medium | Audit confusion risk. |
| Auto-mode VPC Network in production | Medium | Uncontrolled IP allocation. |
| Firewall rule with >20 source ranges | Medium | Excessive complexity. |

### Cloud Interconnect health

| Metric | Severity | Action |
|--------|----------|--------|
| VLAN attachment state not ACTIVE | Critical | No traffic flow; engage the provider. |
| BGP session DOWN | High | Check ASN, authentication, and link. |
| Single edge availability domain | High | No redundancy; add a second domain. |
| Learned route count >80% of limit | Medium | Approaching route capacity. |

### Cloud NAT port utilisation

| Available ports (%) | Severity | Action |
|---------------------|----------|--------|
| <10% | Critical | Connection drops; increase allocation. |
| 10 to 25% | High | Enable Dynamic Port Allocation. |
| 25 to 50% | Medium | Monitor the trend. |
| >50% | Low | Healthy. |

## Decision trees

### Is this firewall rule overly permissive?

```
Firewall rule under review
|-- Source range is 0.0.0.0/0?
|   |-- Yes
|   |   |-- Port = 22 (SSH) or 3389 (RDP)?
|   |   |   |-- Yes -> CRITICAL: use an IAP tunnel instead of internet exposure.
|   |   |   |-- No
|   |   |       |-- Port = 443 on a load balancer backend?
|   |   |       |   |-- Yes -> Acceptable for public services.
|   |   |       |   |-- No  -> HIGH: review necessity of the open port.
|   |   |       |-- All ports (all protocols)?
|   |   |           |-- CRITICAL: unrestricted ingress.
|   |   |-- Is the rule disabled?
|   |       |-- Yes -> LOW: verify it should remain disabled.
|   |       |-- No  -> Classify severity by port scope above.
|   |-- No (specific CIDR or service account source)
|       |-- Target uses a service account? -> Stronger, IAM-controlled binding.
|       |-- Target uses a network tag?
|           |-- Tag on a sensitive workload? -> MEDIUM: migrate to a service account target.
|           |-- Tag on dev / test?           -> LOW: acceptable.
```

### Is this VPC Network design following GCP best practices?

```
VPC Network under review
|-- Custom-mode?
|   |-- No (auto-mode)
|   |   |-- Connected to on-premises? -> HIGH: IP conflicts likely.
|   |   |-- Production only            -> MEDIUM: convert to custom-mode.
|   |   |-- Development / test only    -> Acceptable.
|   |-- Yes
|       |-- Subnets in the required regions? -> Verify distribution.
|       |-- VPC Flow Logs on production subnets?
|       |   |-- No  -> HIGH: no traffic visibility.
|       |   |-- Yes -> Check aggregation interval and sampling rate.
|       |-- Private Google Access on internal-only subnets?
|           |-- No  -> MEDIUM: internal VMs cannot reach Google APIs.
|           |-- Yes -> Good.
|-- Shared VPC?
|   |-- Yes -> Audit host designation, per-subnet IAM, service project associations.
|   |-- No  -> OK for single-project.
|-- Hierarchical firewall policy present?
|   |-- No  -> HIGH: no org-wide baseline.
|   |-- Yes -> Audit goto_next vs deny placement.
|-- Dynamic routing mode?
    |-- Regional + multi-region workload -> Switch to global.
    |-- Global -> Verify cross-region propagation.
```

## Report template

```
GCP VPC NETWORK AUDIT REPORT
================================
Project: [project-id] ([project-name])
Organization: [org-id or N/A]
VPC Network: [network-name]
Routing Mode: [regional / global]
Network Type: [auto-mode / custom-mode]
Audit Date: [timestamp]
Performed By: [operator / agent]

VPC NETWORK ARCHITECTURE:
Subnets: [total] across [n] regions
Type: [auto-mode / custom-mode]
Private Google Access: [enabled on n / total subnets]
VPC Flow Logs: [enabled on n / total subnets]

FIREWALL RULES:
Total: [n] | With 0.0.0.0/0 ingress: [n] | Disabled: [n]
Target type: tag-based:[n] service-account:[n] all-instances:[n]
Hierarchical policies: [n at org] [n at folder]

CLOUD NAT:
Gateways: [n] | Covered subnets: [n]
IP allocation: [automatic / manual] | Port min: [n]
NAT logging: [enabled / disabled]

CONNECTIVITY:
Cloud Interconnect: [n attachments] | BGP: [UP / DOWN]
Cloud VPN: [n tunnels] | Status: [ESTABLISHED / other]
Shared VPC: [host-project or N/A] | Service projects: [n]
VPC Network Peering: [n active]

CLOUD ROUTER:
Routers: [n] | Dynamic mode: [regional / global]
Custom advertisements: [yes / no]
Graceful restart: [enabled / disabled]
Learned routes: [n] / [limit]

OPTIMISATION:
Unused static IPs: [n] | Disabled firewall rules: [n]
Tag-based rules on sensitive workloads: [n]
Cloud NAT port utilisation: [assessment]

FINDINGS:
1. [Severity] [Category] - [Description]
   Resource: [resource-name] -> Recommendation: [action]

RECOMMENDATIONS: [prioritised by severity]
NEXT AUDIT: [CRITICAL findings: 30d, HIGH: 90d, clean: 180d]
```

## Troubleshooting

### VPC Flow Logs not enabled on subnets

VPC Flow Logs in GCP are subnet-level, not VPC-level; each subnet must be enabled individually. Enabling is non-disruptive. Missing Flow Logs on production subnets is a High finding. Use `gcloud compute networks subnets describe <subnet> --region <region> --format="value(logConfig)"` per subnet.

### Firewall rule not applied to expected VMs

Verify the target. If the rule uses a target tag, confirm the tag is present on the VM (tags are case-sensitive). If it uses a service account target, verify the VM runs with that service account. A firewall rule with no target applies to all VMs in the VPC Network.

### Cloud Interconnect VLAN attachment not active

Check `state` and `operationalStatus`. `UNPROVISIONED_ATTACHMENT` means partner provisioning is incomplete; `OS_LACP_DOWN` indicates a Layer 2 failure. Verify the Cloud Router BGP session has the correct ASN and IP pair.

### Shared VPC service project cannot deploy to a subnet

Verify the deploying service account holds `compute.networkUser` on the specific subnet in the host project. Subnet-level IAM is required even when the service project is associated with the host project.

### Cloud Router BGP session flapping

Check Cloud Logging with `resource.type="gce_router"`. Common causes: the on-premises router exceeding its learned-route limit, an authentication key mismatch, or MTU issues on the Cloud Interconnect link. Enable graceful restart to preserve forwarding during brief flaps.

## Nine-element response contract (production-impacting recommendations)

Per `multi-vendor-network-ops`, any recommendation that would alter production GCP networking state MUST include all nine elements. This is the iron rule for production audits; missing any element is a deferral signal, not a green light.

1. **Project**: `<project-id>` (`<project-name>`), plus `<org-id>` when a hierarchical firewall policy is in scope.
2. **Region**: `<region>` (or "global" for a VPC Network or global-mode Cloud Router change).
3. **VPC Network scope**: `<network-name>` and any peered or Shared VPC networks that share the blast radius.
4. **IAM principal**: which account or service account will execute the change; verify least-privilege.
5. **Safety tier**: read-only audit (no risk) vs targeted change (defined blast radius) vs broad change (multi-region, Shared VPC, or hierarchical policy).
6. **Blast radius**: subnets / VMs / cross-region propagation / inter-project connectivity affected.
7. **Rollback path**: explicit `gcloud` command(s) to reverse the change, or the exported prior configuration to restore from.
8. **Approval**: who signed off (named human plus timestamp), referenced from the audit ticket.
9. **Evidence**: pre-change `gcloud compute ... describe` output, post-change `describe` output, VPC Flow Log diff window.

## Cross-link surface

Live cross-refs (vault skills that pair with this one):

- **`cloud-network-design`**: the vendor-neutral cloud-network design umbrella. This audit skill audits the running GCP network; that skill owns the cross-cloud design decisions. Route design questions (should this workload be on GCP at all, multi-cloud egress cost, global VPC vs regional-per-cloud topology) up to it.
- **`aws-networking-audit`**: the AWS parity sibling audit (VPC, Security Groups, NACLs, Transit Gateway, Flow Logs). Cross-cloud reviews run the two side by side.
- **`multi-vendor-network-ops`**: umbrella; nine-element response contract above.
- **`acl-rule-analysis`**: firewall rule pattern catalogue; overly-permissive-rule decision logic carries across to GCP firewall rules and hierarchical policies.
- **`secrets-hygiene`**: GCP credentials, service accounts, `gcloud auth` discipline; the "Probing the credential store" pattern applies to every credential probe in this skill.
- **`network-log-analysis`**: VPC Flow Log REJECT triage, top-talker aggregation, cross-region traffic accounting (Steps 1 and 3).
- **`cloud-security-posture`**: CSPM control-catalogue boundary. This skill audits the network plane (firewall rules, hierarchical policies, routes, Cloud NAT, connectivity); it does NOT own the CSPM control catalogue. Route posture grading (CIS GCP Foundations scoring, NIST 800-53 control mapping) there.
- **`siem-log-analysis`**: VPC Flow Log to SIEM forwarding playbooks (Cloud Logging to Pub/Sub to Splunk / Sumo / Elastic).
- **`incident-response-network`**: silent-drop route triage, scanning-pattern response, post-incident firewall and hierarchical policy review.
- **`oncall-runbooks`**: cross-project audit procedure, severity classification, escalation.
- **`systematic-debugging`**: rule out one layer at a time during connectivity diagnosis (hierarchical policy -> VPC firewall rule -> route -> Cloud Router BGP -> Shared VPC IAM).
- **`completion-gate`** Layer 3: production-audit cadence; sign-off on the findings ledger.
- **`utc-timestamps`**: audit-date and next-audit-due timestamps in the report template are recorded in UTC.
- **`plan-time-tooling`**: enumerate this skill plus `secrets-hygiene` + `acl-rule-analysis` + `humanise-comms` + `cite-sources` at any GCP-audit chunk plan-mode entry.
- **`subagent-delegation`**: blast-radius grep before any state-changing follow-on PR.

- `azure-networking-audit`: the Azure VNet parity sibling audit, completing the multi-cloud audit trio with `aws-networking-audit` and this skill.

## Out of scope

- **Cloud CDN** (CDN edge; separate audit surface).
- **Cloud Armor** (WAF and DDoS protection; separate audit surface).
- **Load balancer URL maps** (L7 content routing; covered by application-layer audits).
- **Cloud DNS** (separate audit; covers public zones, private zones, DNSSEC).
- **State-changing gcloud commands**: this skill is read-only. All commands are `list`, `describe`, `get-status`, `get-iam-policy`, `get-value`. Any remediation a finding implies is surfaced as a recommendation, not executed.
- **General GCP troubleshooting unrelated to VPC networking**: use vendor docs or service-specific skills.

## Provenance

Customised from `https://github.com/vahagn-madatyan/netsec-skills-suite/tree/main/skills/gcp-networking-audit` (Apache-2.0). Vault customisations:

- **Frontmatter**: 4-field House style (`name` + `description` + `license: Apache-2.0` + `metadata: { version: 1.0.0 }`). Upstream `safety: read-only`, `openclaw: {...}`, `metadata.author`, `metadata.safety` fields dropped (vault tooling does not consume them). Description re-quoted as a double-quoted single-line YAML scalar for loader safety.
- **Description**: rewritten for vault Claude-Search-Optimisation discipline; trigger-phrase dense across all six step domains plus compliance and cost-optimisation framings; ends by naming the six-step procedure, the three threshold tables, the two decision trees, and the cross-refs.
- **`references/vpc-architecture.md` folded into body**: the GCP global VPC Network model and GCP-vs-AWS-vs-Azure comparison (Step 1), auto-mode vs custom-mode (Step 1), the firewall rule and hierarchical firewall policy evaluation order and actions table (Step 2), the Cloud Interconnect topology and redundancy model (Step 4), the Shared VPC host / service project model, IAM model, and audit checks (Step 4), VPC Network Peering constraints (Step 4), and the Cloud Router routing model, route-selection precedence, and BGP session states (Step 5). Upstream file deleted; vault keeps only `references/cli-reference.md`.
- **`references/cli-reference.md` kept**: dash purge (em / en dashes removed), US-to-UK spelling cleaned, header rewritten to point back at the vault SKILL.md.
- **Dash purge**: zero em dashes and en dashes anywhere in SKILL.md or cli-reference.md. Vault `humanise-comms` discipline.
- **US-to-UK spelling**: `optimi[sz]ation`, `utilis`, `behavio[u]r`, `organi[sz]e`, `analy[sz]e`, `centrali[sz]e` normalised to UK / Pacific forms throughout. GCP product proper nouns (Cloud NAT, Cloud Router, Private Google Access, and so on) kept literal.
- **Skill marker block**: added at the top of the body per vault convention.
- **Nine-element response contract**: added to map onto `multi-vendor-network-ops` (vault umbrella iron rule for production-impacting recommendations).
- **Cross-link surface**: authored for the vault, routing design questions up to `cloud-network-design`, naming `aws-networking-audit` and `azure-networking-audit` as the live parity siblings, and drawing the `cloud-security-posture` CSPM boundary.

See `merged-skills-registry/SKILL.md` for the full registry row and audit history.
