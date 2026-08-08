---
name: azure-networking-audit
description: "Use for any Azure VNet networking security audit, posture review, connectivity assessment, or compliance pass. Triggers include \"Azure VNet audit\", \"VNet security review\", \"VNet architecture review\", \"NSG rule audit\", \"NSG review\", \"NSG rule review\", \"effective security rules\", \"effective NSG rules\", \"Azure Firewall policy audit\", \"Azure Firewall rule collection review\", \"DNAT rule audit\", \"threat intelligence mode check\", \"Azure IDPS review\", \"ExpressRoute audit\", \"ExpressRoute BGP peering diagnosis\", \"VPN Gateway audit\", \"VPN connection troubleshooting\", \"VNet peering audit\", \"VNet peering route validation\", \"UDR validation\", \"user-defined route audit\", \"effective route table review\", \"forced tunneling check\", \"asymmetric routing\", \"BGP route propagation audit\", \"0.0.0.0/0 inbound NSG\", \"Internet service tag inbound\", \"SSH/RDP from internet Azure\", \"Azure Bastion recommendation\", \"subnet exhaustion Azure\", \"address space overlap check\", \"subnet delegation review\", \"service endpoint vs private endpoint\", \"DDoS Protection Standard check\", \"orphaned NIC audit\", \"unassociated public IP audit\", \"Application Gateway utilisation\", \"hub-spoke topology review\", \"gateway transit audit\", \"Azure CIS networking\", \"Azure NIST networking\", \"Azure PCI segmentation review\", \"Azure HIPAA networking audit\", \"Azure post-migration networking audit\". Azure-only single-vendor surface; no multi-cloud or vendor-tag splits. Diagnose-first; read-only `az network ...`, `az account show`, `az role assignment list` throughout. No state-changing commands. Six-step audit procedure (VNet inventory and design, NSG rule audit, Azure Firewall and network security, connectivity via ExpressRoute and VPN Gateway and VNet peering, UDR and routing validation, report and optimisation). Three threshold tables (NSG rule severity, ExpressRoute circuit health, subnet utilisation). Three decision trees (overly permissive NSG rule, VNet best-practice design review, Azure connectivity routing diagnosis). Inlines the VNet packet flow model (subnet NSG and NIC NSG evaluation order, both directions), the NSG priority-based first-match model and service tags, the Azure Firewall processing pipeline (DNAT then network then application rule collections), the ExpressRoute routing and gateway-transit model, VNet peering constraints (non-transitive, no overlapping address spaces, bi-directional creation required, no edge-to-edge routing), and the UDR and effective-routes model (UDR over BGP over system routes). Out of scope: Azure Front Door, Azure WAF, Application Gateway path rules, Azure DNS. Reference `references/cli-reference.md` for read-only Azure CLI commands organised by audit step. Maps onto `multi-vendor-network-ops` nine-element response contract for production-impacting recommendations. Routes design questions up to `cloud-network-design`; parity siblings `aws-networking-audit` and `gcp-networking-audit`. Pairs with `acl-rule-analysis` for NSG rule pattern review, `secrets-hygiene` for Azure credential and service-principal `az login` discipline, `network-log-analysis` for NSG Flow Log REJECT triage and top-talker aggregation, `cloud-security-posture` for the CSPM control-catalogue boundary, `systematic-debugging` for connectivity diagnosis, `oncall-runbooks` for escalation, `completion-gate` for production sign-off, `utc-timestamps` for audit timestamps. Customised from vahagn-madatyan/netsec-skills-suite/azure-networking-audit (Apache-2.0); references/vnet-architecture.md folded into body; references/cli-reference.md kept and cleaned; upstream safety/openclaw/author frontmatter dropped per vault four-field house style."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Azure VNet networking audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: azure-networking-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Cloud resource audit for Azure Virtual Network (VNet) architecture, network security posture, and hybrid connectivity. Evaluates provider-specific Azure networking constructs (VNet design, Network Security Groups with priority-based rules, Azure Firewall rule collection groups, ExpressRoute circuits, VPN Gateways, VNet peering topology, User-Defined Routes, effective security rules) rather than generic cloud networking advice.

Scope covers VNet-layer networking: address space planning, subnet delegation, NSG filtering, Azure Firewall inspection, hybrid connectivity via ExpressRoute and VPN Gateway, and route management. Out of scope: Azure Front Door CDN policies, Azure WAF custom rule authoring, application-layer routing in Application Gateway path rules, and Azure DNS zone management.

Reference `references/cli-reference.md` for read-only Azure CLI commands organised by audit step.

## When to use

- VNet architecture design review: validating address space allocation, subnet delegation, and service endpoint or Private Endpoint configuration before or after deployment.
- Post-migration networking audit: verifying VNet connectivity, NSG rules, and UDR entries after workload migration.
- Security assessment: identifying overly permissive NSG rules, default NSG exposure, and missing Azure Firewall policies.
- Connectivity troubleshooting: diagnosing ExpressRoute BGP peering failures, VPN Gateway tunnel drops, or VNet peering asymmetric routing.
- Compliance preparation: documenting VNet segmentation, NSG justification, and Azure Firewall logging for auditors (PCI DSS 4.0, HIPAA, CIS Azure Foundations, NIST 800-53).
- Cost optimisation review: identifying unassociated public IPs, orphaned NICs, and underutilised Application Gateway instances.

