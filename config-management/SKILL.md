---
name: config-management
description: "Use for network device configuration assurance on Cisco (IOS-XE / NX-OS), Juniper (JunOS) and Arista (EOS): config backup and archive freshness, running versus startup comparison, golden-config baselines, section-by-section drift detection, required and forbidden pattern compliance, and drift remediation guidance. Triggers include \"config drift\", \"golden config\", \"configuration backup\", \"config archive\", \"unsaved changes\", \"running vs startup\", \"unauthorised change\", \"config compliance audit\", \"required and forbidden config patterns\", \"telnet or SNMPv2 still enabled\", \"configure replace\", \"JunOS rollback\", \"config diff noise\", \"normalise config before diff\". Ongoing assurance, not a single change event. NOT for the before-and-after verification of one change window (change-verification), NOT for pyATS test and rollback code (pyats-network-automation), NOT for reconciling devices against a NetBox or Nautobot record (network-source-of-truth), NOT for firewall rulebase hygiene (acl-rule-analysis and the firewall audit skills)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Configuration management

> **Skill marker**: When applying this skill, begin your reply with `[skill: config-management]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Ongoing configuration assurance for network devices: back up, detect drift, validate against a golden baseline and a compliance rule set. It finds unauthorised or unintended change by comparing what a device is running with what it should be running, and tells you how serious each difference is.

Commands are labelled **[Cisco]**, **[JunOS]** or **[EOS]** where syntax diverges; unlabelled statements apply to all three. Syntax was written from vendor documentation and was not run against devices while authoring, so confirm it on the release and platform you operate. Command syntax by task is in `references/cli-reference.md`; normalisation rules, compliance patterns, the severity matrix and drift scoring are in `references/drift-detection.md`.

**Posture.** Steps 1, 2, 4, 5 and 6 are read-only and safe at any time. Steps 3 (archival to remote storage) and 7 (remediation) may write to a device or a file store and are marked **WRITE**. Confirm authorisation and that no maintenance window explains the drift before a **WRITE** step.

## When to use

- A scheduled compliance audit against golden baselines.
- Investigating a suspected unauthorised or forgotten configuration change.
- Post-maintenance proof that the running config was saved to startup.
- Checking consistency across a device group, role or stack.
- Checking that mandated patterns (AAA, NTP, syslog, SSH-only management) are present and forbidden ones (telnet, default credentials, SNMPv1 or v2c without an ACL) are absent.
- Building or refreshing a configuration archive before a change window.
- Periodic drift detection as operational hygiene, daily or weekly.

## When not to use

- **One change window, before and after:** use `change-verification`. It captures a baseline for that event and decides accept or roll back; this skill is what you run between events.
- **Writing the automation:** `pyats-network-automation` (its configuration-management section is a five-stage change-with-rollback workflow), `napalm-netmiko` (config get, diff, replace), `nornir-automation`, `ansible-network-modules` (resource modules). This skill defines what to check and how to grade it, not how to script it.
- **Device versus intended-state record (IPs, VLANs, cables):** `network-source-of-truth`. This skill compares a device with a golden text baseline; that one compares it with a source-of-truth object model.
- **Firewall rulebase review** (shadowed rules, any-any, unused objects): `acl-rule-analysis` and the per-vendor firewall audit skills.
- **MikroTik, Nokia and other platforms:** the vendor syntax here covers Cisco, JunOS and EOS only; `multi-vendor-network-ops` and `mikrotik-routeros` cover the rest.

## Prerequisites

- SSH or console access (read-only is enough for assessment; configure privilege for archival and remediation).
- A golden baseline for the device role, or a previous archived config to compare against. Step 4 explains how to establish one.
- The organisation's compliance rules: required services, forbidden protocols, mandatory security features.
- For archival: a reachable SCP, TFTP or FTP target, or local flash space.
- Awareness of any active maintenance window that explains expected drift.
- Cisco commands are shown for IOS-XE. On NX-OS use `bootflash:` as the file system and `checkpoint [name]` with `rollback running-config checkpoint [name]` in place of `configure replace`.
- Credentials handled per `secrets-hygiene`. Treat an archived config as a secret: it can hold password hashes, community strings and keys. Store archives with restricted access, redact before quoting, and never paste a raw config into a ticket or chat.

## Procedure

### Step 1: Config collection

Capture the running and the saved configuration.

- **[Cisco]** `show running-config`, `show startup-config`
- **[JunOS]** `show configuration | display set`
- **[EOS]** `show running-config`, `show startup-config`

JunOS uses a candidate and commit model: `show configuration` is the committed (active) config, and uncommitted candidate edits appear only under `show | compare`. See `references/cli-reference.md` for the architectural differences.

### Step 2: Running versus startup comparison

Find unsaved changes, meaning running config that would be lost on reload.

- **[Cisco]** `show archive config differences system:running-config nvram:startup-config`
- **[JunOS]** `show | compare` in configuration mode (candidate against active). JunOS has no separate startup config, so the equivalent risk is an uncommitted candidate or a pending `commit confirmed` (see `show system commit`).
- **[EOS]** `show running-config diffs`

Any difference is an unsaved change. Record the diff and a timestamp, then grade the age with the unsaved-change table below. If it is intentional (live maintenance), note the ticket.

### Step 3: Config archival

**WRITE**: back up the current configuration with a timestamped name.

- **[Cisco]** `copy running-config scp://[user]@[server]/[hostname]-YYYYMMDD-HHMM.cfg`
- **[JunOS]** `show configuration | save /var/tmp/[hostname]-YYYYMMDD-HHMM.conf`
- **[EOS]** `copy running-config flash:[hostname]-YYYYMMDD-HHMM.cfg`

