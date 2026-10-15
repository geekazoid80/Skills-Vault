---
name: change-verification
description: "Use for pre-change and post-change verification of a network change window on Cisco (IOS-XE / NX-OS), Juniper (JunOS) or Arista (EOS) devices: baseline capture, change-scope documentation, safe execution patterns, post-change diff, impact classification and the accept-or-roll-back decision. Triggers include \"change window\", \"maintenance window verification\", \"pre-change baseline\", \"post-change check\", \"before and after comparison\", \"did the change work\", \"should we roll back\", \"rollback criteria\", \"software upgrade verification\", \"SFP or linecard replacement check\", \"circuit turn-up verification\", \"soak period\", \"commit confirmed\", \"configure session\", \"configure replace\". Covers ONE change event from before to after. NOT for ongoing config drift or golden-config compliance (config-management), NOT for protocol diagnosis of a failed adjacency (bgp-analysis, igp-routing-analysis, evpn-vxlan-fabric), NOT for pyATS test code (pyats-network-automation), NOT for the generic done-claim gate (completion-gate)."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Change verification

> **Skill marker**: When applying this skill, begin your reply with `[skill: change-verification]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Event-driven verification for a single network change window. It guides baseline capture before the change, safe execution patterns during it, a structured diff afterwards, and a rollback decision when something unexpected moves. The unit of work is one change event (before, during, after), not the device's long-term state.

Commands are labelled **[Cisco]**, **[JunOS]** or **[EOS]** where syntax diverges; unlabelled statements apply to all three. Syntax was written from vendor documentation and was not run against devices while authoring, so confirm it on the release and platform you operate. Command syntax by phase is in `references/cli-reference.md`; per-change-type checklists and the rollback decision matrix are in `references/checklist-templates.md`.

**Posture.** Baseline capture (Step 1 reads), diff analysis and impact assessment (Steps 4 and 5) are read-only and safe at any time. Steps that write to a device are marked **WRITE**: the config archive in Step 1, execution in Step 3 and rollback in Step 6. Confirm an approved change ticket and an open maintenance window before any **WRITE** step, and never run one from this skill on your own initiative.

## When to use

- A planned maintenance window that needs structured pre and post verification.
- A configuration change (routing policy, ACLs, interface config) with a rollback plan.
- A software upgrade or patch that needs before and after state comparison.
- A hardware replacement (linecard, SFP, PSU) that needs service validation.
- A circuit turn-up or decommission that needs adjacency and traffic verification.
- An emergency change that needs fast baseline capture and rollback readiness.
- A post-change soak period with periodic re-verification against the baseline.

## When not to use

- **Ongoing drift, backup freshness or compliance against a golden config:** use `config-management`. This skill ends when the change is accepted or rolled back.
- **A peer or adjacency that will not come back and needs protocol reasoning:** hand over to `bgp-analysis`, `igp-routing-analysis` or `evpn-vxlan-fabric` once Step 5 has classified it as unexpected.
- **Writing the automation that runs the checks:** `pyats-network-automation` (its configuration-management section is the pyATS form of this lifecycle), `napalm-netmiko`, `nornir-automation` or `ansible-network-modules`.
- **A generic "is it done" claim outside network devices:** `completion-gate` Layer 3 applies to every claim; this skill supplies the network evidence for it.
- **Entry point for general network work, or the nine-element response contract:** `multi-vendor-network-ops`.

## Prerequisites

- SSH or console access to every device in the change scope (read-only for baselines; configure privilege for execution and rollback).
- An approved change ticket with scope, expected impact and a rollback plan that carries timing criteria.
- A named list of devices and interfaces in scope, and knowledge of what is expected to move (routes, bounced interfaces, flapping adjacencies).
- A place to archive baselines (device flash, an SCP server or local disk).
- An escalation contact for the moment a rollback criterion is met.
- Credentials handled per `secrets-hygiene`: never paste device passwords or tokens into the conversation, and redact secrets in any captured config before it is quoted.
- Treat baselines and archives as sensitive: they hold password hashes and community strings. Restrict access, and redact before quoting.
- Cisco commands are shown for IOS-XE. On NX-OS use `bootflash:` as the file system and `checkpoint [name]` with `rollback running-config checkpoint [name]` in place of `configure replace`.
- Per-change-type prerequisites are in `references/checklist-templates.md`.

## Procedure

Run the steps in order for each change event. Steps 1 and 2 happen before anything changes, Step 3 is the change, Steps 4 to 6 decide whether it stands.

### Step 1: Pre-change baseline capture

Capture state snapshots before any change and store them with timestamps. Use exactly the commands you will re-run in Step 4.

**Routing state**

- **[Cisco]** `show ip route summary`, `show ip bgp summary`, `show ip ospf neighbor`
- **[JunOS]** `show route summary`, `show bgp summary`, `show ospf neighbor`
- **[EOS]** `show ip route summary`, `show ip bgp summary`, `show ip ospf neighbor`

**Interface and adjacency state**

- **[Cisco]** `show interfaces summary`, `show cdp neighbors`, `show ip arp`
- **[JunOS]** `show interfaces terse`, `show lldp neighbors`, `show arp no-resolve`
- **[EOS]** `show interfaces status`, `show lldp neighbors`, `show ip arp`

**Configuration and hardware**

- **[Cisco]** `show running-config`, `show environment all`, `show inventory`
- **[JunOS]** `show configuration`, `show chassis environment`, `show chassis hardware`, `show system commit` (record the latest commit index for Step 6)
- **[EOS]** `show running-config`, `show environment all`, `show inventory`

**WRITE**: archive the baseline config to persistent storage.

- **[Cisco]** `copy running-config flash:pre-change-[ticket]-[date].cfg`
- **[JunOS]** `show configuration | save /var/tmp/pre-change-[ticket].conf`
- **[EOS]** `copy running-config flash:pre-change-[ticket]-[date].cfg`

Record the headline numbers for later comparison: total route count (IPv4 and IPv6), BGP peers Established, OSPF neighbours Full, notable interface error counters and hardware sensor readings. Note the wall-clock time of capture so syslog can be correlated afterwards.

### Step 2: Change scope documentation

Before executing, write down:

1. **Change description:** the configuration lines added, modified or removed.
2. **Expected impact:** which peers flap, which routes shift, which interfaces bounce, and for how long.
3. **Rollback trigger criteria:** the specific thresholds that mandate rollback (see Threshold tables).
4. **Rollback procedure:** the exact commands to revert (`references/cli-reference.md`).
5. **Success criteria:** what "done" looks like: baselines restored, intended changes visible, no unexpected deviation.
6. **Soak period:** how long to observe before declaring success.

A change with no written rollback trigger has no rollback decision, only an argument at 3am.

### Step 3: Change execution

**WRITE**: apply the change with the safest pattern the platform offers.

- **[Cisco]** IOS and IOS-XE have no per-line commit-confirm, but a timed replace gives the same safety net: `configure replace flash:[file] time [minutes]` reverts on its own unless you run `configure confirm`, and `reload in [minutes]` (cancel with `reload cancel`) is the blunt fallback. On NX-OS use `configure session` and a `checkpoint`. For bulk changes prepare a full file and use `configure replace`.
- **[JunOS]** Use `commit confirmed [minutes]` so the device rolls itself back if you lose it, then `commit` to confirm after verification.
- **[EOS]** Use `configure session change-[ticket]`, review with `show session-config`, then `commit`.

**Multi-device changes** go in stages: apply to one device, run Step 4 against it, and continue only after it passes every check.

**Security changes** (AAA, ACLs on management or VTY lines) carry the highest risk of locking yourself out. Keep a second session or console path open and prefer commit-confirm or a timed replace. The loss of management access may not be reversible without physical console access.

### Step 4: Post-change verification

Re-run every Step 1 capture with identical commands and diff against the baseline.

| Metric | Compare against | Expected outcome |
|---|---|---|
| Route count | Pre-change summary | Within the deviation threshold |
| BGP peers Established | Pre-change peer list | All restored, or changed per plan |
| OSPF neighbours Full | Pre-change neighbour list | All adjacencies restored |
| Interface errors | Pre-change counters | No new sustained errors |
| Config diff | Archived pre-change config | Only intended lines changed |

Config diff commands:

- **[Cisco]** `show archive config differences flash:pre-change-[ticket]-[date].cfg system:running-config`
- **[JunOS]** `show | compare rollback [N]` in configuration mode, where N is the pre-change commit index recorded in Step 1
- **[EOS]** `diff running-config flash:pre-change-[ticket]-[date].cfg`

Read every line of the diff and label it **expected** (part of the plan) or **unexpected** (not in scope). Ignore generated noise such as timestamps and build strings, but say that you ignored it.

### Step 5: Impact assessment

Sort every deviation into one of four classes:

1. **Expected, intended:** the goal of the window (a new peer appears, an old ACL disappears). No action.
2. **Expected, side effect:** caused by the intended change but not its goal (route count rises because a new peer advertises). Confirm it is benign.
3. **Unexpected, minor:** unrelated and low severity (a single counter increment). Investigate; do not necessarily roll back.
4. **Unexpected, critical:** collateral damage (an adjacency lost on an unrelated interface, a route withdrawn outside the plan). Go straight to Step 6.

### Step 6: Rollback decision

**Roll back if any of these hold:**

- A service-affecting outage on interfaces or peers outside the change scope.
- Route count deviates past the threshold and the routes are not accounted for in the plan.
- Adjacency loss persists beyond the expected convergence window.
- Hardware errors (PSU, fan, temperature) appear that were absent from the baseline.
- The change did not achieve its intended effect (Step 2 success criteria not met).

**Accept only if all of these hold:** every success criterion is met, the diff contains only expected lines, every baseline metric is within threshold, no unexpected critical deviation exists, and the soak period has elapsed without regression.

**WRITE**: rollback.

- **[Cisco]** `configure replace flash:pre-change-[ticket]-[date].cfg force`
- **[JunOS]** `rollback [N]` then `commit`, where N is the pre-change commit index from Step 1 (not always 1: a confirming `commit` adds an entry)
- **[EOS]** `configure replace flash:pre-change-[ticket]-[date].cfg`

After any rollback, repeat Step 4 to prove the device is back at its pre-change state. A rollback that is not verified is a second unverified change.

## Threshold tables

### Acceptable deviation

| Metric | Normal | Warning | Rollback trigger |
|---|---|---|---|
| IPv4 route count | within 2% of baseline | within 5% | over 10% or unplanned loss |
| IPv6 route count | within 2% of baseline | within 5% | over 10% or unplanned loss |
| BGP Established peers | 0 lost (unless planned) | 1 lost, in scope | 1 or more lost outside scope |
| OSPF Full adjacencies | 0 lost (unless planned) | flap then recover in under 2 min | lost for over 2 min |
| New interface errors | 0 new CRC or input errors | under 10 in the first 5 min | sustained over 10 per minute |
| Interface flaps | 0 (unless a planned bounce) | 1 flap on an in-scope interface | any flap outside scope |

These are starting points. A change ticket that states different numbers for a specific device wins over this table.

### Timing

| Phase | Maximum | Action if exceeded |
|---|---|---|
| Change execution | per the change ticket | pause and escalate |
| Post-change convergence | 5 min | begin rollback assessment |
| Adjacency re-establishment | 2 min per peer | escalate if the peer is critical |
| Route table stabilisation | 3 min | check for route oscillation |
| Soak, minor change | 15 min | declare success or investigate |
| Soak, major change | 60 min | declare success or investigate |
| Rollback execution | 5 min | escalate to a senior engineer |

## Decision trees

### Post-change diff contains unexpected lines

```
Config diff shows unexpected changes
├── Lines are in sections RELATED to the change scope
│   ├── Side effect of the intended change (an auto-generated route-map sequence)
│   │   └── Expected, side effect: document and accept
│   └── Unintended consequence (the wrong interface was touched)
│       └── Unexpected, critical: evaluate rollback
└── Lines are in sections UNRELATED to the change scope
    ├── Timestamps, counters or cosmetic lines
    │   └── Expected, side effect: ignore, and say so
    └── Substantive config (an ACL modified, a route-map added)
        └── Unexpected, critical: immediate rollback