## Prerequisites

- **Azure CLI** authenticated (`az account show` succeeds).
- **RBAC permissions**: Reader role on the target subscription, or granular read permissions covering `Microsoft.Network/virtualNetworks/read`, `Microsoft.Network/networkSecurityGroups/read`, `Microsoft.Network/azureFirewalls/read`, `Microsoft.Network/expressRouteCircuits/read`, `Microsoft.Network/virtualNetworkGateways/read`, `Microsoft.Network/routeTables/read`, `Microsoft.Network/networkInterfaces/read`, `Microsoft.Network/publicIPAddresses/read`.
- **Target scope identified**: specific subscription, resource group(s), and VNet name(s). Multi-subscription audits require `az account set --subscription <id>` per subscription.
- **Network Watcher enabled**: NSG Flow Logs and effective security rules require Network Watcher in the target region. If disabled, document as a Critical finding.
- **Credential handling**: never paste service-principal secrets, session tokens, or `az login` device codes into the chat. Per `secrets-hygiene` "Probing the credential store" subsection, probe with `az account show > /dev/null 2>&1 && echo ok`; never surface tokens or the raw `az account get-access-token` output in transcripts.

## Procedure

Six steps in sequence. Each builds on prior findings, moving from inventory through security analysis to optimisation.

### Step 1: VNet inventory and design assessment

Enumerate all VNets in the target subscription and assess architectural design.

```
az network vnet list --output table
az network vnet show --name <vnet-name> --resource-group <rg>
az network vnet subnet list --vnet-name <vnet-name> --resource-group <rg>
```

For each VNet, evaluate:

- **Address space allocation**: primary and additional address spaces. Check for RFC 1918 compliance, overlapping address spaces across peered VNets (blocks VNet peering), and sufficient address space for growth.
- **Subnet layout**: identify subnets by purpose (workload subnets, AzureFirewallSubnet which is the required name for Azure Firewall, GatewaySubnet which is required for VPN Gateway and ExpressRoute Gateway, AzureBastionSubnet). Verify each required named subnet exists for the deployed services.
- **Subnet delegation**: check delegations to Azure services (`Microsoft.Sql/managedInstances`, `Microsoft.Web/serverFarms`). Delegated subnets restrict which resources can deploy: a subnet delegated to SQL Managed Instance cannot host VMs or other services.
- **Service endpoints vs Private Endpoints**: service endpoints route PaaS traffic over the Azure backbone but do not remove the public endpoint on the PaaS resource. Private Endpoints create a private IP within the VNet for the PaaS service, removing public exposure entirely. Audit whether data services (Storage, SQL, Key Vault) use Private Endpoints (preferred for zero-trust) or service endpoints (legacy approach with broader exposure).
- **DDoS Protection**: verify whether DDoS Protection Standard is enabled on the VNet. Basic DDoS protection is automatic for all Azure resources; Standard adds volumetric attack mitigation, cost-protection guarantees, and access to the DDoS Rapid Response team.

### Step 2: NSG rule audit

Audit Network Security Groups using Azure's priority-based evaluation model. Before evaluating individual rules, review the VNet packet flow model below: Azure evaluates NSGs at both the subnet and NIC level, and the evaluation order reverses between inbound and outbound.

#### VNet packet flow model

##### Inbound packet flow (network to VM)

```
Packet arrives at subnet
        |
        v
+---------------------------+
| UDR / Route Table         |  If a UDR exists on the subnet, route
| (if applicable)           |  evaluation determines next-hop before NSG.
+---------------------------+
        |
        v
+---------------------------+
| Subnet NSG                |  Priority-based; lowest number evaluated
| Inbound rules             |  first. First match wins (Allow or Deny).
|                           |  Defaults: AllowVNetInBound (65000),
|                           |  DenyAllInBound (65500).
+---------------------------+
        | Permitted
        v
+---------------------------+
| NIC NSG                   |  Second layer, evaluated after subnet NSG.
| Inbound rules             |  Same priority-based evaluation. Traffic
|                           |  must pass BOTH NSGs.
+---------------------------+
        | Permitted
        v
   Packet delivered to VM NIC
```

##### Outbound packet flow (VM to network)

```
VM sends packet
        |
        v
+---------------------------+
| NIC NSG                   |  Outbound rules evaluated first (NIC level).
| Outbound rules            |  Defaults: AllowVNetOutBound (65000),
|                           |  AllowInternetOutBound (65001),
|                           |  DenyAllOutBound (65500).
+---------------------------+
        | Permitted
        v
+---------------------------+
| Subnet NSG                |  Outbound rules evaluated second (subnet
| Outbound rules            |  level). Same priority-based evaluation.
+---------------------------+
        | Permitted
        v
+---------------------------+
| Route Table               |  UDR routes over BGP routes over system
| Route selection           |  routes. Longest prefix match within each
|                           |  category. Next-hop: VNet, Internet, Virtual
|                           |  Appliance, VNet Gateway, VNet peering, None.
+---------------------------+
        |
        v
   Packet exits subnet
```

