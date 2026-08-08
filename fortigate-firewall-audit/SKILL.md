---
name: fortigate-firewall-audit
description: Use for any audit, change review, or compliance pass on a FortiGate firewall (hardware appliance or FortiGate-VM), whether standalone, FortiManager-managed, or part of a FortiCloud estate. Triggers include "audit this FortiGate config", "review FortiOS policy", "UTM profile coverage", "missing IPS sensor", "missing antivirus profile", "VDOM segmentation audit", "inter-VDOM link bypass", "FortiGuard signatures stale", "SSL inspection mode", "deep-inspection vs certificate-inspection", "SD-WAN fail-open risk", "SD-WAN steers around UTM", "FortiGate HA checksum mismatch", "session pickup configuration", "FortiClient EMS endpoint posture", "FortiManager policy package drift", "ADOM hierarchy", "post-upgrade UTM schema change", "split-VDOM vs multi-VDOM", "policy hit count zero", "FortiOS implicit deny logging", "compliance audit on FortiGate". Covers FortiOS 7.x+ on FortiGate hardware and FortiGate-VM, multi-VDOM and split-VDOM modes, UTM profile suite (AV / IPS / WebFilter / AppCtrl / EmailFilter / DLP), FortiGuard signature freshness, SD-WAN SLA-based steering security implications, HA active-passive and active-active posture, and brief FortiManager-managed deployment notes. Six-step audit procedure, severity table, three decision trees. Diagnose-first; read-only `show` / `diagnose` queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite/fortigate-firewall-audit (Apache-2.0).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# FortiGate firewall audit

Policy-audit-driven analysis of FortiGate / FortiOS firewall policies. Unlike generic firewall checklists that only look for open ports and default-deny, this skill evaluates the FortiOS-specific security architecture: Virtual Domain (VDOM) segmentation, UTM profile binding on every allow policy, FortiGuard signature freshness, SD-WAN SLA-based traffic steering security implications, and HA cluster posture.

Covers FortiOS 7.x+ on FortiGate hardware appliances and FortiGate-VM virtual instances. For FortiManager-managed deployments, the audit addresses ADOM hierarchy and policy package consistency; see the brief subsection below.

