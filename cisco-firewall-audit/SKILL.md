---
name: cisco-firewall-audit
description: Use for any audit, change review, or compliance pass on a Cisco ASA or Firepower Threat Defense (FTD) firewall, whether managed by ASDM, FMC, or FDM. Triggers include "audit this ASA config", "review FTD access policy", "ACL hit count is zero", "ACP rule shadowing", "Snort IPS coverage", "permit any any", "Modular Policy Framework gap", "missing Intrusion Policy", "Trust rule audit", "default action is Allow", "NAT section conflict", "static NAT exposure", "FMC pushed policy review", "ASA-to-FTD migration baseline", "multi-context ASA audit", "VPN crypto strength on ASA", "Snort passive vs inline", "File / Malware policy binding", "logging severity below informational", "failover not monitoring", "site-to-site VPN review", "AnyConnect remote access posture", "compliance audit on Cisco firewall". Covers ASA 9.x+, FTD 6.x+ / 7.x+, FMC and FDM management surfaces, multi-context ASA, and the dual evaluation model (ASA security-level + interface ACL vs FTD ACP + Snort). Six-step audit procedure with severity table and two decision trees. Diagnose-first; read-only `show` / FMC API queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite/cisco-firewall-audit (Apache-2.0).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Cisco ASA / FTD firewall audit

Policy-audit-driven analysis covering both Cisco ASA (classic) and Firepower Threat Defense (FTD). Unlike generic firewall checklists that just look for open ports and default-deny, this skill evaluates the platform-specific security architecture: ASA security levels with interface-bound ACLs and Modular Policy Framework, or FTD Access Control Policy (ACP) with Snort IPS integration and Firepower Management Center (FMC) orchestration.

Where platforms diverge, sections use **[ASA]** and **[FTD]** labels. Shared concepts apply to both platforms unlabelled. Covers ASA 9.x+ and FTD 6.x+ / 7.x+ managed by FMC or FDM.

