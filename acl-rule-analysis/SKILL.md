---
name: acl-rule-analysis
description: Use for any ACL or firewall-rule analysis, audit, refactor, or risk review across L3 / L4 ACLs (Cisco IOS / IOS-XE / NX-OS / IOS-XR / ASA-FTD; Juniper JunOS; Arista EOS) and policy firewalls (PAN-OS, FortiGate, CheckPoint). Triggers include "review this ACL", "audit firewall rules", "ACL hit count is zero / stale", "rule shadowing", "shadowed deny rule", "rule consolidation", "redundant rules", "NAT precedence", "object-group / address-group sprawl", "any-any permit / deny", "rule reorder safety", "ACL applied wrong direction or wrong interface", "broad permit risk", "is this rule reachable", "rule documentation drift", "rulebase hygiene", "post-migration cleanup", "compliance prep for rule justification", "merger / acquisition rulebase consolidation". Seven-step diagnostic procedure (collect rulebase, identify shadowed rules, detect overly permissive rules, find unused rules, identify redundant rules, rule ordering optimisation, generate consolidated recommendations). Severity tables, hit-count staleness thresholds, decision trees for remediation priority and reorder safety, executive-summary report template. Vendor-agnostic rule-walk discipline (top-down first-match, NAT precedence, group resolution, implicit-deny semantics per platform). NOT a replacement for the deeper Stage 3 per-vendor firewall-audit skills (cisco-firewall-audit, palo-alto-firewall-audit, fortigate-firewall-audit) when those land. Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); references swapped to local vault skills.
metadata:
  version: 1.0.0
---

# ACL Rule Analysis

Vendor-agnostic rule analysis for access-control lists and firewall policies. Unlike vendor-specific firewall-audit skills (which evaluate platform features like App-ID, Security Profile Groups, zone protection), this skill focuses on universal rule patterns that apply across all platforms: shadowed rules, redundant rules, overly permissive rules, unused rules.

This skill is the cross-platform methodology layer. The `multi-vendor-network-ops` umbrella stays the entry point for general network work; this skill loads when the work is specifically rule audit or refactor. For per-platform deep firewall audits, the Stage 3 per-vendor skills (`cisco-firewall-audit`, `palo-alto-firewall-audit`, `fortigate-firewall-audit`) go further; until those land, this skill is the primary firewall analysis surface.

Covers ACL-based platforms (Cisco IOS / IOS-XE / NX-OS / IOS-XR / ASA-FTD, Juniper JunOS, Arista EOS) and policy-based firewalls (Palo Alto PAN-OS, Fortinet FortiGate, Check Point). The analysis algorithms are vendor-agnostic; only the rule-retrieval commands differ by platform.

Commands use inline labels `[Cisco]`, `[JunOS]`, `[EOS]`, `[PAN-OS]`, `[FortiGate]`, `[CheckPoint]` where syntax diverges. Unlabeled statements apply universally.

