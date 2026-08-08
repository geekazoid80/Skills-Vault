---
name: palo-alto-firewall-audit
description: Use for any audit, change review, or compliance pass on a Palo Alto Networks PAN-OS firewall (PA-series hardware or VM-series virtual), whether standalone or Panorama-managed. Triggers include "audit this Palo Alto config", "review PAN-OS security policy", "App-ID coverage", "application any audit", "Security Profile Group missing", "decryption policy review", "zone protection profile gap", "WildFire binding", "URL filtering coverage", "review this Panorama push", "device group rule shadowing", "pre-rule vs post-rule order", "shared vs device-group policy", "Panorama commit failed", "template stack drift", "PAN-OS rule reorder safety", "GlobalProtect zone audit", "User-ID integration check", "dynamic address group membership", "PAN-OS post-NAT match", "compliance audit on Palo Alto firewall". Covers PAN-OS 10.x+, PA-series and VM-series, Panorama hierarchy (shared pre-rules / device-group pre-rules / local rules / device-group post-rules / shared post-rules), zone-based segmentation, App-ID + Content-ID, Security Profile Groups, zone protection, decryption policy, and the test security-policy-match validation harness. Six-step audit procedure plus a substantive Panorama-managed deployments section, severity table, and two decision trees. Diagnose-first; read-only `show` / XML API queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite/palo-alto-firewall-audit (Apache-2.0); Panorama workflow lifted from automateyournetwork/netclaw/paloalto-panorama (Apache-2.0).
license: Apache-2.0
metadata:
  version: 1.0.0
---

# PAN-OS firewall audit (with Panorama)

Policy-audit-driven analysis of Palo Alto Networks PAN-OS security policies. Unlike generic firewall checklists that only look for open ports and default-deny, this skill evaluates the PAN-OS-specific security architecture: zone-based segmentation, the App-ID identification chain, Security Profile Group binding coverage, zone protection profiles, and the multi-layer Panorama policy hierarchy.

Covers PAN-OS 10.x+ on PA-series hardware and VM-series virtual firewalls. For Panorama-managed deployments, the audit addresses device-group hierarchy, template stack drift, and pre-rule / post-rule evaluation order; see the dedicated section below.

