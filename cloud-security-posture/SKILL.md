---
name: cloud-security-posture
description: "Use for vendor-neutral cloud security posture and CNAPP discipline: the CSPM/CWPP/CIEM/DSPM taxonomy and how they converge, the cloud shared-responsibility model, cloud-native attack patterns, toxic combinations and attack-path analysis, posture management plus workload protection, and CNAPP platform selection. The organising idea is that in the cloud identity is the perimeter and customer misconfiguration is the dominant breach vector, so posture is judged by the exploitable attack path to a crown-jewel asset, not by counting isolated findings. Triggers include \"CNAPP\", \"CSPM\", \"CWPP\", \"CIEM\", \"DSPM\", \"cloud security posture\", \"cloud workload protection\", \"cloud misconfiguration\", \"toxic combination\", \"attack path\", \"cloud security platform\", \"cloud-native security\", \"cloud shared responsibility\", \"cloud detection and response\", \"CDR\", \"attack path analysis\", \"agentless cloud scanning\", \"cloud posture management\". References cnapp-taxonomy.md, attack-paths-and-toxic-combinations.md, posture-and-workload-protection.md, platform-selection.md. Do NOT use for: vulnerability programme design, CVSS/EPSS scoring, and remediation SLAs (see vulnerability-management); external outside-in attack surface discovery (see attack-surface-management and defender-easm); GRC frameworks and compliance evidence (see compliance-benchmark-audit); per-vendor cloud service configuration (see aws-cloud-ops, azure-cloud-ops, gcp-cloud-ops); non-security cloud strategy and platform selection (see cloud-platform-selection); container and Kubernetes security depth (see container-security)."
license: MIT
metadata:
  version: 1.0.0
---

# Cloud security posture