Use one naming scheme, `{hostname}-{YYYYMMDD}-{HHMM}.cfg`, in UTC. Verify the write by size and by comparing a hash of the backup with the running config. Keep at least three archives per device so a rollback has options. Use SCP, not TFTP: TFTP carries the config, with its secrets, in clear text. The JunOS and EOS commands above save on the device; copy the file off-box with `file copy /var/tmp/[file] scp://[user]@[server]/[path]` (JunOS) or `copy flash:[file] scp://[user]@[server]/[path]` (EOS).

### Step 4: Golden config baseline

Get the golden (intended-state) config for the device's role: access switch, core router, WAN edge, and so on.

If none exists, establish one:

1. Start from a known-compliant device.
2. Replace device-specific values with tokens (hostname, management IP, loopback, interface descriptions, SNMP location; the token table is in `references/drift-detection.md`).
3. Keep every compliance-mandated section (AAA, NTP, logging, SNMP, ACLs).
4. Record the golden version and approval date.

Normalise both sides before diffing, or the diff will be dominated by generated lines.

### Step 5: Drift detection

Compare the current config with the golden baseline section by section. Split each config into five functional sections so drift lands in a domain you can grade:

| Section | Cisco examples | JunOS examples | EOS examples |
|---|---|---|---|
| Routing | `router bgp`, `router ospf` | `protocols` | `router bgp`, `router ospf` |
| Switching | `spanning-tree`, `vlan` | `vlans`, `protocols rstp` | `spanning-tree`, `vlan` |
| Security | `access-list`, `line vty` | `firewall`, `system login` | `ip access-list`, `management` |
| Management | `logging`, `ntp`, `snmp` | `system syslog`, `system ntp` | `logging`, `ntp`, `snmp-server` |
| Services | `ip dhcp`, `ip nat` | `forwarding-options` | `ip dhcp`, `ip nat` |

For each section list additions, deletions and modifications, and grade each with the severity table. Sort set-format lines only inside blocks where order does not matter (interfaces, system services). Never sort order-sensitive structures such as firewall filter terms, policy-statement terms, ACLs or route-maps: compare those in order, because a reordering there is real drift.

### Step 6: Compliance validation

Check required and forbidden patterns.

**Required (must be present):** AAA authentication active; NTP to authorised sources; syslog to central collectors; SNMP restricted by ACL; management over SSH only.

**Forbidden (must be absent):** default credentials; telnet or plain HTTP management; SNMPv1 or v2c without a source ACL; VTY access with no ACL; DHCP snooping or ARP inspection disabled on access ports.

The full rule set with per-vendor patterns (REQ-001 onwards, FRB-001 onwards) is in `references/drift-detection.md`. The same requirement is written differently per vendor (disabling telnet is `transport input ssh` on Cisco VTY lines, `delete system services telnet` on JunOS, `no management telnet` on EOS), so match on the vendor's own pattern.

### Step 7: Remediation guidance

**WRITE**: address drift according to severity.