> **Skill marker**: When applying this skill, begin your reply with `[skill: cisco-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Cisco firewall estate (ASA versus FTD, FMC-managed versus FDM, multi-context, HA pairs, software versions) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Platform and architecture**
   - ASA (classic) or FTD? FMC-managed, FDM, or CDO?
   - Single-context or multi-context ASA?
   - HA / failover pair, active-active cluster, or standalone?
   - Software version (ASA 9.x branch; FTD 6.x / 7.x branch)?

2. **Audit driver**
   - Compliance pass, post-incident review, migration prep (ASA to FTD), or rule cleanup?
   - Specific concerns (overly permissive rule, IPS tuning, NAT policy, VPN posture)?

3. **Evidence and access**
   - Read-only access (ASDM, FMC UI, FMC API, Expert shell, exported config)?
   - Hit-count or syslog telemetry available?
   - Pending deploy queued in FMC that affects audit scope?

---

## Scope and when to use

- ACL or ACP review after rule changes or migration from ASA to FTD.
- Annual or quarterly compliance audit requiring per-rule justification.
- Post-incident rule assessment to identify how traffic was permitted (or why it was blocked).
- **[ASA]** Security-level and interface-ACL gap analysis; Modular Policy Framework (MPF) inspection-map verification.
- **[FTD]** ACP rule ordering and IPS coverage review; Snort tuning (false-positive vs detection-gap balance).
- NAT policy validation after re-addressing or migration.
- Site-to-site or remote-access VPN configuration security review.
- Failover / HA posture verification.
- Pre-migration baseline before ASA-to-FTD conversion.

When the work is broader than Cisco (mixed estate with PAN-OS, FortiGate, CheckPoint, and similar), use `acl-rule-analysis` for the cross-vendor methodology pass, then this skill for the Cisco-specific deep-dive. For platform-managed PAN-OS work see `palo-alto-firewall-audit`; for FortiGate see `fortigate-firewall-audit`; for VPN-only deep-dives see `vpn-tunnel-troubleshooting`.

## Prerequisites

- **[ASA]** Privilege level 5+ (read-only `show`) or ASDM read-only access.
- **[FTD]** Read-only analyst access to FMC web UI or FMC REST API; Expert shell access for Snort-level diagnostics.
- Topology knowledge: which interfaces exist, their security levels (**[ASA]**) or zone membership (**[FTD]**), and segment assignments.
- Knowledge of expected access policies per interface pair or zone.
- For multi-context ASA: access to system context plus each security context.
- **[FTD]** Knowledge of expected IPS baseline (Snort ruleset, network-analysis policy, file-policy posture).
- Evaluating the running configuration, not pending changes (or note explicitly when a deploy is queued in FMC).

## Procedure

Follow the six steps in order; each builds on prior findings. The flow moves from platform identification through access policy, NAT, inspection / IPS, VPN, and logging.

### Step 1: platform identification and architecture inventory

```
show version
```

Identify ASA vs FTD, software version, hardware platform (ASA 5500-X, Firepower 1000 / 2100 / 4100 / 9300, virtual), and licensed features.

**[ASA]** Inventory interfaces, security levels, and context mode:

```
show interface ip brief
show nameif
show mode
```

Security levels (0 to 100) determine implicit traffic flow: higher to lower is permitted by default unless ACLs override; lower to higher is denied by default. Record each interface name, security level, and IP. For multi-context ASA, run `show context` then `changeto context <name>` and repeat.

**[FTD]** Identify management model and registered devices:

```
show managers
```

FTD managed by FMC: policy is pushed from FMC, audit via FMC UI / API. FTD managed by FDM (local): policy configured on-device, audit via FDM web UI or REST API.

Check failover / HA status on both platforms:

```
show failover
show failover state
```

Record active / standby status, failover interface, and last failover time.

### Step 2: access policy analysis

**[ASA]** ACL-based access control:

```
show access-list
show running-config access-list
show running-config access-group
```

ASA uses interface-bound ACLs. Each ACL is applied inbound or outbound on an interface via `access-group`. Evaluate:

- **ACL evaluation order:** top-down within each ACL. First matching ACE is applied; implicit deny at the bottom.
- **Global ACL:** if configured, applies to all interfaces. Interface ACLs evaluate before the global ACL.
- **Overly permissive ACEs:** `permit ip any any` or `permit tcp any any` are Critical findings.
- **Unused ACEs:** zero hit count over 90+ days is a cleanup candidate (see `acl-rule-analysis` for the staleness bands).
- **EtherType ACLs:** used on transparent interfaces; review for overly broad EtherType permits.

**[FTD]** Access Control Policy (ACP) via FMC UI or REST API. Evaluate the chain top-down:

- **Prefilter policy:** hardware-level rules that bypass Snort. Overly broad prefilter Trust rules skip all inspection.
- **SSL policy:** determines which TLS flows are decrypted for inspection.
- **Access Control rules:** top-down. Actions: Allow (with or without IPS), Trust (bypass Snort), Block, Monitor.
  - Allow + no Intrusion Policy = traffic permitted without IPS inspection.
  - Trust = bypasses all further inspection (IPS, file, malware). Use only for verified trusted flows (backup paths, intra-fabric).
- **Default action:** applied when no rule matches. Should be Block with logging, not Allow.
- **Intrusion Policy binding:** each Allow rule can bind an Intrusion Policy (Snort ruleset). Rules without one pass uninspected.

```
system support diagnostic-cli
show access-control-config
```

### Step 3: NAT policy audit

**[ASA]** NAT order of operations:

```
show nat
show nat detail
show running-config nat
show xlate
```

ASA NAT evaluates in three sections:

- **Section 1 (Manual NAT / Twice NAT):** explicit rules, top-down. Highest priority. Used for fine-grained control.
- **Section 2 (Auto NAT / Object NAT):** per-object NAT definitions. Evaluated after Section 1. Static rules first, then dynamic.
- **Section 3 (Manual NAT after-auto):** low-priority manual rules evaluated after auto NAT. Used for catch-all translations.

A Section 1 rule that matches the same traffic as a Section 2 object NAT always wins. Verify that static NAT entries for published servers have corresponding ACL entries restricting access.

**[FTD]** NAT in FMC follows the same three-section model. Verify Manual NAT precedence over auto NAT, that NAT rules align with ACP source / destination references, and that no unnecessary identity NAT rules are consuming processing.

Cross-reference NAT entries with access policy on both platforms; static NAT that exposes internal servers MUST have restrictive access rules.

### Step 4: inspection and IPS assessment

**[ASA]** Modular Policy Framework (MPF):

```
show running-config class-map
show running-config policy-map
show running-config service-policy
show service-policy
```

ASA inspection uses MPF: class-maps define traffic; policy-maps bind inspections; service-policies apply to interfaces. Evaluate:

- **Default inspection:** ASA enables inspection for common protocols (HTTP, DNS, FTP) via `global_policy`. Verify `service-policy global_policy global` is applied.
- **Custom inspections:** verify they hit the correct interfaces.
- **Missing inspections:** traffic not matching any class-map gets only ACL enforcement, no application-layer inspection.
- **Connection limits:** review for overly permissive or missing connection limits on internet-facing interfaces.

**[FTD]** Snort IPS plus File / Malware policies:

- **Intrusion Policy:** check that internet-facing Allow rules bind one. Base policies in order of strictness: Connectivity Over Security (loosest), Balanced Security and Connectivity (production minimum), Security Over Connectivity, Maximum Detection.
- **Network Analysis Policy (NAP):** controls protocol decoders and preprocessor configuration. Misconfigured NAP causes detection gaps.
- **File and Malware Policy:** bind on rules permitting file-carrying protocols (HTTP, SMTP, FTP, SMB).
- **Snort deployment mode:** inline (can block) vs passive (alert only). Production = inline.

```
system support diagnostic-cli
show snort statistics
```

### Step 5: VPN and remote-access audit

```
show crypto ipsec sa
show crypto ikev2 sa
show vpn-sessiondb
```

Check:

- **Site-to-site tunnels:** IKE version (IKEv2 preferred), encryption (AES-256-GCM recommended; DES / 3DES are findings), DH groups (group 14+; groups 1 / 2 / 5 are weak), PFS settings.
- **Crypto maps / tunnel groups:** **[ASA]** review crypto map entries and tunnel group definitions; **[FTD]** review site-to-site VPN topology in FMC.
- **AnyConnect / remote access VPN:** authentication method (certificate + MFA preferred), split tunneling (full tunnel preferred for security; document the choice if split is used), connection profiles, group policies, client certificate validation, banner and session timeout.

```
show running-config tunnel-group
show running-config group-policy
```

- **IKE / IPsec SA lifetimes:** very long lifetimes (>24 h IKE, >8 h IPsec) increase exposure if keys are compromised.

For deeper IPsec / DMVPN / ADVPN diagnosis see `vpn-tunnel-troubleshooting`.

### Step 6: logging and monitoring

**[ASA]** Syslog configuration:

```
show logging
show running-config logging
```

- **Syslog severity:** at least informational (level 6) for security-relevant events. Level 5 misses connection-teardown events; level 7 generates excessive volume.
- **Syslog destinations:** verify reachability. Encrypted syslog (TCP / TLS) for log integrity.
- **SNMP:** if configured, verify community strings are not defaults; SNMPv3 for auth + encryption.

**[FTD]** Firepower event logging:

- **Connection events:** in FMC, verify connection logging is enabled on ACP rules. "Log at End of Connection" is standard.
- **Intrusion events:** automatically logged by Snort when rules trigger. Verify forwarding to SIEM.
- **eStreamer:** Firepower event-streaming API for SIEM integration; verify client connectivity if in use.

Logging must cover denied connections, permitted connections (audit trail), VPN events, failover events, and administrative access.

## Severity classification

| Finding | Severity | Rationale |
|---|---|---|
| **[ASA]** `permit ip any any` in interface ACL | Critical | Permits all IP traffic; no access restriction. |
| **[FTD]** ACP default action set to Allow | Critical | All unmatched traffic permitted without inspection. |
| **[FTD]** Prefilter Trust rule with broad match (any / any) | Critical | Traffic bypasses all Snort inspection. |
| **[ASA]** No global service-policy applied | High | No application-layer inspection on any traffic. |
| **[FTD]** Allow rule without Intrusion Policy binding | High | Traffic permitted without IPS inspection. |
| **[FTD]** SSL policy not decrypting internet-bound traffic | High | Snort sees only metadata on encrypted flows. |
| VPN using DES / 3DES or DH group 1 / 2 / 5 | High | Weak cryptographic algorithms. |
| Static NAT with no restricting ACL | High | Published server accessible on all ports. |
| Failover configured but standby not monitoring | High | HA not providing redundancy. |
| **[FTD]** Snort in passive mode (production) | High | IPS detects but cannot block. |
| **[ASA]** ACE with hit count 0 for >90 days | Medium | Unused rule; cleanup candidate (cross-check with `acl-rule-analysis`). |
| **[FTD]** File / Malware policy not bound on file-carrying rules | Medium | Malware-detection gap on HTTP / SMTP / FTP / SMB. |
| VPN split tunneling enabled without explicit policy | Medium | Remote-user traffic may bypass corporate controls. |
| Logging severity below informational (level 6) | Medium | Security events not captured. |
| **[ASA]** Equal security levels with same-security-traffic disabled | Low | Traffic between equal interfaces blocked (may be intentional). |

### IPS / inspection maturity

| Coverage | Maturity | Guidance |
|---|---|---|
| **[FTD]** All Allow rules have Intrusion + File / Malware policies | Mature | Maintain; tune Snort rules quarterly. |
| **[FTD]** Most Allow rules have Intrusion Policy, some gaps | Developing | Bind Intrusion Policy to remaining Allow rules. |
| **[ASA]** Global inspection policy active, custom maps defined | Developing | Evaluate FTD migration for deeper inspection. |
| **[ASA]** Default global_policy only, no custom inspections | Immature | Add custom inspection maps for critical protocols. |

## Decision trees

### Access policy gap remediation

```
Overly permissive access rule identified
├── Platform?
│   ├── [ASA] permit ip any any in ACL
│   │   ├── Is ACL applied to an interface (access-group)?
│   │   │   ├── Yes -> CRITICAL: all traffic permitted on that interface
│   │   │   │   └── Analyse connections: show conn detail [interface]
│   │   │   │       -> Replace with specific permit entries (port + source scope)
│   │   │   └── No -> ACL exists but not applied; verify intent before deletion
│   │   └── Global ACL?
│   │       └── Applies to all interfaces -> assess scope of exposure
│   │
│   └── [FTD] Allow rule without Intrusion Policy
│       ├── What traffic does the rule match?
│       │   ├── Internet-bound -> bind Intrusion Policy (Balanced minimum)
│       │   │   └── Also bind File / Malware policy
│       │   ├── Inter-zone -> bind Intrusion Policy
│       │   └── Trusted internal -> evaluate risk; bind at minimum
│       │
│       └── Is it a Trust rule?
│           ├── Yes -> bypasses ALL inspection
│           │   └── Verify traffic is truly trusted (e.g. backup, intra-fabric)
│           │       └── Consider changing to Allow + Intrusion Policy
│           └── No (Allow) -> add Intrusion Policy binding
│
└── Action = Trust vs Allow?
    ├── Trust -> zero inspection; use sparingly
    └── Allow -> inspection possible; bind policies
