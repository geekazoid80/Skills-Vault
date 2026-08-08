---
name: checkpoint-firewall-audit
description: Use for any audit, change review, or compliance pass on a Check Point Security Gateway (R80.x / R81.x; standalone, Security Management Server, or Multi-Domain Server / MDS), whether on physical or virtual gateways. Triggers include "audit this Check Point config", "review Check Point rulebase", "check SIC trust", "SIC status broken", "policy out of date on gateway", "blade activation audit", "Software Blade enabled but not licensed", "Threat Prevention profile not bound", "HTTPS Inspection not deployed", "Unified Policy layer review", "ordered layer vs inline layer", "implicit cleanup rule", "stealth rule missing", "NAT rule conflict automatic vs manual", "manual NAT before automatic", "Identity Awareness assessment", "Access Role coverage gap", "MDS domain isolation", "Multi-Domain Server audit", "Check Point compliance audit", "fwaccel template bypassing inspection", "SecureXL bypass IPS", "ClusterXL HA member drift", "VSX virtual system audit", "Check Point upgrade R80 to R81". Covers R80.x / R81.x gateways managed via SmartConsole connected to a Security Management Server or Multi-Domain Server; rulebase ordered + inline layers; Software Blade activation (Firewall, IPS, Application Control, URL Filtering, Anti-Bot, Anti-Virus, Threat Emulation, Threat Extraction, Content Awareness, HTTPS Inspection); Automatic vs Manual NAT; Identity Awareness with AD Query / Identity Collector / Captive Portal; MDS / VSX / ClusterXL considerations. Six-step audit procedure plus blade-coverage matrix, severity table, and two decision trees. Diagnose-first; read-only `mgmt_cli` / `cpstat` / `fw` queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite/checkpoint-firewall-audit (Apache-2.0); em dashes removed; British / Pacific English; references swapped to local vault skills; nine-element response contract mapping added.
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Check Point firewall security policy audit