> **Skill marker**: When applying this skill, begin your reply with `[skill: fortigate-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the FortiGate estate (single device, HA cluster, FortiManager-managed fleet, VDOM topology, FortiOS version) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Platform and architecture**
   - Standalone, HA active-passive, or active-active cluster?
   - Single VDOM, multi-VDOM (root + child), or VDOM-disabled?
   - Managed by FortiManager (FMG / ADOM) or device-local?
   - FortiOS major / minor version?

2. **Audit driver**
   - Compliance pass, post-incident review, migration baseline, or rule cleanup?
   - Specific concerns (UTM profile coverage, SSL inspection posture, SD-WAN policy, VPN)?

3. **Evidence and access**
   - Read-only access (GUI, CLI via SSH, FMG ADOM, exported `show full-configuration`)?
   - Hit-count, traffic-log, or UTM-event telemetry available?
   - Pending changes queued in FMG that affect audit scope?

---

## Scope and when to use

- Post-change policy review after rule additions, VDOM topology changes, or major FortiOS upgrade.
- VDOM segmentation audit verifying inter-VDOM link isolation and per-VDOM policy independence.
- UTM profile coverage assessment, finding allow policies without antivirus, IPS, web-filter, application-control, or DLP inspection.
- SD-WAN security evaluation, confirming SLA failures do not steer traffic around security controls.
- FortiGuard licence and connectivity validation, ensuring signature databases are current.
- HA cluster security posture check, verifying firmware parity, config sync, session-sync settings, encrypted heartbeat.
- FortiManager policy-package drift check on managed deployments.
- Quarterly or annual compliance audit requiring per-policy justification.
- Pre-upgrade baseline before FortiOS major version changes.

For mixed-vendor estate work, run `acl-rule-analysis` first for the cross-vendor methodology pass, then this skill for the FortiOS deep-dive. Sibling Stage 3 specialists: `cisco-firewall-audit`, `palo-alto-firewall-audit`. For VPN-only deep dives (IPsec / SSL-VPN site-to-site, FortiClient endpoint VPN, WireGuard) see `vpn-tunnel-troubleshooting`.

## Prerequisites

- Read-only administrative access to FortiOS CLI (or `diagnose`-level privilege for runtime state).
- Topology knowledge: which VDOMs exist, their function (management, traffic, DMZ), and expected inter-VDOM links.
- Knowledge of expected UTM profile assignments per policy category (internet-bound, inter-zone, intrazone, monitoring-only).
- For FortiManager-managed environments: access to the ADOM with visibility into policy packages and installation status.
- Awareness of SD-WAN configuration: SLA targets, member interfaces, health-check definitions.
- Running configuration committed (audit evaluates the active configuration, not pending changes).

## Procedure

Follow the six steps in order. The flow moves from VDOM architecture inventory through per-VDOM rule analysis to UTM coverage, FortiGuard health, SD-WAN security, and HA posture.

### Step 1: VDOM architecture inventory

```
config global
get system status
diagnose sys vd list
```

For each VDOM, record name, type (traffic / management / admin), assigned interfaces (physical and virtual), inter-VDOM link pairs, and VDOM resource limits (session count, CPU quota). Identify the management VDOM; FortiGuard updates, logging, and administrative access are configured there.

```
show system vdom-link
```

Inter-VDOM links function as virtual interfaces connecting two VDOMs. Traffic crossing a VDOM link is subject to the receiving VDOM's firewall policies; verify that inter-VDOM traffic is not bypassing inspection.

```
config global
get system vdom-property
```

Flag any VDOM without explicit resource limits in a multi-VDOM deployment; an unbounded VDOM can starve other VDOMs during volumetric events.

### Step 2: firewall policy rule-by-rule analysis

For each VDOM:

```
config vdom
edit <vdom-name>
show firewall policy
```

FortiOS evaluates policies top-down by sequence number within each VDOM. First match wins. Evaluate against:

- **Overly permissive policies:** `srcaddr "all"` plus `dstaddr "all"` plus `service "ALL"` plus `action accept` are Critical findings.
- **Missing UTM profiles:** allow policies without `av-profile`, `webfilter-profile`, `application-list`, `ips-sensor`, etc., pass traffic uninspected. Check `utm-status` first; if disabled, all bindings are no-ops.
- **Disabled policies:** `status disable` policies still occupy sequence numbers and create audit confusion. Flag for cleanup.
- **Schedule-based policies:** policies with `schedule` other than `always` may create off-hours gaps. Verify schedules align with intended access windows.
- **Implicit deny:** FortiOS has an implicit deny (policy ID 0) at the bottom of each VDOM's policy table. Verify it is logging traffic for visibility into denied connections.

```
diagnose firewall iprope show 100004 <policy-id>
```

Policies with zero hits over 90+ days are cleanup candidates (cross-check with `acl-rule-analysis` staleness bands).

### Step 3: UTM profile binding audit

For each allow policy in every VDOM, verify that UTM inspection profiles are bound. Goal: zero allow policies without threat inspection.

- **Antivirus (`av-profile`):** required on internet-bound and inter-zone policies.
- **Web Filter (`webfilter-profile`):** required on policies permitting HTTP / HTTPS.
- **Application Control (`application-list`):** FortiOS equivalent of App-ID; required on rules with broad service scope.
- **IPS (`ips-sensor`):** required on allow policies carrying untrusted traffic.
- **Email Filter (`emailfilter-profile`):** required on email-carrying policies (SMTP / IMAP / POP3).
- **DLP Sensor (`dlp-sensor`):** required where sensitive data egress risk exists.
- **SSL Inspection (`ssl-ssh-profile`):** without `deep-inspection`, AV and IPS see only metadata on HTTPS. `certificate-inspection` is the lighter mode and limits UTM efficacy.

Summarise coverage: count allow policies with full UTM binding versus partial or none. Calculate the UTM coverage ratio per VDOM.

```
config vdom
edit <vdom-name>
get system settings | grep inspection-mode
```

Flow-based mode applies UTM in a single pass (faster, fewer features). Proxy-based mode buffers and inspects fully (slower, full feature set). Mode affects which UTM features are available.

### Step 4: FortiGuard service validation

```
get system fortiguard-service status
diagnose autoupdate versions
```

Verify signature freshness:

| Database | Maximum age | Check |
|---|---|---|
| Antivirus | 24 hours | `diagnose autoupdate versions \| grep -A2 'Virus'` |
| IPS signatures | 7 days | `diagnose autoupdate versions \| grep -A2 'IPS'` |
| Web filter database | 7 days | `get webfilter status` |
| Application control DB | 7 days | `diagnose autoupdate versions \| grep -A2 'App'` |
| Anti-spam database | 7 days | `diagnose autoupdate versions \| grep -A2 'Spam'` |

```
diagnose debug rating
execute ping service.fortiguard.net
```

If FortiGuard is unreachable, all cloud-dependent features (web-filter rating queries, FortiSandbox cloud, outbreak prevention) operate in degraded mode using cached data only.

```
show system autoupdate schedule
```

Best practice: scheduled updates every 1 to 4 hours for AV, daily for IPS / App-Control. Manual-only updates are a finding.

### Step 5: SD-WAN SLA and rule security

If SD-WAN is configured:

```
config vdom
edit <vdom-name>
show system sdwan
diagnose sys sdwan health-check
diagnose sys sdwan service
```

Review:

- **SLA targets and health checks:** verify health-check servers are reachable and meaningful for the SLA metric (latency, jitter, packet loss).
- **SD-WAN rules:** each rule maps traffic to preferred WAN members based on SLA status. Review rule priorities and tie-break method.
- **Fail-open behaviour:** when all SLA members fail, SD-WAN rules may fall through to standard routing. Determine whether the fallback path still traverses security inspection. A fail-open that routes around a security VDOM or UTM-inspecting policy is a Critical finding.
- **SD-WAN plus firewall policy interaction:** SD-WAN selects egress; firewall policies still control access. Verify that policies cover all SD-WAN member interfaces. A policy referencing one interface may not match when SD-WAN steers traffic to an alternate member.

### Step 6: HA and session-sync audit

```
get system ha status
diagnose sys ha checksum cluster
show system ha
```

Check:

- **HA mode:** active-passive (recommended for stateful firewalls) vs active-active (requires careful session-sync configuration). Record the mode and verify it matches design intent.
- **Firmware parity:** both members MUST run the same FortiOS version. Mismatch causes session-sync failures and policy inconsistencies.
- **Configuration checksum:** mismatched checksums between members indicate config drift; a security risk when policies differ between HA members.
- **Session sync:** verify `session-pickup` and `session-pickup-connectionless` settings. Unsynchronised sessions drop during failover.
- **HA heartbeat security:** verify heartbeat interfaces use encryption and authentication. Unencrypted heartbeats on shared segments are vulnerable to spoofing.
- **HA management interface:** verify `ha-mgmt-interfaces` is configured for each member so both nodes remain independently accessible.

## FortiManager-managed deployments (brief)

FortiManager (FMG) is Fortinet's central policy and configuration manager. The full operational depth of FMG (ADOM design, revision history, policy-package install workflow, change-control gating, ServiceNow integration) is outside this skill's scope. Touch points relevant to a FortiGate audit:

- **Audit the firewall, not just FortiManager.** Local policies plus installation state may diverge from the FortiManager package. Use `show firewall policy` on the FortiGate and compare against the installed package in FMG.
- **Detect drift.** `diagnose fortimanager policy-check` (FortiOS) or the ADOM revision-diff in FMG identifies discrepancies between the ADOM-pushed policy and the running config.
- **Push status discipline.** A push that succeeds at the FMG but fails on one or more FortiGates is a partial-install hazard. Verify per-device install status before drawing conclusions about estate-wide enforcement.
- **ADOM hierarchy.** Policies in the ADOM apply to every device in the ADOM unless overridden via per-device policy. Audit shared policies first because they have the broadest blast radius.

A standalone `fortimanager-ops` skill is on the watchlist (see `merged-skills-registry`); revisit if the FortiManager workflow becomes the primary surface.

## Severity classification

| Finding | Severity | Rationale |
|---|---|---|
| `srcaddr "all"` + `dstaddr "all"` + `service "ALL"` + `action accept` | Critical | Fully open policy; no restriction on source, destination, or service. |
| Allow policy without any UTM profile (no AV, IPS, web-filter) | Critical | Traffic passes without threat inspection. |
| FortiGuard unreachable; all signatures stale | Critical | UTM profiles active but signatures outdated; detection efficacy severely degraded. |
| SD-WAN fail-open bypasses security inspection path | Critical | SLA failure routes traffic around UTM inspection. |
| Allow policy with `service "ALL"` (specific src / dst) | High | Permits all services; evaluate whether specific services can be defined. |
| FortiGuard signatures >7 days old | High | Detection gap for new threats discovered in the past week. |
| VDOM without resource limits in multi-VDOM deployment | High | Unbounded VDOM can starve other VDOMs during volumetric events. |
| HA configuration checksum mismatch between members | High | Policy or configuration drift; active and standby may enforce different rules. |
| HA firmware version mismatch | High | Session sync and feature parity issues during failover. |
| FortiManager partial-install (push succeeded at FMG, failed on N devices) | High | Estate divergence; FortiGates run different policy versions until reconciled. |
| Allow policy with partial UTM (missing IPS or AV) | Medium | Some inspection but exploit or malware detection gap. |
| Disabled policies in production VDOM | Medium | Audit confusion; stale configuration; cleanup recommended. |
| SSL inspection not set to deep-inspection on internet-bound policy | Medium | UTM sees only metadata on encrypted traffic; AV / IPS efficacy reduced. |
| Schedule-based policy creates off-hours security gap | Medium | Access permitted during window only; verify the gap during that window is intentional. |
| Inter-VDOM link without receiving-side policy | Medium | Traffic may traverse VDOM boundary without inspection. |
| Unencrypted HA heartbeat on shared segment | Medium | Vulnerable to spoofing; enable HA heartbeat encryption. |
| Policies with zero hits >90 days | Low | Unused rules; cleanup candidates. |

### UTM coverage maturity

| UTM coverage ratio | Maturity | Guidance |
|---|---|---|
| >90% allow policies with full UTM | Mature | Maintain; review remaining gaps quarterly. |
| 60 to 90% allow policies with UTM | Developing | Prioritise internet-bound and inter-zone policies for UTM binding. |
| <60% allow policies with UTM | Immature | Systematic UTM profile binding campaign needed. |

## Decision trees

### UTM gap remediation

```
Allow policy without UTM profiles
├── What traffic does this policy carry?
│   ├── Internet-bound -> CRITICAL: bind full UTM (AV + IPS + WebFilter + AppCtrl + SSL deep-inspection)
│   ├── Inter-VDOM or inter-zone -> HIGH: bind AV + IPS + AppCtrl minimum
│   ├── Intra-zone management -> MEDIUM: bind IPS + AppCtrl; AV optional
│   └── Monitoring / logging only -> LOW: evaluate if accept is needed at all
│
├── SSL inspection mode?
│   ├── certificate-inspection -> UTM limited to metadata on HTTPS
│   │   └── Evaluate switching to deep-inspection for this policy
│   ├── deep-inspection -> full UTM efficacy on encrypted traffic
│   └── none -> only unencrypted traffic inspected
│       └── Add ssl-ssh-profile before binding UTM profiles
│
└── Inspection mode (VDOM-level)?
    ├── flow-based -> single-pass; good performance, some UTM features limited
    └── proxy-based -> full buffered inspection; verify resource impact
        └── Check headroom: get system performance status; diagnose sys top 2 20
