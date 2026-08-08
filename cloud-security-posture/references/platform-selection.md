# Platform selection

The platform is the last decision, not the first. Settle the dominant estate (which clouds, which workload types), the team's maturity and appetite for agents, and the regulatory drivers; then match a product. No single platform leads on every axis, and a mature programme sometimes runs more than one. The vendors named below appear only as routing context so you can place a tool; their configuration and operations are not the subject of this vault today.

## Platform archetypes

CNAPP products cluster into a few architectural archetypes. Recognising the archetype matters more than memorising a feature grid, because the archetype decides deployment friction, runtime depth, and multi-cloud reach.

| Archetype | How it deploys | Strength | Trade-off | Named examples |
|---|---|---|---|---|
| Agentless-first CNAPP | reads provider APIs and scans snapshots; optional runtime sensor | fast broad coverage, low friction, strong multi-cloud posture and attack-path graph | runtime detection is an add-on, not the core | Wiz, Orca |
| Agent-rich hybrid CNAPP | agentless posture plus a substantial agent fleet for runtime workload protection | deep runtime protection and behavioural detection alongside posture | agent deployment and maintenance overhead | Prisma Cloud (Palo Alto) |
| Cloud-native, single-provider | built into one provider's control plane | tight native integration, low cost of entry within that cloud | weak or absent coverage of other clouds | Microsoft Defender for Cloud (Azure-centric), AWS Security Hub (AWS-only) |
| Finding aggregator | ingests and normalises findings from other tools | single pane over many sources | aggregation, not a full CNAPP in its own right | AWS Security Hub |

A note on the single-provider tools: Defender for Cloud is strong for Azure-centric estates and extends to other clouds through connectors with less depth; AWS Security Hub is an AWS-native aggregation and standards service rather than a full CNAPP. Both now have vault vendor skills for configuration and operations: `defender-cloud` (Microsoft Defender for Cloud) and `aws-security-hub`; general provider work stays with `azure-cloud-ops` and `aws-cloud-ops`.

## Selection dimensions

Score a candidate on the dimensions that actually differentiate, not on a feature checklist:

| Dimension | Question |
|---|---|
| Deployment model | agentless-only, or agents required for the runtime depth you need? |
| Multi-cloud reach | genuine parity across your clouds, or strong in one and thin elsewhere? |
| Runtime protection | is live behavioural detection core, an optional sensor, or absent? |
| CNAPP completeness | does it correlate posture, workload, identity, and data into one attack-path graph, or cover only some pillars? |
| Identity depth (CIEM) | does it compute net-effective permissions and privilege-escalation paths, or only list policies? |
| Data posture (DSPM) | does it discover and classify sensitive data to anchor attack paths on real crown jewels? |
| Code and shift-left | does it push checks into infrastructure-as-code and CI/CD, or stop at the deployed estate? |

## Decision method

1. **Profile the estate.** Which clouds dominate, and which workload types (VMs, containers, serverless, managed services)? A genuinely multi-cloud estate pulls toward an agentless-first or agent-rich CNAPP with real cross-cloud parity; a single-cloud estate can lead with that provider's native tool and add breadth later.
2. **Profile the team.** A small team with little appetite for agent fleet management is better served by agentless-first coverage plus selective agents on high-value workloads than by an agent-rich platform it cannot operate. A team that already runs endpoint agents may absorb an agent-rich hybrid comfortably.
3. **Profile the drivers.** A regulated-data obligation raises the weight on DSPM and compliance mapping; a history of privilege-escalation incidents raises the weight on CIEM; a board-level exposure metric raises the weight on attack-path correlation.
4. **Map to an archetype, then a product.** Choose the archetype the estate and team point to, and accept that a multi-cloud programme sometimes runs a native single-provider tool for its home cloud alongside a cross-cloud CNAPP for correlation.
5. **Deploy in maturity order.** Whatever the platform, turn on posture first, then workload protection, then entitlements, then data posture, then attack-path correlation, per the maturity model in `posture-and-workload-protection.md`. Buying the full platform and using only its CSPM is the common failure.
6. **Plan the integrations.** Wire the platform's findings into the vulnerability programme (`vulnerability-management`) for workload vulnerability scoring and SLAs, into the compliance programme (`compliance-benchmark-audit`) for audit evidence, and take an external-exposure feed from `attack-surface-management` and `defender-easm` to anchor the entry points of attack-path analysis.

## Routing out

- Vulnerability scoring and remediation SLAs for the workload findings CWPP produces: `vulnerability-management`.
- Compliance-framework interpretation and audit evidence built from CSPM findings: `compliance-benchmark-audit`.
- External, outside-in discovery of unknown internet-facing entry points: `attack-surface-management` and `defender-easm`.
- Per-vendor cloud service and security configuration once a posture target is set: `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`.
- Non-security cloud provider or landing-zone selection: `cloud-platform-selection`.
- Container and Kubernetes security depth behind the CWPP container surface: `container-security`.