**Key audit implication.** NSG evaluation order reverses between directions: inbound is subnet NSG then NIC NSG (outside-in); outbound is NIC NSG then subnet NSG (inside-out). Traffic must pass BOTH NSGs. A Deny in either NSG blocks the traffic regardless of the other NSG's rules. This differs from AWS, where Security Groups (instance-level, stateful) and NACLs (subnet-level, stateless) evaluate independently.

#### NSG rule evaluation model

Azure NSG rules use a priority-based first-match model, fundamentally different from AWS Security Groups (which evaluate all rules and permit if any match).

- **Priority range**: 100 to 4096 for custom rules, 65000 to 65500 for default rules. Lower number means higher priority (a rule at priority 100 is evaluated before priority 200).
- **First match wins**: the first matching rule determines the action (Allow or Deny); subsequent rules are not evaluated.
- **Default rules (65000+)**: cannot be deleted but are overridden by any custom rule with a lower priority number.

##### Default rules (always present)

Inbound defaults:

| Priority | Name | Source | Destination | Action |
|----------|------|--------|-------------|--------|
| 65000 | AllowVNetInBound | VirtualNetwork | VirtualNetwork | Allow |
| 65001 | AllowAzureLoadBalancerInBound | AzureLoadBalancer | * | Allow |
| 65500 | DenyAllInBound | * | * | Deny |

Outbound defaults:

| Priority | Name | Source | Destination | Action |
|----------|------|--------|-------------|--------|
| 65000 | AllowVNetOutBound | VirtualNetwork | VirtualNetwork | Allow |
| 65001 | AllowInternetOutBound | * | Internet | Allow |
| 65500 | DenyAllOutBound | * | * | Deny |

##### Service tags

Azure NSG rules support service tags as source or destination instead of IP ranges. Key service tags for audit:

| Service tag | Scope |
|-------------|-------|
| VirtualNetwork | VNet address space plus peered VNets plus on-prem (VPN / ExpressRoute) |
| AzureLoadBalancer | Azure health probes |
| Internet | All public IP space (excludes VNet, peered, on-prem) |
| AzureCloud | All Azure datacentre IPs |
| Storage | Azure Storage service IPs (region-specific variants available) |
| Sql | Azure SQL Database service IPs |
| AzureActiveDirectory | Azure AD authentication endpoints |

#### NSG analysis

```
az network nsg list --output table
az network nsg rule list --nsg-name <nsg-name> --resource-group <rg> --include-default --output table
```

For each NSG, evaluate inbound and outbound rules:

- **Priority ordering conflicts**: an Allow at priority 200 cannot be overridden by a Deny at priority 300. Verify Deny rules have lower priority numbers than the conflicting Allows. This is the inverse of the AWS NACL rule-number logic in wording but the same "lower number wins" principle.
- **Internet inbound**: NSG rules permitting inbound from `*` or the `Internet` service tag are findings. Severity depends on port: SSH (22) or RDP (3389) from `Internet` is Critical; HTTPS (443) on an Application Gateway subnet may be acceptable. The `Internet` service tag covers all public IP space excluding VNet, peered VNet, and on-premises ranges.
- **Effective security rules**: NSGs apply at both subnet and NIC level, and traffic must pass both. A rule allowed by the subnet NSG but denied by the NIC NSG is effectively denied. Use `az network nic show-effective-nsg` to see the combined effective rules with resolved priorities, computed as: for inbound, subnet NSG then NIC NSG; for outbound, NIC NSG then subnet NSG; traffic passes only if BOTH allow.
- **Application Security Groups (ASGs)**: ASGs group NICs for use as source or destination in NSG rules instead of IP ranges. Audit ASG membership for correctness; an over-broad ASG silently widens every rule that references it.
- **Default NSG rules in effect**: a subnet or NIC with no custom NSG rules falls back to the defaults, which allow all VNet-to-VNet traffic (AllowVNetInBound / AllowVNetOutBound). Flag production subnets relying solely on defaults as Medium.
- **Unused NSGs**: NSGs not associated with any subnet or NIC are cleanup candidates.

### Step 3: Azure Firewall and network security

Evaluate Azure Firewall policies, rule collection groups, and threat intelligence. Before evaluating individual rules, review the processing pipeline below: Azure Firewall processes traffic through rule collections in a strict priority-and-type order.

#### Azure Firewall processing pipeline

```
Traffic arrives at Azure Firewall
        |
        v
+---------------------------+
| DNAT rule collections     |  Processed first (inbound only). Translates
| (priority order)          |  destination IP/port to a private IP. On
|                           |  match, implicitly allows via a network rule.
+---------------------------+
        | No DNAT match
        v
+---------------------------+
| Network rule collections  |  Processed second. L3/L4 rules
| (priority order)          |  (IP, port, protocol). Allow or Deny.
+---------------------------+
        | No network rule match
        v
+---------------------------+
| Application rule          |  Processed last. L7 rules (FQDN, URL,
| collections               |  web categories). Allow or Deny.
| (priority order)          |
+---------------------------+
        | No match in any collection
        v
   Default action: implicit deny-all
```