```

### VDOM consolidation assessment

```
Multi-VDOM deployment evaluation
├── How many VDOMs are configured?
│   ├── >10 VDOMs -> evaluate consolidation; management complexity increases risk
│   ├── 3 to 10 VDOMs -> typical; verify each serves a distinct security function
│   └── 1 to 2 VDOMs -> minimal; verify VDOM is needed vs single-VDOM mode
│
├── Do all VDOMs have active policies?
│   ├── Empty or minimal policy VDOMs -> consolidation or removal candidates
│   └── Active policy VDOMs -> verify traffic segmentation justification
│
├── Are inter-VDOM links necessary?
│   ├── Inter-VDOM traffic inspected by receiving VDOM -> correct architecture
│   └── Inter-VDOM traffic not inspected -> finding: add policies on VDOM links
│
└── Resource contention?
    ├── VDOM resource limits configured -> check utilisation vs limits
    └── No limits -> set limits per VDOM to prevent starvation
```

### SD-WAN fail-open risk evaluation

```
SD-WAN SLA failure scenario
├── All SLA members for a rule fail
│   ├── Rule has dst = security VDOM or UTM-inspecting path?
│   │   ├── Yes -> traffic falls to routing table
│   │   │   ├── Routing-table path includes UTM inspection? -> acceptable
│   │   │   └── Routing-table path bypasses UTM? -> CRITICAL: fail-open gap
│   │   └── No -> standard egress; verify firewall policy still matches
│   │
│   └── SLA health-check server unreachable (false positive)?
│       ├── Single health-check server -> HIGH: add redundant check servers
│       └── Multiple servers, all down -> likely real outage; verify failover
│
└── Partial SLA failure (some members down)
    ├── Traffic steers to remaining members -> verify capacity
    └── Remaining member is a lower-security path -> evaluate risk
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
FORTIGATE SECURITY POLICY AUDIT REPORT
========================================
Device: [hostname] | FortiOS: [version] | Platform: [model / VM]
VDOM mode: [multi-vdom / split-vdom / disabled]
Management: [standalone / FortiManager ADOM <name>]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[FortiManager last install succeeded; signatures up to date; no in-flight change.]