> **Skill marker**: When applying this skill, begin your reply with `[skill: checkpoint-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Policy-audit-driven analysis of Check Point Security Gateway policies. Unlike generic firewall checklists that check for open ports and default-deny, this skill evaluates the Check Point-specific security architecture: rulebase ordered and inline layers, Software Blade activation coverage, management plane trust (SIC), and the Unified Policy model introduced in R80+.

Covers R80.x and R81.x gateways managed via SmartConsole connected to a Security Management Server (SMS) or Multi-Domain Server (MDS). Sister to `cisco-firewall-audit`, `palo-alto-firewall-audit`, and `fortigate-firewall-audit`; same six-step audit shape, different vendor surface. For multi-vendor work that crosses platforms, drive via `multi-vendor-network-ops` and load this skill alongside the others.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Check Point estate (gateway count, R-version, MDS vs SMS, blade licensing posture, change-management ticketing) before authoring an audit plan. Only ask the user for information not already covered or specific to this run.

Before authoring an audit, understand:

1. **Management architecture**
   - SMS or MDS deployment? MDS has independent per-domain policies.
   - Management Server, Log Server, SmartEvent topology?
   - Number of Security Gateways; ClusterXL HA pairs; VSX virtual systems?

2. **R-version and blade licensing**
   - R80.x or R81.x? R81.10 / R81.20 introduce new blade defaults.
   - Per-gateway blade entitlement (read `cplic print` and compare with `cpstat blades`).
   - Threat Prevention auto-update posture (manual, scheduled, or off).

3. **Audit scope and change posture**
   - Single gateway, full estate, or post-incident scoped to a rule set?
   - Read-only audit (SmartConsole API + `cpstat` + `fw stat`), or change-bearing (`mgmt_cli` writes; staged session)?
   - Maintenance window, change ticket, rollback plan (policy revision rollback via SmartConsole or `mgmt_cli show changes`)?

## When to use

- Rulebase layer review after rule additions, layer restructuring, or migration consolidation.
- Blade activation audit verifying that licensed blades are enabled on all gateways.
- Annual or quarterly compliance audit requiring per-rule justification.
- Post-incident rulebase assessment to identify how traffic was permitted.
- SmartConsole management plane validation (SIC trust, log server connectivity, Management Server health).
- Multi-Domain (MDS) domain isolation audit for MSSP or multi-tenant environments.
- NAT policy review after network re-addressing or migration.
- Pre-upgrade rulebase baseline before R80.x to R81.x migration.
- Identity awareness assessment, verifying AD integration and access role coverage.

## Do NOT use this skill for

- Day-to-day rule additions where the audit harness is overkill (the skill is for systematic review, not single-rule pushes).
- Cisco ASA / FTD audits (use `cisco-firewall-audit`).
- Palo Alto Networks audits (use `palo-alto-firewall-audit`).
- FortiGate audits (use `fortigate-firewall-audit`).
- Generic ACL shadowing / hit-count work on non-Check Point platforms (use `acl-rule-analysis`).
- Endpoint Security E1 / E80 client audits (the body covers the gateway, not the endpoint agent).

## Prerequisites

- Read-only administrator access to SmartConsole or Management Server API (`mgmt_cli` / Web API).
- SSH access to the Security Gateway for `fw`, `cpstat`, and `cpview` commands (Expert mode).
- Understanding of the management architecture (Management Server, Log Server, and Security Gateway relationships).
- Knowledge of expected blade activation per gateway (which blades should be enabled where).
- For MDS environments: domain-level access with visibility into each managed domain.
- Policy installed (audit evaluates the INSTALLED policy, not the SmartConsole staging session).
- Credentials sourced via `secrets-hygiene` patterns (vault retrieval, env vars, OS keyring); never plaintext.

## Procedure

Follow this audit flow sequentially. Each step builds on prior findings. The procedure moves from management architecture through rulebase layer analysis to blade activation, NAT, identity, and compliance verification.

### Step 1: Management architecture inventory

Map the management plane topology.

```
cpstat mg
mgmt_cli show gateways-and-servers --format json -r true
```

Record: Management Server hostname and version, Log Server(s), Security Gateway(s) with version and SIC status. In MDS environments, list all domains and their assigned gateways.

Verify SIC trust between Management Server and each gateway:

```
cpstat sic
fw stat
```

SIC (Secure Internal Communication) trust must be established for policy installation and log forwarding. A gateway with SIC status other than "Trust established" cannot receive policy updates, so any running policy is stale; flag as Critical.

For Multi-Domain deployments, verify domain isolation:

```
mdsstat
```

Each domain should be an independent management container. Cross-domain policy leakage indicates an architecture misconfiguration.

Check Management Server disk space and health; a full log partition prevents logging:

```
cpstat os -f disk
cpview
```

### Step 2: Rulebase layer analysis

R80+ uses a Unified Policy model with ordered layers. Each layer is an independent rulebase evaluated sequentially.

```
mgmt_cli show access-rulebase name "Network" --format json -r true
```

Retrieve each access layer and evaluate:

- **Layer structure.** Ordered layers evaluate top-to-bottom. Each layer must independently reach a decision (Accept / Drop / Reject) for the traffic, or the traffic is implicitly dropped. An inline layer is embedded within a rule in a parent layer; it sub-divides that rule's match.
- **Rule ordering within layers.** First-match evaluation. Rules within a layer are evaluated top-down; the first matching rule is applied.
- **Implicit rules.** Check Point inserts implicit rules controlled by Global Properties. Key implicit rules include:
  - Accept control connections (Management, logging).
  - Accept outgoing from gateway.
  - Cleanup rule (default drop at bottom).
  - Stealth rule (protect the gateway itself; must be explicitly added).
- **Disabled rules.** Rules with `enabled: false` consume rulebase space but do not evaluate. Flag for cleanup.
- **Rule hit counts.** Identify rules with zero hits over 90+ days as cleanup candidates. Hit counts are available via SmartConsole or API.
- **Overly permissive rules.** Rules with Source=Any, Destination=Any, Service=Any, Action=Accept are Critical; they permit all traffic within the layer.

```
mgmt_cli show access-rulebase name "Network" details-level full --format json -r true
```

Use `details-level full` to retrieve source, destination, service, action, track, and profile bindings for each rule. For protocol semantics behind a flagged rule (shadowing, redundant rules, hit-count staleness, overly broad rule classification), pair with `acl-rule-analysis`.

### Step 3: Blade activation audit

Check Point Software Blades provide security functions. Each blade must be licensed and enabled per gateway.

```
cpstat blades
cpstat fw
```

Verify activation status for each blade on every gateway:

| Blade | Function | Expected on |
|---|---|---|
| Firewall | Stateful packet inspection | All gateways. |
| IPS | Intrusion prevention signatures | Internet-facing gateways. |
| Application Control | Application identification and enforcement | Internet-facing gateways. |
| URL Filtering | URL categorisation and blocking | Gateways with user web traffic. |
| Anti-Bot | Bot C2 communication detection | All gateways. |
| Anti-Virus | File-based malware scanning | All gateways. |
| Threat Emulation | Sandbox analysis for unknown files | Internet-facing gateways. |
| Threat Extraction | Content disarm and reconstruction | Email / download gateways. |
| Content Awareness | Data visibility and DLP | Gateways handling sensitive data. |
| HTTPS Inspection | TLS decryption for content inspection | Internet-facing gateways. |

Compare licensed blades (contract entitlement) against enabled blades. Licensed but disabled blades represent undeployed security capability. Enabled but unlicensed blades will stop functioning on licence expiry.

```
cpstat licenseStat
cplic print
```

Check Threat Prevention profiles assigned to rules; blades are only effective when both enabled on the gateway AND referenced in policy rules via a Threat Prevention profile.

### Step 4: NAT policy review

Check Point supports two NAT methods: Automatic NAT (per-object) and Manual NAT (explicit rulebase).

```
mgmt_cli show nat-rulebase --format json -r true
```

Evaluate NAT policy:

- **Automatic NAT rules.** Defined on network objects (host, network, address range). Check Point generates NAT rules automatically based on object NAT settings. Review each object's NAT configuration.
- **Manual NAT rules.** Explicit rules in the NAT rulebase, evaluated top-down BEFORE automatic rules. Review rule ordering for conflicts.
- **NAT method.** Hide NAT (many-to-one PAT) vs Static NAT (one-to-one). Static NAT on internal servers should have corresponding security rules restricting access to required services only.
- **NAT rule ordering.** Manual rules evaluate before Automatic rules. Within each section, rules evaluate top-down. Conflicting rules in the manual section override automatic NAT.

Verify that NAT does not expose internal addressing or create unintended access paths. Cross-reference static NAT entries with security policy rules.

### Step 5: Identity Awareness and Access Role assessment

If the Identity Awareness blade is enabled, evaluate the identity integration.

```
pdp status stat
mgmt_cli show access-roles --format json -r true
```

Check:

- **Identity sources.** Active Directory integration (AD Query or Identity Collector), RADIUS accounting, Terminal Servers agent, Captive Portal, Remote Access VPN identity. Verify connectivity to each source.
- **Access roles in security rules.** Access roles combine user / group identity with machine identity. Rules referencing access roles require functioning identity sources; if AD connectivity fails, identity-based rules cannot match, and traffic falls to non-identity rules.
- **Identity agent deployment.** Check whether Identity Agent or Captive Portal covers all user segments. Gaps in identity collection mean those users match rules as "unknown user".
- **Identity sharing.** In MDS or distributed environments, verify identity information is shared between gateways that need it.

### Step 6: Log and compliance verification

Verify log infrastructure and compliance monitoring.

```
cpstat logging
fw log -t
```

Check:

- **Log Server connectivity.** Verify each gateway can forward logs to the Log Server. Check for log gaps that indicate connectivity interruptions.
- **Log completeness.** Rules with Track=None produce no log entries. Identify security-relevant rules without logging; at minimum, all Drop and Reject rules should log.
- **SmartEvent correlation.** If SmartEvent is deployed, verify the correlation policy is active and generating events from security logs.
- **Compliance blade.** If enabled, verify compliance checks are running and review the latest compliance report for failed checks.

```
cpstat antimalware
cpstat appi
```

Verify Threat Prevention signature databases are current:

| Database | Maximum age | Check |
|---|---|---|
| IPS signatures | 7 days | `cpstat ips` |
| Application Control DB | 7 days | `cpstat appi` |
| Anti-Bot signatures | 24 hours | `cpstat antimalware` |
| Anti-Virus signatures | 24 hours | `cpstat antimalware` |
| URL Filtering DB | 7 days | `cpstat urlf` |

## Threshold tables

### Policy rule severity classification

| Finding | Severity | Rationale |
|---|---|---|
| Source=Any, Destination=Any, Service=Any, Action=Accept | Critical | Fully open rule; permits all traffic within the layer. |
| Gateway SIC trust not established | Critical | Gateway cannot receive policy updates; running stale policy. |
| Licensed blades not enabled on internet-facing gateway | High | Purchased security capability not deployed. |
| Rule with Action=Accept and no Threat Prevention profile | High | Traffic passes without IPS, Anti-Bot, or AV inspection. |
| HTTPS Inspection not enabled on internet-bound traffic | High | Encrypted traffic bypasses content inspection blades. |
| Threat Prevention signatures older than 7 days | High | Detection gap for recently discovered threats. |
| Missing Stealth rule (no rule protecting gateway itself) | High | Gateway management plane exposed to data-plane traffic. |
| Manual NAT rule conflicts with Automatic NAT | Medium | Unexpected NAT behaviour; traffic may not translate as intended. |
| Rules with zero hit count older than 90 days | Medium | Unused rules; cleanup candidates. |
| Disabled rules in production layer | Medium | Audit confusion; stale configuration. |
| Track=None on Drop / Reject rule | Medium | Security-relevant denied traffic not logged. |
| Identity Awareness source connectivity failure | Medium | Identity-based rules unable to match users; fallback behaviour kicks in silently. |
| Log Server connectivity intermittent | Medium | Log gaps reduce incident investigation capability. |
| Implicit cleanup rule handling all denied traffic | Low | Expected behaviour, but verify logging is enabled. |

### Blade activation maturity

| Coverage | Maturity | Guidance |
|---|---|---|
| All licensed blades enabled + profiles in policy | Mature | Maintain; review profile settings quarterly. |
| Blades enabled but profiles not referenced in rules | Developing | Bind Threat Prevention profiles to all Accept rules. |
| Licensed blades not enabled | Immature | Enable blades and create Threat Prevention profiles. |

## Decision trees

### Overly permissive rule remediation

```
Rule has Source=Any, Destination=Any, Service=Any
|-- Action = Accept?
|   |-- Yes -> CRITICAL: fully open rule
|   |   |-- Is this a temporary migration rule?
|   |   |   |-- Yes -> set expiration; add to migration tracker
|   |   |   `-- No  -> immediate remediation required
|   |   `-- Identify actual traffic via SmartLog:
|   |       filter by rule number -> analyse source / dest / service
|   |       -> replace with specific objects and services
|   `-- No (Drop / Reject) -> this is the cleanup rule; verify Track=Log
|
|-- Threat Prevention profile bound?
|   |-- No -> bind profile BEFORE narrowing rule scope
|   |   `-- ensures threat visibility during migration
|   `-- Yes -> proceed with scope reduction
|
`-- Rule in ordered layer or inline layer?
    |-- Ordered layer -> affects all traffic in that layer
    `-- Inline layer  -> scoped to parent rule match
        `-- check parent rule scope to assess true exposure