Rule collection groups provide hierarchical organisation: a **rule collection group** (has a priority) contains **rule collections**; a rule collection (has a priority and an action) contains **rules**. Groups are processed by priority (lowest first); within a group, collections are processed by priority; within a collection, rules are processed sequentially.

```
az network firewall list --output table
az network firewall policy rule-collection-group list --policy-name <policy> --resource-group <rg>
```

Evaluate:

- **Rule collection group priority**: verify the priority order matches intent. DNAT collections process before network collections, which process before application collections, regardless of the numeric priority you assign within each type.
- **DNAT rules**: translate inbound traffic to private IPs. Verify each DNAT rule maps to a valid, live backend. Stale DNAT rules pointing to decommissioned hosts create exposure.
- **Network rules**: permit or deny by IP, port, protocol. Audit for overly broad rules (`*` source or destination, wide port ranges).
- **Application rules**: filter outbound by FQDN or URL. Verify application rules enforce FQDN restrictions for workload internet access.
- **Threat intelligence mode**: Azure Firewall supports threat-intelligence filtering in Alert or Deny mode. Verify production firewalls use Deny mode.
- **IDPS**: Azure Firewall Premium supports signature-based IDPS. Verify the mode (Alert vs Alert and Deny) and that any bypass rules are justified. TLS inspection, full URL filtering, and web categories are Premium-only; confirm the SKU matches the controls the audit expects.
- **Azure Firewall subnet**: AzureFirewallSubnet must be /26 or larger, with a public IP and UDRs routing traffic through the firewall.

### Step 4: Connectivity analysis

Evaluate hybrid and inter-VNet connectivity through ExpressRoute, VPN Gateway, and VNet peering.

#### ExpressRoute routing model

ExpressRoute provides private connectivity from on-premises networks to Azure VNets through a connectivity provider or a direct connection. Each circuit carries a primary and secondary connection to the Microsoft Enterprise Edge (MSEE), and splits into Azure Private Peering (reaches VNets) and Microsoft Peering (reaches Microsoft 365 and Azure PaaS public endpoints).

- **BGP route exchange**: on Azure Private Peering, on-premises advertises on-prem routes and Azure advertises VNet address spaces, exchanged via BGP over the primary and secondary connections.
- **Route propagation to VNets**: the ExpressRoute Gateway in the GatewaySubnet receives BGP routes and injects them into VNet route tables, unless a UDR disables BGP propagation.
- **Gateway Transit**: the hub VNet peering must set `AllowGatewayTransit: true`; the spoke VNet peering must set `UseRemoteGateways: true`. This lets spoke VNets use the hub's ExpressRoute (or VPN) Gateway, and ExpressRoute-learned routes propagate through the hub to the spokes.
- **Maximum prefixes**: ExpressRoute Standard supports 4,000 routes for Azure Private Peering; Premium supports 10,000. Exceeding the limit drops the BGP session, so a route-count near the ceiling is a finding.

```
az network express-route show --name <circuit> --resource-group <rg>
az network express-route peering list --circuit-name <circuit> --resource-group <rg>
```

- **Circuit status**: verify the circuit shows "Provisioned" (provider side) and "Enabled" (Azure side). "NotProvisioned" means the provider has not completed circuit setup and no traffic will flow.
- **BGP peering state**: check Azure Private Peering and Microsoft Peering BGP session state. It should be "Connected"; "Idle" or "Active" without "Connected" indicates a peering negotiation failure (ASN mismatch, VLAN ID mismatch, or a provider issue).
- **Advertised routes**: verify on-premises routes are visible in Azure via `az network express-route list-route-tables`, and that Azure VNet routes are advertised back to on-premises. Missing routes cause silent traffic drops.

**VPN Gateway:**

```
az network vpn-connection show --name <conn> --resource-group <rg>
```

- **Connection status**: should show "Connected". "Connecting" indicates an IKE / IPsec parameter mismatch.
- **Gateway SKU**: Basic SKU lacks BGP and zone-redundancy. VpnGw2 or higher is recommended for production.

#### VNet peering

VNet peering creates a direct networking link between two VNets over the Azure backbone (no public internet, no encryption needed).

```
az network vnet peering list --vnet-name <vnet> --resource-group <rg> --output table
```

##### VNet peering properties

| Property | Default | Impact |
|----------|---------|--------|
| AllowVirtualNetworkAccess | true | Peer VNet address space is included in the VirtualNetwork service tag. |
| AllowForwardedTraffic | false | If false, blocks traffic forwarded by an NVA in the peer VNet. |
| AllowGatewayTransit | false | If true on the hub, allows peers to use this VNet's gateway. |
| UseRemoteGateways | false | If true on a spoke, uses the peer VNet's gateway for on-prem routes. |

##### VNet peering constraints