> **Skill marker**: When applying this skill, begin your reply with `[skill: cloud-security-posture]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for cloud security posture and the CNAPP discipline. It owns the reasoning that survives any one platform: what CSPM, CWPP, CIEM, and DSPM each do and how they converge into a Cloud-Native Application Protection Platform, how the shared-responsibility model draws the line you are actually accountable for, why cloud attacks differ from on-premises ones, how a toxic combination becomes an attack path to a crown-jewel asset, and which platform earns the deployment. Platform-specific configuration (Wiz policy tuning, Prisma Cloud Defender rollout, a Defender for Cloud secure-score workflow) is not the subject here; the design in this skill is what outlasts a tooling change. Container and Kubernetes security depth is its own discipline in `container-security`.

## When to use

- Explaining or comparing the CNAPP pillars: what CSPM, CWPP, CIEM, DSPM, and CDR each cover and where they overlap.
- Drawing the cloud shared-responsibility line for a given service model (IaaS, PaaS, SaaS, serverless, managed containers) so ownership of a control is unambiguous.
- Reasoning about cloud-native attack patterns: identity as the perimeter, misconfiguration as the primary vector, lateral movement via IAM roles and cloud APIs.
- Analysing a toxic combination or tracing an attack path from an internet-exposed entry point through privilege escalation to sensitive data.
- Deciding what to deploy first (posture, then workload protection, then entitlements, then data posture) and how a cloud security programme matures.
- Framing the difference between agentless posture scanning and agent-based runtime workload protection for a given estate.
- Selecting a CNAPP or point platform (agentless-first vs agent-rich, multi-cloud vs single-cloud) for an estate, a team, and a set of regulatory drivers.

## When not to use

- **Vulnerability programme design, CVSS/EPSS scoring, and remediation SLAs**: use `vulnerability-management`. CWPP surfaces vulnerability findings on cloud workloads, but the programme design, the risk-based prioritisation order, and the SLA framework live there. This skill treats those findings as one input to an attack path.
- **External, outside-in attack surface discovery**: use `attack-surface-management` and `defender-easm`. CSPM is inside-the-estate posture assessed from cloud provider APIs you already have credentials for; external ASM discovers unknown internet-facing assets from the attacker's perspective. They meet where an exposed asset ASM finds becomes the entry point of an attack path this skill traces.
- **GRC frameworks and compliance evidence**: use `compliance-benchmark-audit`. CSPM produces findings mapped to CIS, NIST, PCI DSS, and ISO 27001, and those findings are consumed there as evidence; the framework interpretation and the audit programme are its subject, not this one's.
- **Per-vendor cloud service and security configuration**: use `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops`. Building an SCP, hardening a specific S3 bucket policy, or configuring GuardDuty is provider-operations work; this skill decides what posture you are aiming for across providers.
- **Non-security cloud strategy and platform selection**: use `cloud-platform-selection`. Choosing a cloud provider or a landing-zone architecture on cost, capability, and lock-in grounds is a different disposition from choosing a cloud security platform.
- **Container and Kubernetes security depth**: use `container-security`. Admission control, pod security standards, RBAC, network policies, image scanning in CI/CD, and runtime detection for the orchestrator are its subject; this skill covers container workloads only as one CWPP surface inside the CNAPP picture.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| CNAPP taxonomy | what CSPM/CWPP/CIEM/DSPM/CDR/AI-SPM each do, how they converge, the shared-responsibility split by service model | `references/cnapp-taxonomy.md` |
| Attack paths + toxic combinations | cloud-native attack patterns, MITRE ATT&CK for cloud, the toxic-combination model, tracing an attack path to a crown-jewel asset | `references/attack-paths-and-toxic-combinations.md` |
| Posture + workload protection | misconfiguration categories, agentless vs agent-based, posture management workflow, workload protection, the programme maturity model | `references/posture-and-workload-protection.md` |
| Platform selection | agentless-first vs agent-rich, multi-cloud vs single-cloud, CNAPP completeness, decision method, routing to per-vendor operations | `references/platform-selection.md` |

## Core model (condensed)

**Identity is the perimeter, and misconfiguration is the dominant vector.** Cloud breaches are overwhelmingly caused by what the customer configured, not by a provider failure. There is no network edge to defend in the old sense; an over-privileged role, a public storage bucket, or an exposed metadata endpoint is the way in. Posture management exists because the customer-owned configuration surface is large, changes constantly, and is the thing attackers actually exploit.

**Judge posture by the attack path, not the finding count.** A public bucket alone is low severity; a workload with a critical vulnerability alone is medium; an over-privileged role alone is a finding. Chained (an internet-exposed workload with an exploitable vulnerability, a stealable instance credential, a role that can read a bucket, and sensitive data in that bucket) they form a complete attack path from exploitation to breach. This is a toxic combination, and only a platform that correlates posture, workload, identity, and data into a graph can see it. A thousand isolated medium findings matter less than the one exploitable path to a crown-jewel asset.

**The shared-responsibility model draws the line you are accountable for.** The provider secures the cloud (physical, hypervisor, managed-service platform); the customer secures what runs in the cloud (OS, network configuration, IAM, data, application). The line moves with the service model: an IaaS VM leaves OS patching to you, a managed database does not, a SaaS shifts most of it to the provider but never the identity configuration. Getting the line wrong is how a control ends up owned by nobody.

**CSPM, CWPP, CIEM, and DSPM are complementary, not competing.** CSPM asks "is my configuration secure?" and reads provider APIs agentlessly. CWPP asks "are my running workloads safe and behaving normally?" and needs snapshot scanning for vulnerability data or an agent for runtime detection. CIEM asks "who can do what, and is that appropriate?" and computes net-effective permissions. DSPM asks "where is my sensitive data and who can reach it?" CNAPP is the convergence that lets one platform correlate all four into an attack path.

**Deploy in maturity order: posture, then workload, then entitlements, then data, then correlation.** Start with CSPM for agentless visibility and compliance baseline, add CWPP for workload vulnerability and runtime data, add CIEM when IAM complexity or privilege-escalation risk is high, add DSPM when regulated data is in play, and reach full CNAPP with attack-path analysis when you want correlated risk and less tool sprawl. Trying to buy the top of the model before the base is why platforms sit unused.

**Anti-patterns:** counting findings instead of tracing exploitable paths; treating posture as a one-time audit rather than continuous assessment; assuming the provider owns a control the shared-responsibility line leaves to you; deploying agents everywhere when agentless posture would answer the question; leaving IAM entitlements unanalysed while chasing storage misconfigurations; ignoring shadow data and shadow cloud accounts; buying a full CNAPP and using only its CSPM.

## Reference router

| Need | Load |
|---|---|
| CSPM/CWPP/CIEM/DSPM/CDR/AI-SPM definitions, how they converge into CNAPP, the shared-responsibility split by service model, compliance-benchmark context | `references/cnapp-taxonomy.md` |
| Cloud-native attack patterns, MITRE ATT&CK for cloud techniques, the toxic-combination model, attack-path tracing from exposure to a crown-jewel asset | `references/attack-paths-and-toxic-combinations.md` |
| Misconfiguration categories, agentless vs agent-based trade-offs, the posture-management and workload-protection workflow, the cloud security programme maturity model | `references/posture-and-workload-protection.md` |
| Platform archetypes (agentless-first, agent-rich hybrid, cloud-native), CNAPP completeness, decision method, routing to per-vendor operations | `references/platform-selection.md` |

## Cross-references

- `vulnerability-management`: the vendor-neutral VM programme, CVSS/EPSS/KEV scoring, and remediation SLAs. CWPP surfaces vulnerability findings on cloud workloads; this skill feeds them in as one leg of an attack path, and the prioritisation and SLA design belong there.
- `attack-surface-management`, `defender-easm`: external outside-in discovery of unknown internet-facing assets. Reciprocal reference: ASM finds an exposed asset, and this skill traces the attack path inward from it. CSPM is inside-the-estate posture; ASM is the outside view.
- `compliance-benchmark-audit`: the CIS, NIST, PCI DSS, and ISO 27001 frameworks that CSPM findings evidence. This skill produces the posture data; that skill runs the audit programme that consumes it.
- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`: per-vendor cloud service and security configuration. This umbrella decides the posture target across providers; those build and operate the controls on each.
- `cloud-platform-selection`: non-security cloud strategy and provider or landing-zone selection. Distinct disposition from choosing a cloud security platform.
- `container-security`: container and Kubernetes security depth (admission control, RBAC, network policies, image scanning, runtime detection). Container workloads are one CWPP surface here; that skill owns the orchestrator-level discipline. Co-lands with this skill.