> **Skill marker**: When applying this skill, begin your reply with `[skill: palo-alto-firewall-audit]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Palo Alto estate (single firewall, HA pair, Panorama-managed, multi-vsys, log-collector layout, PAN-OS version) before starting the audit. Only ask the user for information not already covered or specific to this engagement.

Before starting the audit, understand:

1. **Platform and architecture**
   - Single firewall, HA active-passive / active-active, or Panorama-managed fleet?
   - Single vsys or multi-vsys?
   - Panorama device groups and template stacks involved?
   - PAN-OS major / minor version?

2. **Audit driver**
   - Compliance pass, post-incident review, migration baseline, or rule cleanup?
   - Specific concerns (App-ID coverage, decryption posture, Threat Prevention profile, GlobalProtect)?

3. **Evidence and access**
   - Read-only access (WebUI, CLI, Panorama, exported config, XML API)?
   - Hit-count, traffic-log, or threat-log telemetry available?
   - Pending commits queued in Panorama that affect audit scope?

---

## Scope and when to use

- Security policy review after rule changes, port-based-to-App-ID migration, or major PAN-OS version upgrade.
- Annual or quarterly compliance audit requiring rule-level justification.
- Post-incident rule assessment to identify how traffic was permitted (or why it was blocked).
- Zone segmentation validation after redesign or VLAN renumbering.
- Security Profile Group gap analysis, finding allow rules without threat inspection.
- App-ID adoption assessment (migration from `application any` to named App-IDs).
- Pre-upgrade policy baseline.
- **Panorama push validation:** confirming device-group rules are consistent across managed firewalls; auditing pre-rule / post-rule evaluation; commit-queue triage.
- Decryption policy review for full Content-ID / WildFire visibility.

For mixed-vendor estate work, run `acl-rule-analysis` first for the cross-vendor methodology pass, then this skill for the PAN-OS deep-dive. Sibling Stage 3 specialists: `cisco-firewall-audit`, `fortigate-firewall-audit`. For VPN-only deep dives, see `vpn-tunnel-troubleshooting`.

## Prerequisites

- Read-only administrative access to PAN-OS CLI, XML API, or REST API (PAN-OS 9.1+ for REST).
- Zone topology knowledge: which zones exist, their trust classification, expected traffic flows between zone pairs.
- Knowledge of expected application allowlists per zone pair (which App-IDs should be permitted where).
- Awareness of Security Profile Group assignments per traffic category.
- For Panorama-managed environments: access to Panorama with visibility into device-group hierarchy and template stacks; access to commit-queue history.
- Candidate configuration committed (audit evaluates the running configuration, not candidate). For Panorama: verify the latest device-group push has succeeded before drawing conclusions about device behaviour.

## Procedure

Follow the six steps in order. The flow moves from architecture inventory through rule-level analysis to profile and protection validation, with the Panorama section running in parallel for managed deployments.

### Step 1: zone architecture inventory

```
show running zone
```

Record each zone: name, type (L3 / L2 / V-Wire / Tap / Tunnel), assigned interfaces, and zone protection profile. Count inter-zone security policy rules per zone pair. Identify zones with no protection profile assigned; these lack flood, reconnaissance, and packet-based attack protection.

```
show running zone-protection-profile
```

Flag any L3 zone without a zone protection profile.

### Step 2: security policy rule-by-rule analysis

```
show running security-policy
```

For Panorama-managed devices, rules evaluate in this order: shared pre-rules; device-group pre-rules; local rules; device-group post-rules; shared post-rules. The effective rulebase on each managed firewall can be verified with the same `show running security-policy` from the device CLI.

Evaluate each rule against:

- **Overly permissive application:** rules with `application any` plus `action allow` are Critical findings; they bypass App-ID entirely.
- **Missing Security Profile Group (SPG):** allow rules without an SPG (or individual profiles) pass traffic without threat inspection. Check `profile-setting`.
- **Disabled rules:** still consume rulebase space and create audit confusion. Flag for cleanup.
- **Shadowed rules:** a rule is shadowed when a preceding rule matches all the same traffic with equal or broader criteria. Compare source / destination zone, address, application, service.
- **Overly broad source / destination:** rules using `any` for both source and destination address within a zone pair; evaluate whether address objects can narrow the scope.

Validate specific traffic scenarios with the test harness (read-only):

```
test security-policy-match source <IP> destination <IP> protocol <num> application <app> destination-port <port> from <zone> to <zone>
```

### Step 3: App-ID coverage assessment

Quantify App-ID adoption across the rulebase. Count rules using `application any` versus rules with specific App-IDs. Mature deployments target >80% of allow rules using named App-IDs.

```
show system info
```

Check `app-version` and `app-release-date`. Signatures older than 7 days indicate update failures; App-ID accuracy depends on current signatures.

For rules still using `application any`, check whether they also restrict by `service`. Rules with `application any` plus `service any` are the highest-risk combination.

### Step 4: Security Profile Group validation

```
show running profile-group
```

A complete SPG includes Antivirus, Anti-Spyware, Vulnerability Protection, URL Filtering, File Blocking, and WildFire Analysis. Optionally Data Filtering for DLP.

For each allow rule, check `profile-setting`:

- **group:** an SPG is bound (best practice).
- **profiles:** individual profiles are bound (acceptable; verify completeness).
- **none:** no profiles bound (finding: traffic passes uninspected).

Internet-facing rules MUST include WildFire Analysis for zero-day protection. Internal-only rules may use a lighter group but should still include Anti-Spyware as a minimum.

### Step 5: zone protection profile audit

Zone Protection Profiles defend against volumetric and packet-based attacks at the zone ingress point, before security policy evaluation. Check each zone for:

- **Flood protection:** SYN flood (SYN-cookies threshold), UDP flood, ICMP flood, Other IP flood; verify activate / alarm / maximum rates against expected traffic volume.
- **Reconnaissance protection:** TCP / UDP port scan and host sweep detection; should be enabled on external-facing zones.
- **Packet-based attack protection:** IP spoofing, fragmented traffic, known-bad flags (SYN+FIN, NULL flags), strict IP address check.

### Step 6: decryption policy review

```
show running ssl-decryption-policy
```

Without decryption, Security Profiles can inspect only connection metadata on encrypted flows. Check:

- **Coverage:** which zone pairs have SSL Forward Proxy enabled? Internet-bound traffic from user zones SHOULD be decrypted.
- **Certificate status:** Forward trust / untrust CA validity and distribution to endpoints.
- **Exclusions:** technical and compliance exclusions (financial, healthcare). Lists should be minimal and justified.
- **SSH decryption:** inbound SSH proxy rules for server segments, if applicable.

## Panorama-managed deployments

Panorama is the policy and configuration manager for fleets of PAN-OS firewalls. Panorama-driven audit work happens on TWO surfaces: the Panorama config itself (the central source of truth) AND the merged effective policy on each managed firewall (the deployed reality). Both must be audited; auditing only Panorama misses local-rule drift; auditing only the firewall misses pre-rule / post-rule context.

### Hierarchy primer (rule evaluation order on a managed firewall)

```
shared pre-rules
  -> device-group pre-rules (parent -> child)
    -> local rules (configured on the firewall directly)
      -> device-group post-rules (child -> parent)
        -> shared post-rules
          -> default action (interzone-default / intrazone-default)
