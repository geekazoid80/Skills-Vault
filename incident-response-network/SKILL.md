---
name: incident-response-network
description: "Use for any network-forensics work during security incidents across Cisco (classic IOS, IOS-XE, NX-OS, IOS-XR), Juniper JunOS, or Arista EOS. Triggers include \"preserve evidence\", \"network forensics\", \"lateral movement investigation\", \"verify containment\", \"chain of custody for network evidence\", \"timeline reconstruction from network data\", \"packet capture during incident\", \"flow record analysis NetFlow IPFIX sFlow\", \"what did the attacker touch on the network\", \"rogue MAC detected\", \"ARP table forensics\", \"MAC table preservation before aging\", \"CAM table evidence capture\", \"post-incident network state capture\", \"verify ACL containment is matching\", \"null route present and not overridden\", \"VLAN isolation verification\", \"show tech-support for incident bundle\", \"sha256 hash evidence file\", \"syslog and SNMP trap evidence retrieval\", \"monitor capture on device\", \"ethanalyzer NX-OS capture\", \"EPC IOS-XR embedded packet capture\", \"lateral movement on SMB 445 RDP 3389 WinRM 5985\", \"internal-to-internal flow analysis\". Six-step procedure (evidence preservation, initial triage, lateral movement detection, containment verification, timeline reconstruction, post-incident documentation). Two threshold tables (Evidence Priority Classification with 7 evidence types ranked by volatility, Containment Verification Criteria with ACL counter / null route / VLAN isolation / flow-record checks). One decision tree (Evidence Collection Priority with active-vs-post-incident routing and time-window-based ARP / MAC / flow / syslog branches). Multi-vendor syntax labels `[IOS]` / `[IOS-XE]` / `[NX-OS]` / `[IOS-XR]` for the Cisco family (each broken out separately because forensics commands diverge: classic IOS lacks `monitor capture`; NX-OS uses `ethanalyzer local interface` instead of `monitor capture`; IOS-XR drops `ip` from many shows and EPC has platform-dependent support), `[JunOS]` for Juniper, `[EOS]` for Arista. Scoped to network artefacts only (packet captures, flow records, ARP / MAC / CAM tables, routing snapshots, device syslog, SNMP trap history, tech-support bundles); not general incident response, endpoint forensics, malware analysis, or organisational communication plans (use `incident-response-lifecycle` for the NIST 800-61 process layer; use `oncall-runbooks` for the generic devops incident container). Read-only investigation; containment verification confirms previously applied controls are effective, it does NOT execute containment. Every collected evidence file gets a SHA-256 hash immediately after collection per the chain-of-custody discipline. Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); cli-reference.md and forensics-workflow.md folded into body in full because methodology content not lookup-table; four-way Cisco breakout authored at vault for IOS / IOS-XR / NX-OS forensics commands the upstream does not ship."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Incident Response: Network Forensics

Network-specific evidence collection and analysis during security incidents. This skill covers network artefacts only: packet captures, flow records (NetFlow / sFlow / IPFIX), ARP / MAC / CAM tables, routing table state, device syslog, SNMP trap history, and tech-support bundles. It does not cover general incident response lifecycle (use `incident-response-lifecycle` for the NIST 800-61 process layer; use `oncall-runbooks` for the generic devops incident container), endpoint forensics, malware analysis, or organisational communication plans.

The procedure follows an event-driven lifecycle shaped around forensic evidence: preserve volatile data, triage scope, detect lateral movement, verify containment, reconstruct timeline, document findings. All commands are read-only. Containment verification confirms that previously applied controls are effective; it does NOT execute containment.

Commands use `[IOS]`, `[IOS-XE]`, `[NX-OS]`, `[IOS-XR]`, `[JunOS]`, or `[EOS]` vendor labels where syntax diverges. The four Cisco platforms are broken out separately because forensics commands diverge meaningfully: classic IOS lacks `monitor capture` (use legacy `debug ip packet detail acl <name>` or `ip traffic-export`); NX-OS uses `ethanalyzer local interface <intf>` instead of `monitor capture`; IOS-XR drops `ip` from many show commands and EPC has platform-dependent support (ASR9k vs CRS-1 vs NCS5500). The "Evidence handling" section between Prerequisites and Procedure carries the volatility-ordering table and the chain-of-custody record template.