```

### Blade gap remediation

```
Gateway missing expected blades
|-- Blade licensed?
|   |-- No  -> procurement required; document risk until enabled
|   `-- Yes -> enable blade in SmartConsole gateway object
|       |-- IPS                 -> assign IPS profile; set to Prevent mode
|       |-- Application Control -> create / assign App Control policy
|       |-- Anti-Bot            -> assign profile; enable in Threat Prevention
|       |-- Anti-Virus          -> assign profile; enable in Threat Prevention
|       |-- Threat Emulation    -> assign profile; select emulation environment
|       |-- HTTPS Inspection    -> configure CA cert + inspection policy
|       `-- URL Filtering       -> assign categorisation profile
|
|-- Performance concern?
|   |-- SecureXL acceleration enabled? -> verify blade compatibility
|   `-- CoreXL CPU allocation          -> check SNDs and FW workers balance
|       cpstat os -f multi_cpu
|
`-- After enabling -> install policy and verify blade active:
    cpstat blades -f blade_name
```

## Report template (nine-element response contract)

This template maps onto the `multi-vendor-network-ops` nine-element response contract. Use for production-impacting audit findings or change recommendations.

```
CHECK POINT SECURITY POLICY AUDIT REPORT
=========================================
Management Server: [hostname] [version]
Gateway(s): [hostname(s)] [version(s)]
Domain: [domain name (MDS) or N/A (SMS)]
Policy Name: [installed policy name]
Audit Date: [timestamp_utc per utc-timestamps]
Performed By: [operator or agent]