> **Skill marker**: When applying this skill, begin your reply with `[skill: acl-rule-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the firewall estate (vendors, platforms, prior audit findings) before walking rulebases. Only ask the user for information not already covered or specific to this audit.

Before starting the rule walk, understand:

1. **Estate and scope**
   - Which vendor(s) and platform(s) are in scope (PAN-OS, ASA, FTD, FortiGate, others)?
   - One device, one cluster, or an estate-wide pass?
   - Running config, candidate config, or a proposed change diff?

2. **Audit driver**
   - Compliance pass, post-incident review, pre-migration baseline, or rule cleanup?
   - Output format expected (per-rule spreadsheet, executive summary, remediation list)?

3. **Evidence on hand**
   - Read-only access path (CLI, manager UI, exported config)?
   - Recent hit-count or log telemetry available?
   - Change history (who edited what, when, why)?

---

## When to use

- Post-migration rule cleanup after converting from one platform to another.
- Periodic rulebase hygiene to remove accumulated technical debt.
- Compliance preparation requiring rule-level justification and minimal privilege.
- Incident investigation: determining whether a rule permitted malicious traffic.
- Change validation after rulebase modifications to confirm no shadowed rules.
- Capacity optimisation: reducing rule count to improve lookup performance.
- Merger / acquisition integration: consolidating overlapping rulebases.

## Do NOT use this skill for

- Generic "what is an ACL" tutoring.
- Routing protocol work (use `bgp-analysis` or `igp-routing-analysis`).
- Layer 2 work (use `multi-vendor-network-ops` diagnose table).
- Per-platform deep firewall audits when the Stage 3 skills are present (use the dedicated vendor skill).
- Pure pyATS / Genie automation around ACLs (use `pyats-network-automation` for the framework; combine with this skill for the rule-walk semantics).

## Prerequisites

- Read-only access to the target device via SSH, console, or API.
- Rulebase with hit counters enabled (most platforms enable by default).
- For unused-rule detection: hit-count data accumulated over an extended period (30 days minimum, 90 days recommended for seasonal traffic patterns).
- Knowledge of intended security policy: which traffic should be permitted and which should be denied between network segments.
- Understanding of implicit-deny behaviour for the platform (varies; see Common failure modes).

## Procedure

Sequential. Each step builds on prior findings. Data collection first, pattern detection second, consolidated recommendations third.

### Step 1: Collect rulebase

Retrieve the full ACL or firewall policy from the target device.

`[Cisco]` IOS / IOS-XE / NX-OS / IOS-XR:
```
show ip access-lists
show access-lists
```

`[Cisco]` ASA / FTD:
```
show access-list
show running-config access-list
```

`[JunOS]`:
```
show configuration firewall family inet filter
show firewall filter
```

`[EOS]`:
```
show ip access-lists
show access-lists counters
```

`[PAN-OS]`:
```
show running security-policy
```

`[FortiGate]`:
```
get firewall policy
```

`[CheckPoint]` SmartConsole CLI or Expert mode:
```
fw stat -l
```

Record each rule: sequence number / name, match criteria (source, destination, protocol, port / service), action (permit / deny / drop / reject), and hit count. Normalise the data into a common format for analysis.

### Step 2: Identify shadowed rules

A rule is **shadowed** when a preceding rule matches all traffic that the shadowed rule would match. The shadowed rule never triggers because the earlier rule always matches first.

Detection algorithm:

1. For each rule R at position N, examine all rules at positions 1 through N-1.
2. If any preceding rule P has match criteria that is a superset of R's criteria and the same or broader action scope, then R is shadowed by P.
3. A superset means P's source contains R's source, P's destination contains R's destination, and P's service / port contains R's service / port.

**Critical case:** a permit rule shadowing a deny rule means traffic intended to be blocked is actually permitted. This is a security gap; flag as Critical.

**Benign case:** a deny rule shadowing another deny rule is a redundancy issue, not a security gap; flag as Medium.

Verify suspected shadows by checking hit counts: a truly shadowed rule has zero hits despite the traffic pattern existing in the network.

### Step 3: Detect overly permissive rules

Identify rules with excessively broad match criteria that violate least privilege. Risky patterns by platform family:

ACL platforms (Cisco, JunOS, EOS):

- `permit ip any any`: allows all IPv4 traffic, bypasses all filtering.
- `permit ip any <broad-subnet>` where subnet is /8 or larger.
- `permit tcp any any eq <high-risk-port>`: unrestricted source to sensitive service (e.g. SSH, RDP, SQL).

Policy platforms (PAN-OS, FortiGate, CheckPoint):

- Source `any` plus destination `any` plus action `allow`.
- Application / service set to `any` or `all`.
- Broad service groups containing dozens of ports.

For each overly permissive rule found, check its hit count and traffic logs to determine actual usage patterns. Many "any / any" rules exist as legacy migration artifacts that can be narrowed to observed traffic.

### Step 4: Find unused rules

Unused rules have zero hit count over an extended observation period.

`[Cisco]`: check hit counts inline with `show access-lists` output.

`[JunOS]`: `show firewall filter <name> counter` (per-term counters).

`[EOS]`: `show access-lists counters` (per-entry match counts).

`[PAN-OS]`: `show rule-hit-count vsys vsys1 security rules all`.

`[FortiGate]`: `diagnose firewall iprope list` (per-policy packet / byte counts).

`[CheckPoint]`: SmartConsole, Policy, hit-count column; or `cpstat fw -f policy`.

Caveats for unused-rule detection:

- Hit counters reset on device reboot; verify uptime before concluding a rule is unused.
- Seasonal traffic (quarterly reports, annual processes) may not appear in 30-day windows; extend observation to 90+ days when possible.
- Backup / failover paths only activate during outages; low hit count does not mean the rule is unnecessary.
- Unused deny rules are low-risk findings; unused permit rules waste rulebase space and may indicate abandoned access that should be revoked.

### Step 5: Identify redundant rules

Redundant rules have overlapping match criteria and the same action. They increase rulebase complexity without adding security value.

Detection approach:

1. Group rules by action (permit / deny).
2. Within each group, compare pairs for overlapping source, destination, and service criteria.
3. If rule A's match criteria is a subset of rule B's and both have the same action, rule A is redundant (B already covers it).
4. If two rules have identical match criteria and the same action, one is a direct duplicate.

Merge candidates: rules with adjacent or overlapping source / destination ranges and the same action can often be consolidated into a single rule with a summarised address range.

### Step 6: Rule ordering optimisation

Rule ordering affects both security and performance.

**Performance optimisation:** place highest-hit-count rules near the top. ACL platforms evaluate rules sequentially; a rule matching 80 percent of traffic at position 50 forces 49 unnecessary comparisons per packet.

**Security optimisation:** place most-specific deny rules before broader permit rules to ensure explicit blocks take precedence.

**Conflict analysis:** when a permit rule and a deny rule match the same traffic, the first-match rule determines the outcome. Identify all permit / deny conflicts and verify the intended rule wins by position.

Review current ordering:

1. Sort rules by hit count (descending).
2. Compare current position against hit-count-optimal position.
3. Identify rules where reordering would improve performance without changing security posture.
4. Flag any reordering that would change effective policy (a permit moving above a deny, or vice versa); these require explicit approval.

### Step 7: Generate consolidated recommendations

Compile findings from Steps 2 to 6 into a prioritised remediation list.

Prioritisation order:

1. **Critical**: shadowed deny rules (security gap), any-any permits.
2. **High**: overly permissive rules with active traffic, unused permit rules.
3. **Medium**: redundant rules, suboptimal ordering, unused deny rules.
4. **Low**: cosmetic issues (naming, comments, organisation).

For each finding, document: the rule identifier, the finding category, the specific risk, and the recommended action (remove, narrow, reorder, merge).

## Threshold tables

Rule risk severity classification:

| Finding | Severity | Rationale |
|---|---|---|
| Permit rule shadowing a deny rule | Critical | Traffic intended to be blocked is permitted |
| `permit ip any any` / any-any-allow | Critical | No filtering; all traffic passes |
| Broad subnet permit (source or dest /8 or larger) | High | Overly wide scope; likely exceeds intent |
| Unused permit rule (0 hits, 30+ days) | High | Abandoned access; potential unauthorised path |
| Permit with `any` source to sensitive service | High | Unrestricted access to high-risk ports |
| Redundant rules (same action, overlapping match) | Medium | Complexity without security value |
| Suboptimal rule ordering (high-hit rule low in list) | Medium | Performance impact on sequential evaluation |
| Shadowed deny by another deny | Medium | Redundancy, not a security gap |
| Unused deny rule (0 hits, 30+ days) | Low | Minimal risk; cleanup recommended |
| Missing rule comments / descriptions | Low | Maintainability concern |

Hit-count staleness thresholds:

| Observation period | Confidence | Action |
|---|---|---|
| less than 7 days | very low | insufficient data; do not remove rules based on hit count |
| 7 to 29 days | low | flag for review; extend observation period |
| 30 to 89 days | moderate | reasonable basis for unused-rule identification |
| 90+ days | high | strong evidence for rule removal or narrowing |
| 180+ days | very high | recommend removal with change-control documentation |

## Decision tree: remediation priority

```
Found a flagged rule
├── Is the rule overly permissive (any / any)?
│   ├── Yes
│   │   ├── Is it actively used (hit count greater than 0)?
│   │   │   ├── Yes: analyse traffic logs to narrow match criteria
│   │   │   │   ├── Can it be narrowed to specific IPs / services?
│   │   │   │   │   ├── Yes: create replacement rules, test, then remove original
│   │   │   │   │   └── No: document business justification, add compensating controls
│   │   │   │   └── Is there a Security Profile / IPS covering this rule?
│   │   │   │       ├── Yes: lower priority, but still narrow when feasible
│   │   │   │       └── No: high priority; no inspection on broad permit
│   │   │   └── No (zero hits): schedule removal with change control
│   │   └── Severity: Critical
│   └── No
│       ├── Is the rule shadowed?
│       │   ├── Shadowed deny (by a permit): Critical, security gap
│       │   ├── Shadowed permit (by another permit): Medium, remove redundancy
│       │   └── Shadowed deny (by another deny): Low, remove redundancy
│       ├── Is the rule unused?
│       │   ├── Unused permit: High, revoke abandoned access
│       │   └── Unused deny: Low, cleanup at convenience
│       └── Is the rule redundant?
│           └── Merge with covering rule: Medium
```

## Decision tree: rule reorder safety

```
Proposed rule reorder
├── Does the reorder change which rule matches any traffic flow?
│   ├── Yes: STOP; this is a policy change, not just optimisation
│   │   ├── Would a deny move below a permit for the same traffic?
│   │   │   ├── Yes: REJECT; security degradation
│   │   │   └── No: evaluate as an intentional policy change
│   │   └── Submit for change-control review
│   └── No: safe to reorder for performance
│       ├── Validate with test traffic or policy simulation
│       └── Implement during maintenance window
```

## Report template

For production-impacting rule changes, map findings onto the `multi-vendor-network-ops` 9-element response contract (assumptions, risk category, evidence, recommendation, pre-checks, execution guidance, post-checks, rollback, escalation). The rule-audit-specific report skeleton:

```markdown
# ACL / Firewall Rule Analysis Report

