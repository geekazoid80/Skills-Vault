# CNAPP taxonomy

Cloud security tooling proliferated into silos: one product for misconfigurations, another for workload vulnerabilities, another for identity, another for data. Each found issues in isolation and none saw how they combined. CNAPP is the answer to that fragmentation. Understanding the taxonomy is knowing what each pillar covers, where they overlap, and why convergence matters.

## Cloud-Native Application Protection Platform (CNAPP)

Gartner coined CNAPP in 2021 to describe the convergence of CSPM, CWPP, and the adjacent cloud security tools into a single platform that correlates context across posture, workload, identity, and data. The organising insight: individual tools find individual issues, but only a unified platform with a graph model can see that a misconfigured bucket, an exploitable workload, and an over-privileged role together form a complete attack path. That correlated, contextual risk is the value CNAPP adds over a bag of point tools.

The pillars below are the capability categories a CNAPP unifies. A given product may lead with one pillar and cover the others to varying depth; the taxonomy is stable even as vendor packaging shifts.

## The pillars

| Capability | Acronym | The question it answers | Typical signal |
|---|---|---|---|
| Cloud Security Posture Management | CSPM | Is my cloud configured securely? | storage bucket public, security group open to 0.0.0.0/0, MFA disabled, logging off |
| Cloud Workload Protection Platform | CWPP | Are my running workloads safe and behaving normally? | critical CVE in a running image, shell spawned in a container, crypto miner process |
| Cloud Infrastructure Entitlement Management | CIEM | Who can do what, and is that appropriate? | role with admin-equivalent permissions, unused service account with broad access |
| Data Security Posture Management | DSPM | Where is my sensitive data and who can reach it? | PII in a public bucket, unencrypted database, shadow data store |
| Cloud Detection and Response | CDR | Is an attack happening right now in my cloud? | credential exfiltration, anomalous API calls, lateral movement via assume-role |
| AI Security Posture Management | AI-SPM | Where are my AI/ML workloads and what is exposed? | exposed model endpoint, training data in accessible storage, model exfiltration risk |
| Shift-left / code security | (no standard acronym) | Is the misconfiguration or secret caught before deployment? | Terraform misconfiguration, hardcoded cloud key in source, vulnerable dependency |

### CSPM (posture)

Continuously scans cloud resource configurations against security benchmarks by reading cloud provider APIs, so it needs no agents. Coverage spans IAM policies, network configuration, storage permissions, encryption settings, logging and monitoring configuration, and service-specific settings. It maps findings to benchmarks (CIS Foundations for AWS, Azure, and GCP, plus NIST 800-53, SOC 2, PCI DSS, ISO 27001, HIPAA, FedRAMP). Key metrics are open findings by severity, compliance score per framework, and mean time to remediate. CSPM is the usual entry point because it is agentless and gives fast visibility.

### CWPP (workload)

Protects the workloads themselves (VMs, containers, serverless functions, databases) by two approaches with different trade-offs:

- **Agentless snapshot scanning** reads cloud storage snapshots of a workload without running inside it. High coverage for vulnerability and malware detection, low coverage for runtime behaviour, near-zero deployment friction.
- **Agent-based runtime protection** installs an agent in the workload. Full runtime visibility (process execution, file-system changes, network connections, drift), behavioural detection of an active attack, at the cost of deployment and maintenance.

Capabilities include vulnerability scanning of OS packages and language libraries, malware detection, runtime behavioural monitoring, and drift detection. The vulnerability findings CWPP produces are prioritised and SLA-managed under the `vulnerability-management` discipline, not here.

### CIEM (entitlements)

Analyses every IAM entity (users, roles, groups, service accounts, federated identities) and computes **net-effective permissions**: what an identity can actually do after all attached policies, permission boundaries, service control policies, resource policies, and conditions are evaluated. It surfaces over-privileged identities, stale and unused credentials, cross-account trust relationships, privilege-escalation paths, and shadow admin accounts. The governing principle is least privilege: grant only what a specific task needs. Because identity is the cloud perimeter, CIEM is where privilege-escalation attack paths are cut.

### DSPM (data posture)