```

A "local rule" is a rule configured on the firewall, not via Panorama. Local rules sit BETWEEN device-group pre and post rules. Operations teams sometimes inject local rules for emergency change; these MUST be audited because Panorama does not see them.

### Templates and template stacks

Panorama templates define interface, zone, log forwarding, and network configuration. Template stacks layer templates (most-specific wins). Template drift is a common audit finding: Panorama template defines one log-forwarding profile, the firewall has been hot-patched with another. Check:

```
show config pushed-shared-policy   (run on the managed firewall)
show config pushed-template        (run on the managed firewall)
```

Compare against the Panorama template stack. Drift is a deploy-checklist failure.

### Rule Impact Analysis workflow (Panorama)

When asked "can host A reach host B through Panorama-managed Palo Alto?" or "what changes if we touch this rule?", run:

1. **Resolve scope.** Identify the relevant device group and the target firewalls under it.
2. **Search policy.** Search security and NAT policies (Panorama UI: Policies; CLI: `show running security-policy` on each target firewall). Filter by source zone, destination zone, application, service, source / destination address.
3. **Resolve indirection.** Walk address objects, address groups (static and dynamic), services, application filters, application groups, and tags tied to the traffic path. A rule that references a DAG with tag-based membership has scope that changes as tagged objects are added or removed.
4. **Gate the change.** If a policy CHANGE is required, create and approve a change request (ServiceNow CR or equivalent) before any write. Per `secrets-hygiene` and `plan-time-tooling`, a state-changing Panorama push is a production-mutating operation that fires `engineering:deploy-checklist`.
5. **Verify after commit.** After the Panorama commit and push, verify commit status, push job status, and post-change traffic behaviour. Hit-count deltas on the changed rule plus traffic logs validate the outcome.

### Commit and push discipline

Panorama has THREE state-changing actions: commit (to Panorama itself); push (to managed firewalls); commit-and-push. Differences:

- **Commit only:** changes Panorama's own config. Managed firewalls are unaffected until a push happens.
- **Push only:** sends the last-committed Panorama config to managed firewalls. Affects production immediately.
- **Commit-and-push:** atomic for the operator; still serially applied per device.

Always use `validate` before commit / push when available. Always check the commit queue and recent job status after a push:

```
show jobs all
show jobs id <job-id>
```

A push that succeeds on Panorama but fails on one managed firewall is a partial-push hazard; the firewall now diverges from Panorama until the failure is resolved.

### Shared vs device-group ordering trap

A common audit finding: a shared pre-rule with `application any` + `service any` + `action allow` permits traffic that the device-group rules below it never get to evaluate. Shared pre-rules are EVALUATED FIRST and override everything below. Audit shared pre-rules with extra scrutiny; they are the most dangerous policy surface in a Panorama estate.

## Severity classification

| Finding | Severity | Rationale |
|---|---|---|
| `application any` + `action allow` + `service any` | Critical | Permits all applications on all ports; no App-ID or port restriction. |
| Shared pre-rule with `application any` + `action allow` | Critical | Shadows everything below it across the entire estate. |
| `application any` + `action allow` (specific service) | High | Bypasses App-ID on specified ports. |
| Allow rule without Security Profile Group | High | Traffic passes without AV / anti-spyware / vulnerability inspection. |
| Allow rule with incomplete profile group (missing WildFire / URL) | Medium | Partial inspection; zero-day and URL threats uninspected. |
| Disabled rule in production rulebase | Medium | Audit confusion; cleanup recommended. |
| Shadowed rule (never matches) | Medium | Dead configuration; remove or reorder. |
| Zone without zone protection profile | High | No flood, recon, or packet-based attack defence at zone boundary. |
| Decryption not enabled on internet-bound traffic | High | Encrypted traffic bypasses content inspection. |
| App-ID signatures >7 days old | Medium | Application identification accuracy degraded. |
| Rule with `any` source AND `any` destination | Medium | Overly broad scope; evaluate address narrowing. |
| Local rule injected on Panorama-managed firewall | Medium | Out-of-band change; audit required; confirm via `show config pushed-shared-policy`. |
| Template / template-stack drift between Panorama and firewall | Medium | Indicates manual hot-patch; reconcile back to Panorama. |
| Partial-push (succeeded Panorama, failed on N firewalls) | High | Estate divergence; firewalls now run different policy versions. |

### App-ID adoption maturity

| App-ID rule ratio | Maturity | Guidance |
|---|---|---|
| >80% named App-IDs | Mature | Maintain; review remaining `any` rules quarterly. |
| 50 to 80% named App-IDs | Developing | Prioritise high-traffic `any` rules for App-ID migration. |
| <50% named App-IDs | Immature | Systematic App-ID migration needed; begin with known applications. |

## Decision trees

### Overly permissive rule remediation

```
Rule has application = any
├── Also service = any?
│   ├── Yes -> CRITICAL: fully open rule
│   │   ├── Is this a temporary migration rule?
│   │   │   ├── Yes -> set expiration date, add to migration tracker, bind SPG immediately
│   │   │   └── No -> immediate remediation required
│   │   └── Identify actual applications via Traffic Log:
│   │       show log traffic rule equal <rulename>
│   │       -> Replace with specific App-IDs + service
│   └── No (specific service)
│       └── HIGH: port-restricted but App-ID bypassed
│           └── Identify applications on that port via ACC
│               -> Replace application any with observed App-IDs
│
├── Security Profile Group bound?
│   ├── No -> add SPG BEFORE narrowing App-ID (preserves threat visibility during migration)
│   └── Yes -> proceed with App-ID migration
│
├── Where does the rule live in Panorama hierarchy?
│   ├── Shared pre-rule -> blast radius is the entire estate; escalate to architecture review
│   ├── Device-group pre-rule -> blast radius is the device group
│   ├── Local rule -> blast radius is one firewall; investigate why local injection happened
│   └── Device-group / shared post-rule -> usually catch-all; verify it's intentional
│
└── Rule disabled?
    ├── Yes -> schedule removal after change window
    └── No -> active rule, proceed with analysis above
