---
name: multi-vendor-network-ops
description: "Use for any network infrastructure work across one or more vendors. Covers Cisco (IOS / IOS-XE / NX-OS / IOS-XR; ASA-FTD; ACI / Catalyst Center / Meraki / SD-WAN as secondary), Juniper (JunOS), MikroTik (RouterOS), Nokia (SR OS), Arista (EOS). Topic surface is carrier-grade: BGP / OSPF / IS-IS / EIGRP / MPLS / L2VPN / L3VPN / VPLS / EVPN-VXLAN / VLAN / VXLAN / VRRP / HSRP / GLBP / PPPoE / IPoE / GPON / FTTH / fixed wireless / carrier peering / firewall / ACL / NAT / QoS / SNMP / monitoring / migrations / capacity planning. Triggers include \"review this network change\", \"audit this config\", \"translate this Cisco config to Juniper\", \"BGP / OSPF adjacency issue\", \"STP / VLAN / port-channel / vPC issue\", \"ACL / NAT review\", \"MikroTik equivalent of X\", \"carrier MPLS / EVPN\", \"GPON / FTTH design\", \"PPPoE / IPoE subscriber\", \"review this Ansible / Netmiko / pyATS / NETCONF automation against any of the supported vendors\". Diagnose-first workflow on offline artifacts (configs, diffs, CLI output, parsed telemetry, NMS alerts, topology notes, tickets, automation code); does NOT assume direct device access. Enforces a 9-element response contract for safety-critical responses (assumptions / risk category / evidence / recommendation / pre-checks / execution guidance / post-checks / rollback / escalation). Localised consolidation of olandodeflexy/cisco-network-ops-skill (Cisco discipline + 9-element contract + diagnose table) plus JoshFinlayAU/claude-skills/carrier-network-engineering (5-vendor per-vendor reference files; load on demand from upstream). Cross-references systematic-debugging, oncall-runbooks, secrets-hygiene, plan-time-tooling, completion-gate, bash-defensive, linux-host-bringup, linux-host-ops, using-git-worktrees."
metadata:
  version: 1.0.0
---

# Multi-Vendor Network Ops

Diagnose-first guidance for network operations across the user's actual gear mix. One entry-point regardless of vendor; the workflow + safety rules + 9-element response contract are vendor-agnostic. Per-vendor knowledge (CLI syntax, command names, feature parity) loads from per-vendor reference files held in the upstream JoshFinlayAU repo.

This skill is advisory by default. It does NOT assume direct access to routers, switches, firewalls, controllers, or production networks.

