# Zero trust, ZTNA, and maturity assessment

The zero-trust foundations, the ZTNA design and migration, and a five-pillar maturity model with a scoring method and assessment methodology. Identity-platform depth (IdP, MFA, PAM, IGA) lives in `identity-access-management`; this reference owns the network-access and assessment side.

## The seven NIST SP 800-207 tenets

1. All data sources and computing services are resources, regardless of location.
2. All communication is secured regardless of network location; the local network is not automatically trusted.
3. Access to individual resources is granted per-session; broad lateral movement is not permitted.
4. Access is determined by dynamic policy, considering client identity, application, device posture, behavioural signals, and time.
5. The enterprise monitors and measures the integrity and posture of all owned and associated assets continuously.
6. All authentication and authorisation is dynamic and strictly enforced before access, re-evaluated per request or at least per session.
7. The enterprise collects as much information as possible about the current state of assets, infrastructure, and communications, and uses it to improve posture.

Forrester's Zero Trust eXtended (ZTX) expresses the same idea as seven pillars to invest across: Networks, Devices, People, Workloads, Data, Visibility and Analytics, and Automation and Orchestration.

## ZTNA versus VPN

| Aspect | VPN | ZTNA |
|---|---|---|
| Network access | Full tunnel; lateral movement possible | Application-specific only |
| Trust model | Trust everything inside the tunnel | Verify every request, trust no network |
| Authentication | Once, at connection | Continuous assessment |
| Visibility | Limited (encrypted tunnel) | Full inspection and logging |
| Scalability | Appliance-constrained bottleneck | Cloud-native, elastic |
| Split tunnelling | Complex to manage safely | Native; only private-app traffic is tunnelled |
| App exposure | IP-based; network segments are exposed | Name-based; the app is never exposed to the internet |

### ZTNA 1.0 versus ZTNA 2.0