```

### Missing Security Profile Group remediation

```
Allow rule without profile-setting
├── Traffic type?
│   ├── Internet-bound -> bind full SPG (AV + Anti-Spyware + VP + URL + FB + WildFire)
│   ├── Inter-zone internal -> bind standard SPG (AV + Anti-Spyware + VP minimum)
│   ├── Intra-zone -> evaluate risk; bind Anti-Spyware + VP minimum
│   └── Management traffic -> bind Anti-Spyware + VP; URL / WildFire optional
│
├── Decrypted traffic?
│   ├── Yes -> full SPG effective; bind complete group
│   └── No -> SPG limited to metadata inspection
│       └── Evaluate adding decryption first; otherwise document the gap
│
└── Performance concern?
    ├── Session rate >100K/s -> use hardware-accelerated profiles
    └── Below threshold -> full SPG with default settings
```

## Report template (maps onto multi-vendor-network-ops nine-element contract)

```
PAN-OS SECURITY POLICY AUDIT REPORT
=====================================
Device: [hostname] | PAN-OS version: [version] | Platform: [PA-xxxx / VM-series]
Management: [standalone / Panorama device-group <name>]
Audit timestamp (UTC): [ISO-8601 Z]
Performed by: [operator / agent]

ASSUMPTIONS:
[Latest Panorama push succeeded; no in-flight change; signatures current.]

ZONE ARCHITECTURE:
- Zones configured: [n]
- Zones with protection profile: [n] / [total]
- Zone pairs with security policy: [n]

POLICY SUMMARY:
- Total security rules (effective on this device): [n]
- Allow: [n] | Deny: [n] | Drop: [n]
- Rules with SPG bound: [n] / [allow count]
- App-ID adoption: [%] of allow rules use named App-IDs

PANORAMA HIERARCHY (managed devices only):
- Shared pre-rules: [n] | Device-group pre-rules: [n]
- Local rules: [n] | Device-group post-rules: [n] | Shared post-rules: [n]
- Last successful push job ID: [id] | Partial-push status: [none / N firewalls failed]
- Template stack: [name] | Drift detected: [yes / no]

DECRYPTION COVERAGE:
- Zone pairs with SSL Forward Proxy: [list]
- Estimated encrypted traffic inspected: [%]
- Exclusion categories: [n]

EVIDENCE: [show command output, XML API extracts, Panorama job IDs attached]

FINDINGS (per row in severity order):
[Severity] [Category] -- [Description]
Rule: [name] | Hierarchy slot: [shared pre / DG pre / local / DG post / shared post]
Zone Pair: [from-zone] -> [to-zone]
Issue: [problem] -> Recommendation: [remediation]