## Executive Summary
- **Device:** [hostname]
- **Platform:** [Cisco IOS / ASA / JunOS / EOS / PAN-OS / FortiGate / CheckPoint]
- **Rulebase size:** [total rules]
- **Analysis date (UTC):** [timestamp]
- **Performed by:** [operator / agent]
- **Observation period for hit counts:** [start date] to [end date] ([N] days)

**Summary:** [N] findings across [rules examined] rules. [critical count]
Critical, [high count] High, [medium count] Medium, [low count] Low.

## Shadowed rules
| Rule | Rule name | Shadowed by | Match overlap | Severity | Action |
|------|-----------|-------------|---------------|----------|--------|
| [seq] | [name] | Rule [seq] | [description] | [sev] | Remove / Reorder |

## Overly permissive rules
| Rule | Rule name | Source | Destination | Service | Hit count | Severity |
|------|-----------|--------|-------------|---------|-----------|----------|
| [seq] | [name] | [src] | [dst] | [svc] | [count] | [sev] |

**Recommendation:** [Narrow to observed traffic / Add compensating controls]

## Unused rules
| Rule | Rule name | Action | Last hit (UTC) | Days observed | Severity |
|------|-----------|--------|---------|---------------|----------|
| [seq] | [name] | [act] | [date] | [days] | [sev] |