Discovers data stores across the estate (object storage, managed databases, blob storage, data warehouses, NoSQL tables), classifies data by sensitivity (PII, PCI, PHI, secrets, intellectual property), and maps exposure: who and what has access, whether data is encrypted, whether it is publicly reachable, whether access is logged. It surfaces **shadow data**, sensitive stores that security teams did not know existed. DSPM is newer than CSPM, CWPP, and CIEM and is still maturing, but it is what tells an attack-path analysis whether the asset at the end of the path is actually a crown jewel.

### CDR (detection and response)

Real-time threat detection and response across cloud telemetry: audit logs (management-plane API activity), workload telemetry from agents, network flow logs, and identity events. Detection blends behavioural analytics, anomaly detection, threat intelligence, and rules. Typical detections are credential exfiltration, unusual API patterns, lateral movement via role assumption, and crypto-mining signatures. CDR is the runtime, in-the-moment counterpart to CSPM's configuration-time posture view.

### AI-SPM and shift-left

**AI-SPM** is the newest category, discovering AI and ML workloads (managed model services, custom model endpoints, training pipelines) and their specific risks: exposed model endpoints, training data in accessible storage, prompt-injection surfaces, and model exfiltration. **Shift-left / code security** moves the check earlier: infrastructure-as-code scanning (Terraform, CloudFormation, ARM, Bicep, Pulumi) before deployment, secrets detection in source, software composition analysis for vulnerable dependencies, container image scanning in CI/CD, and pipeline security. Catching a misconfiguration in a pull request is cheaper than remediating it in production.

## Shared-responsibility model

Cloud providers secure the cloud; customers secure what they run in it. The provider owns the physical infrastructure, hardware, hypervisor, global network, and the managed-service platforms. The customer owns configuration, deployment, and operation of everything on top. The single most important consequence: the leading cause of cloud security incidents is customer misconfiguration, not provider failure, which is precisely why posture management exists.

The line moves with the service model:

| Service model | Example | OS patching | Network config | IAM | Application security | Data |
|---|---|---|---|---|---|---|
| IaaS | virtual machine, self-managed compute | Customer | Customer | Customer | Customer | Customer |
| PaaS | managed database, managed app runtime | Shared | Shared | Customer | Customer | Customer |
| SaaS | managed productivity or CRM suite | Provider | Provider | Customer | Provider | Shared |
| Serverless | managed functions | Provider | Shared | Customer | Customer | Customer |
| Managed containers | managed container or Kubernetes service | Shared | Shared | Customer | Customer | Customer |

Two rules of thumb hold across providers. First, IAM configuration is always the customer's, in every service model, because the provider cannot know who in your organisation should have access. Second, the more managed the service, the more the provider absorbs, but never to the point of owning your identity or your data classification. A control that neither side clearly owns is the control that goes unimplemented, so the shared-responsibility line has to be drawn explicitly per service, not assumed.

Provider-specific defaults vary (some clouds give per-project service accounts, organisation policies, and OS-login by default), and the operations of hardening each provider belong to `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops`. The posture target across providers is what this skill sets.

## Compliance-benchmark context

CSPM findings are routinely mapped to frameworks so they double as audit evidence: CIS Foundations benchmarks (the usual CSPM baseline, structured in tiers from basic to high-security), NIST 800-53 and NIST CSF 2.0, PCI DSS 4.0, HIPAA, SOC 2, ISO 27001, and cloud-specific guidance such as each provider's well-architected security guidance and FedRAMP for US federal workloads. This skill treats the frameworks only as the target CSPM measures against; interpreting a framework, choosing controls, and running the audit programme are the subject of `compliance-benchmark-audit`. See the official CIS Benchmarks and the framework publications themselves for the authoritative control text rather than relying on any tool's paraphrase.

## How the pillars converge

The pillars are complementary lenses on the same estate, and their value multiplies when correlated. CSPM sees the public bucket. CWPP sees the exploitable workload. CIEM sees the over-privileged role. DSPM sees that the bucket holds PII. Individually each is a finding of modest severity. Correlated in a graph, they are a single critical attack path from an internet-exposed foothold to a data breach, which is the toxic-combination reasoning developed in `attack-paths-and-toxic-combinations.md`. Deploy the pillars in maturity order (posture first, then workload, then entitlements, then data, then full correlation), a sequence developed in `posture-and-workload-protection.md`.
