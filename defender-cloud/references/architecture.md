# Microsoft Defender for Cloud architecture

Defender for Cloud (DfC) is Microsoft's cloud-native application protection platform (CNAPP): a control plane hosted by Microsoft that pairs cloud security posture management (CSPM) with cloud workload protection (CWPP). It is deepest for Azure, extends to on-premises and other clouds through Azure Arc and native connectors, and correlates into the Microsoft Defender XDR portal. Understanding the free-versus-paid split, how each plan protects a resource family, and how the security graph is built is what lets you reason about what a subscription is actually protected against.

## Foundational CSPM versus Defender CSPM

This is the most important distinction in the product.

### Foundational CSPM (free)

On for every Azure subscription at no additional cost:

- **Secure score**: an aggregate posture metric derived from recommendation health.
- **Security recommendations**: actionable guidance mapped to the Microsoft Cloud Security Benchmark (MCSB) controls.
- **Regulatory compliance dashboard**: assessment against MCSB and any assigned standards (CIS, PCI DSS, NIST, and others).
- **Asset inventory**: a centralised view of every resource and its security state.
- **Workbook templates**: pre-built Azure Monitor workbooks for security reporting.

What the free tier does not have: threat detection (no workload alerts), vulnerability assessment (no CVE scanning), runtime protection, and the deeper recommendations (no JIT, no FIM, no adaptive controls, no attack paths).

### Defender CSPM (paid plan)

A single paid plan, billed per billable resource, that turns the posture layer into a full CSPM:

- **Attack-path analysis**: multi-hop routes to critical assets.
- **Cloud security explorer**: a query interface over the security graph.
- **Agentless VM vulnerability assessment**: via Microsoft Defender Vulnerability Management (MDVM), no agent.
- **Agentless container-image scanning**: registry images scanned without a build-time agent.
- **Data-aware security posture (DSPM)**: sensitive-data discovery and classification for cloud data stores.
- **Cloud infrastructure entitlement management (CIEM)**: cloud identity and permissions analysis.
- **Code-to-cloud (DevOps security)** and the **external attack surface management (EASM)** integration.

### Capability matrix

| Capability | Foundational (free) | Defender CSPM (paid) |
|---|---|---|
| Security recommendations | Yes | Yes |
| Secure score | Yes | Yes |
| Continuous assessment | Yes | Yes |
| Regulatory compliance dashboard | Yes | Yes |
| Asset inventory | Yes | Yes |
| Attack-path analysis | No | Yes |
| Cloud security explorer | No | Yes |
| Agentless VM scanning | No | Yes |
| Agentless container-image scanning | No | Yes |
| Data-aware security posture (DSPM) | No | Yes |
| CIEM (permissions analysis) | No | Yes |
| Governance rules | No | Yes |
| External attack surface (EASM) | No | Yes |

Note that Defender CSPM is separate from the per-resource Defender plans below. A subscription can run Defender CSPM (posture and attack paths) without any Defender plan (workload runtime protection), or vice versa; they solve different problems.

## The Defender plans catalogue

Each Defender plan is a paid CWPP for one resource family, billed per resource, and adds runtime threat detection and, where relevant, vulnerability assessment.

| Plan | Billing unit | What it protects and detects |
|---|---|---|
| Defender for Servers P1 | Per server | Defender for Endpoint (MDE) integration bringing EDR to Azure and Arc VMs, JIT VM access, MDE-powered vulnerability data |
| Defender for Servers P2 | Per server | Everything in P1 plus MDVM or Qualys vulnerability assessment, adaptive application controls, file integrity monitoring, network map, and free Log Analytics ingestion (500 MB per server per day) |
| Defender for Containers | Per vCore-hour | Kubernetes audit-log analysis, runtime behavioural protection via the Defender sensor, container-image vulnerability scanning, CIS Kubernetes hardening, admission control |
| Defender for Databases | Per instance | SQL injection, anomalous access, and brute-force detection across Azure SQL, SQL on VMs, Cosmos DB, and the open-source engines (MySQL, PostgreSQL, MariaDB) |
| Defender for Storage | Per storage account (plus per-scan) | Anomalous access, malware upload scanning, anonymous-access and data-exfiltration detection for Blob, Files, and Data Lake Gen2 |
| Defender for App Service | Per plan | Web-shell and command-injection detection, dangling-DNS subdomain takeover, suspicious outbound connections |
| Defender for Key Vault | Per vault | Access from suspicious IPs, high-volume operations, unusual access patterns, account-takeover indicators |
| Defender for Resource Manager | Per subscription | Management-plane threat detection for ARM operations |
| Defender for DNS | Per subscription | DNS tunnelling, C2 over DNS, and malicious-domain resolution from Azure resources |
| Defender for APIs | Per API | Threat detection and posture for Azure API Management-published APIs |

### Defender for Servers workload controls