> **Skill marker**: When applying this skill, begin your reply with `[skill: multi-vendor-network-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the network estate (vendor mix, role topology, change-control posture, escalation paths) before responding. Only ask the user for information not already covered or specific to this engagement.

Before responding to any production-impacting query, understand:

1. **Estate and topology**
   - Vendor(s) and OS version(s) on the affected device(s)?
   - Topology role (CPE, distribution, core, edge, transit, peering)?
   - Environment criticality (lab, enterprise, carrier / ISP, data centre)?

2. **Symptom and change context**
   - Failure category from the diagnose table (change blast radius, platform mismatch, drift, routing, security policy)?
   - When did the symptom start; what correlates (config edit, software upgrade, upstream event)?
   - Maintenance window and rollback plan, if applicable?

3. **Evidence on hand**
   - Read-only access (SSH, console, parsed telemetry)?
   - Recent show / display output, logs, alerts, automation history?

---

## When to use

Activate for any network infrastructure work, regardless of vendor:

- Config review, planned change risk analysis, incident triage.
- Routing / switching troubleshooting (BGP, OSPF, IS-IS, EIGRP, MPLS, STP, VLAN, port-channel, vPC, VSS).
- ACL / NAT / policy review or design.
- HA / redundancy checks (HSRP, VRRP, GLBP, vPC, VSS, StackWise).
- Telemetry interpretation, log analysis, NMS alerts.
- Migration: cross-vendor (Cisco-to-Juniper, MikroTik-to-Cisco, etc.); version uplifts; hardware refresh.
- Carrier-grade work: MPLS L2VPN / L3VPN / VPLS / EVPN-VXLAN; BGP peering with policy / community / RPKI; PPPoE / IPoE subscriber; GPON / FTTH access; fixed wireless.
- Translation requests: "translate this Cisco config to Juniper", "MikroTik equivalent of X".
- Automation review: Ansible, Nornir, Netmiko, pyATS / Genie, NETCONF, RESTCONF, controller APIs, streaming telemetry.

## Do NOT use this skill for

- General networking definitions that do not involve real ops work.
- Certification tutoring or exam-prep drills.
- Official Cisco / TAC / Juniper-JTAC / vendor-authoritative claims (this skill is advisory; not vendor-authored).
- Direct production device access, credential handling, or autonomous remediation. Artefact-first only.
- Full SD-WAN, ACI, wireless RF, UCS, Intersight, Webex design (those are platform-product-specialist territory).
- Pure host-side admin (use `linux-host-bringup` or `linux-host-ops`).

## Vendors covered

5 vendors plus a cross-vendor protocol reference, all maintained in the upstream JoshFinlayAU repo: https://github.com/JoshFinlayAU/claude-skills/tree/main/carrier-network-engineering/references

| Vendor | Platforms |
|---|---|
| **MikroTik** | RouterOS |
| **Cisco** | IOS, IOS-XE, NX-OS, IOS-XR, ASA / FTD (secondary), ACI / Catalyst Center / Meraki / SD-WAN (context-only) |
| **Juniper** | JunOS |
| **Nokia** | SR OS |
| **Arista** | EOS |

Before generating any vendor config: fetch the matching upstream reference file (`mikrotik.md`, `cisco.md`, `juniper.md`, `nokia.md`, or `arista.md`) from the URL above. For multi-vendor scenarios (migration, interop, peering), fetch all relevant files. Also fetch `protocols.md` for cross-vendor protocol best practices.

When platform or version is missing, say so and avoid platform-specific commands that may be wrong.

## Response contract (9 elements; production-impacting advice keeps the full shape)

For safety-critical network operations responses, include:

1. **Assumptions:** vendor, platform, OS version if known, topology role, environment criticality, access path, and missing context.
2. **Risk category:** one or more categories from the diagnose table below.
3. **Evidence:** exact config, diff, log, command output, alert, or automation behaviour used.
4. **Recommendation:** next diagnostic step or remediation, with trade-offs.
5. **Pre-checks:** read-only commands, backups, neighbour state, interface state, route / policy evidence.
6. **Execution guidance:** ordered steps or draft config only when appropriate.
7. **Post-checks:** verification commands, parsed checks, telemetry, or before / after comparisons.
8. **Rollback:** inverse config, checkpoint / restore path, abort criteria, and retained evidence.
9. **Escalation notes:** when to involve TAC / vendor JTAC / internal escalation and what data to collect.

Small factual answers may compress the contract. Production-impacting advice must keep the full shape.

## Workflow

1. **Identify context:** which vendor(s) are involved? OS version? Topology role? Environment criticality (carrier / ISP, enterprise, data centre)? Maintenance window? Change intent? Available artefacts?
2. **Classify the failure mode** using the diagnose table below.
3. **Fetch vendor reference(s)** from the upstream JoshFinlayAU repo (URL in "Vendors covered" above) matching the platform(s) involved. For multi-vendor scenarios, fetch all relevant files. Also fetch `protocols.md` for cross-vendor protocol best practices.
4. **Separate evidence from inference.** State when a conclusion is unproven.
5. **Prefer read-only diagnostics** before any configuration. Use `show` / `display` / `print` (depending on vendor) before any state-changing command.
6. **For state-changing work**, produce pre-checks, execution steps, post-checks, rollback, and abort criteria.
7. **Validate** with lab (GNS3, EVE-NG, vendor virtual platforms), parser, pyATS / Genie, Batfish, lint, or staged post-checks where applicable.
8. **Emit the 9-element response contract.**

## Diagnose before you generate

| Failure category | Symptoms | What to think about first |
|---|---|---|
| **Change blast radius** | Large target set, unclear affected devices, no maintenance window, no rollback, no pre / post evidence | Stop. Get the change-safety basics in place before touching anything. The fix is process, not config. |
| **Platform mismatch** | IOS-XE / NX-OS / IOS-XR syntax mixed; Cisco syntax used on Juniper or vice-versa; unsupported commands; wrong commit / rollback model | Confirm vendor + OS version + feature parity. The same protocol behaves differently across vendors (e.g. BGP route-reflector defaults; HSRP version 1 vs 2; VRRP vendor extensions). |
| **Config drift / idempotency** | Running config differs from intended state; repeated automation changes; unbounded CLI pushes | Compare running vs intended; root-cause why drift accumulates (manual edits, missing source-of-truth, bad CI). |
| **Routing convergence risk** | BGP / OSPF / EIGRP / IS-IS adjacency changes; route loss; redistribution; policy edits | Check neighbour state, prefix counts, policy filters; confirm before / after evidence; consider blast radius. For BGP-specific depth use `bgp-analysis`; for IGP depth (OSPF / EIGRP / IS-IS) use `igp-routing-analysis` (per-protocol references inside); sequence IGP-then-BGP in maintenance windows. |
| **Layer 2 risk** | STP, VLAN, trunk, port-channel, vPC, loop, blackhole, MAC move symptoms | STP root, port roles, trunk allowed VLANs, port-channel hashing; vPC peer-keepalive and consistency. Vendor-specific extensions matter (Cisco vPC vs Juniper MC-LAG vs Nokia MC-LAG). |
| **HA / redundancy risk** | HSRP / VRRP / GLBP, vPC, VSS, StackWise, dual supervisor / RP state, asymmetric failover | State on both sides; preempt config; tracking objects; failover symmetry; failover drill cadence. |
| **ACL / NAT / policy shadowing** | Rule order errors; broad permits / denies; NAT precedence; object-group mistakes | Walk the rule order from top to bottom; identify the first match; check NAT order vs ACL evaluation point. ASA / FTD NAT semantics differ from IOS-XE; confirm before assuming. For cross-vendor methodology, use `acl-rule-analysis`; for per-vendor depth use `cisco-firewall-audit` (ASA / FTD), `palo-alto-firewall-audit` (PAN-OS + Panorama), `fortigate-firewall-audit` (FortiOS + brief FortiManager); for MikroTik specifically use `mikrotik-routeros`. |
| **MPLS / EVPN risk** | Label distribution; LSP path; VRF / VPN-instance config; route targets / RDs; EVPN-VXLAN data-plane vs control-plane mismatch | Check label exchange; verify route targets and RDs match between PEs; trace control-plane (BGP-EVPN) vs data-plane (VXLAN encapsulation). For data-centre EVPN-VXLAN (BGP-EVPN with route types 1 to 5; anycast gateway; ESI multihoming; VTEP / VNI; underlay-before-overlay discipline) use `evpn-vxlan-fabric`. |
| **VPN tunnel risk** | IKE SA stuck; Phase 2 not coming up; encap / decap counter zero; tunnel flapping; WireGuard handshake stuck; AllowedIPs scoping; multi-vendor proposal mismatch; DMVPN / ADVPN spoke-to-spoke shortcut | Diagnose by state machine, not by guess. Read IKE FSM state OR WireGuard handshake age first; isolate the failure leg before changing crypto. For deep multi-technology coverage (IPsec / IKEv2 across Cisco / Juniper / PAN-OS / FortiOS / StrongSwan, WireGuard kernel + userspace + Tailscale-style orchestration, DMVPN, ADVPN, CNSA 1.0 / 2.0 crypto suite selection) use `vpn-tunnel-troubleshooting`. |
| **Subscriber / access risk** | PPPoE / IPoE session establishment; GPON ONT registration; FTTH provisioning; fixed wireless link budget | Check radius / TACACS auth; trace from subscriber side; verify QoS / shaping; check optical levels for GPON. |
| **Secret exposure** | Passwords, SNMP communities, keys, tokens, certs, configs or logs exposing credentials | STOP. Per `secrets-hygiene`, redact immediately; flag the exposure to the user; never repeat the literal in your response. |
| **Observability gaps** | Missing before / after evidence; weak telemetry; no alert correlation; unclear success signal | Insist on evidence-gathering before fixes (per `systematic-debugging` Phase 1 boundary evidence). |
| **Validation blind spots** | No lab, parser, dry-run, pyATS, Batfish, lint, or staged verification | Add at least one validation step before deployment; staged rollout if a lab isn't available. For Cisco pyATS / Genie test framework discipline (testbed, AEtest, pCall, baseline-and-rollback), use `pyats-network-automation`. For multi-vendor Python automation (NAPALM idempotent config push with diff and rollback; Netmiko raw SSH for vendors NAPALM does not cover) use `napalm-netmiko`. For parallel fan-out across a multi-vendor fleet (inventory-driven; per-host failure isolation; severity-sorted aggregation) use `nornir-automation`. For declarative YAML-first network automation (Ansible network collections; resource modules; check / diff / apply two-phase loop; ansible-vault credentials) use `ansible-network-modules`. |

## Safety rules

- Treat ALL production config as draft text until a human reviews it.
- Label commands as read-only or state-changing when giving runbooks.
- Never imply the agent has live device access unless a tool explicitly provides it.
- Prefer `show` / `display` / `print` evidence before `configure terminal` (Cisco), `configure` / `commit` (Juniper / Nokia), or `/ip / ip firewall` (MikroTik) state-changing commands.
- Do NOT recommend direct production writes without maintenance context, pre-checks, post-checks, rollback, and abort criteria.
- Redact secrets from pasted configs; avoid repeating credentials in responses (per `secrets-hygiene`).
- For ambiguous symptoms, give the next evidence-gathering command before giving a fix (per `systematic-debugging` Phase 1).

## Multi-vendor migration discipline

Migrations between vendors are the highest-risk routine work. Standard sequence:

1. **Inventory:** complete config + interface map + protocol-state snapshot from the OLD vendor.
2. **Translate:** generate the equivalent NEW vendor config; flag features with no direct equivalent.
3. **Lab:** validate the new config in a lab (GNS3, EVE-NG, vendor virtual platforms, Batfish offline analysis) BEFORE production.
4. **Stage:** parallel-run with a maintenance window where possible; cut over at low-traffic times.
5. **Verify:** post-migration evidence (BGP neighbour state, route counts, interface counters, end-to-end reachability) before declaring done.
6. **Rollback:** keep the old device's config and ports physically available until the verification window closes.

Use `completion-gate` Layer 3 for the "migration succeeded" claim.

## Output format per vendor

Configs in fenced code blocks with the vendor name as the language tag:

````
```routeros
# MikroTik configs use routeros
```

```ios
! Cisco IOS / IOS-XE configs use ios
```

```junos
# Juniper configs use junos
```

```sros
# Nokia SR OS configs use sros
```

```eos
! Arista EOS configs use eos
```
````

Saved config files use vendor-appropriate extensions:

- MikroTik: `.rsc`
- Cisco: `.cfg` or `.conf`
- Juniper: `.conf` or `.set` (for set-style)
- Nokia: `.cfg`
- Arista: `.cfg`

## Quick decision matrix

| User intent | Default output shape |
|---|---|
| "Review this change" | Risk categories from the diagnose table; evidence; pre-checks; post-checks; rollback; approval questions |
| "Troubleshoot this output" | Most likely causes with confidence per cause; next read-only commands; escalation data |
| "Generate config for vendor X" | Confirm OS version and topology if missing; emit draft config in vendor's native CLI; provide validation commands and rollback |
| "Translate config from vendor A to vendor B" | Identify features with no direct equivalent; flag them; emit per-vendor config side-by-side; note interop considerations |
| "Review automation" | Idempotency; blast radius; secret handling per `secrets-hygiene`; parser / test strategy; vendor support coverage |
| "Summarise incident" | Timeline (UTC); impact; evidence; current hypothesis; next actions; escalation bundle (per `oncall-runbooks` postmortem template) |

## Cross-references

### Stage 2 protocol-depth and automation specialists (adopted)

- `bgp-analysis`: BGP protocol-depth specialist. The "Routing convergence risk" diagnose-table row routes here for BGP work. Six-step procedure, two decision trees, threshold tables per vendor. Sequence: stabilise IGP first via `igp-routing-analysis`, then BGP.
- `igp-routing-analysis`: IGP family protocol-depth specialist (OSPF / EIGRP / IS-IS). The "Routing convergence risk" diagnose-table row routes here for IGP work. Thin umbrella SKILL.md owns the protocol-selection decision tree, vendor-platform matrix, and cross-cutting invariants (mutual IGP redistribution with route-tag iron rule, IGP-then-BGP sequencing recipe, migration patterns); per-protocol depth in `references/ospf.md` (5-step procedure, MTU-mismatch-is-the-most-common-cause callout, area design validation), `references/eigrp.md` (DUAL FSM with Stuck-in-Active triage, feasibility condition RD < FD for loop prevention, K-value silent-adjacency-failure callout; Cisco-only: IOS-XE classic / named, NX-OS named-only), `references/isis.md` (adjacency FSM with P2P-vs-broadcast circuit-type distinction, DIS-preemption rule unlike OSPF DR, LSPDB-integrity invariants, MTU-mismatch-is-silent callout, level 1 / 2 route-leaking discipline; Cisco IOS / IOS-XE / NX-OS / IOS-XR, Juniper JunOS, Arista EOS; IOS-XR receives prominent treatment as dominant SP-core platform). Pair with `bgp-analysis` for IGP-then-BGP sequencing.
- `acl-rule-analysis`: cross-platform rule-audit methodology. The "ACL / NAT / policy shadowing" diagnose-table row routes here. Vendor-agnostic rule walk (top-down first-match, NAT precedence, group resolution, implicit-deny semantics per platform). Goes deeper than this umbrella for ACL / firewall work, and routes onward to per-vendor Stage 3 specialists for platform deep-dive.
- `pyats-network-automation`: Cisco pyATS / Genie framework specialist. The "Validation blind spots" diagnose-table row routes here for pyATS validation. Eight sections covering testbed, Genie parsing, AEtest, baseline-and-rollback config management, fleet orchestration with pCall.

### Stage 6 multi-vendor automation specialists (adopted)

- `napalm-netmiko`: multi-vendor Python network device transport / abstraction specialist. The "Validation blind spots" diagnose-table row routes here for non-pyATS Python automation. NAPALM driver model with idempotent replace and merge config pushes (compare_config narrated to user before commit_config); Netmiko raw SSH for vendors NAPALM does not cover (FortiOS, F5, Aruba, MikroTik, etc.). Per-vendor quirks across IOS / IOS-XE / NX-OS / IOS-XR / ASA / JunOS / EOS / PAN-OS / FortiOS / F5 / Linux. Single-threaded concurrency caveat: for parallel fan-out, hand off to `nornir-automation`.
- `nornir-automation`: Python network automation orchestration specialist. Inventory-driven parallel task execution with per-host failure isolation. Plugin ecosystem (nornir_napalm, nornir_netmiko, nornir_netconf, nornir_jinja2, nornir_pyez, nornir_routeros, nornir_f5). F filter syntax, custom Processor sinks (ServiceNow, Slack, S3, Splunk, Datadog), dry-run-first / diff-narrated discipline. Sits underneath this umbrella as the orchestration layer driving `napalm-netmiko` (or NETCONF / PyEZ / RouterOS-API) plugins in parallel.
- `ansible-network-modules`: declarative YAML-first network automation specialist. Ansible network collections (cisco.ios, cisco.iosxr, cisco.nxos, junipernetworks.junos, arista.eos, paloaltonetworks.panos, fortinet.fortios, fortinet.fortimanager, checkpoint.mgmt). Resource modules (state: replaced / merged / deleted / rendered / parsed / gathered / overridden). Connection plugins (network_cli / httpapi / netconf / libssh) with `ansible_network_os` per platform. Ansible-vault for credentials. Two-phase --check --diff before apply; serial knob for safe rollouts; block / rescue for transactional change. Better fit than the Python skills when change management is built around playbook review.

### Stage 3 platform and protocol specialists (adopted)

- `cisco-firewall-audit`: Cisco ASA + FTD platform specialist. ASA security-level + interface ACL + Modular Policy Framework; FTD ACP + Snort + FMC / FDM; multi-context ASA. Six-step audit; severity table; two decision trees. Used after `acl-rule-analysis` for the Cisco-specific deep-dive.
- `palo-alto-firewall-audit`: PAN-OS platform specialist with substantive Panorama-managed deployments section. Zone-based segmentation; App-ID; Security Profile Groups; zone protection; decryption; pre-rule / device-group / local / post-rule hierarchy; partial-push hazard; shared-vs-device-group ordering trap. Used after `acl-rule-analysis` for the PAN-OS-specific deep-dive.
- `fortigate-firewall-audit`: FortiOS platform specialist with brief FortiManager subsection. Multi-VDOM segmentation; UTM profile binding (AV / IPS / WebFilter / AppCtrl / EmailFilter / DLP); FortiGuard signature freshness; SD-WAN SLA + fail-open risk; HA + session-sync. Used after `acl-rule-analysis` for the FortiOS-specific deep-dive.
- `vpn-tunnel-troubleshooting`: multi-technology VPN diagnostic specialist. The "VPN tunnel risk" diagnose-table row routes here. IPsec / IKEv2 across Cisco / Juniper / PAN-OS / FortiOS / StrongSwan; WireGuard kernel + userspace + Tailscale-style orchestration; DMVPN; ADVPN; CNSA 1.0 today + CNSA 2.0 transition by 2033. Six-step IKE FSM procedure plus a WireGuard sub-procedure.
- `evpn-vxlan-fabric`: data-centre fabric specialist. The "MPLS / EVPN risk" diagnose-table row routes here for data-centre EVPN-VXLAN. Multi-vendor (Cisco NX-OS, Arista EOS, Juniper Junos, Cumulus Linux); BGP-EVPN route types 1 to 5; VTEP / VNI sanity; anycast gateway consistency; ESI multihoming with DF election; underlay-before-overlay iron rule.
- `mikrotik-routeros`: MikroTik RouterOS v7.x specialist. Eleven upstream skills folded into one (tikoci collection plus drodecker mikrotik-api). Path-tree CLI plus REST plus mikrotik-api Python client; firewall (filter / NAT / mangle) with comment-as-tag idempotency; container plus /app YAML; hotspot; sniffer with TZSP; CHR in QEMU. Used for the MikroTik-specific deep-dive when the umbrella points to vendor-specific work.

### Cross-cutting workflow

- `systematic-debugging`: Phase 1 evidence-gathering at every component boundary IS the diagnose-before-generate pattern. Use it especially when the failure category is "observability gaps" or "ambiguous symptoms".
- `oncall-runbooks`: when a network issue becomes an incident; runbook structure applies (severity, mitigation-vs-resolution, blameless postmortem with UTC timeline).
- `incident-response-network`: network-forensics during security incidents. When an incident requires evidence preservation (packet captures, flow records, ARP / MAC snapshots before aging), lateral movement investigation, or read-only containment verification (ACL counter delta, null-route presence, VLAN isolation paths), this skill is the network-side arm. Pairs with `oncall-runbooks` (generic incident container), `siem-log-analysis` / `network-log-analysis` (log retrieval and timeline reconstruction), and `incident-response-lifecycle` for the NIST 800-61 process layer.
- `incident-response-lifecycle`: NIST 800-61 process layer for declared incidents. Severity P1-P4 classification on user-impact / service-impact / data-risk axes, four-role assignment (Incident Commander / Technical Lead / Communications Lead / Scribe), escalation matrix with vendor TAC engagement criteria, stakeholder communications (executive / technical / customer / regulatory templates), phased recovery with enhanced monitoring period, blameless post-mortem with 5-whys RCA and four-disposition action-item model (fix / mitigate / accept / transfer). Wraps `oncall-runbooks` (devops-flavour generic), `siem-log-analysis` / `network-log-analysis` (log-side evidence), and `incident-response-network` (network-forensics technical evidence) when an incident is formally declared with security-IR framing.
- `wireless-security-audit`: Stage 4 wireless LAN security audit specialist. 6-step procedure (SSID policy inventory, authentication and encryption audit, 802.1X / RADIUS validation, rogue AP assessment, RF security posture, report). Six-platform OS-honest vendor-tag split: `[AireOS]` (Cisco legacy WLC) + `[IOS-XE-WLC]` (Catalyst 9800) + `[Aruba AOS]` (Mobility Controller) + `[Aruba AOS-CX]` (CX wireless gateway) + `[Meraki]` (Dashboard API) + `[Mist]` (Cloud API). Pairs with `incident-response-network` (rogue AP IR handoff and post-incident SSID posture review), `acl-rule-analysis` (wired-side enforcement of wireless segmentation: VLAN-to-SSID mapping, inter-VLAN ACL between wireless and corporate), `siem-log-analysis` / `network-log-analysis` (wireless event log investigation), and `secrets-hygiene` (RADIUS shared secrets, controller admin credentials, Meraki / Mist API tokens).
- `secrets-hygiene`: the "secret exposure" failure category in the diagnose table maps directly. Real credentials in pasted configs MUST be redacted before any further work; per-device credentials live in the secret store, not the runbook.
- `plan-time-tooling`: any state-changing network work fires the `engineering:deploy-checklist` mandatory trigger. Plan it as a chunk; do not freelance.
- `completion-gate` Layer 3: post-checks IS the iron law (no claim of "change worked" / "migration succeeded" without fresh verification evidence in this turn).
- `bash-defensive`: any wrapper scripts (deploy, backup, healthcheck, multi-vendor pre-upgrade snapshot) follow strict mode + traps + ShellCheck.
- `using-git-worktrees`: when reviewing network-config-as-code in a Git repo, the never-fight-the-harness discipline applies.
- `linux-host-bringup` and `linux-host-ops`: when the network device is fronted or managed by a Linux jumphost, RANCID / Oxidized config-collector host, or NMS appliance.

### Bonus skills from same upstream repo (warm pointers; not yet adopted)

JoshFinlayAU/claude-skills also contains:

- `voip-pbx`: VoIP / PBX with Australian voice + codecs / media + network design + PBX platforms + SIP protocol + troubleshooting.
- `ip-phone-provisioning`: Fanvil + Polycom + Snom + Yealink desk phones.
- `netconf`: NETCONF protocol; pairs with `pyats-network-automation`.

These are warmpointed in `_docs/skill-review-queue.md` for adoption when relevant projects land.

### Watchlist (deferred; revisit when in scope)

- `paloalto-panorama` standalone -- folded into `palo-alto-firewall-audit` Panorama-managed deployments section instead. The standalone netclaw skill (~63 LOC, MCP-coupled to `iflow-mcp-cdot65-palo-alto-mcp`) was not adopted as its own skill because the substantive content (template hierarchy, device-group + pre-rule / post-rule order, commit-and-push discipline) lives more usefully alongside the per-firewall audit.
- `fortimanager-ops` standalone -- brief mention only inside `fortigate-firewall-audit`. Standalone netclaw skill (~61 LOC, severe MCP coupling) deferred. Revisit if FortiManager becomes the primary surface (ADOM design, full revision history, policy-package install workflow, ServiceNow integration would warrant a dedicated skill at that point).
- `checkpoint-firewall-audit` (vahagn-madatyan) -- optional per the queue; not in current scope. Watchlist for the case Check Point is added to the estate.
- `cisco-secure-client` deep-dive (chrishuffman5) -- optional per user direction. Brief pointer kept inside `vpn-tunnel-troubleshooting`; full DAP / TND / Always-On / per-app VPN / ISE / Umbrella integration deferred.

## Common mistakes

- Generating vendor-specific config without confirming the vendor and OS version (silent platform mismatch).
- Translating Cisco to Juniper word-for-word without checking that the JunOS feature actually behaves the same way (e.g. BGP route-reflector defaults differ; OSPF area types differ).
- Designing a multi-vendor BGP peering without considering RPKI policy alignment (one side validates, the other doesn't, prefixes get dropped silently).
- Migrating from MikroTik to Cisco without inventorying the firewall rules first (RouterOS firewall syntax is structurally different from IOS ACLs).
- Cutting over a production link without parallel-run validation.
- Pulling the old device before the new device's verification window closes.
- Recommending `configure terminal` / `commit` / `write memory` without rollback and abort criteria.
- Fixing the symptom (e.g. clearing BGP) without diagnosing the root cause (e.g. policy filter regression).
- Walking ACL evaluation top-down without identifying which interface and which direction the ACL is applied to.
- Treating ASA / FTD ACL / NAT semantics as identical to IOS-XE (they are not; NAT happens at different points in the packet flow).
- Reproducing a credential / SNMP community in the response when the user pasted it (compounds the secrets exposure).
- Pushing automation that is not idempotent (every run leaves new diff; running config drifts unboundedly).
- Producing a "summary" of the change in human prose without the 9-element response contract (less useful for the on-call engineer at 3am).

## Red flags

- About to recommend a state-changing command without pre-checks, post-checks, rollback, and abort criteria.
- About to repeat a credential, SNMP community, or pre-shared key that appeared in the user's paste.
- About to give a vendor-specific command without confirming the vendor and OS version.
- About to recommend ACL changes without walking the rule order from the top.
- About to clear a routing protocol session ("clear ip bgp *", `restart routing`, etc.) without explaining the blast radius.
- About to declare a migration "done" without post-migration verification (per `completion-gate` Layer 3).
- About to recommend a maintenance-window-free cutover for any state-changing change.
- About to translate config word-for-word without flagging features that have no equivalent on the target vendor.
- About to combine GPON / FTTH access design with carrier MPLS upstream design in one pass without separating the access plane from the core plane.
- About to generate VRRP / HSRP config without confirming that both sides support the same vendor extension (e.g. HSRP version 2 vs version 1).
- Generating an Ansible / Netmiko / pyATS playbook without idempotency considerations.
- Skipping the response contract for a production-impacting change ("here's the config; deploy it").

## Bottom line

One entry-point for any network work, regardless of vendor. 9-element response contract is the iron rule for anything production-impacting. Diagnose-first; read-only evidence before state-changing commands. 5 vendors covered (MikroTik / Cisco / Juniper / Nokia / Arista) via per-vendor reference files held upstream. Migrations always have inventory + translate + lab + stage + verify + rollback. Redact secrets always. The Cisco-specific deep discipline (response contract, diagnose table, safety rules) lifts cleanly to all 5 vendors with the per-vendor knowledge plugged in.