> **Skill marker**: When applying this skill, begin your reply with `[skill: incident-response-network]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the network topology in scope, evidence-handling policy (chain-of-custody record format, storage location, retention period), and containment authority (who can apply containment and via which change-management path) before collecting evidence. Only ask the user for information not already covered or specific to this incident.

Before collecting evidence, understand:

1. **Blast radius and incident scope**
   - Which devices are in scope (compromised, suspected, transit)?
   - What is the suspected incident type (lateral movement, data exfiltration, unauthorised access, DoS / DDoS, insider threat)?
   - Is the incident currently active or post-event? Active incidents require immediate volatile-evidence preservation.

2. **Evidence-preservation discipline**
   - What is the chain-of-custody record format (template in this skill's Evidence handling section; verify if the organisation has its own form that overrides).
   - Where do evidence files land (on-device flash, central forensics share, S3 bucket, encrypted local volume)?
   - Who handles evidence after collection (incident commander, security lead, external forensics firm)?

3. **Containment authority and read-only stance**
   - Has containment already been applied (ACLs, null routes, VLAN isolation)? If yes, this skill verifies effectiveness (Step 4); if no, this skill is investigation-only and containment requires a separate change.
   - Does the organisation require a change ticket before any device-state-changing command? Even `show tech-support` saves output to flash and counts as device-touching on some change-control regimes.

## When to use

- **Active security incident** requiring network-level evidence collection (packet captures, flow analysis, device logs)
- **Post-incident network forensics**: reconstructing what happened on the network after a confirmed security event
- **Lateral movement investigation**: tracing attacker movement between internal hosts using flow records, ARP / MAC table changes, and routing state analysis
- **Unauthorised access investigation**: identifying how an external or internal actor reached target systems via network path analysis
- **Data exfiltration analysis**: quantifying outbound data transfers via flow record byte counts and packet capture content analysis
- **Containment verification**: confirming (read-only) that ACLs, null routes, or VLAN isolation applied by responders are blocking attacker traffic effectively

## Do NOT use this skill for

- General incident-response process management (severity classification, role assignment, stakeholder comms, post-mortem facilitation); use `incident-response-lifecycle` for the NIST 800-61 process layer or `oncall-runbooks` for the generic devops incident container
- Endpoint forensics, host process analysis, memory dump triage, or disk imaging (out of network scope; use the appropriate endpoint / DFIR tooling)
- Malware reverse engineering or static / dynamic payload analysis (out of network scope)
- Executing containment actions (ACL push, null-route injection, VLAN-isolation config). This skill is read-only; containment execution belongs in a change ticket with peer review, blast-radius assessment, and an explicit change-management path. This skill only VERIFIES that previously applied containment is effective.
- Routine network troubleshooting (`bgp-analysis`, `igp-routing-analysis`, `multi-vendor-network-ops` cover protocol-depth diagnosis; this skill is incident-driven forensics)
- General log search not tied to an incident (use `siem-log-analysis` or `network-log-analysis` or `graylog-log-investigation`)

## Prerequisites

- **Device CLI access**: read-only access to network devices in the incident scope is sufficient for all evidence collection commands. No enable / configure privilege is required for any command in this skill.
- **Flow collection infrastructure**: NetFlow, sFlow, or IPFIX collectors must be receiving exports from network devices. Verify with flow export commands per platform:
  - **[IOS / IOS-XE]** `show flow monitor`, `show flow exporter <name> statistics`, `show flow interface`
  - **[NX-OS]** `show flow exporter`, `show flow record`, `show flow monitor` (NetFlow v9 / Netstream)
  - **[IOS-XR]** `show flow exporter-map`, `show flow monitor-map`, `show flow platform producer statistics location <loc>`
  - **[JunOS]** `show services flow-monitoring version-ipfix template`, `show services flow-monitoring version9 template`, `show services accounting status`, `show services accounting flow`
  - **[EOS]** `show flow tracking`, `show flow tracking hardware`, `show flow tracking counters`
  Without flow data, lateral movement analysis (Step 3) is limited to ARP / MAC / syslog correlation.
- **Centralised logging**: device syslog events must be forwarded to a SIEM or syslog server. Local device log buffers are small and rotate quickly. Missing centralised logs create timeline gaps. Cross-reference `siem-log-analysis` (SIEM-equipped) or `network-log-analysis` (no-SIEM raw syslog) for the log-side investigation.
- **NTP synchronisation**: all devices must be time-synchronised. Verify with `[IOS / IOS-XE / NX-OS]` `show ntp status`, `[IOS-XR]` `show ntp status` (no `ip` keyword), `[JunOS]` `show system ntp`, `[EOS]` `show ntp status`. Skewed clocks corrupt timeline correlation.
- **Known-good baseline**: saved copies of routing tables, ARP tables, and device configurations from before the incident for comparison. Without baselines, anomaly detection relies on general heuristics rather than delta analysis.
- **Terminal session logging** (folded from upstream cli-reference): start a terminal log before collecting any evidence to create an audit trail.
  - **[IOS / IOS-XE / NX-OS / IOS-XR]** `terminal length 0` disables paging for complete output capture; SSH-client-side logging captures the session.
  - **[JunOS]** `set cli screen-length 0` disables paging; use `| save /var/tmp/<file>` to save individual command output.
  - **[EOS]** `terminal length 0` disables paging; use `| redirect flash:<file>` for on-device save.

## Evidence handling

This section folds the volatility-ordering table and chain-of-custody record template from the upstream `forensics-workflow.md` reference (213 lines). Both apply throughout the Procedure section below.

### Evidence volatility ordering

Collect evidence in order of volatility: most volatile first. This ordering determines the sequence in Step 1 (Evidence Preservation).

| Priority | Evidence type | Volatility | Typical lifespan | Rationale |
|----------|--------------|------------|------------------|-----------|
| 1 | ARP / MAC / CAM tables | Very high | Minutes to hours (aging timers) | ARP entries age out in 4 hours (default); CAM entries in 5 minutes. Overwritten continuously. |
| 2 | Active packet captures | Very high | Real-time only | Live traffic exists only while flowing. Must capture during the incident window or it is lost forever. |
| 3 | Routing table state | High | Hours (convergence events) | Route changes overwrite previous state. OSPF / BGP convergence can alter tables within seconds of a topology change. |
| 4 | Flow records (NetFlow / sFlow / IPFIX) | Medium | Hours to days (collector retention) | Collector retention varies: 24 hours to 30 days depending on infrastructure. Export gaps are permanent. |
| 5 | Device running configuration | Low | Until next change | Running config persists until modified. Changes overwrite previous state without version history unless archival is configured. |
| 6 | Syslog messages | Low | Days to months (server retention) | Centralised syslog servers retain messages per policy. Local device buffers are small and rotate quickly. |
| 7 | SNMP trap history | Low | Days (trap receiver retention) | Trap receivers retain events per retention policy. |
| 8 | Saved configurations / archives | Very low | Persistent | Startup configs and config archives are persistent until explicitly deleted. |

### Chain-of-custody record template

Every piece of evidence collected must be documented to maintain forensic integrity. Use the following template for each evidence item.

```
EVIDENCE COLLECTION RECORD
===========================
Evidence ID:          [unique sequential identifier, e.g., NET-INC-2026-001-E01]
Incident Reference:   [incident ticket or tracking number]
Collection Timestamp: [YYYY-MM-DD HH:MM:SS UTC]
Collector:            [name and role of person collecting]
Collection Method:    [command used, tool, or export method]
Source Device:        [hostname, IP, model, serial number]
Source Interface:     [interface name if applicable]
Evidence Type:        [packet capture / flow record / ARP table / etc.]
Time Window:          [start to end of captured data, if applicable]
File Name:            [exact filename of saved evidence]
File Size:            [bytes]
Hash (SHA-256):       [hash of evidence file immediately after collection]
Storage Location:     [where the evidence file is stored]
Chain-of-Custody:     [transfer log: who handled, when, to / from where]
Notes:                [any conditions, limitations, or observations]
```

### Hash verification

After collecting evidence to a file, immediately compute a SHA-256 hash to establish integrity. Document the hash in the evidence collection record.

| Platform | Command |
|----------|---------|
| Linux / macOS | `sha256sum <filename>` |
| Network device (Cisco IOS / IOS-XE / NX-OS / IOS-XR) | `verify /sha256 flash:<filename>` (IOS / IOS-XE / NX-OS) or `show hash sha256 <filename>` (IOS-XR) |
| Network device (JunOS) | `file checksum sha-256 /var/tmp/<filename>` |
| Network device (EOS) | `verify /sha256 flash:<filename>` |

## Procedure

Follow these six steps in order. Earlier steps capture volatile evidence before it ages out; later steps analyse and document. Each step folds the relevant CLI commands from the upstream cli-reference (now inline) and methodology from forensics-workflow (now inline in Evidence handling and Step 5).

### Step 1: Evidence preservation

Capture volatile network evidence before it ages out or is overwritten. Follow the volatility ordering from the Evidence handling section above; most volatile first.

#### 1a. ARP / MAC / CAM tables (highest volatility; minutes to hours)

Collect the current ARP and MAC address tables from every device in the incident scope. These tables map IP addresses to MAC addresses and MAC addresses to physical switch ports; essential for identifying which hosts were connected where.

- **[IOS / IOS-XE]** `show arp` and `show mac address-table`
- **[NX-OS]** `show ip arp` and `show mac address-table` (note `ip arp` not just `arp`)
- **[IOS-XR]** `show arp` and (for L2VPN bridge-domain cases on platforms with L2 forwarding) `show l2vpn forwarding bridge-domain mac-address`. Pure L3 IOS-XR routers (ASR9k typical) have no CAM table.
- **[JunOS]** `show arp no-resolve` and `show ethernet-switching table`
- **[EOS]** `show arp` and `show mac address-table`

Save output to files with timestamps. ARP entries typically age out in 4 hours; CAM entries in 5 minutes. Delay here means losing L2 mapping.

#### 1b. Active packet captures (real-time; exists only while traffic flows)

If the incident is active and the investigation requires payload-level evidence, initiate packet captures on relevant interfaces immediately.

- **[IOS]** classic IOS lacks `monitor capture`. Use `debug ip packet detail acl <name>` (CPU-impacting; narrow ACL essential) or legacy `ip traffic-export apply <intf>` to mirror to a destination MAC. Prefer span / mirror to an external capture appliance for classic IOS rather than on-device capture.
- **[IOS-XE]** `monitor capture CAP1 interface <intf> both` then `monitor capture CAP1 match any` (or `match access-list <name>` for filtered) then `monitor capture CAP1 start`; stop with `monitor capture CAP1 stop`; export with `monitor capture CAP1 export flash:evidence.pcap`. Verify status with `show monitor capture CAP1`.
- **[NX-OS]** `ethanalyzer local interface <intf> capture-filter "<bpf>" write bootflash:evidence.pcap` (BPF syntax, not Cisco ACL; capture runs on supervisor CPU; limit packet count or duration).
- **[IOS-XR]** Embedded Packet Capture (EPC) availability is platform-dependent (ASR9k yes, CRS-1 limited, NCS5500 yes). Where supported: `monitor capture <name> interface <intf> direction both`, `monitor capture <name> start`, `monitor capture <name> stop`, export via `copy harddisk:<name>.pcap` to remote. Where unsupported (legacy CRS-1): use span / mirror to an external capture appliance.
- **[JunOS]** `monitor traffic interface ge-0/0/0 size 1500 write-file /var/tmp/capture.pcap`; add `matching "host 10.1.1.1"` for filtering. Live display without file: `monitor traffic interface ge-0/0/0 no-resolve`.
- **[EOS]** `bash tcpdump -i et1 -w /mnt/flash/evidence.pcap -c 10000` (EOS-shell-based; `-c` limits packet count). Alternative span: `monitor session 1 source Et1 both` plus `monitor session 1 destination Cpu` for local capture, or destination to a mirror port for external capture.

**Performance note:** on-device packet capture consumes CPU. Monitor device health during capture and set packet count or duration limits. On NX-OS specifically, `ethanalyzer` runs on the supervisor and can saturate the management CPU if the BPF filter is too broad.

#### 1c. Routing table snapshots (hours; convergence overwrites state)

- **[IOS / IOS-XE / NX-OS / EOS]** `show ip route` and `show ip route summary`
- **[IOS-XR]** `show route` and `show route summary` (no `ip` keyword)
- **[JunOS]** `show route` and `show route summary`

Also capture routing protocol adjacency state to document peering status at the time of collection:
- **[IOS / IOS-XE / NX-OS / EOS]** `show ip ospf neighbor`, `show ip bgp summary`, `show ip eigrp neighbors`, `show isis adjacency`
- **[IOS-XR]** `show ospf neighbor`, `show bgp summary`, `show isis adjacency` (no `ip`)
- **[JunOS]** `show ospf neighbor`, `show bgp summary`, `show isis adjacency`

#### 1d. Flow export verification (hours to days; collector retention)

Confirm that flow data from the incident time window is available in the flow collector. Verify export is active and records exist (commands from Prerequisites).

#### 1e. Device configuration and comprehensive state

Save the running configuration and full tech-support output for each device in scope:

- **[IOS / IOS-XE]** `show tech-support | redirect flash:tech-<hostname>-<date>.txt`
- **[NX-OS]** `show tech-support | redirect bootflash:tech-<hostname>-<date>.txt` (note `bootflash:` not `flash:`)
- **[IOS-XR]** `show tech-support file harddisk:tech-<hostname>-<date>.tgz` (IOS-XR bundles into compressed archive)
- **[JunOS]** `request support information | save /var/tmp/tech-<hostname>-<date>.txt`
- **[EOS]** `show tech-support | redirect flash:tech-<hostname>-<date>.txt`

Compute SHA-256 hashes immediately after saving evidence files (see Evidence handling section for the per-platform hash commands).

### Step 2: Initial triage

Determine the scope of the incident (affected devices, time window, involved IP addresses) using log and flow data collected in Step 1.

**Identify the time window:** find the earliest indicator (first alert, first anomalous event) and the latest known malicious activity. Add a buffer of plus / minus 2 hours to account for undetected precursor activity.

**Identify involved IPs:** extract unique source and destination IP addresses from alerts, SIEM events, and flow records within the time window. Classify each as internal, external, or infrastructure.

**Identify affected devices:** determine which network devices handled traffic to / from involved IPs. Use routing tables to trace the forwarding path and identify all transit devices.

**Scope assessment output:** a list of (1) affected time window, (2) involved IP addresses with classification, (3) affected network devices, and (4) evidence types available for each device. This scoping drives the depth of Steps 3-5.

### Step 3: Lateral movement detection

Trace internal-to-internal connections that indicate attacker movement between hosts. Lateral movement leaves evidence in flow records (new internal connections), ARP / MAC tables (new L2 entries), and syslog (authentication events, new sessions).

**Flow record analysis:** query the flow collector for internal-to-internal connections involving known compromised IPs during the incident time window. Look for:

- Connections to ports commonly used for lateral movement (SMB / 445, RDP / 3389, SSH / 22, WinRM / 5985, WMI / 135)
- Connections from a compromised host to hosts it has never contacted before (new destination analysis)
- High byte-count transfers between internal hosts (staging or exfil prep)
- Sequential connections from one host to many hosts in a short time window (scanning behaviour)

**ARP / MAC table analysis:** compare current ARP / MAC tables (from Step 1a) against baseline captures. Look for:

- New MAC addresses on access ports (rogue devices)
- MAC address appearing on a different port than baseline (device moved or MAC spoofing)
- Multiple IP addresses mapped to a single MAC (IP aliasing, potential MITM)

**Syslog correlation:** review authentication events on network devices during the incident window. Attacker lateral movement often involves:

- Failed authentication attempts from internal IPs against network device management interfaces
- Successful logins from unexpected source IPs
- Configuration view commands from unusual user accounts

Cross-reference `siem-log-analysis` or `network-log-analysis` for the per-vendor authentication-failure patterns.

### Step 4: Containment verification (read-only)

Verify that containment measures applied by the incident response team are functioning as intended. This step is strictly read-only; it confirms effectiveness, it does NOT apply containment.

**ACL hit count verification:** confirm that blocking ACLs are matching the attacker's traffic. Rising hit counters on deny rules confirm the ACL is intercepting traffic.

- **[IOS / IOS-XE]** `show access-lists <containment-acl-name>`; check hit counters on deny entries
- **[NX-OS]** `show ip access-lists <containment-acl-name>`; check per-entry match counts (note `ip access-lists` not just `access-lists`)
- **[IOS-XR]** `show access-lists <containment-acl-name>`; for hardware counters use `show access-lists <name> hardware ingress location <loc>`
- **[JunOS]** `show firewall filter <containment-filter>`; check term counters for deny actions
- **[EOS]** `show access-lists <containment-acl-name>`; check per-entry match counts

**Routing containment verification:** if null routes or route modifications were applied for containment, verify they are present and effective:

- Confirm the null route exists in the routing table:
  - **[IOS / IOS-XE / NX-OS / EOS]** `show ip route <attacker-prefix>` should show Null0 / discard
  - **[IOS-XR]** `show route <attacker-prefix>` should show Null0 / discard
  - **[JunOS]** `show route <attacker-prefix>` should show next-hop `discard` or `reject`
- Verify no more-specific routes bypass the null route
- Check routing protocol advertisements to confirm containment routes are not being overridden by dynamic protocols

**Network isolation verification:** if VLAN isolation was applied, verify that the isolated segment has no unintended paths:

- Check the routing table for routes to / from the isolated VLAN
- Verify trunk port allowed VLAN lists exclude the isolated VLAN on uplinks
- Confirm no layer-3 interfaces provide alternative paths

### Step 5: Timeline reconstruction

Build a unified chronological sequence of network events from all evidence sources. This timeline is the primary deliverable of network forensics investigation. This step folds the timeline reconstruction methodology from the upstream forensics-workflow reference (now inline).

**Step 5.1: Establish anchor events.** Identify high-confidence, timestamped events that serve as fixed points:

- First alert or detection event (the trigger)
- Interface state changes (link up / down; recorded by multiple systems)
- BGP / OSPF adjacency changes (logged by both peers)
- Firewall deny events for known-bad indicators
- Configuration changes (logged with user attribution)

**Step 5.2: Normalise timestamps.** All evidence timestamps must be converted to a single timezone (UTC) before correlation. Common timestamp issues:

- Device clock skew (check NTP status on each device)
- Timezone inconsistencies (some devices log local time, others UTC)
- Daylight saving time transitions during the incident window
- Syslog timestamp precision (seconds vs milliseconds)

Cross-reference `utc-timestamps` skill for the UTC-everywhere discipline.

**Step 5.3: Correlate by shared attributes.** Link events across sources using:

- **IP address**: same source or destination IP appears in flow records, ARP tables, and syslog events
- **Timestamp proximity**: events within a defined window (plus / minus 60 seconds for automated correlation, plus / minus 5 minutes for manual review)
- **Session identifier**: VPN tunnel IDs, TCP session hashes, or flow record keys
- **Device / interface**: events on the same device or interface

**Step 5.4: Identify gaps.** Document time periods with missing evidence:

- Time windows with no events from a device that should be active
- Flow record gaps indicating export or collector issues
- Syslog gaps indicating forwarding failures or device reboot
- ARP / MAC table gaps (evidence was volatile and lost before collection)

Document gaps explicitly; they represent uncertainty in the timeline.

**Step 5.5: Assemble chronological sequence.** Merge all correlated events into a single timeline sorted by timestamp. Annotate each entry with:

- Source (which evidence type and device)
- Confidence (high for multi-source corroborated, medium for single source, low for inferred from circumstantial evidence)
- Phase (reconnaissance, initial access, lateral movement, objective, exfiltration, containment, recovery)

**Key timeline elements:**

1. **Anchor events**: high-confidence events that serve as fixed points (first alert, interface state changes, BGP / OSPF adjacency changes)
2. **Correlated events**: events linked by shared IP addresses, timestamps, or session identifiers across multiple devices
3. **Gaps**: time periods with missing evidence from devices that should have been active (document explicitly as uncertainty)
4. **Phase transitions**: points where activity shifts from reconnaissance to access, access to lateral movement, lateral movement to objective or exfiltration

**Timeline validation:** cross-reference the reconstructed timeline against multiple evidence sources. Events confirmed by two or more independent sources (e.g., firewall deny in syslog plus flow record for same session) are high confidence. Single-source events are medium confidence.

### Step 6: Post-incident documentation

Compile investigation findings into a structured evidence package. This documentation supports organisational incident response (handed off to `incident-response-lifecycle`) and any subsequent legal or compliance review.

**Required documentation artefacts:**

- Evidence inventory with chain-of-custody records (template in Evidence handling section)
- Reconstructed timeline of network events (from Step 5)
- Lateral movement map showing affected hosts and connection paths (from Step 3, if lateral movement was detected)
- Containment verification results (from Step 4)
- List of affected network devices with evidence types collected
- Identified gaps in evidence and their impact on conclusions

Hand off the completed documentation package to `incident-response-lifecycle` for the post-mortem facilitation and stakeholder communication wrapper.

## Threshold tables

### Evidence priority classification

| Priority | Evidence type | Condition | Rationale |
|----------|--------------|-----------|-----------|
| **Critical** | Active packet captures | Incident is active, payload evidence required | Live traffic cannot be recovered after the fact |
| **Critical** | ARP / MAC / CAM tables | Any incident within the last 4 hours | Aging timers overwrite entries; shortest evidence lifespan |
| **High** | Flow records | Incident time window within collector retention | Reveals communication patterns and lateral movement paths |
| **High** | Syslog events | Incident time window within log retention | Provides the event narrative: auth, config, state changes |
| **Medium** | Routing table snapshots | Suspected route manipulation or path analysis needed | Shows forwarding state but only captures current point-in-time |
| **Medium** | SNMP trap history | Corroborating physical or threshold events | Supplements syslog but with less detail |
| **Low** | Historical config archives | Baseline comparison or configuration drift analysis | Persistent data; available for later retrieval if needed |

### Containment verification criteria

| Check | Expected result | Failure indicator |
|-------|----------------|-------------------|
| ACL deny counters | Incrementing on containment rules | Zero or static counters; ACL not matching traffic |
| Null route presence | Attacker prefix routes to Null0 / discard | Route missing or overridden by dynamic protocol |
| VLAN isolation | No L3 routes to / from isolated segment | Routes exist, providing bypass path |
| Flow records post-containment | No new flows from / to attacker IPs | Continuing flows indicate containment bypass |

## Decision trees

### Evidence collection priority

```
Incident reported
├── Is the incident currently active?
│   ├── Yes (Active threat)
│   │   ├── Is payload-level evidence needed?
│   │   │   ├── Yes → Start packet capture immediately (Step 1b)
│   │   │   └── No → Proceed to ARP / MAC collection (Step 1a)
│   │   └── Simultaneously: collect ARP / MAC tables (Step 1a)
│   │       └── Then: routing snapshots (Step 1c) → flow verification (Step 1d)
│   │
│   └── No (Post-incident investigation)
│       ├── How long ago did the incident occur?
│       │   ├── Less than 4 hours → ARP / MAC tables may still have entries (Step 1a)
│       │   ├── 4-24 hours → ARP tables likely aged out; start with flow data
│       │   └── More than 24 hours → Rely on syslog and flow collector retention
│       └── Verify flow data and syslog coverage for incident window (Steps 1d, 1e)
│
├── Has containment been applied?
│   ├── Yes → Add containment verification (Step 4) after triage
│   │   └── Check ACL counters, null routes, VLAN isolation
│   └── No → Skip Step 4, proceed through Steps 1-3, 5-6
│
└── Proceed to initial triage (Step 2)
```

## Report template

```
NETWORK FORENSICS EVIDENCE SUMMARY
=====================================
Incident Reference:   [ticket / tracking number]
Investigation Period: [start] to [end] (UTC)
Network Scope:        [number] devices across [number] sites
Analyst:              [name / identifier]
Collection Date:      [date evidence collection began]