- **ZTNA 1.0** (most products): grants access to an application at connection, does not re-verify within the session, tends to be network-level (port/protocol) rather than true app-level, and does not inspect traffic inside the allowed connection.
- **ZTNA 2.0** (Palo Alto's framing): full app-level control per request, continuous trust verification through the session, deep inspection of allowed traffic (IPS and malware scanning within the session), across all ports and protocols rather than just HTTP/HTTPS.

When a product is called "ZTNA", verify which of these it actually does. Connect-then-trust (1.0) leaves much of the lateral-movement risk in place.

## VPN-to-ZTNA migration framework

**Phase 1, discovery and inventory.** Inventory every VPN-accessed application; classify each as internal app, SaaS, internet, or legacy non-HTTP; map user groups to applications; flag apps with client-certificate or other special requirements.

**Phase 2, connector deployment.** Deploy application connectors in the private segment that hosts the applications, publish the first application through ZTNA, and test with a pilot group (the IT team) to validate performance and access.

**Phase 3, pilot.** Select 50 to 100 users across diverse job functions, run VPN and ZTNA in parallel, move the pilot users' applications to ZTNA, gather feedback, tune policy, and resolve legacy issues (non-HTTP protocols, thick clients).

**Phase 4, production migration.** Migrate department by department, decommission VPN for each migrated group, keep VPN only for true network-level cases (administrator access to network devices, legacy non-web apps), then fully decommission for end-user access.

**Legacy considerations.** SSH and RDP are usually supported via native tunnelling or HTML5 browser access; custom TCP apps need every required port verified under a port-based rule; apps that whitelist a source IP should be updated to the connector's stable IP; Kerberos or NTLM apps need the connector domain-joined or able to pass the ticket through.

## Zero-trust maturity model

Score five pillars across five levels. Grounded in NIST SP 800-207 and structured after the CISA Zero Trust Maturity Model.

### The five pillars

- **Identity**: authentication and authorisation of every human and machine identity before access (MFA, certificate-based auth, SSO, service identity, conditional access). Depth lives in `identity-access-management`.
- **Device**: validation of device health, compliance, and trust before access (endpoint management, device certificates, posture agents, asset-inventory completeness).
- **Network**: micro-segmentation, encrypted transport, and dynamic per-flow access control (segmentation, encrypted east-west, software-defined perimeter, NAC, DNS security).
- **Application**: application-level access control, workload identity, and runtime protection (app-aware firewalling, API-gateway enforcement, service-mesh security, WAF, access brokers).
- **Data**: classification, encryption, access control, and loss prevention at rest, in transit, and in use.

### The five levels

1. **Traditional**: perimeter-centric, VLAN-only segmentation, single-factor auth, implicit internal trust, no continuous posture.
2. **Initial**: MFA for privileged access, some segmentation beyond VLANs, partial asset inventory, centralised logging but not correlated.
3. **Advanced**: universal MFA, micro-segmentation in critical zones, device-posture checks enforced, a centralised policy engine and correlated SIEM, automated provisioning.
4. **Optimal**: risk-adaptive, continuous verification (sessions re-evaluated on behaviour and posture change), encrypted east-west, data-centric controls at access points, automated response.
5. **Adaptive**: fully automated and self-healing, real-time policy adaptation from threat intelligence and analytics, zero standing privileges, full telemetry feeding a closed-loop policy engine.

### Scoring matrix (per pillar)

| Level | Identity | Device | Network | Application | Data |
|---|---|---|---|---|---|
| 1 | Password-only, local accounts, no IdP | No inventory or posture checks | Flat or VLAN-only, no east-west inspection | No app-layer control, network access implies app access | No classification, location-based access, no DLP |
| 2 | MFA for privileged, central IdP for devices | Basic inventory, 802.1X on some ports | ACL zones, VRF-lite, perimeter IDS/IPS | Basic WAF, initial API gateway | Basic classification, at-rest DB encryption, email DLP |
| 3 | MFA for all, certificate auth, automated lifecycle, conditional access | NAC enforces posture, device certs, 802.1X everywhere | Micro-segmentation, identity-aware rules, encrypted management plane | All external apps behind a proxy/ZTNA, API auth, workload segmentation | Automated classification, egress DLP, sensitive-store access logging |
| 4 | Risk-adaptive MFA, continuous evaluation, just-in-time elevation, passwordless | Continuous posture, auto-quarantine, IoT profiling | Encrypted east-west, SDP, dynamic segmentation | Service mesh mTLS, RASP, CI/CD scanning | Access governance analytics, rights management, classification-driven encryption |
| 5 | Zero standing privileges, behavioural biometrics, real-time risk scoring | Real-time device risk, auto-remediation, hardware-rooted attestation | Fully automated segmentation, per-flow encryption, closed-loop enforcement | Real-time app behaviour analytics, auto-generated policy | Real-time data-access risk scoring, predictive DLP, full lineage |

### Calculating overall maturity

The overall posture is the **lowest pillar**, not the average, because zero trust is only as strong as its weakest pillar (a Level 4 network behind Level 1 identity is a false comfort):

```
Overall maturity = MIN(Identity, Device, Network, Application, Data)
```

For tracking incremental progress, also report a **weighted average** (defaults reflect identity and network being foundational):

```
Weighted = Identity 0.25 + Device 0.20 + Network 0.25 + Application 0.15 + Data 0.15
```

Report both: the weighted average shows trajectory, the lowest-pillar score shows true posture.

### Assessment methodology

1. **Evidence collection**: gather configuration artefacts, policy documents, and operational data per pillar; document what exists against what is claimed. Verify technical controls with the platform tooling (per-vendor detail in `zscaler`, `prisma-access`, `fortisase`).
2. **Pillar scoring**: score each pillar independently, assigning the highest level for which all criteria are met. Partial implementation of a level does not earn it.
3. **Gap analysis**: for each pillar, find the delta to the target level and classify each gap as a quick win (0 to 30 days, configuration), a project (1 to 6 months, new tooling), or strategic (6 months or more, organisational change).
4. **Roadmap**: address the lowest-scoring pillar first, sequence foundational pillars (Identity, Network) before dependent ones (Application, Data), and set milestones, resource estimates, and re-assessment dates.

## Compliance mapping

| Control area | NIST 800-207 | CIS Controls v8 | ISO 27001 |
|---|---|---|---|
| Identity verification | Tenets 3, 6 | CIS 5 (Account Management) | A.9 Access Control |
| Device health | Tenet 5 | CIS 4 (Asset Management) | A.8 Asset Management |
| Network segmentation | Tenets 2, 3 | CIS 12 (Network Infrastructure) | A.13 Network Security |
| Continuous monitoring | Tenet 7 | CIS 8 (Audit Log Management) | A.12 Operations Security |
| Data protection | Tenet 1 | CIS 3 (Data Protection) | A.18 Compliance |

**US federal (OMB M-22-09)** mandates a zero-trust strategy across five pillars: Identity (phishing-resistant MFA), Devices (MDM enrolment and posture in access decisions), Networks (encrypted DNS and traffic, HTTPS enforcement), Applications (all apps treated as internet-facing with app-level access control), and Data (categorise, automate protection, log all access). CISA's Zero Trust Maturity Model provides the Traditional to Optimal ladder per pillar that the model above follows.