PRE-CHECKS proposed (read-only): [list]
EXECUTION (state-changing) proposed: [list, with backout point per item]
POST-CHECKS proposed: [list, including hit-count delta verification]
ROLLBACK: [Panorama commit revert ref or per-firewall revert step]
ESCALATION: [name + contact, sourced from config; never invented]

NEXT AUDIT: CRITICAL findings -> 30 d, HIGH -> 90 d, clean -> 180 d.
```

## Common failure modes

- **Auditing Panorama in isolation:** misses local-rule drift on managed firewalls. Always cross-check with `show running security-policy` on each firewall.
- **Auditing the firewall in isolation:** misses pre-rule / post-rule context. The local rulebase is sandwiched between Panorama-pushed rules.
- **Large rulebases (>500 rules):** export via XML API for programmatic analysis. Prioritise by hit count; rules with zero hits in 90 days are cleanup candidates (cross-check with `acl-rule-analysis` staleness bands).
- **Dynamic Address Groups (DAG) shifting effective scope:** rules referencing DAGs with tag-based membership change as objects are tagged / untagged. Document the DAG snapshot at audit time via `show object dynamic-address-group all`.
- **GlobalProtect and Captive Portal zones:** GP VPN users and CP-authenticated sessions enter zones differently from interface traffic. Verify policies cover GP tunnel zones and User-ID is functioning for identity-based rules.
- **Content update failures:** if App-ID or Threat Prevention signatures are outdated, findings may not reflect the current threat landscape. Verify via `show system info | match content` and `show jobs processed`. Resolve update failures before finalising the report.
- **Partial-push left unresolved:** the estate runs different policy versions. Resolve before further changes.

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the PAN-OS specialist. Apply the nine-element response contract to every state-changing Panorama push.
- `acl-rule-analysis` -- vendor-agnostic ACL methodology, hit-count staleness bands, severity-pattern catalogue. Run first for cross-vendor estate work, then this skill for the PAN-OS deep-dive.
- `cisco-firewall-audit`, `fortigate-firewall-audit` -- sibling Stage 3 specialists; sequence vendor-by-vendor when auditing a mixed estate.
- `vpn-tunnel-troubleshooting` -- IPsec / DMVPN / WireGuard deep-dive; the PAN-OS GlobalProtect + IKE-side state-machine analysis lives there.
- `bgp-analysis`, `igp-routing-analysis` -- when a firewall change risks routing convergence (e.g. large policy push on a transit firewall), pause and run those skills first.
- `pyats-network-automation` -- Genie parsers exist for some PAN-OS show output; useful for fleet automation around the audit.
- `secrets-hygiene` -- API keys, GlobalProtect group passwords, Panorama service-account passwords, Content-update credentials all fall under the patterns there.
- `completion-gate` Layer 3 -- every state-changing Panorama push requires fresh post-check evidence (commit-status verified, push-job ID recorded, hit-count delta confirmed) before claiming "policy deployed".
- `plan-time-tooling` -- every state-changing audit recommendation fires `engineering:deploy-checklist` at plan time.
- `systematic-debugging` -- Phase 1 boundary evidence (which zone pair, which rule line, which DG layer, which DAG tag) before any change.
- `oncall-runbooks` -- incident classification when audit findings overlap with active incidents.

## Red flags (about-to-act warnings)

- About to push to a Panorama estate without `validate` first.
- About to push to a Panorama estate during business hours without explicit change-window approval.
- About to add a `application any` + `service any` rule to shared pre-rules.
- About to delete a rule with non-zero hit count without identifying the traffic source.
- About to enable SSL decryption on a zone pair without certificate distribution to endpoints (will break TLS for users).
- About to extend GlobalProtect tunnel scope without User-ID coverage check.
- About to commit on Panorama without checking commit queue.
- About to ignore a partial-push failure ("just retry later").
- About to inject a local rule on a Panorama-managed firewall as an emergency change without immediate Panorama-side reconciliation plan.

## Bottom line

Audit the PAN-OS architecture, not just the rules. The architecture is zones plus App-ID plus Security Profile Groups plus zone protection plus decryption, with Panorama layering shared and device-group pre and post rules around the local rulebase. Diagnose-first via read-only `show` and the `test security-policy-match` harness; audit BOTH Panorama and the deployed firewalls; map every state-changing recommendation onto the nine-element response contract. Severity rankings drive remediation cadence (CRITICAL 30 d, HIGH 90 d, clean 180 d). Local rules and partial-pushes are the most common audit smells; check both first.