VDOM ARCHITECTURE:
- VDOMs configured: [n]
- Management VDOM: [name]
- Inter-VDOM links: [n] ([list pairs])
- VDOMs with resource limits: [n] / [total]

PER-VDOM POLICY SUMMARY:
VDOM: [name]
  - Total firewall policies: [n]
  - Accept: [n] | Deny: [n]
  - Policies with full UTM profiles: [n] / [accept count]
  - Inspection mode: [flow-based / proxy-based]
  - SSL inspection (deep): [n] policies
  [Repeat per VDOM]

FORTIGUARD STATUS:
- Connectivity: [connected / unreachable]
- AV / IPS / WebFilter / AppCtrl / Anti-Spam ages: [list with timestamps]
- Update schedule: [interval]

SD-WAN STATUS:
- Enabled: [yes / no]
- SLA health checks: [n] ([all passing / N failing])
- Fail-open risk: [none / risk details]

HA STATUS:
- Mode: [active-passive / active-active / standalone]
- Firmware parity: [matched / mismatched + versions]
- Config checksum: [matched / mismatched]
- Session sync: [enabled / disabled]
- Heartbeat encryption: [on / off]

EVIDENCE: [show + diagnose output, REST API extracts attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
VDOM: [name] | Policy ID: [id] (Seq: [n]) | Interfaces: [srcintf] -> [dstintf]
Issue: [problem] -> Recommendation: [remediation]

UTM COVERAGE:
- Per-VDOM ratios: [list each VDOM: n / total (%)]
- Policies missing AV / IPS / web-filter / app-control: [counts]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list, including hit-count delta verification]
ROLLBACK: [config revision restore ref or per-policy revert step]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **Auditing FortiManager in isolation:** misses local policy drift on individual FortiGates. Always cross-check `show firewall policy` on the device against the installed FMG package.
- **Auditing the firewall in isolation:** misses ADOM-level shared policies that are part of the effective rulebase.
- **Large multi-VDOM deployments (>10 VDOMs):** export per-VDOM tables via REST API (`/api/v2/cmdb/firewall/policy?vdom=<name>`) for programmatic analysis. Prioritise VDOMs carrying internet-bound or inter-zone traffic.
- **UTM performance impact:** before binding UTM on high-throughput policies, assess headroom via `get system performance status` and `diagnose sys top 2 20`. FortiGate models have rated NGFW and Threat Protection throughput; ensure traffic volume is within rated capacity.
- **Firmware-upgrade impact on policies:** FortiOS major upgrades may change UTM profile schema or deprecate features. Export the policy baseline before upgrading; post-upgrade verify UTM bindings preserved, sequence intact, SD-WAN rules migrated, HA cluster upgraded in sequence (secondary first).
- **Split-VDOM mode vs multi-VDOM mode confusion:** split-VDOM provides two VDOMs (root + FG-traffic); full multi-VDOM allows custom count. Audit whether split-VDOM segmentation is sufficient for compliance requirements. Changing VDOM mode requires a reboot.
- **Heartbeat encryption left at default:** factory default may not enforce HA1 / HA2 encryption; flag for any cluster on a shared segment.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the FortiOS specialist. Apply the nine-element response contract to every state-changing recommendation.
- `acl-rule-analysis` -- vendor-agnostic ACL methodology, hit-count staleness bands, severity-pattern catalogue. Run first for cross-vendor estate work, then this skill for the FortiOS deep-dive.
- `cisco-firewall-audit`, `palo-alto-firewall-audit` -- sibling Stage 3 specialists; sequence vendor-by-vendor when auditing a mixed estate.
- `vpn-tunnel-troubleshooting` -- IPsec / SSL-VPN site-to-site, FortiClient EMS endpoint posture, WireGuard, and IKE state-machine analysis live there. This skill stops at FortiGate-side firewall policy.
- `bgp-analysis`, `igp-routing-analysis` -- when a firewall change risks routing convergence (large policy push or VDOM topology change), pause and run those skills first.
- `pyats-network-automation` -- Genie parsers exist for some FortiOS show output; useful for fleet-wide UTM coverage scans.
- `secrets-hygiene` -- API tokens, FortiGuard licence keys, FortiManager service-account passwords, SNMP community strings, FortiCloud credentials all fall under the patterns there.
- `completion-gate` Layer 3 -- every state-changing change requires fresh post-check evidence (commit ID recorded, hit-count delta confirmed, FortiGuard signature ages re-verified) before claiming "policy deployed".
- `plan-time-tooling` -- every state-changing audit recommendation fires `engineering:deploy-checklist` at plan time.
- `systematic-debugging` -- Phase 1 boundary evidence (which VDOM, which policy ID, which interface pair, which UTM profile binding) before any change.
- `oncall-runbooks` -- incident classification when audit findings overlap with active incidents.