1. CONTEXT
   - Management architecture: SMS or MDS; gateway count; HA / VSX posture.
   - Audit scope: full estate, single gateway, post-incident, pre-upgrade.

2. INTENT
   - Read-only audit, or audit-then-remediate.
   - Findings deliverable, change-bearing follow-up, or both.

3. EVIDENCE GATHERED
   - mgmt_cli show output, cpstat output, SmartLog filters, hit counts.
   - SIC status per gateway; blade activation status; Threat Prevention age.

4. FINDINGS
   - Per finding: [severity] [category] [layer name] [rule number] [issue] [current config] [recommendation].
   - Cross-reference each Critical / High to the severity table above.

5. RECOMMENDATIONS
   - Prioritised action list by severity.
   - Each action: owner, change ticket, target window.

6. RISK ASSESSMENT
   - Pre-remediation risk if action deferred.
   - Post-remediation risk if action implemented (rollback, blast radius).

7. ROLLBACK PLAN
   - SmartConsole revision rollback (Sessions or Revisions tab).
   - mgmt_cli show changes / publish discard pattern for staged sessions.
   - Per-blade disable steps if a blade change causes traffic impact.

8. VERIFICATION
   - Post-change re-run of relevant Step 1 to Step 6 commands.
   - Confirm SIC trust, blade activation, log forwarding, signature currency.
   - Per `completion-gate` Layer 3: no "applied" claim without fresh post-check evidence in this turn.