EVIDENCE INVENTORY:
| # | Device | Evidence Type | File | SHA-256 | Collected At |
|---|--------|--------------|------|---------|-------------|
| 1 | [host] | [type] | [file] | [hash] | [time UTC] |

INCIDENT TIMELINE:
| # | Time (UTC) | Device | Event | Details | Confidence |
|---|-----------|--------|-------|---------|------------|
| 1 | [time] | [host] | [event] | [details] | [H / M / L] |

LATERAL MOVEMENT MAP (if detected):
- Source host then destination host : port (first seen, last seen, byte count)
- [list all observed internal-to-internal attacker paths]

CONTAINMENT VERIFICATION:
| Control | Device | Status | Evidence |
|---------|--------|--------|----------|
| [ACL / route / VLAN] | [host] | [Effective / Bypassed] | [counter values] |

EVIDENCE GAPS:
- [device / time period with missing evidence and impact on conclusions]

RECOMMENDATIONS:
1. [network-level remediation or monitoring improvement]
2. [hand-off to incident-response-lifecycle for post-mortem]
3. [process improvements for the incident-response lifecycle]
```

## Common failure modes

### Insufficient flow data coverage

**Symptom:** flow records do not exist for devices or time windows critical to the investigation.

**Diagnosis:** verify flow export configuration on each device using the per-platform commands in Prerequisites. Check collector storage; retention may have expired for the incident time window.

**Workaround:** substitute with syslog events (lower fidelity but covers event timestamps) and ARP / MAC table correlation. Document the flow gap and its impact on lateral movement analysis completeness.

### Time synchronisation gaps

**Symptom:** events from different devices appear out of order or correlation produces implausible sequences.

**Diagnosis:** check NTP status on each device. Compare timestamps of events that should be near-simultaneous (e.g., both ends of a link-down event logged by adjacent devices).

**Workaround:** calculate clock offset per device and apply correction to the timeline. Note the correction in evidence documentation. Reduce correlation confidence for events involving desynchronised devices.

### Evidence overwritten by log rotation

**Symptom:** syslog events from the incident time window no longer exist on the device or in the SIEM.

**Diagnosis:** check device log buffer size (`show logging` to see buffer capacity and oldest retained message). Check SIEM retention policy for the relevant index.

**Workaround:** use flow records or SNMP trap history as alternative event sources. Note the syslog gap in the timeline with an explicit confidence reduction for that time period.

### Packet capture performance impact

**Symptom:** device CPU spikes or forwarding performance degrades during on-device packet capture.

**Diagnosis:** monitor CPU utilisation during capture. On-device capture processes packets in software, bypassing hardware forwarding. NX-OS `ethanalyzer` is particularly susceptible because it runs on the supervisor; broad BPF filters can saturate the management CPU.

**Workaround:** limit captures with ACL filters (capture only relevant traffic), set packet count limits (`-c` flag on EOS tcpdump; `monitor capture ... limit packets <n>` on IOS-XE), use span / mirror sessions to an external capture appliance instead of on-device capture, or reduce capture duration. If performance impact is unacceptable, stop capture and rely on flow records for metadata-level analysis.

### Incomplete ARP / MAC table recovery

**Symptom:** ARP or MAC address tables are mostly empty; entries have already aged out by the time evidence collection begins.

**Diagnosis:** default ARP aging is 4 hours; default CAM aging is 5 minutes. If more than 4 hours have elapsed since the incident, ARP entries for inactive hosts will be gone.

**Workaround:** cross-reference DHCP lease logs for IP-to-MAC mappings during the incident window. Use flow records to identify involved IP addresses without L2 mapping. Check if any NMS polled ARP / MAC tables via SNMP during the incident window.

### NX-OS uses `ip arp` not `arp`

**Symptom:** `show arp` on NX-OS returns "Invalid command" or limited output.

**Diagnosis:** NX-OS syntax is `show ip arp` for the L3 ARP table. The bare `show arp` form does not exist on NX-OS.

**Workaround:** use `show ip arp` on NX-OS. Cross-reference `network-log-analysis` skill's `references/syslog-patterns.md` for the full NX-OS command syntax catalogue.

### IOS-XR EPC unavailable on legacy platforms

**Symptom:** `monitor capture` on IOS-XR returns "feature not supported" on CRS-1 or older line cards.

**Diagnosis:** IOS-XR Embedded Packet Capture (EPC) is platform-dependent. ASR9k supports EPC on most line cards; CRS-1 support is limited to specific line-card families; NCS5500 supports EPC.

**Workaround:** use span / mirror to an external capture appliance. Or use `show controllers <intf> stats` for header-level counters where payload is not required.

## Cross-references

- `incident-response-lifecycle`: NIST 800-61 process layer wrapping this skill. Receives the completed forensics documentation package from Step 6 for post-mortem facilitation, severity classification (P1-P4 on data-risk axis), four-role assignment (IC / Tech Lead / Comms Lead / Scribe), audience-specific communications, recovery coordination, and 5-whys post-mortem with contributing-factor categorisation. Step 3 of incident-response-lifecycle explicitly hands evidence collection to this skill (the two skills are complementary: lifecycle handles process, this skill handles technical evidence).
- `oncall-runbooks`: generic devops incident container. Used for SEV-classified runbook execution, postmortem-with-5-whys, on-call handoff structure. This skill is the security-IR-flavour network-forensics arm; `oncall-runbooks` is the devops-flavour generic discipline.
- `siem-log-analysis`: SIEM-equipped log evidence retrieval. Step 1d (flow verification) and Step 2 (triage) reach for SIEM events; this skill's Step 5 (timeline reconstruction) consumes structured event output from siem-log-analysis investigations.
- `network-log-analysis`: no-SIEM raw-syslog evidence retrieval. Companion to siem-log-analysis; same role in this skill's procedure.
- `acl-rule-analysis`: containment ACL design and rule-ordering analysis. When Step 4 surfaces an ACL that is not matching attacker traffic, the rule-level analysis (shadowed rules, ordering bugs) lives in this skill.
- `cisco-firewall-audit`, `palo-alto-firewall-audit`, `fortigate-firewall-audit`, `checkpoint-firewall-audit`: when containment uses a firewall (rather than a router ACL or VLAN isolation), the verification side lives here; the firewall-side audit details live in the appropriate vendor skill.
- `wireless-security-audit`: when the incident involves wireless (rogue AP discovered, evil twin spoofing a managed SSID, RADIUS compromise affecting 802.1X, mass WIDS containment misfire), the wireless-side audit handoff lives here. Six-platform coverage (`[AireOS]` / `[IOS-XE-WLC]` / `[Aruba AOS]` / `[Aruba AOS-CX]` / `[Meraki]` / `[Mist]`) lets the post-incident SSID posture review and rogue AP classification re-baseline cover any enterprise wireless estate. This skill captures the volatile wireless evidence (AP join logs, client association history, controller packet captures); wireless-security-audit handles the post-incident posture re-assessment and remediation planning.
- `bgp-analysis`, `igp-routing-analysis`: when Step 1c routing-snapshot capture surfaces unexpected adjacency state or route hijack, the protocol-depth diagnosis lives in these skills.
- `multi-vendor-network-ops`: umbrella entry-point skill. The 9-element response contract applies on any production-impacting recommendation arising from forensics evidence.
- `systematic-debugging`: when the incident triggers a wider debugging loop (not just forensics), the four-phase loop (collect, hypothesise, test, validate) sits underneath this skill's procedure.
- `secrets-hygiene`: every evidence file goes through a redaction pass for credentials, session tokens, API keys before sharing. The chain-of-custody record format does not embed credentials.
- `utc-timestamps`: Step 5 timeline reconstruction mandates UTC; this is the authoritative source for the UTC-everywhere discipline.
- `cite-sources`: when post-incident reports cite external threat intelligence (CVEs, vendor advisories, threat-intel feeds), cite with date and identifier.
- `completion-gate` Layer 3: post-investigation verification (the suspected-malicious traffic should have stopped after containment; re-run Step 4 ACL counter check post-fix to confirm).
- `humanise-comms`: forensics reports go to mixed audiences (security analysts, executives, regulators, law enforcement). Match the audience; technical detail goes in appendices.

## Red flags

- **Paste auth key, session token, or credential in an evidence file shared outside the IR team.** Syslog messages and packet captures can contain SSH session IDs, API keys in URL parameters, RADIUS shared secrets. Audit and redact before sharing externally. The chain-of-custody record format must not embed credentials.
- **Packet capture without packet-count or duration limit.** Unbounded `monitor capture` or `ethanalyzer` can saturate device CPU and degrade forwarding. Always set `-c <n>` (EOS tcpdump) or `limit packets <n>` (IOS-XE) or duration cap.
- **Declare containment effective on zero ACL counter delta.** If `show access-lists <containment-acl>` shows the same hit counts before and after the suspected containment activation, the ACL is not matching attacker traffic. Either the ACL syntax is wrong, the wrong direction was applied (inbound vs outbound), or the attacker switched tactics. Investigate before declaring containment effective.
- **Treat ARP-aged-out as "no host present".** ARP aging is 4 hours default; CAM aging is 5 minutes. An empty ARP entry does not mean the host was never present; it means the host has been idle for longer than the aging timer. Cross-reference DHCP leases and flow records before concluding the host was absent.
- **Skip hash verification on a collected evidence file.** Without SHA-256 hash captured at collection time, you cannot later prove the file is unmodified. Chain-of-custody breaks. Hash every file the moment it is saved, before any transfer.
- **Log into a device using a shared admin account during forensics.** Attribution discipline requires per-analyst credentials so the audit log shows who executed which command. Shared accounts contaminate the audit trail and can interfere with incident attribution if the attacker also has the shared credential.
- **Execute containment from this skill.** This skill is read-only verification. Recommending or executing an ACL push, null-route injection, or VLAN-isolation config requires a change ticket, peer review, blast-radius assessment, and an explicit change-management path. Hand off to the appropriate vendor skill (`acl-rule-analysis`, the firewall audits) plus `completion-gate` Layer 3 post-checks.
- **Run `show tech-support` on a device under live attack without rate-limiting.** Tech-support output is large (10-100 MB) and CPU-intensive. On a device already under DoS or high CPU load from an active attack, tech-support collection can tip the device into unresponsiveness. Capture during a CPU lull or accept the risk.
- **Trust collector timestamps when device NTP is broken.** A collector that ingests events from a desynchronised device timestamps them at receive-time, which is wrong for forensic purposes (the event happened at the device's clock-skewed time, not the receive time). Always verify NTP per device.
- **Conflate this skill with `incident-response-lifecycle`.** This skill is network forensics (technical evidence layer). `incident-response-lifecycle` is NIST 800-61 process (severity classification, role assignment, comms, post-mortem). The two are complementary; do not try to do role-assignment or stakeholder comms work from this skill.

## Bottom line

Network forensics during security incidents is a six-step procedure: preserve volatile evidence (ARP / MAC then captures then routing then flows then config), triage scope, detect lateral movement, verify containment, reconstruct timeline, document. Read-only throughout; containment is verified, not executed. Six vendor lanes covered: classic IOS, IOS-XE, NX-OS, IOS-XR, JunOS, EOS. Every evidence file gets a SHA-256 hash at collection time; every timeline entry gets a confidence level; every report gets UTC timestamps and gaps documented. Hand off the documentation package to `incident-response-lifecycle` for the NIST 800-61 process wrapper. Network-log evidence retrieval is in `siem-log-analysis` or `network-log-analysis`; containment execution is in `acl-rule-analysis` and the firewall audits.