```

### NAT conflict resolution

```
NAT rule conflict suspected
├── [ASA] Which section is each rule in?
│   ├── Section 1 (Manual) vs Section 2 (Auto) -> Section 1 always wins
│   ├── Both in Section 2 -> Static evaluates before dynamic; check overlap
│   └── Section 1 vs Section 3 -> Section 1 wins; Section 3 may be unreachable
│
├── [FTD] Same three-section model via FMC
│   └── Review NAT policy in FMC -> identify ordering conflicts
│
└── Verify with packet tracer (read-only on both platforms):
    packet-tracer input <iface> tcp <src> <sport> <dst> <dport>
    -> Shows ACL/ACP, NAT, inspection, routing, egress phases.
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
CISCO ASA / FTD SECURITY POLICY AUDIT REPORT
===============================================
Device: [hostname] | Platform: [ASA model / FTD model] | Software: [version]
Management: [ASDM / FMC hostname / FDM]
Mode: [routed / transparent] [single / multi-context]
Failover: [active-standby / active-active / standalone]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[ASA: security levels stable; FTD: FMC-pushed policy is current; topology unchanged.]

INTERFACE / ZONE SUMMARY:
[ASA] Interfaces: [n] (security levels: [list]) | Multi-context: [yes/no]
[FTD] Zones: [n] ([list]) | Managed by: [FMC / FDM]