**Recommendation:** [Remove with change control / Extend observation period]

## Redundant rules
| Rule | Rule name | Redundant with | Overlap type | Recommendation |
|------|-----------|----------------|--------------|----------------|
| [seq] | [name] | Rule [seq] | [type] | Merge / Remove |

## Ordering recommendations
| Current position | Rule | Hit count | Optimal position | Impact |
|------------------|------|-----------|------------------|--------|
| [pos] | [seq] | [count] | [new pos] | [desc] |

## Prioritised remediation plan
1. [Critical] [Finding description]: [Specific action]
2. [High] [Finding description]: [Specific action]
3. [Medium] [Finding description]: [Specific action]

## Next review
- Critical findings present: re-audit in 30 days after remediation.
- High findings only: re-audit in 90 days.
- Medium / Low only: re-audit in 180 days.
```

## Common failure modes

### Hit counters reset after reboot

Most platforms reset ACL / policy hit counters on reboot. Before concluding a rule is unused, verify device uptime: `[Cisco]` `show version | include uptime`; `[JunOS]` `show system uptime`; `[EOS]` `show uptime`; `[PAN-OS]` `show system info | match uptime`; `[FortiGate]` `get system performance status`; `[CheckPoint]` `cpstat os -f ifconfig`. If uptime is less than the desired observation period, hit-count data is incomplete.

### ACL vs firewall-policy semantic differences

ACL-based platforms (Cisco IOS, EOS) evaluate rules top-to-bottom with first-match semantics. Firewall-policy platforms (PAN-OS, FortiGate, CheckPoint) also use first-match but have additional dimensions (zones, applications, user identity) that affect matching. Shadowed-rule detection must account for **all** match dimensions on policy platforms, not just source / destination / port.

### Implicit deny varies by platform

`[Cisco]` ACLs have an implicit `deny ip any any` at the end (not shown in the ACL output). `[JunOS]` firewall filters have an implicit discard at the end of each term list. `[EOS]` follows Cisco convention with implicit deny. `[PAN-OS]` has configurable interzone-default and intrazone-default rules (deny and allow respectively). `[FortiGate]` has implicit deny at end of policy list. `[CheckPoint]` has implicit drop rule at end of policy (configurable in SmartConsole).

Account for implicit deny when analysing rule coverage; the absence of an explicit deny at the bottom is intentional on most platforms.

### NAT precedence and ACL evaluation point

ASA / FTD evaluate ACLs after NAT for inbound, before NAT for outbound. IOS / IOS-XE evaluate ACLs based on the interface and direction; NAT happens at different points in the packet flow. PAN-OS uses post-NAT addresses for security policy matching by default. Understand the platform's evaluation order before walking a rule against a packet capture.

### Object groups and false-positive shadowing

Object groups, address groups, and nested service groups can create false-positive shadow detections. When rule A uses an address group and rule B uses individual addresses that are members of that group, automated tools may report B as shadowed. Expand all groups to their member objects before running shadow comparisons.

### Large rulebases (500+ rules)

Manual analysis of large rulebases is impractical. Export the rulebase programmatically for automated analysis: `[Cisco]` parse `show access-lists` output; `[PAN-OS]` use XML API to export the full policy as structured data; `[FortiGate]` use REST API (`/api/v2/cmdb/firewall/policy`); `[CheckPoint]` use Management API (`mgmt_cli show access-rulebase`). Prioritise analysis by hit count; start with the highest-traffic rules and work down.

## Cross-references

- `multi-vendor-network-ops`: umbrella entry-point for general network work; the "ACL / NAT / policy shadowing" diagnose-table row routes here. The 9-element response contract is the iron rule for any production-impacting rule change.
- `bgp-analysis`: when "BGP peer not establishing" turns out to be a TCP/179 ACL block, the rule walk lives here.
- `igp-routing-analysis`: when "OSPF adjacency not forming" turns out to be a multicast 224.0.0.5 / 6 ACL block, the rule walk lives here.
- `pyats-network-automation`: pyATS / Genie can parse `show access-lists` output into structured form for automated diff and shadow analysis at scale.
- `wireless-security-audit`: wired-side enforcement of wireless segmentation lives in ACL discipline. When a wireless audit surfaces a VLAN-to-SSID mapping that depends on inter-VLAN ACL between wireless and corporate (or guest and corporate, or IoT and management VLANs) to be effective, the wired-side rule walk and shadow analysis lives in this skill. The wireless audit notes the boundary; this skill validates the wired-side enforcement.
- `systematic-debugging`: Phase 1 boundary evidence (which interface, which direction, which match criteria) is the diagnose-before-generate pattern.
- `secrets-hygiene`: rules with embedded credentials (community strings in SNMP ACLs, RADIUS / TACACS shared secrets in management-plane ACLs) are secrets. Never repeat them in responses; redact when pasted.
- `completion-gate` Layer 3: no claim of "rule applied", "rule removed", "rulebase clean" without fresh post-checks (hit-count delta, packet-capture verification, traffic test) in this turn.
- `plan-time-tooling`: any state-changing rule work fires the `engineering:deploy-checklist` mandatory trigger. Plan it as a chunk; do not freelance.

### Forward pointer to Stage 3 firewall-audit skills

This skill is methodology + rule-walk discipline. The Stage 3 per-vendor firewall-audit skills (when they land) go deeper:

- `cisco-firewall-audit`: ASA / FTD object-group resolution, NAT-rebase, threat-detection, ASDM contexts.
- `palo-alto-firewall-audit`: App-ID semantics, Security Profile Groups, zone protection, Panorama considerations.
- `fortigate-firewall-audit`: UTM profile chains, SSL inspection profiles, FortiManager templates.

Until those land, this skill is the primary firewall analysis surface.

## Red flags

- About to commit `permit any any` (or any-any-allow on a policy firewall) without a documented business justification and compensating controls.
- About to reorder rules without a dry-run / policy-simulation step that proves no traffic flow changes match.
- About to delete a rule with non-zero hit count without identifying the traffic source.
- About to remove an "unused" rule based on less than 30 days of hit-count data, or without checking device uptime.
- About to declare a rule shadowed without expanding object groups / address groups to their member objects first (false-positive risk).
- About to recommend an ACL change on a router without confirming which interface and which direction the ACL is applied to.
- About to walk an ASA / FTD rule against a packet capture without accounting for NAT-before-ACL on inbound.
- About to skip the implicit-deny check when assessing whether traffic is permitted (the absence of an explicit deny at the bottom is intentional on most platforms).
- About to repeat a community string, RADIUS secret, or TACACS key from a pasted ACL in your response.
- About to declare rule cleanup done without post-checks (per `completion-gate` Layer 3).

## Bottom line

Vendor-agnostic rule walk: top-down first-match, expand groups before comparing, account for the implicit deny per platform. Shadowed permit-over-deny is the security gap; redundant deny-over-deny is hygiene. Hit counts need 30 days minimum for confidence, 90 days for seasonal. Reorders that change traffic outcomes are policy changes, not optimisations. Production-impacting rule work always emits the 9-element response contract per `multi-vendor-network-ops`. Stage 3 per-vendor firewall-audit skills will go deeper when they land; until then, this skill is the primary surface.