```

### Adjacency loss after the change

```
Neighbour or peer no longer in the expected state
├── The device IS in the change scope
│   ├── The interface was bounced on purpose
│   │   ├── Recovers inside the timing threshold: expected, record the time
│   │   └── Does not recover: check interface state, cable, peer config
│   └── The interface was NOT bounced on purpose
│       └── Unexpected, critical: look for a config error, roll back if unresolved
└── The device is NOT in the change scope
    ├── The peer sits on an in-scope device (far-end impact)
    │   └── Expected side effect: confirm it recovers inside the threshold
    └── The peer sits on an unrelated device
        └── Unexpected, critical: a separate failure, investigate on its own
```

### Route count outside the normal band

```
Route count differs from baseline by more than 2%
├── The plan adds or removes prefixes
│   ├── Direction matches the plan: expected, verify the exact prefixes
│   └── Direction opposes the plan: unexpected, critical, check the routing process and peer state
├── The plan has NO routing change
│   ├── Under 5% and from in-scope peers: warning, likely convergence, monitor 3 min
│   ├── 5 to 10%, or from out-of-scope sources: unexpected, investigate now
│   └── Over 10% or any unplanned loss: unexpected, critical, evaluate rollback
└── Count is oscillating
    └── Unexpected, critical: loop or flapping, immediate rollback