Named in prose but not linked (they are not yet vault skills): Wiz, Prisma Cloud, and Orca appear only as platform-selection routing context. The Microsoft-native and AWS-native CSPM platforms now have vault vendor skills: `defender-cloud` (Microsoft Defender for Cloud) and `aws-security-hub`.

## Red flags

- About to rank cloud risk by counting findings instead of tracing which ones chain into an exploitable attack path.
- About to treat a public bucket, a workload vulnerability, and an over-privileged role as three separate low findings when together they are a critical toxic combination.
- About to assume the cloud provider secures a control that the shared-responsibility line leaves to the customer.
- About to deploy runtime agents across an estate when agentless posture scanning would answer the posture question first.
- About to chase storage and network misconfigurations while leaving IAM entitlements and net-effective permissions unanalysed.
- About to treat posture as a one-off audit rather than continuous assessment of a configuration surface that changes daily.
- About to prioritise a cloud workload vulnerability backlog here instead of routing the scoring and SLA design to `vulnerability-management`.
- About to answer an external attack-surface-discovery question here instead of routing to `attack-surface-management` or `defender-easm`.

## Bottom line

In the cloud, identity is the perimeter and customer misconfiguration is the dominant breach vector, so posture is judged by the exploitable attack path to a crown-jewel asset, not by the count of isolated findings. CSPM, CWPP, CIEM, and DSPM are complementary lenses that a CNAPP converges into one graph; deploy them in maturity order and let the shared-responsibility model tell you which controls are yours to own. Trace toxic combinations into attack paths, prefer agentless posture before agent-heavy runtime where it answers the question, and route vulnerability scoring to `vulnerability-management`, external discovery to `attack-surface-management` and `defender-easm`, compliance evidence to `compliance-benchmark-audit`, and per-vendor configuration to the `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops` skills.