- **Critical (routing, security):** check whether the change was authorised. If not, prepare a rollback to the last known-good config. **[Cisco]** `configure replace flash:[backup].cfg force`; **[JunOS]** `rollback [n]` then `commit`; **[EOS]** `configure replace flash:[backup].cfg`.
- **Warning (management plane, logging):** record the deviation and schedule the fix for the next window; apply missing lines incrementally.
- **Info (cosmetic):** log it and fix opportunistically.

After any remediation repeat Steps 1 and 2 to confirm the config matches intent, then save the corrected running config to startup (**[Cisco]**, **[EOS]** `copy running-config startup-config`; **[JunOS]** `commit`). For a planned, permanent change that created the drift, update the golden baseline instead of reverting.

## Threshold tables

### Drift severity by section

| Section | Severity | Rationale |
|---|---|---|
| Routing (BGP, OSPF, static) | Critical | Direct traffic impact, possible outage |
| Security (ACLs, AAA, CoPP) | Critical | Exposure to unauthorised access |
| Switching (STP, VLANs) | High | Loop risk, VLAN leakage |
| Management (logging, NTP, SNMP) | Warning | Loss of operational visibility |
| Services (DHCP, NAT) | Warning | Service-level impact, no network-wide risk |
| Cosmetic (descriptions, banners) | Info | No operational impact |

### Unsaved change age

| Age | Severity | Action |
|---|---|---|
| under 1 hour | Info | Probably live maintenance; confirm with the operator |
| 1 to 4 hours | Warning | Check whether a window is open |
| 4 to 24 hours | High | Likely a forgotten save; save or revert |
| over 24 hours | Critical | At high risk of loss on reload; save or revert now |

### Archive freshness

| Last archive | Status | Action |
|---|---|---|
| under 7 days | Current | None |
| 7 to 30 days | Stale | Schedule a refresh |
| 30 to 90 days | Warning | Archive before any change |
| over 90 days | Critical | Archive immediately |

The severity-by-change-type matrix, the escalation triggers and the drift score thresholds are in `references/drift-detection.md`. Treat all of these as defaults; a local policy that states different ages wins.

## Decision trees

### Drift detected

```
Drift between running config and golden baseline
├── Classify the section
│   ├── Routing or security: Critical
│   ├── Switching: High
│   ├── Management or services: Warning
│   └── Cosmetic: Info
├── Check authorisation
│   ├── A change ticket covers this device and window
│   │   ├── Permanent: update the golden baseline
│   │   └── Temporary: record as an accepted deviation
│   ├── No ticket
│   │   ├── Critical or High: escalate and prepare a rollback
│   │   └── Warning or Info: document and schedule a fix
│   └── Cannot tell: treat as unauthorised and notify the operator
└── Remediation path
    ├── A fresh archive exists: config replace (Step 7)
    └── None: manual remediation
        └── Afterwards re-run Steps 1 to 6
```

### Running differs from startup

```
Running config differs from startup config
├── A maintenance window is active
│   └── Expected; remind the operator to save when it ends
└── No window
    ├── Under 1 hour: possibly a recent change, ask the operator
    ├── 1 to 24 hours: likely a forgotten save; save or revert
    └── Over 24 hours: critical; save or revert, then archive
Cannot determine the age
└── Look at the last-change timestamp
    ├── [Cisco] show running-config | include Last config
    ├── [JunOS] show system commit
    └── [EOS] show logging | include CONFIG_I
```

### Compliance violation

```
Required pattern missing or forbidden pattern present
├── Severity
│   ├── AAA missing, default credentials, telnet: Critical
│   ├── Syslog or NTP missing: Warning
│   └── Banner missing: Info
├── Fix type
│   ├── Additive (add an NTP server): generate a snippet, apply in a window
│   ├── Removal (remove telnet, remove default credentials): check dependencies first
│   └── Structural (enable AAA, rework SNMP): manual review under a change request
└── Record the violation in the compliance report
```

## Report template