```

## Report template

```
# Change verification report: [ticket ID]

## Change summary
- Ticket: [ID]
- Start / end (UTC): [timestamps]
- Devices: [list]
- Change type: [routing | switching | security | upgrade | other]
- Executed by: [name or team]

## Pre-change baseline
- Route count (IPv4 / IPv6): [count]
- BGP peers Established: [count]
- OSPF adjacencies Full: [count]
- Notable interface errors: [any]
- Config archived to: [location]

## Execution
- Method: [manual | commit-confirm | session | replace]
- Duration: [minutes]
- Issues: [none | description]

## Post-change verification
- Route count (IPv4 / IPv6): [count] (change [delta])
- BGP peers Established: [count] (change [delta])
- OSPF adjacencies Full: [count] (change [delta])
- New interface errors: [count]
- Config diff lines: [expected N, unexpected N]

## Impact assessment
- Expected, intended: [list]
- Expected, side effect: [list]
- Unexpected, minor: [list or none]
- Unexpected, critical: [list or none]

## Decision
- Result: [ACCEPTED | ROLLED BACK | ESCALATED]
- Rationale: [reason]
- Soak: [duration and outcome]

## Action items
- [ ] [follow-up]
```

## Troubleshooting

### Baseline capture returns incomplete output

- Long outputs can be truncated by a terminal buffer. Set `terminal length 0` (**[Cisco]**, **[EOS]**) or `set cli screen-length 0` (**[JunOS]**) before capture.
- High CPU causes CLI timeouts. Check `show processes cpu` (**[Cisco]**), `show system processes extensive` (**[JunOS]**) or `show processes top` (**[EOS]**).
- If archiving to remote storage fails, save to local flash and record where it went.

### The config diff is mostly noise

- Filter timestamp and comment lines that change on every display (`! Last configuration change at ...`).
- On **[JunOS]**, `show | compare rollback [N]` (configuration mode) gives a clean structured diff. On **[Cisco]**, `show archive config differences` can report line-order differences that are not real changes.
- Use the per-change-type checklist in `references/checklist-templates.md` to focus on the sections the change could affect.

### An adjacency does not recover after an expected bounce

- Check interface state: `down/down` is physical, `up/down` is protocol.
- Confirm the peer accepted its half of the change: a mismatched OSPF area or BGP ASN on one end prevents the adjacency.
- Wait one full timer cycle before escalating: OSPF dead interval is 40 s by default; BGP hold time is commonly 180 s on Cisco and 90 s on JunOS.

### The rollback command fails or leaves an odd state

- **[Cisco]** `configure replace` needs the archive feature enabled; without it, reverse the lines by hand.
- **[JunOS]** `rollback N` fails if the commit history was cleared or the device rebooted since the baseline commit; list the points with `show system commit`.
- **[EOS]** `configure replace` needs a complete configuration file, not a fragment; confirm the archive is a full `show running-config` capture.
- Always repeat Step 4 afterwards.

### The window closes before verification finishes

- Check routing adjacencies and interface state first and defer the detailed diff if services are healthy.
- If the soak is shortened, record the reduced observation window and schedule a follow-up check.
- Do not delay a rollback because the window has closed while service is degraded.

## Cross-references

- `config-management`: the sibling for ongoing drift, archive freshness and golden-config compliance. After an accepted change, update the golden baseline there if the change is permanent.
- `completion-gate` Layer 3: no "change applied" or "change verified" claim without fresh post-check evidence in the same turn. This skill is the network-device form of that rule; do not restate it, apply it.
- `pyats-network-automation`: automates baseline capture and parsed diffs; its configuration-management section is the pyATS version of this lifecycle.
- `multi-vendor-network-ops`: the nine-element response contract for any production-impacting recommendation, and the diagnose-first entry point.
- `bgp-analysis`, `igp-routing-analysis`, `evpn-vxlan-fabric`: protocol-depth diagnosis when Step 5 finds an unexpected adjacency or route problem.
- `network-source-of-truth`: the intended-state record to update when the change alters the documented network.
- `oncall-runbooks` and `incident-response-network`: when a failed change becomes an incident.
- `secrets-hygiene`: redact keys, community strings and passwords from any captured config before quoting it.

## Red flags

- About to start a change with no written rollback trigger.
- About to apply a change before the baseline commands have been run and stored.
- About to claim the change worked without re-running the identical baseline commands.
- About to roll out to the remaining devices before the first device has passed Step 4.
- About to change AAA or management ACLs without a second session or commit-confirm.
- About to treat "no alarms" as success when the diff has not been read line by line.
- About to roll back and not verify the device returned to its baseline.
- About to run a **WRITE** step because the skill described it, without a change ticket and an open window.

## Bottom line

One change, one lifecycle: baseline, written scope and rollback criteria, safe execution, an identical post-check, a line-by-line diff, and a decision made against thresholds that were agreed before the change. Verify the rollback as hard as the change.

## Provenance

Re-authored from the Apache-2.0 `change-verification` skill in `vahagn-madatyan/netsec-skills-suite`. Upstream persona, safety-tier and tool-dependency metadata removed; vendor commands, thresholds, decision trees and report template kept; cross-references repointed to this vault.