ACCESS POLICY:
[ASA] ACLs: [n] | ACEs: [n] | hit-count 0 (>90d): [n] | Global service-policy: [yes/no]
[FTD] ACP rules: [n] (Allow:[n] Block:[n] Trust:[n])
      IPS-bound: [n]/[allow] | File / Malware-bound: [n]/[allow] | Default: [Block / Allow]

NAT: Section 1: [n] | Section 2: [n] | Section 3: [n] | Static: [n] | Conflicts: [n / none]

INSPECTION / IPS:
[ASA] Service-policy: [applied / missing] | Inspected: [protocols]
[FTD] IPS policy: [name] | Snort: [inline / passive] | SSL decrypt: [n rules / none]

VPN: Tunnels: [n] | IKE: [v1 / v2] | Crypto: [algs] | AnyConnect: [yes / no] | Split: [yes / no]

EVIDENCE: [show command output, FMC API extracts attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Platform: [ASA / FTD] | Rule: [id] | Interface / Zone: [name]
Issue: [problem] -> Recommendation: [remediation]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list]
ROLLBACK: [snapshot ref or revert step per change]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **ASA-to-FTD migration drift:** the Cisco Firepower Migration Tool produces a baseline policy but ordering is often suboptimal. Audit the migrated ACP for shadowing and Trust-rule inflation. Crypto maps do not migrate directly.
- **Multi-context audits skipped:** each security context is an independent firewall. Audit each via `changeto context <name>`. `show resource allocation` for per-context limits.
- **Large ACLs (>1000 ACEs):** export `show running-config access-list` and parse programmatically. Prioritise by hit count; high-hit ACEs carry the most traffic. Zero-hit ACEs over 90 days are removal candidates (see `acl-rule-analysis` staleness bands).
- **FTD diagnostic CLI mistaken for source of truth:** the canonical policy source is FMC. `system support diagnostic-cli` shows the deployed result, not pending changes.
- **Packet-tracer used as a planning tool:** packet-tracer is read-only and shows phase-by-phase processing; useful for verification, not for changing policy. Pair with the `completion-gate` Layer 3 post-check loop.
- **VPN review skipped for site-to-site only:** AnyConnect and clientless SSL are common; review group-policies and split-tunnel posture even if no recent changes.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the Cisco-firewall specialist. Apply the nine-element response contract to any state-changing recommendation produced here.
- `acl-rule-analysis` -- vendor-agnostic ACL methodology, hit-count staleness bands, severity-pattern catalogue. Run this skill first for cross-vendor estate work, then this skill for the Cisco-specific deep-dive.
- `palo-alto-firewall-audit`, `fortigate-firewall-audit` -- sibling Stage 3 specialists. Sequence rule reviews vendor-by-vendor when auditing a mixed estate.
- `vpn-tunnel-troubleshooting` -- IPsec / DMVPN / ADVPN deep-dive; covers IKE state machines, crypto suites, vendor templates beyond what this skill summarises.
- `bgp-analysis`, `igp-routing-analysis` -- when firewall change risks routing convergence (large ACL push that drops BGP / OSPF transit), pause and run those skills first.
- `secrets-hygiene` -- VPN pre-shared keys, AnyConnect group passwords, SNMP community strings, FMC credentials all fall under the secrets-hygiene patterns.
- `completion-gate` Layer 3 -- every state-changing change requires fresh post-check evidence before claiming "policy deployed".
- `plan-time-tooling` -- every state-changing audit recommendation fires the `engineering:deploy-checklist` skill at plan time (production-mutating operation).
- `systematic-debugging` -- Phase 1 boundary evidence (which interface, which zone, which ACL line, which ACP rule, what hit-count delta) before any change.
- `oncall-runbooks` -- incident classification when audit findings overlap with active incidents.

## Red flags (about-to-act warnings)

- About to clear an ACE without explaining the blast radius (which connections, which sessions, which services).
- About to push an FMC deploy without verifying the pending change set (`Deploy -> View Deployments`).
- About to change Snort base policy on a Friday afternoon.
- About to delete a "permit any any" without first replacing with the specific permits.
- About to enable Snort inline mode in production without staging in passive first.
- About to extend AnyConnect split-tunnel scope without policy sign-off.
- About to disable failover monitoring without an explicit maintenance window.

## Bottom line

Audit the platform-specific architecture, not just the rules. ASA is interface-bound ACL plus MPF inspection plus Section 1 / 2 / 3 NAT. FTD is ACP plus Snort plus File / Malware plus FMC orchestration. Diagnose-first via read-only commands and FMC queries; map every state-changing recommendation onto the nine-element response contract; pair with the cross-vendor methodology in `acl-rule-analysis` for mixed estates. Severity rankings drive remediation cadence (CRITICAL 30 d, HIGH 90 d, clean 180 d).