9. NEXT REVIEW
   - CRITICAL findings: 30 days.
   - HIGH findings: 90 days.
   - Clean audit: 180 days.
```

## Troubleshooting

### Large rulebases spanning multiple layers

Auditing rulebases with hundreds of rules across multiple ordered layers is impractical via SmartConsole alone. Use the Management API to export all layers programmatically:

```
mgmt_cli show access-rulebase name "<layer>" details-level full --format json -r true
```

Iterate over all layers and merge into a single dataset for automated shadow detection, profile gap analysis, and hit count review. For the shadow-detection methodology itself (overlap, redundant, fully-shadowed rule classification), pair with `acl-rule-analysis`.

### Multi-Domain Server (MDS) audits

In MDS deployments, each domain is an isolated management container. The auditor must connect to each domain separately (or use the MDS-level API with domain context). Policy in one domain does not affect another, but verify that cross-domain traffic paths have consistent policies on both domain gateways.

### Policy installation failures

If a gateway shows "Policy out of date" in SmartConsole, the running policy may not match the current rulebase. Use `fw stat` on the gateway to see the installed policy name and timestamp. Compare with SmartConsole to identify the delta. Audit findings should be based on the INSTALLED policy, not the pending session.

### SecureXL and CoreXL impact on inspection

SecureXL accelerates traffic by bypassing full inspection for established sessions. Some blades (especially IPS and Threat Emulation) require traffic to pass through the Firewall kernel (Medium Path or Firewall Path), not the accelerated path. Verify SecureXL template status:

```
fwaccel stat
fwaccel templates -S
```

Templates that match security-sensitive traffic and bypass blade inspection are a finding.

### ClusterXL and VSX considerations

In ClusterXL (HA) deployments, verify both members run the same policy version and software release. In VSX (Virtual System Extension) deployments, each virtual system has independent policy; audit each VS separately. Use `vsx stat -v` to list virtual systems.

## Cross-references

- `multi-vendor-network-ops` umbrella; this skill is one of the four firewall specialists. Apply the nine-element response contract to every state-changing change.
- `cisco-firewall-audit`, `palo-alto-firewall-audit`, `fortigate-firewall-audit` sister skills; same six-step audit shape, different vendor surface. In a multi-vendor estate, load alongside whichever firewalls are present.
- `acl-rule-analysis` for the rule-shadowing, redundant-rule, hit-count-staleness, and overly-broad-rule classification methodology that sits behind any rulebase finding here.
- `bgp-analysis`, `igp-routing-analysis` when an audit surfaces dynamic-routing-over-VPN issues; the protocol semantics live there.
- `vpn-tunnel-troubleshooting` when an audit surfaces Check Point IPsec / Remote Access VPN issues; the IKE FSM and crypto-suite triage lives there.
- `secrets-hygiene` Management Server API credentials and gateway Expert-mode passwords MUST come from vault / env / keyring, never plaintext; SmartLog exports MUST redact sensitive fields before sharing.
- `humanise-comms` audit reports and findings emails go to humans; no em dashes, British / Pacific English, professional-direct tone.
- `completion-gate` Layer 3 post-change verification is the iron law; no "remediated" claim without fresh re-run of the relevant Step 1 to Step 6 commands in this turn.
- `bash-defensive` any wrapper shell scripts (SmartConsole API loop, gateway-side audit harness, log archive uploader) follow strict-mode + traps + ShellCheck; never inject shell metacharacters from API output.
- `oncall-runbooks` post-incident Check Point audits feed the postmortem timeline; attach the audit report archive URL in the incident review.
- `systematic-debugging` if an audit finding diverges from documented expected behaviour (blade enabled in SmartConsole but `cpstat blades` shows disabled; SIC reports trust but policy install fails), follow the four-phase root-cause flow before applying any fix.
- `plan-time-tooling` state-changing Check Point work (policy install, blade enable, NAT rule add) fires the `engineering:deploy-checklist` mandatory trigger; ServiceNow / change-window verification is part of plan-time tooling.

## Red flags

- About to publish a SmartConsole session without running `mgmt_cli show changes` to review the staged diff.
- About to install policy on a gateway with SIC trust other than "Trust established".
- About to enable a blade on a gateway that does not have the licence (silent failure on licence expiry).
- About to add a rule with Source=Any, Destination=Any, Service=Any, Action=Accept without an explicit Threat Prevention profile bound AND without a documented temporary-migration expiration.
- About to claim a Check Point audit done without fresh `cpstat blades`, `cpstat sic`, and `fw stat` evidence in this turn.
- About to share a SmartLog export in a customer-facing channel without redacting source IPs, internal hostnames, and user identities.
- About to call rollback "manual" without the SmartConsole revision rollback ID or `mgmt_cli show changes` discard plan pre-computed.
- About to declare an MDS-domain audit complete without confirming domain-isolation (cross-domain leakage is the most missed finding).
- About to ignore a SecureXL template that bypasses IPS or Threat Emulation on security-sensitive traffic.
- About to declare a ClusterXL HA pair audited based on the active member alone (the standby may be running a different policy or software release).
- About to push policy without `completion-gate` Layer 3 post-check evidence (re-run `fw stat` and `cpstat blades` after install).

## Bottom line

Six-step audit: management architecture; rulebase layer analysis; blade activation; NAT policy; Identity Awareness; log + compliance. SIC trust is the prerequisite for everything else. Blades only count when licensed AND enabled AND bound to Threat Prevention profiles in rules. Manual NAT evaluates before Automatic NAT. MDS domains are isolated containers; audit each separately. SecureXL templates can silently bypass blade inspection on security-sensitive traffic. ClusterXL HA and VSX virtual systems each need independent audit. Findings reports follow the nine-element response contract per `multi-vendor-network-ops`; no claim of "remediated" without `completion-gate` Layer 3 post-check evidence.