| Constraint | Detail |
|------------|--------|
| Non-transitive | VNet-A to VNet-B and VNet-B to VNet-C does NOT allow VNet-A to VNet-C. |
| No overlapping address spaces | Peering fails if VNet address spaces overlap. |
| Cross-region supported | Global VNet peering is supported; cross-region data transfer charges apply. |
| Bi-directional creation required | Both VNets must create the peering link; one side only leaves the "Initiated" state. |
| No edge-to-edge routing (by default) | Cannot use a peer's gateway or NVA without the explicit transit settings above. |
| Maximum peerings per VNet | 500 (default limit, adjustable via support). |

- **Peering state**: both sides must show "Connected". "Initiated" means the reciprocal peering is missing.
- **Transit settings**: `AllowGatewayTransit` on the hub and `UseRemoteGateways` on the spoke enable a shared ExpressRoute or VPN gateway. Verify the settings match hub-spoke intent.
- **Address space overlap**: VNet peering requires non-overlapping address spaces. Compare both VNets.
- **Forwarded traffic**: `AllowForwardedTraffic` must be enabled on both peering links for transit routing through an Azure Firewall in the hub. Spoke-to-spoke traffic routed via the hub firewall silently drops if either link leaves it disabled.

### Step 5: UDR and routing validation

Audit User-Defined Routes for correctness, forced tunneling, and conflicts. Azure resolves routing decisions using a defined priority order when multiple route sources exist.

#### Route evaluation priority

```
Route evaluation priority (highest to lowest):
  1. UDR (User-Defined Routes) on the subnet
  2. BGP routes (from ExpressRoute or VPN Gateway)
  3. System routes (auto-created for VNet, Internet, RFC 1918)

Within each category:
  - Longest prefix match wins (a /24 beats a /16).
  - UDR does NOT override the local VNet route for the VNet address
    space: intra-VNet traffic always routes locally.
```

System routes are auto-created: the VNet address space routes to next-hop VirtualNetwork; `0.0.0.0/0` routes to next-hop Internet; the RFC 1918 ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) route to next-hop None (dropped) unless they fall within a VNet address space or a peering. A UDR with next-hop "Virtual Appliance" overrides the system route to force traffic through an NVA or Azure Firewall; next-hop "None" creates an explicit drop; next-hop "VirtualNetworkGateway" forces traffic to the VPN or ExpressRoute Gateway.

```
az network route-table list --output table
az network route-table route list --route-table-name <rt> --resource-group <rg>
az network nic show-effective-route-table --name <nic> --resource-group <rg>
```

- **Forced tunneling**: UDRs with a `0.0.0.0/0` next-hop to Azure Firewall or an NVA force internet traffic through inspection. Verify forced tunneling is NOT applied to AzureFirewallSubnet, GatewaySubnet, or AzureBastionSubnet, which breaks those services.
- **Asymmetric routing**: inbound via ExpressRoute but return via an Azure Firewall UDR causes asymmetry; the firewall drops return packets with no session state. Verify UDR next-hop addresses match the expected traffic path in both directions.
- **Effective routes per NIC**: Azure resolves UDR over BGP over system routes. Use `az network nic show-effective-route-table` for the final effective routes rather than reasoning from the route table alone.
- **BGP route propagation**: UDR tables can disable BGP propagation (`disableBgpRoutePropagation`). When disabled, ExpressRoute and VPN Gateway routes are not injected. Verify this matches the routing design.
- **Next-hop validation**: UDR routes to virtual-appliance IPs must reference running, healthy NVAs or an Azure Firewall. A stopped-VM next-hop creates a silent black hole.

### Step 6: Report and optimisation

Compile findings and identify resource optimisation opportunities.

```
az network nic list --query "[?virtualMachine==null]" --output table
az network public-ip list --query "[?ipConfiguration==null]" --output table
```

- **Orphaned NICs**: NICs not attached to a VM, common after deletions. Each may carry NSG rules and a private IP consuming address space.
- **Unassociated public IPs**: Standard SKU public IPs incur charges when unassociated. Release or associate.
- **Application Gateway optimisation**: Application Gateway v2 runs continuously. Verify the autoscale min/max matches traffic patterns.
- **Azure Advisor recommendations**: check `az advisor recommendation list --category Cost` for networking optimisation opportunities.

Compile the findings report using the Report Template section below.

## Threshold tables

### NSG rule severity

| Finding | Severity | Rationale |
|---------|----------|-----------|
| NSG allows SSH (22) from Internet | Critical | Direct shell access from internet. |
| NSG allows RDP (3389) from Internet | Critical | Remote desktop open to internet. |
| NSG allows all ports from `*` source | Critical | No port or source restriction. |
| NIC with no NSG, subnet NSG allows broad access | High | No NIC-level filtering. |
| Allow rule at lower priority number than a conflicting Deny | High | Priority ordering undermines the deny intent. |
| NSG allows database ports from non-app subnets | High | Database access not restricted to the application tier. |
| NSG with >50 custom rules | Medium | Excessive complexity; likely over-permissive. |
| NSG not associated with any subnet or NIC | Medium | Unused; cleanup candidate. |

### ExpressRoute circuit health

| Metric | Severity | Action |
|--------|----------|--------|
| Circuit status NotProvisioned | Critical | No connectivity; engage the provider. |
| BGP peering state Idle | High | Negotiation failure; check ASN and VLAN ID. |
| Learned routes missing expected prefixes | High | On-prem routes not advertised. |
| Circuit utilisation >80% sustained | Medium | Plan an upgrade or a second circuit. |