```
CONFIGURATION MANAGEMENT REPORT
=================================
Device: [hostname]
Vendor: [Cisco | JunOS | EOS]
Role: [access-switch | core-router | WAN-edge | ...]
Check time (UTC): [timestamp]
Performed by: [name or team]
Golden config version: [version and date]

SAVED STATE
- Running vs startup: [match | differs]
- Unsaved change age: [duration or n/a]
- Last archive: [date]
- Archive freshness: [current | stale | warning | critical]

DRIFT SUMMARY
- Sections checked: [n]
- Deviations: [n]  (Critical [n], High [n], Warning [n], Info [n])
- Drift score: [n]

DRIFT FINDINGS
1. [Severity] [Section]: [description]
   Golden:  [expected line or block]
   Current: [actual line or block]
   Authorisation: [ticket | unauthorised | unknown]
   Action: [rollback | schedule fix | accept | update baseline]

COMPLIANCE
- Required patterns present: [n of total]
- Forbidden patterns found: [n]
- Violations: [list]

REMEDIATION
- [Prioritised actions with target window]

NEXT CHECK: [Critical 4 h | High 8 h | Warning 24 h | Healthy 7 d]
```

## Troubleshooting

### The diff is full of false positives

Generated lines (timestamps, certificate hashes, build strings, auto-tuned values such as `ntp clock-period`) change between captures without being drift. Normalise both configs first, using the per-vendor rules in `references/drift-detection.md`.

### JunOS candidate confusion

`show configuration` shows the committed config. Uncommitted candidate changes do not affect the running device but take effect on the next commit. Before reporting drift on a JunOS box, check `show | compare` for a pending candidate.

### Archive transfer fails

Typical causes: an ACL blocking outbound SCP or TFTP, a name that does not resolve, SCP authentication failure, or no space on flash. Ping the target first, check credentials, and check free space with `dir flash:` (Cisco, EOS) or `file list /var/tmp/` (JunOS).

### A very large config overwhelms the diff

Configs past about 10,000 lines produce diffs nobody reads. Compare one functional section at a time in severity order, and sort order-insensitive blocks before diffing to remove positional noise, and never sort ACLs, route-maps or policy terms.

### The same requirement matches differently per vendor

Use the vendor-specific pattern for each rule in `references/drift-detection.md` rather than one regex for all three, or you will miss real violations and flag compliant devices.

## Cross-references

- `change-verification`: the per-event sibling. A permanent change it accepts should update the golden baseline here; an unauthorised change found here is a candidate for its rollback procedure.
- `completion-gate` Layer 3: no claim that drift is "fixed" or a device "compliant" without a fresh collection and diff in the same turn.
- `pyats-network-automation`, `napalm-netmiko`, `nornir-automation`, `ansible-network-modules`: the tools that automate collection, diff and replace at fleet scale. Run the checks here through them, and keep device writes behind the same authorisation.
- `network-source-of-truth`: the intended-state record for addressing, VLANs and links. Golden config answers "does the text match the template"; that skill answers "does the device match the model".
- `acl-rule-analysis` and the firewall audit skills (`fortigate-firewall-audit`, `palo-alto-firewall-audit`, `cisco-firewall-audit`, `checkpoint-firewall-audit`): the rulebase view of the security section.
- `multi-vendor-network-ops`: the diagnose-first entry point and the nine-element response contract for any production-impacting remediation.
- `secrets-hygiene`: archived configs and diffs contain secrets; redact before sharing.
- `utc-timestamps`: archive names and report times are UTC.

## Red flags

- About to **WRITE** (archive to a server, `configure replace`, rollback) without confirming authorisation and that no window explains the drift.
- About to diff without normalising generated lines, then reporting the noise as drift.
- About to report a JunOS device as clean without checking for an uncommitted candidate.
- About to quote a config, diff or archive into a ticket or chat without redacting secrets.
- About to treat an unauthorised-looking change as authorised because nobody objected; if the ticket cannot be found, the drift is unauthorised until someone says otherwise.
- About to revert drift that came from a permanent, approved change instead of updating the baseline.
- About to apply a structural fix (enabling AAA, reworking SNMP) as an auto-remediation; those go through a change request.
- About to call a device compliant from a collection made in an earlier turn.

## Bottom line

Collect, compare, grade, then act. Normalise before you diff, grade by section so routing and security drift outranks cosmetics, treat unsaved change as a risk with an age, and keep every archive as sensitive as the config it holds. Drift is either corrected or accepted into the baseline; it is never left as an unexplained difference.

## Provenance

Re-authored from the Apache-2.0 `config-management` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; vendor commands, thresholds, decision trees and compliance rule set kept; secrets handling and cross-references added for this vault.