- **JIT VM access**: management ports (SSH 22, RDP 3389, WinRM) stay blocked in the network security group by default. On an approved request, a time-limited NSG rule opens the port to a specific source IP for a chosen window (typically one to eight hours), then auto-removes. Every request is logged to the Azure activity log.
- **Adaptive application controls**: machine learning profiles the processes that normally run across a group of VMs and recommends an allowlist policy. In audit mode an unknown process raises an alert; in enforce mode it is blocked.
- **File integrity monitoring (FIM)**: tracks changes to critical files and registry keys (on Windows, `HKLM\System` and `HKLM\Software` and `system32`; on Linux, `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/bin`, `/sbin`, and SSH authorised-keys), plus custom paths. Changes flow to Log Analytics with alerts on suspicious edits.

## Secure score model

Secure score is a percentage: points earned over points available.

```
Secure score = sum of points earned / sum of maximum points available
```

- Recommendations group into **security controls** (for example "Remediate vulnerabilities" or "Enable MFA").
- Each control has a maximum point contribution.
- A control contributes its points only when **every** recommendation in it is healthy for **every** in-scope resource. Partial completion earns zero for that control. The scoring is binary per control, not linear per recommendation.
- The highest-leverage remediation is therefore the control with the largest potential score increase and the fewest remaining unhealthy resources, not the one with the most findings.

Recommendation categories include identity and access (MFA for owners and contributors, remove deprecated accounts), network (close management ports, apply adaptive network hardening), data and storage (private endpoints, secure transfer, block public access), and applications (latest TLS, HTTPS-only, remediate container-image CVEs).

## CSPM assessment pipeline

DfC uses Azure Policy as its CSPM assessment engine.

```
Azure resources
  -> Azure Resource Manager (reads resource configurations)
    -> Azure Policy engine (the DfC security initiative)
       - evaluates configurations against policy rules
       - marks resources compliant or non-compliant
      -> Defender for Cloud
         - turns non-compliant resources into security recommendations
         - calculates secure score from recommendation health
```

Assessment cadence: policy compliance is evaluated continuously, new resources are assessed within minutes, recommendation state refreshes every few hours, and secure score updates near real-time. The default initiative is the Microsoft Cloud Security Benchmark; regulatory-compliance standards (CIS, PCI DSS, NIST, and others) are assigned as separate initiatives, and custom frameworks are custom initiatives.

## CWPP data collection

For workload protection, DfC collects telemetry through agents on servers and a sensor on Kubernetes.

- **Azure Monitor Agent (AMA, current)**: the primary collection mechanism, configured through data collection rules (DCRs), supporting multi-homing and auto-provisioning to in-scope VMs. It replaces the legacy Log Analytics agent (`MicrosoftMonitoringAgent` on Windows, `omsagent` on Linux), which is deprecated.
- **What the agents collect**: Windows security events and Linux syslog for threat detection, performance counters, FIM events, process-execution events for adaptive application controls, and network-connection events.
- **MDE sensor**: Defender for Servers P1 and P2 auto-provision the Microsoft Defender for Endpoint sensor to eligible Azure and Arc VMs. MDE threat detections forward to DfC alerts, MDVM vulnerability data forwards to DfC recommendations, and the device inventory shows in the DfC asset inventory.
- **Defender sensor for Kubernetes**: a DaemonSet that collects kernel-level events (process execution, network, file access) via eBPF and sends compressed telemetry to DfC for behavioural threat detection. On AKS it is deployed automatically; on Arc-enabled clusters it is the Defender for Containers extension (a Helm chart).

### Container registry scanning

```
Container registry (ACR, or connected ECR/GCR)
  -> on image push, or scheduled scan
    -> Microsoft Defender Vulnerability Management (MDVM)
       - OS package CVE detection
       - application package CVE detection
      -> findings surface as Defender for Cloud recommendations
```

## Multi-cloud onboarding

### Azure Arc (agent-based, full depth)

Azure Arc extends Azure management, including DfC, to non-Azure resources.

```
Non-Azure resource (AWS EC2, GCP GCE, on-premises VM)
  -> Azure Connected Machine agent
     - outbound HTTPS (TCP 443) to Azure endpoints
     - managed service identity for authentication
     - registers as Microsoft.HybridCompute/machines in a resource group
  -> Azure Resource Graph (the Arc machine appears as a resource)
  -> Defender for Cloud (applies recommendations, policies, and Defender plans)
```

Once a server is Arc-enabled it can carry Defender for Servers P1 or P2 with the full MDE, JIT, FIM, and adaptive-controls depth. Arc-enabled Kubernetes connects any cluster (EKS, GKE, OpenShift, self-managed) and runs Defender for Containers with the sensor DaemonSet and Kubernetes audit-log shipping.

### Native AWS and GCP connectors (agentless, CSPM breadth)

For CSPM visibility without deploying Arc agents:

```
AWS account
  -> cross-account IAM role (read-only), deployed by a CloudFormation template
     - AWS Config resource configurations
     - AWS Security Hub findings (imported as DfC alerts)
     - selected CloudTrail audit events
     - EC2, S3, IAM inventory via API
  -> Defender for Cloud
     - CSPM recommendations for AWS resources
     - AWS resources in the unified asset inventory
     - agentless EC2 scanning (with Defender CSPM)
```

The GCP connector is equivalent, using a service account with the required roles and pulling Security Command Center findings, Cloud Audit Logs, and GCE, GKE, Cloud Storage, IAM, and BigQuery inventory. The native connectors deliver CSPM visibility and, with Defender CSPM, agentless VM and container scanning; they do not provide the agent-based runtime depth, which needs Arc.

## Agentless scanning

Defender CSPM includes agentless VM and container-image scanning.

1. DfC takes a read-only disk snapshot of the VM (an Azure managed snapshot, or an EBS snapshot on AWS).
2. The snapshot is analysed in an isolated Microsoft environment: installed software, OS patch level, and vulnerabilities are extracted.
3. Results appear in DfC as vulnerability recommendations.
4. The snapshot is deleted after analysis.

No agent is required, so coverage extends to every VM automatically across Azure, AWS, and GCP through the connectors. Vulnerability assessment providers are MDVM (integrated, no extra cost with P2 or Defender CSPM), Qualys (built-in integration, separate licensing), or a bring-your-own scanner.

## The cloud security graph

With Defender CSPM enabled, DfC builds a security graph of the estate and uses it for attack-path analysis and the cloud security explorer.

**Data model:**

- **Resource nodes**: VMs, storage, databases, identities, networks, containers.
- **Edge types**: network exposure, IAM permission, data-storage relationship.
- **Enrichment**: CVE data from agentless scanning and MDVM, data classification from DSPM.

**Attack-path analysis** walks the graph to surface multi-hop routes to critical assets and shows the remediation that breaks the path (fix the weakest link). Typical paths:

```
Internet-exposed VM
  -> critical vulnerability on the VM
    -> VM has a managed identity with storage-account access
      -> storage account holds sensitive data (from DSPM)
```

```
Public internet
  -> S3 bucket (AWS) publicly accessible
    -> bucket holds credentials or secrets
      -> credentials allow lateral movement to other resources
```

**Cloud security explorer** is the query interface over the same graph, comparable to other CNAPP graph query languages:

```
Virtual machine > filter: exposed to internet = true
  and contains > vulnerability: severity = critical

Identity > filter: unused admin permissions
```

Without Defender CSPM there is no graph, so there is no attack-path analysis and no cloud security explorer, however many workload alerts the Defender plans generate.

## Log Analytics workspace relationship

- **Default workspace**: DfC auto-creates a default workspace per region (`defaultworkspace-<subscriptionId>-<region>`); agent-collected events and syslog land there and DfC queries it for threat detection.
- **Custom workspace**: point DfC at a customer-managed workspace to combine security data with other operational logs, control retention, and manage cost.
- **Security-relevant tables**: `SecurityEvent` (Windows security events), `Syslog` (Linux), `SecurityAlert` (DfC alerts), `SecurityRecommendation` (recommendation snapshots), `AzureActivity` (control-plane audit), and the firewall tables. Entra ID `SigninLogs` and `AuditLogs` arrive through a separate connector.

## Defender XDR and SIEM correlation

DfC alerts flow into the Microsoft Defender XDR portal, where they correlate with Defender for Endpoint (device), Defender for Office 365 (email), Defender for Identity (on-premises AD), and Entra ID signals into unified incidents.

```
Azure resource event or agent telemetry
  -> Defender for Cloud analysis (rule-based, ML anomaly, threat-intelligence correlation)
    -> security alert (in Defender for Cloud)
      -> Microsoft Sentinel (native connector, no export config needed)
         - alert ingested as a SecurityAlert record
         - Fusion correlates with other signals
         - incident created when an analytics rule matches
        -> automated response (Logic App automation rule, Sentinel playbook, or auto-remediation task)
```

The native Sentinel connector streams security alerts, secure-score changes, and regulatory-compliance changes with no export configuration. Continuous export can additionally push findings to a Log Analytics workspace, an Event Hub (for Splunk, Elastic, and other SIEMs), or Azure Storage for archival. Route the SIEM correlation work to `siem-soar-investigation`; route the device-side depth to `defender-for-endpoint`.

## Cost model

Defender plans bill per resource per plan per month; Defender CSPM bills per billable resource. Indicative billing units (confirm against current Microsoft pricing): Defender CSPM per billable resource-hour, Defender for Servers P1 and P2 per server per month, Defender for Containers per vCore-hour, Defender for Databases and App Service per instance or plan per month, Defender for Storage per storage account plus per-scan, Defender for Key Vault per transaction block, and Defender for DNS and Resource Manager per subscription. Cost-management practice: enable plans only where needed (scope by resource group or tag exclusion), start Servers at P1 for MDE and JIT and upgrade to P2 for full CWPP, and enforce consistent enablement across subscriptions through a management-group policy.
</content>