### Subnet utilisation

| Available IPs (% of address space) | Severity | Action |
|-------------------------------------|----------|--------|
| <10% remaining | High | Exhaustion risk; plan expansion. |
| 10 to 25% remaining | Medium | Monitor growth proactively. |
| >75% unused | Low | Over-provisioned; consider a smaller address space next time. |

## Decision trees

### Is this NSG rule overly permissive?

```
NSG rule under review
|-- Source is * or the Internet service tag?
|   |-- Yes
|   |   |-- Port = 22 (SSH) or 3389 (RDP)?
|   |   |   |-- Yes -> CRITICAL: management ports open to internet.
|   |   |   |        Use Azure Bastion instead.
|   |   |   |-- No
|   |   |       |-- Port = 443 on an Application Gateway subnet?
|   |   |       |   |-- Yes -> Acceptable for public services.
|   |   |       |   |-- No  -> HIGH: review necessity of the open port.
|   |   |       |-- Port = * (all)?
|   |   |           |-- CRITICAL: all ports open to internet.
|   |   |-- Higher-priority Deny covering the same traffic?
|   |       |-- Yes -> Verify Deny priority number < Allow priority number.
|   |       |-- No  -> Classify severity by port.
|   |-- No (specific CIDR or ASG)
|       |-- ASG reference?
|       |   |-- Review ASG membership scope for over-broad inclusion.
|       |-- Broad CIDR (/8, /16)?
|           |-- Medium: verify least-privilege intent.
```

### Is this VNet design following Azure best practices?

```
VNet design under review
|-- Hub-spoke topology?
|   |-- No  -> Acceptable for small deployments.
|   |-- Yes
|       |-- Hub has Azure Firewall? -> Verify UDRs route spoke traffic through the hub.
|       |-- VNet peering correct?
|       |   |-- AllowGatewayTransit on hub? -> Required for shared gateway.
|       |   |-- UseRemoteGateways on spokes? -> Required to use the hub gateway.
|       |   |-- AllowForwardedTraffic on both? -> Required for transit.
|       |-- Spoke-to-spoke via Azure Firewall? -> Best practice.
|-- NSGs on all workload subnets?
|   |-- No  -> HIGH: no network filtering.
|   |-- Yes -> Audit rules per Step 2.
|-- Network Watcher enabled?
|   |-- No  -> CRITICAL: no diagnostics or Flow Logs.
|   |-- Yes -> Verify NSG Flow Logs are configured.
|-- Address space overlaps peered VNets?
    |-- Yes -> Blocks VNet peering; re-plan address space.
    |-- No  -> Confirm sufficient space for growth.
```

### Azure connectivity routing diagnosis

```
Connectivity issue (e.g. VNet-A cannot reach VNet-B, or on-prem cannot reach a spoke)
|-- Inter-VNet (VNet-A to VNet-B)?
|   |-- Both peering links show Connected?
|   |   |-- No (Initiated) -> Create the reciprocal peering link.
|   |   |-- Yes
|   |       |-- Address spaces overlap? -> Peering invalid; re-plan.
|   |       |-- Transit through hub firewall expected?
|   |       |   |-- AllowForwardedTraffic true on both links? -> If no, enable.
|   |       |   |-- UDR on each spoke points 0.0.0.0/0 (or peer CIDR) at the firewall? -> If no, add.
|   |       |-- Effective routes on the NIC show the peer CIDR?
|   |           |-- No  -> Check UDR next-hop and disableBgpRoutePropagation.
|   |           |-- Yes -> Diagnosis points to NSG (subnet + NIC) on the VNet-B side.
|-- Hybrid (on-prem to spoke via ExpressRoute or VPN)?
    |-- Circuit / connection status Connected?
    |   |-- No -> Engage provider (ExpressRoute) or check IKE/IPsec (VPN).
    |   |-- Yes
    |       |-- Gateway Transit configured (AllowGatewayTransit on hub, UseRemoteGateways on spoke)?
    |       |   |-- No -> Spoke cannot use the hub gateway; configure transit.
    |       |-- On-prem routes learned in Azure and Azure routes advertised back?
    |       |   |-- No -> Missing advertisement; silent drop. Check BGP.
    |       |-- UDR asymmetric (inbound direct, return via firewall)?
    |           |-- Yes -> Firewall drops stateless return; route both directions through it or SNAT.
    |           |-- No  -> Diagnosis points to NSG or the destination VM.
```

## Report template