## Red flags (about-to-act warnings)

- About to push to a FortiManager-managed estate without confirming per-device install status post-push.
- About to enable SSL deep-inspection on a zone pair without certificate distribution to endpoints (will break TLS for users).
- About to switch inspection mode (flow vs proxy) without resource-headroom check.
- About to delete a policy with non-zero hit count without identifying the traffic source.
- About to upgrade a HA cluster firmware without secondary-first sequence.
- About to add an "any any accept" policy at the top of a VDOM as a temporary fix.
- About to change SD-WAN rules during business hours without verifying fail-open path.
- About to disable HA heartbeat encryption to "fix" a sync issue.
- About to remove a VDOM resource limit because a workload is bumping the ceiling (find the cause first).
- About to skip the FortiGuard signature age check because the device "feels fine".

## Bottom line

Audit the FortiOS architecture, not just the rules. The architecture is VDOM segmentation plus UTM profile binding plus FortiGuard freshness plus SD-WAN steering plus HA cluster posture, with FortiManager layering ADOM-pushed policy on top. Diagnose-first via read-only `show` and `diagnose`; audit BOTH FortiManager and the deployed FortiGates; map every state-changing recommendation onto the nine-element response contract. Severity rankings drive remediation cadence (CRITICAL 30 d, HIGH 90 d, clean 180 d). Partial-installs and stale FortiGuard signatures are the most common audit smells; check both first.
