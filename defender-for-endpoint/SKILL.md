---
name: defender-for-endpoint
description: "Use for Microsoft Defender for Endpoint (MDE) configuration, operations, and read-only posture audit. Covers the sensor-plus-cloud EDR architecture built on the Microsoft security graph, onboarding per operating system (Windows via Intune, Group Policy, Configuration Manager, or local script; macOS; Linux; mobile; and the server unified agent), device groups and RBAC roles, EDR in block mode, network protection and web content filtering, Attack Surface Reduction (ASR) rules with the audit-then-block tuning workflow, advanced hunting with KQL over the Device tables (DeviceProcessEvents, DeviceNetworkEvents, DeviceFileEvents, DeviceRegistryEvents, DeviceLogonEvents, DeviceEvents, and the DeviceTvm vulnerability tables), Automated Investigation and Response (AIR) automation levels and the Action Center, Microsoft Defender Vulnerability Management (MDVM) with exposure-based prioritisation and exception handling, Threat Analytics, tamper protection, live response, the performance-and-exclusion-hygiene discipline, the Plan 1 versus Plan 2 feature split, and Defender XDR correlation with Defender for Office 365, Defender for Identity, and Entra ID. Also carries a read-only audit lens: sensors onboarded but not reporting, ASR rules stuck in audit, EDR in passive rather than active mode, tamper protection off, AIR at no-automation with no Action Center review, broad path exclusions, and unremediated critical CVEs with a public exploit. When not to use: for vendor-neutral EDR/XDR strategy, detection methodology, and platform selection (which EDR to choose) see endpoint-detection-response; for email and collaboration security see defender-for-office-365; for external attack surface discovery see defender-easm; for the vendor-neutral vulnerability-management PROGRAMME design and scoring see vulnerability-management; for zero-trust IDENTITY governance (Entra ID, MFA, conditional access, PAM, IGA) see identity-access-management; for SIEM/XDR correlation depth and long-term retention see siem-soar-investigation. This skill owns Microsoft Defender for Endpoint configuration and operations. References architecture.md, operations.md, api-and-automation.md. Triggers include \"Defender for Endpoint\", \"Microsoft Defender for Endpoint\", \"MDE\", \"Microsoft Defender ATP\", \"MDATP\", \"ASR rules\", \"attack surface reduction\", \"advanced hunting\", \"DeviceProcessEvents\", \"KQL device hunting\", \"MDE onboarding\", \"device groups\", \"EDR block mode\", \"network protection\", \"web content filtering\", \"Automated Investigation and Response\", \"AIR\", \"Action Center\", \"Defender Vulnerability Management\", \"MDVM\", \"TVM\", \"threat analytics\", \"tamper protection\", \"live response\", \"MDE Plan 1 vs Plan 2\", \"Defender for Endpoint audit\". For vendor-neutral EDR strategy see endpoint-detection-response; for email security see defender-for-office-365; for external attack surface see defender-easm; for identity governance see identity-access-management."
license: MIT
metadata:
  version: 1.0.0
---

# Microsoft Defender for Endpoint