```
AZURE VNET NETWORKING AUDIT REPORT
======================================
Subscription: [id] ([name])
Resource Group(s): [list]
VNet: [name] ([resource-id])
Address Spaces: [list]
Audit Date: [timestamp]
Performed By: [operator / agent]

VNET ARCHITECTURE:
Subnets: [total] (workload:[n] gateway:[n] firewall:[n] bastion:[n])
DDoS Protection: [Basic / Standard]
Private Endpoints: [n] | Service Endpoints: [n]

NSGs:
Total: [n] | Internet inbound: [n] | Unused: [n]
Effective rule conflicts: [n]

AZURE FIREWALL:
Deployed: [yes / no] | SKU: [Standard / Premium]
Threat intelligence: [Alert / Deny] | IDPS: [on / off]
Rule collections: DNAT:[n] Network:[n] Application:[n]

CONNECTIVITY:
ExpressRoute: [circuit or N/A] | BGP: [Connected / Idle]
VPN Gateway: [name or N/A] | Connections: [n]
VNet Peering: [n] | Gateway transit: [yes / no]

ROUTING:
UDR Tables: [n] | Forced tunneling: [n subnets]
BGP propagation disabled: [n tables]

OPTIMISATION:
Orphaned NICs: [n] | Unassociated public IPs: [n]
Application Gateway utilisation: [assessment]

FINDINGS:
1. [Severity] [Category] - [Description]
   Resource: [id]
   Issue: [detail] -> Recommendation: [action]

RECOMMENDATIONS: [prioritised by severity]
NEXT AUDIT: [CRITICAL findings: 30d, HIGH: 90d, clean: 180d]
```

## Troubleshooting

### NSG Flow Logs not enabled

If Network Watcher NSG Flow Logs are not configured, traffic visibility is limited to NSG hit counts. NSG Flow Logs require Network Watcher enabled and a storage account; version 2 includes throughput data. Document missing Flow Logs as High and recommend enabling before further traffic analysis (a non-disruptive operation).

### Effective security rules show unexpected allows

Use `az network nic show-effective-nsg` for the combined subnet and NIC NSG rules. Check for a higher-priority Allow in the NIC NSG overriding a subnet Deny, default rules (65000+) permitting VNet-to-VNet traffic, or an ASG membership that includes unintended NICs.

### ExpressRoute BGP session not established

Verify the VLAN ID matches between Azure and the provider, and the BGP ASN matches the on-premises router. Use `az network express-route peering show` to compare settings. Both primary and secondary connections should show "Connected".

### VNet peering shows Initiated but not Connected

Both peering links must be created. "Initiated" means only one side is configured; create the reciprocal link. Cross-subscription peering requires RBAC on both subscriptions.

### UDR causing asymmetric routing

When ExpressRoute delivers inbound traffic directly but a UDR routes return traffic through Azure Firewall, asymmetric routing occurs: the firewall drops return packets with no session state. Ensure UDR routes both directions through the firewall, or configure Azure Firewall SNAT.

### Multi-subscription VNet audit

For estates spanning subscriptions, set the target with `az account set --subscription <id>` per subscription rather than assuming a single default. Per `secrets-hygiene` "Probing the credential store", never persist a service-principal secret or an `az account get-access-token` value in shell history; use `az login` (or a managed identity on the audit host) and probe read-only.

## Nine-element response contract (production-impacting recommendations)

Per `multi-vendor-network-ops`, any recommendation that would alter production Azure networking state MUST include all nine elements. This is the iron rule for production audits; missing any element is a deferral signal, not a green light.

1. **Subscription**: `<subscription-id>` (`<subscription-name>`).
2. **Resource group and region**: `<rg>` and `<region>`.
3. **VNet scope**: `<vnet-name>` and any peered or ExpressRoute / VPN-connected VNets that share the blast radius.
4. **Identity principal**: which user, service principal, or managed identity will execute the change; verify least-privilege (Reader for audit, a scoped Network Contributor only for the specific change).
5. **Safety tier**: read-only audit (no risk) vs targeted change (defined blast radius) vs broad change (multi-VNet, hub-spoke, hybrid connectivity).
6. **Blast radius**: NICs / subnets / peered VNets / hybrid connectivity affected, and whether the change touches AzureFirewallSubnet, GatewaySubnet, or AzureBastionSubnet.
7. **Rollback path**: explicit `az` command(s) to reverse the change, OR the ARM template / resource export to restore from.
8. **Approval**: who signed off (named human plus timestamp), referenced from the audit ticket.
9. **Evidence**: pre-change `az network ... show` output, post-change `show` output, NSG Flow Log diff window.

## Cross-link surface

Live cross-refs (vault skills that pair with this one):

