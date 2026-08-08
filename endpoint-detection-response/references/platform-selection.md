# EDR platform selection

A cross-platform feature matrix and a per-platform decision guide. The eight platforms below are named as routing context only; the vault keeps the generic methodology and skips the vendor deep-dives. Validate every capability claim against current vendor documentation, since tiers and feature sets change.

## Feature matrix

| Capability | CrowdStrike | Defender MDE | SentinelOne | Carbon Black | Cortex XDR | Elastic Defend | Sophos | Wazuh |
|---|---|---|---|---|---|---|---|---|
| Deployment model | Cloud-native | Cloud (M365) | Cloud/on-prem | Cloud/on-prem | Cloud | Cloud/self-hosted | Cloud (Central) | Self-hosted |
| Agent footprint | Light (~25MB) | Built into Windows | Light | Moderate | Moderate | Via Elastic Agent | Moderate | Light |
| NGAV prevention | Yes | Yes | Yes | Yes | Yes | Yes | Yes (Deep Learning) | Limited |
| Behavioural EDR | Yes (IOA) | Yes (E5) | Yes (Storyline) | Yes | Yes (BIOC) | Yes | Yes | Yes (rules) |
| Threat hunting | CQL / Falcon Insight | KQL Advanced Hunting | Deep Visibility | CB Search | XQL | Kibana / EQL | Sophos Central | OpenSearch |
| Auto-response | RTR | AIR | 1-click rollback | Live Response | Live Terminal | Response actions | AAP | Active response |
| ATT&CK mapping | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| XDR / SIEM integration | Falcon LogScale | Sentinel / Defender XDR | Singularity Data Lake | SIEM connectors | Cortex XSIAM | Elastic SIEM | Sophos MDR | Built-in SIEM |
| Managed service | OverWatch / Complete | Threat Experts | Vigilance | CB TAU | Unit 42 MXDR | N/A | Sophos MDR | N/A |
| Open source | No | No | No | No | No | Partial (EL2.0) | No | Yes (GPLv2) |
| Licensing | Module tiers | M365 E3/E5 | Core/Control/Complete | Standard/Enterprise | Varies | Subscription | Central-based | Free (support paid) |

## Decision guide

**CrowdStrike Falcon** when: cloud-native with no on-prem infrastructure, managed hunting (OverWatch) matters, large enterprise with strict sensor-footprint limits, Threat Graph correlation is valued.

**Microsoft Defender for Endpoint** when: Microsoft-centric (M365 E5/E3), tight integration with Entra ID, Intune, Sentinel, and the Defender XDR suite is needed, built-in vulnerability management (Plan 2) is wanted, Windows-heavy with ASR rules for hardening.

**SentinelOne** when: autonomous response without cloud connectivity is required, 1-click ransomware rollback is a priority, strong macOS and Linux coverage is needed, natural-language hunting (Purple AI) appeals.

**Carbon Black** when: deep process-level forensic visibility and full continuous endpoint recording are required, and there is existing VMware/Broadcom infrastructure. Evaluate the roadmap carefully post-Broadcom acquisition.

**Cortex XDR** when: Palo Alto NGFW and Prisma Cloud are already deployed (native integration), cross-domain correlation (endpoint + network + cloud + identity) is the priority, built-in SOAR (XSOAR) is needed.

**Elastic Defend** when: already running the Elastic stack for SIEM, open-source or cost-sensitive, custom detection-rule development is core, and pipeline flexibility matters.

**Sophos Intercept X** when: SMB or mid-market, deep-learning malware detection without heavy behavioural overhead is preferred, an integrated MDR service is attractive, and simple central management is wanted.

**Wazuh** when: open source (GPLv2) is a hard requirement, combined HIDS + FIM + SCA + SIEM in one platform is needed, regulatory compliance automation (PCI DSS, HIPAA, GDPR) is required, or on-prem / air-gapped deployment is mandatory.

## Selection factors that outrank the matrix

- **OS mix:** Windows-only shops have more choice; heavy macOS/Linux narrows it (SentinelOne, Elastic, Wazuh, CrowdStrike).
- **Existing ecosystem:** MDE for Microsoft, Cortex for Palo Alto, Elastic for an existing ELK stack. Native integration cuts operational cost more than any single feature.
- **Team maturity:** a self-hosted open-source platform (Wazuh, Elastic) costs less in licence and more in operators. Factor the staffing, not just the subscription.
- **Managed-service need:** if there is no 24/7 SOC, weight MDR availability (OverWatch, Sophos MDR, Vigilance, Unit 42) heavily.
- **XDR ambition:** if cross-domain correlation is the goal, prefer a platform whose XDR story is native rather than bolted on, and pair it with siem-soar-investigation and network-detection-response for the non-endpoint domains.