> **Skill marker**: When applying this skill, begin your reply with `[skill: defender-for-endpoint]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Microsoft Defender for Endpoint (MDE, formerly Microsoft Defender ATP) configuration, operations, and read-only posture audit: Microsoft's native endpoint EDR platform, the sensor-plus-cloud stack built on the Microsoft security graph and delivered through the Defender portal at `security.microsoft.com`. It assumes the platform decision (Microsoft-native endpoint EDR rather than a third-party sensor) has already been made; for that vendor-neutral choice, and for the detection methodology and hunting strategy that survives a platform migration, route up to `endpoint-detection-response`. The depth here is the MDE-specific machinery: onboarding per operating system, the device-group and RBAC model, ASR rules and their audit-then-block tuning, KQL advanced hunting over the Device tables, AIR and the Action Center, Defender Vulnerability Management, and the read-only audit lens that keeps an estate covered and least-privilege.

## Overview

MDE is Microsoft's cloud-native EDR. A kernel-level sensor (the Sense service on Windows, a separate agent on macOS and Linux) streams process, file, registry, network, and logon telemetry to the Microsoft security graph, which correlates it with identity, email, and cloud-app signal to raise alerts, drive Automated Investigation and Response, and power Threat Analytics. The pieces an estate usually runs are:

- **Onboarding and the sensor**: the Sense service on Windows 10/11 and Windows Server 2019+, the modern unified agent on Server 2012 R2 and 2016, and separate packages on macOS, Linux, and mobile.
- **Device groups and RBAC**: groups drive policy, automation level, and role-based access all at once; roles map to Entra ID security groups.
- **Attack Surface Reduction (ASR) rules**: configurable kernel-level controls against common exploitation techniques, deployed audit-first then moved to block.
- **Advanced hunting**: the KQL interface over roughly 30 days of Device-table telemetry (Plan 2), plus scheduled custom detection rules built from the same queries.
- **AIR**: playbook-driven automated investigation and remediation with a per-device-group automation level and the Action Center review queue (Plan 2).
- **Defender Vulnerability Management (MDVM)**: exposure-based CVE prioritisation, software inventory, remediation tracking, and exception handling.
- **Network protection, web content filtering, tamper protection, live response, and Threat Analytics** round out the surface.

EDR in block mode, tamper protection, and Defender Antivirus in active (not passive) mode are the load-bearing defensive states; passive-mode or audit-mode drift is the most common gap.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (the licence tier, the management plane, the OS mix, the IdP, whether Defender Antivirus runs active or passive alongside a third-party AV) before advising. Only ask for what is not already covered.

Before configuring or auditing, establish:

1. **The licence tier.** Plan 1 (Microsoft 365 E3) or Plan 2 (E5, E5 Security). NGAV, ASR rules, device control, web content filtering, network protection, endpoint firewall management, and tamper protection are Plan 1. EDR behavioural detection, advanced hunting, AIR, Threat Analytics, Defender Vulnerability Management, live response, and the device timeline are Plan 2. Advising a Plan 2 workflow to a Plan 1 tenant is the most common category error, so pin the tier before recommending.
2. **The management plane.** Intune (cloud-managed), Group Policy (on-premises AD), Configuration Manager, or local script. This determines how onboarding, ASR policy, and exclusions are actually delivered, and whether a change is a policy edit or a per-device action.
3. **The onboarding state.** Which OS families are onboarded, whether sensors are reporting, and whether Defender Antivirus is active or passive (passive on servers or where a third-party AV is present means EDR still detects but does not block at the AV layer).
4. **The task class.** Onboarding and deployment, policy hardening (ASR, network protection, tamper protection), threat hunting and custom detection, incident investigation and AIR, vulnerability management, or a read-only posture audit. The depth lives in different references.
5. **Read-only versus change.** An audit uses read-only Graph and Advanced Hunting scope and never isolates a device, kills a process, or runs a live-response remediation. A configuration change needs a change window; ASR and policy changes roll back cleanly (revert the policy), but block-mode ASR without an audit soak can break line-of-business software.

## When to use

- Onboarding endpoints: choosing the method per OS (Windows via Intune, Group Policy, Configuration Manager, or local script; macOS; Linux; the server unified agent), verifying sensor health, and offboarding on decommission.
- Designing the device-group structure and RBAC roles so policy, automation level, and analyst access line up with the estate's tiers.
- Deploying and tuning ASR rules: the audit-first soak, reading audit telemetry in KQL, building surgical exclusions, then promoting high-confidence rules to block.
- Turning on and tuning EDR block mode, network protection, and web content filtering, and confirming tamper protection is enforced.
- Running advanced hunting over the Device tables, building hunting playbooks, and promoting a query to a scheduled custom detection rule.
- Configuring AIR automation levels per device group and running the Action Center review, including false-positive suppression and submission to Microsoft.
- Operating Defender Vulnerability Management: prioritising by exposure score, driving remediation, and handling exceptions with a review date.
- Using Threat Analytics for threat-informed defence, and live response for interactive host triage and collection.
- Diagnosing MDE performance impact and setting exclusions with the hygiene discipline.
- Running a read-only posture audit: sensors not reporting, ASR stuck in audit, EDR passive, tamper protection off, AIR at no-automation with an unreviewed Action Center, broad exclusions, and unremediated critical exploited CVEs.

## When not to use

- **Vendor-neutral EDR/XDR strategy, detection methodology, and platform selection** (IOA versus IOC, ATT&CK coverage design, which EDR to buy, cross-vendor comparison): route up to `endpoint-detection-response`. That umbrella owns the design and selection reasoning; this skill owns the MDE-specific execution once Microsoft-native is the chosen platform, exactly as a per-vendor skill routes to its umbrella.
- **Email and collaboration security** (Microsoft Defender for Office 365: Safe Links, Safe Attachments, anti-phishing, Threat Explorer): use `defender-for-office-365`. MDE correlates with MDO inside a Defender XDR incident, but it does not own the email side.
- **External attack surface discovery** (Microsoft Defender External Attack Surface Management, internet-facing asset inventory): use `defender-easm`. MDVM sees the CVEs on onboarded devices; EASM sees the estate from the outside.
- **The vendor-neutral vulnerability-management PROGRAMME** (risk scoring model, SLA design, cross-scanner reconciliation, exception governance): use `vulnerability-management`. MDE owns its own Defender Vulnerability Management operation, but the programme strategy and scoring policy live in the umbrella.
- **Zero-trust IDENTITY governance** (Entra ID, MFA rollout, conditional access, privileged access management, identity governance and administration): use `identity-access-management`. MDE consumes the identity and its risk feeds conditional access, but it does not own the identity platform.
- **SIEM/XDR correlation depth and long-term retention** (Microsoft Sentinel analytics, cross-source correlation beyond the Defender portal, SOAR playbooks): use `siem-soar-investigation`. MDE streams to the SIEM; the correlation and retention layer lives there.
- **Storing the Graph app secret, certificate, or admin credential**: use `secrets-hygiene`. Never inline a live secret in a saved API call, a runbook, or a config file.

This skill **owns Microsoft Defender for Endpoint configuration and operations**. Route vendor-neutral strategy and selection, email, external attack surface, vulnerability-programme design, identity, and SIEM correlation out per the list above; keep everything MDE here.

## Core model (condensed)

**Sensor plus cloud, one graph.** The endpoint sensor collects kernel-level telemetry and streams it over TLS to the Microsoft security graph, which does the correlation, detection, AIR, and threat analytics in the cloud. The Defender portal (`security.microsoft.com`) is the single pane for MDE alongside Defender for Office 365, Defender for Identity, and Defender for Cloud Apps; advanced hunting queries all of them from one KQL surface. This is why an endpoint alert can be joined to an email or identity event inside a single Defender XDR incident.

**Plan 1 is prevention and hardening; Plan 2 adds the EDR brain.** Plan 1 gives NGAV, ASR rules, device control, web content filtering, network protection, endpoint firewall management, and tamper protection. Plan 2 adds behavioural EDR detection, KQL advanced hunting, AIR, Threat Analytics, Defender Vulnerability Management, live response, and the device timeline. Confirm the tier first; most of the interesting operational surface is Plan 2 only.

**Onboarding is per-OS and per-management-plane.** Windows onboards via Intune, Group Policy, Configuration Manager, or a local script; the modern unified agent covers Server 2012 R2 and 2016; macOS and Linux use their own packages. Onboarding sets the org identifier and starts the Sense service; verify with the onboarding-state registry value on Windows or `mdatp health` on macOS and Linux. Passive-mode Defender Antivirus (servers, or where a third-party AV is present) still lets EDR detect but not block at the AV layer.

**Device groups drive policy, automation, and RBAC at once.** A device group determines which policy applies, which AIR automation level runs, and which roles can act on those devices. RBAC roles map to Entra ID security groups and tier from alert-read up through live-response-and-isolation. Getting the group structure right is the foundation everything else sits on.

**ASR rules go audit-first, then block, and exclusions are estate-wide.** Each rule has three modes (disabled, audit, block). The workflow is: audit every rule for two to four weeks, read the audit hits in KQL to find false-positive sources, build surgical exclusions, then promote the highest-confidence, lowest-false-positive rules (LSASS credential theft, executable content from email, Win32 calls from Office macros) to block first. ASR exclusions are not per-rule: a path excluded from ASR is excluded from every ASR rule, so exclusion hygiene is critical.

**Advanced hunting is KQL over the Device tables.** `DeviceProcessEvents`, `DeviceNetworkEvents`, `DeviceFileEvents`, `DeviceRegistryEvents`, `DeviceLogonEvents`, and `DeviceEvents` (plus `AlertInfo`, `AlertEvidence`, and the `DeviceTvm` vulnerability tables) hold roughly 30 days of telemetry. A proven hunting query becomes a scheduled custom detection rule that raises alerts and can trigger a response action. Telemetry is not detection: the sensor records far more than it alerts on, and that stored telemetry is what makes hunting and post-incident reconstruction possible.

**AIR automates investigation; the automation level gates the action.** AIR investigates an alert and proposes remediation; the per-device-group automation level decides whether it acts. Start conservative (semi, require approval) and process the Action Center daily, then move stable workstation groups to full automation while keeping critical servers on manual review. Every suppression is scoped by process-plus-parent-plus-path, carries a justification, and has a review date.

**Defender Vulnerability Management prioritises by exposure, not raw CVSS.** MDVM weighs CVSS, public-exploit availability, active exploitation in current campaigns (Threat Analytics correlation), asset criticality (device group), and internet exposure into one score. Triage runs critical-plus-exploited-plus-exposed to emergency patch, down to a scheduled cycle for low severity. Vulnerabilities that cannot be fixed now get a documented exception with a type and a review date, not silence.

**Least privilege and full coverage are the through-line.** Sensors onboarded but not reporting, ASR left in audit forever, EDR or Defender Antivirus in passive when it should be active, tamper protection off, AIR at no-automation with an Action Center nobody reads, exclusions that cover whole drives or `C:\Windows\`, and critical exploited CVEs left unpatched: these are the recurring findings. Onboard and verify, promote ASR to block, keep Antivirus active and tamper protection on, review the Action Center, exclude surgically, and drive the exposed exploited CVEs down first.

## Reference files

- `references/architecture.md`: the sensor-and-cloud EDR architecture and sensor communication, onboarding methods per OS in depth (Windows via Intune, Group Policy, Configuration Manager, and local script; macOS; Linux; mobile; the server unified agent) with health verification and offboarding, the device-group and RBAC model, EDR in block mode and passive-versus-active Defender Antivirus, network protection and web content filtering, the ASR-rules architecture including the reference GUID table and the estate-wide exclusion behaviour, the Plan 1 versus Plan 2 capability matrix, and Defender XDR correlation with Defender for Office 365, Defender for Identity, Entra ID, Intune, and Microsoft Sentinel.
- `references/operations.md`: the ASR audit-then-block tuning workflow with the pre-deployment KQL audit analysis and false-positive sources, the advanced-hunting KQL playbook library over the Device tables with alert-investigation queries, AIR automation levels and the Action Center review process and false-positive tuning, the Defender Vulnerability Management workflow with exposure-based prioritisation and remediation and exception handling, Threat Analytics operational use, tamper protection, live response, the performance-impact-and-exclusion-hygiene discipline, and the read-only audit lens with a threshold table and remediation decision trees.
- `references/api-and-automation.md`: MDE read-only automation through the Microsoft Graph Security API (alerts and incidents), the Advanced Hunting API (`runHuntingQuery` over the Device tables), and machine-actions as a read-only-by-default posture, the OAuth app-registration client-credentials flow with placeholder tokens only, the least-privilege application permissions, throttling and backoff, pagination, and the secret-store discipline for API credentials.

## Cross-references

- `endpoint-detection-response`: the vendor-neutral EDR/XDR umbrella; route detection strategy, ATT&CK coverage design, and platform selection up to it. This skill is the Microsoft-native execution once MDE is the chosen platform.
- `defender-for-office-365`: the email and collaboration security sibling; MDE correlates with MDO inside a Defender XDR incident but does not own the email side.
- `defender-easm`: external attack surface discovery from the outside in; complements the inside-out CVE view MDVM gives on onboarded devices.
- `vulnerability-management`: the vendor-neutral vulnerability-management programme design and scoring; MDE runs its own MDVM operation, but the programme strategy lives in the umbrella.
- `identity-access-management`: the Entra ID, MFA, conditional access, and IGA substrate; MDE device risk feeds conditional access, but it does not own the identity platform.
- `siem-soar-investigation`: when MDE alerts stream to Microsoft Sentinel or another SIEM for correlation, SOAR, and long-term retention.
- `secrets-hygiene`: the Graph app secret, certificate, and admin credential live in the secret store, never inline in a saved API call or runbook.

## Red flags

- Advising a Plan 2 workflow (advanced hunting, AIR, Threat Analytics, live response, Defender Vulnerability Management) to a tenant that only has Plan 1.
- Sensors that show onboarded but are not sending telemetry: no recent events, an onboarding-state value that never reached the reporting state, connectivity blocked by a proxy.
- ASR rules left in audit mode indefinitely: activity is logged but never blocked, so the control provides visibility and no protection.
- Promoting an ASR rule straight to block with no audit soak: line-of-business software (SCCM scripts, vendor Base64 PowerShell, remote-management tooling) breaks in production.
- Defender Antivirus or EDR left in passive mode when active was intended, so nothing blocks at the AV layer.
- Tamper protection off, so an attacker or a rogue admin can disable the sensor and its protections locally.
- A path-based exclusion that covers a whole drive or a system directory such as `C:\Windows\`: an attacker can drop a payload into the excluded path, and ASR exclusions apply across every rule.
- AIR at no-automated-response with an Action Center nobody reviews: investigations run but no remediation ever happens and pending actions pile up.
- Suppression rules scoped by alert title alone, with no process-plus-parent-plus-path context and no expiry: they silently mask real detections.
- Critical CVEs with a public exploit, or active exploitation in a current campaign, left unremediated on internet-facing assets while low-severity items get patched.
- Treating an MDE alert as the whole incident when the kill chain ran through email or identity telemetry the endpoint never saw; pivot to the Defender XDR incident.
- Pasting a Graph app secret, certificate password, or admin credential into a saved API URL, a runbook, or a committed file instead of the secret store.
- Running an audit with write scope (isolating a device, killing a process, running a live-response remediation) during what was meant to be a read-only review.

## Bottom line

MDE is a kernel-level sensor feeding the Microsoft security graph, with ASR rules and network protection hardening the endpoint, EDR and advanced hunting detecting what gets through, AIR remediating, and Defender Vulnerability Management driving the exposed exploited CVEs down. Pin the licence tier before you advise, onboard per OS and verify the sensor is really reporting, take ASR audit-first then block, keep Defender Antivirus active and tamper protection on, review the Action Center, exclude surgically, and prioritise vulnerabilities by exposure rather than raw CVSS. Route vendor-neutral strategy and platform selection up to `endpoint-detection-response`, email to `defender-for-office-365`, external attack surface to `defender-easm`, the vulnerability programme to `vulnerability-management`, identity to `identity-access-management`, SIEM correlation to `siem-soar-investigation`, and keep every credential in the secret store.