- **`cloud-network-design`**: the vendor-neutral cloud-network design umbrella. This skill audits the running Azure network; `cloud-network-design` owns the cross-cloud design decisions. Route design questions (should this be hub-spoke, which connectivity model, address-space strategy across clouds) UP to it.
- **`aws-networking-audit`**: the AWS parity sibling audit. Same six-step diagnose-first shape; the AWS packet-flow and Transit Gateway model is the cross-vendor mirror of this skill's NSG and VNet-peering model.
- **`multi-vendor-network-ops`**: umbrella; the nine-element response contract above.
- **`acl-rule-analysis`**: NSG rule pattern catalogue; overly-permissive-rule decision logic carries across to Azure NSGs.
- **`secrets-hygiene`**: Azure credential, service-principal, and `az login` discipline; the "Probing the credential store" pattern applies to every credential probe in this skill.
- **`network-log-analysis`**: NSG Flow Log REJECT triage, top-talker aggregation, and cross-subnet accounting (Step 2 and Step 6).
- **`cloud-security-posture`**: CSPM control-catalogue boundary. This skill audits the network-plane config (NSG, Azure Firewall, routes, connectivity); it does NOT own the CSPM control catalogue. Route posture grading (CIS Azure Foundations, NIST 800-53 control status, drift over time) to `cloud-security-posture`.
- **`systematic-debugging`**: rule out one layer at a time during connectivity diagnosis (subnet NSG -> NIC NSG -> UDR -> peering transit -> BGP propagation).
- **`oncall-runbooks`**: multi-subscription audit procedure, severity classification, escalation.
- **`completion-gate`** Layer 3: production-audit cadence; sign-off on the findings ledger.
- **`utc-timestamps`**: stamp the audit date and Flow Log diff windows in UTC.
- **`plan-time-tooling`**: enumerate this skill plus `secrets-hygiene` + `acl-rule-analysis` + `humanise-comms` + `cite-sources` at any Azure-audit chunk plan-mode entry.
- **`subagent-delegation`**: blast-radius grep before any state-changing follow-on change.
- **`humanise-comms`**: dash purge plus spelling cleanup for any audit report or follow-on doc text.
- **`azure-cloud-ops`**: vendor-specific Azure operations beyond the network plane (compute, storage, database, identity, cost). This audit skill owns Azure networking; `azure-cloud-ops` owns the rest of the Azure surface.

Related vault skills:

- `cloud-platform-selection`: family-level cross-cloud strategy (AWS vs Azure vs GCP selection, Well-Architected principles, migration framework). Pair when an Azure VNet audit raises strategic questions beyond the VNet layer.
- `sase-sse`: ZTA and zero-trust pillar mapping (the network pillar maps to VNet microsegmentation and NSG least-privilege).

- `gcp-networking-audit`: the GCP parity sibling audit (VPC firewall rules, Cloud Router, VPC peering), completing the multi-cloud audit trio with `aws-networking-audit` and this skill.

## Out of scope

- **Azure Front Door** (CDN and global edge; separate audit surface).
- **Azure WAF** (web application firewall custom rule authoring; separate audit surface).
- **Application Gateway path rules** (L7 content routing; covered by application-layer audits).
- **Azure DNS** (public and private DNS zone management; separate audit surface).
- **State-changing Azure commands**: this skill is read-only. All commands are `show`, `list`, `list-effective-*`, and `show-effective-*`. Any remediation a finding implies is surfaced as a recommendation, not executed.
- **General Azure troubleshooting unrelated to VNet networking**: use vendor docs or service-specific skills.

## Provenance

Customised from `https://github.com/vahagn-madatyan/netsec-skills-suite/tree/main/skills/azure-networking-audit` (Apache-2.0). Vault customisations:

- **Frontmatter**: 4-field House style (`name` + `description` + `license: Apache-2.0` + `metadata: { version: 1.0.0 }`). Upstream `metadata.safety`, `metadata.author`, and `metadata.openclaw` fields dropped (vault tooling does not consume them).
- **Description**: rewritten for vault Claude-Search-Optimisation discipline; trigger-phrase dense across all six step domains plus compliance and cost-optimisation framings; single-line double-quoted YAML scalar.
- **`references/vnet-architecture.md` folded into body**: VNet packet flow model and NSG evaluation order (Step 2), service tags and default-rule tables (Step 2), Azure Firewall processing pipeline (Step 3), ExpressRoute routing and gateway-transit model (Step 4), VNet peering properties and constraints (Step 4), route evaluation priority and UDR override behaviour (Step 5). Upstream file not carried; vault keeps only `references/cli-reference.md`.
- **`references/cli-reference.md` kept**: dash purge, US-to-UK spelling cleaned (organised, optimisation, utilisation), headerless title retained.
- **Dash purge**: zero em dashes or en dashes anywhere in SKILL.md or cli-reference.md (upstream used em dashes in prose and en dashes in numeric ranges). Vault `humanise-comms` discipline; ranges rewritten as "X to Y".
- **US-to-UK spelling**: `optimi[sz]ation`, `utili[sz]ation`, `organi[sz]e`, `analy[sz]e`, `behaviour`, `centre` normalised to UK forms. Azure product names (DDoS Protection Standard, Application Gateway, Azure Firewall Premium) kept as literal product spellings.
- **Skill marker block**: added at top of body per vault convention.
- **Nine-element response contract**: added to map onto `multi-vendor-network-ops` (vault umbrella iron rule for production-impacting recommendations), adapted to Azure identity and blast-radius terms.
- **Third decision tree added**: "Azure connectivity routing diagnosis" for parity with `aws-networking-audit`'s Transit Gateway routing diagnosis, grounded in the source Step 4 connectivity content.
- **Cross-link surface**: extended beyond upstream to cover the live vault skills above plus the `cloud-network-design` design umbrella and the `aws-networking-audit` and `gcp-networking-audit` parity siblings (both live; the multi-cloud audit trio landed together).
- **Secrets-hygiene cross-link**: added at Prerequisites and the multi-subscription troubleshooting entry; "Probing the credential store" pattern applies to every credential probe.

See `merged-skills-registry/SKILL.md` for the full registry row and audit history.
