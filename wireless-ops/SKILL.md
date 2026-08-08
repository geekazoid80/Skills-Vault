---
name: wireless-ops
description: "Use for wireless LAN OPERATIONS: deploying, configuring, optimising, and troubleshooting enterprise wireless networks across Cisco Catalyst 9800 (IOS-XE-WLC), Aruba (AOS 8 Mobility Controller and AOS 10 / Central), Juniper Mist, and Cisco Meraki. References: cisco-wireless.md, aruba-wireless.md, juniper-mist.md, meraki-wireless.md, rf-design.md. Triggers include \"wireless operations\", \"WLAN config\", \"RF optimisation\", \"RRM tuning\", \"channel planning\", \"AP density\", \"roaming optimisation\", \"band steering\", \"DFS event\", \"client connectivity troubleshooting\", \"wireless deployment\", \"Catalyst 9800 config\", \"C9800\", \"FlexConnect\", \"Aruba Central\", \"AOS 10\", \"AirMatch\", \"ClearPass wireless\", \"Mist AI\", \"Marvis\", \"SLE\", \"Mist Edge\", \"Meraki wireless\", \"Meraki SSID\", \"RF profiles\", \"site survey\", \"Wi-Fi 6\", \"Wi-Fi 6E\", \"Wi-Fi 7\", \"802.11ax\", \"802.11be\", \"MLO\", \"OFDMA\", \"WLC troubleshooting\", \"AP join failure\", \"radioactive trace\", \"RRM DCA\", \"channel utilisation\", \"signal quality\", \"client roaming\", \"SSID management\", \"wireless health assessment\". For wireless SECURITY audit (SSID encryption posture, 802.1X/RADIUS validation, rogue AP triage, WLAN compliance) see wireless-security-audit; for multi-vendor switching/routing context see multi-vendor-network-ops."
license: MIT
metadata:
  version: 1.0.0
---

# Wireless operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: wireless-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Enterprise wireless operations spans four major platforms, each with a distinct management model and RF automation approach. This skill owns the day-2 operations loop: RF planning, deployment, client health monitoring, RF tuning, and troubleshooting. Security posture review (SSID encryption audit, 802.1X/RADIUS validation, rogue AP triage) belongs in `wireless-security-audit`.

## When to use

- Deploying or configuring WLANs, SSID profiles, policy profiles, or RF profiles on Catalyst 9800, Aruba Central, Mist, or Meraki.
- Troubleshooting AP join failures, client connectivity issues, roaming failures, or poor wireless performance.
- Tuning RF: channel planning, power settings, RRM/AirMatch/auto-RF optimisation, DFS event response.
- Running a wireless health assessment across one or more platforms.
- Selecting a wireless platform for a new deployment or migration.
- Designing AP density, coverage, and capacity for a site survey.
- Configuring FlexConnect, Mist Edge, or Aruba gateway for branch/remote sites.

## When not to use

- **Wireless security audit** (SSID encryption posture, WPA3 compliance, 802.1X/RADIUS validation, rogue AP classification, WIDS/WIPS posture, PCI DSS wireless): use `wireless-security-audit`.
- **Consumer-grade or home Wi-Fi**: out of scope; vendor consumer docs apply.
- **Wired switching and routing context**: for the broader network environment, use `multi-vendor-network-ops`.
- **Pure BGP/IGP or ACL analysis**: use `bgp-analysis`, `igp-routing-analysis`, or `acl-rule-analysis`.

## Platform selection

| Platform | Management model | RF automation | Cloud vs on-prem | When to pick |
|---|---|---|---|---|
| Cisco Catalyst 9800 (IOS-XE-WLC) | On-prem WLC or VM; optional Catalyst Center | RRM (DCA, TPC, CHD, FRA, CleanAir) | On-prem or cloud VM; Catalyst Center for SD-Access | Cisco campus ecosystems; SD-Access fabric; NETCONF/RESTCONF automation; large campus with on-prem control requirement |
| Aruba AOS 8 (Mobility Controller) | On-prem Mobility Controller | ARM (Adaptive Radio Management) | On-prem; legacy | Existing AOS 8 installs; migration planning to AOS 10 |
| Aruba AOS 10 / Central | Cloud-managed via Aruba Central (HPE GreenLake) | AirMatch (cloud AI, daily batch) | Cloud management, local data plane | Cloud-first deployment; strong NAC (ClearPass); dynamic segmentation; SD-WAN convergence at branch |
| Juniper Mist | AI-native cloud SaaS | Mist RRM (AI-driven, per-AP) | Cloud; Mist Edge for on-prem data plane | AIOps priority; SLE-based monitoring; unified wired/wireless/WAN via single dashboard; indoor location services |
| Cisco Meraki | Cloud dashboard | Auto-RF | Cloud | Distributed or SMB deployments; MSP management; simple SSID operations via dashboard/API |

Quick decision guide:
- Cisco campus, SD-Access, or on-prem WLC required: Catalyst 9800.
- Cloud-managed with advanced NAC and gateway security: Aruba AOS 10 / Central.
- AI-driven ops, SLE visibility, unified wired/wireless/WAN: Juniper Mist.
- Simple cloud ops, MSP, or Meraki-already-deployed: Cisco Meraki.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Cisco Catalyst 9800 | Tag/profile model (WLAN, Policy, RF, Site, AP Join, Flex), deployment modes (centralised/FlexConnect/SD-Access/EWC), RRM (DCA/TPC/CHD/FRA/CleanAir), radioactive tracing, client diagnostics, AP join troubleshooting, Wi-Fi 7 on IOS-XE 17.15 | `references/cisco-wireless.md` |
| Aruba (AOS 8 and AOS 10 / Central) | AOS 10 cloud architecture, Aruba Central management, AirMatch RF optimisation, ClearPass integration (ops context: role assignment, VLAN, profiling), dynamic segmentation, gateway deployment, AP families, AOS 8 vs AOS 10 differences | `references/aruba-wireless.md` |
| Juniper Mist | Mist AI cloud, Marvis conversational AI, Marvis Minis proactive testing, SLE metrics and classifiers, Mist Edge, Wired/WAN Assurance, BLE/vBLE location services, Mist REST API | `references/juniper-mist.md` |
| Cisco Meraki | Dashboard SSID management, RF profile configuration, channel-utilisation and signal-quality metrics, client connectivity troubleshooting workflows, Meraki MCP server tools | `references/meraki-wireless.md` |
| RF design | Wi-Fi 6/6E/7 standards (OFDMA, MU-MIMO, BSS Coloring, MLO, 6 GHz, WPA3), site survey methodology (predictive/passive/active), channel and power planning per band, DFS, roaming protocols (802.11k/v/r, OKC), capacity vs coverage design | `references/rf-design.md` |

## RF and operations in one screen

The day-2 wireless operations loop:

```
1. RF planning (site survey, capacity model, channel plan)
   -> references/rf-design.md

2. Deploy (WLC/cloud provisioning, AP join, SSID/profile config)
   -> vendor reference for the platform in scope

3. Monitor (SLE/client health dashboards, RRM/AirMatch reports, channel utilisation, SNR)
   -> references/juniper-mist.md (SLE), references/meraki-wireless.md (channel util/signal quality),
      references/cisco-wireless.md (show commands), references/aruba-wireless.md (Central alerts)

4. Tune (RRM DCA/TPC overrides, AirMatch maintenance windows, band steering, data-rate policy)
   -> vendor reference for the platform in scope

5. Troubleshoot (client-specific: radioactive trace / Marvis / client events; site-wide: RF heatmap, capacity)
   -> references/cisco-wireless.md (radioactive tracing, AP join debugging)
      references/aruba-wireless.md (Central monitoring, AP CLI)
      references/juniper-mist.md (Marvis Actions, SLE classifiers)
      references/meraki-wireless.md (client connectivity events workflow)
```

Security posture review (step 6 in `wireless-security-audit`) is deliberately separated. Ops and audit use different toolsets and different change authorities.

## Cross-references

- `wireless-security-audit`: security half of wireless operations. SSID encryption posture, 802.1X/RADIUS validation, rogue AP triage, PMF audit, WIDS/WIPS review, WPA3 migration, PCI DSS wireless compliance. Cross-check with this skill when an ops change has a security impact (e.g. adding a new SSID, changing VLAN assignment, adjusting containment policy).
- `multi-vendor-network-ops`: umbrella entry point for mixed wired/wireless operations. The nine-element response contract (assumptions, risk, evidence, recommendation, pre-checks, execution, post-checks, rollback, escalation) applies to any production-impacting wireless config change.
- `incident-response-network`: wireless incident response (mass deauth, RADIUS outage, AP flap storm, coverage collapse). Hands back to this skill for post-incident RF normalisation.
- `acl-rule-analysis`: wired-side ACL enforcement of wireless VLANs; use after SSID or VLAN changes that affect inter-VLAN routing.
- `pyats-network-automation`: live device-state collection from Catalyst 9800 and other IOS-XE platforms; pairs with radioactive tracing and RF diagnostics.
- `secrets-hygiene`: RADIUS shared secrets, Meraki API keys, Mist API tokens, Aruba Central OAuth2 tokens; handle per the hygiene discipline, never inline in automation scripts.
- `utc-timestamps`: all wireless event timestamps, audit logs, and maintenance windows must be expressed in UTC.
- `oncall-runbooks`: wireless-specific runbooks (RADIUS outage, AP join failure, channel storm, Mist SLE breach).

## Red flags

- **Changing channel or power plans in production without a maintenance window.** RRM/AirMatch plan pushes and manual channel reassignments cause brief client disconnections. Schedule changes for off-peak windows; notify stakeholders.
- **Disabling DFS channels without a prior RF survey.** Removing DFS channels concentrates clients onto fewer non-DFS channels, increasing co-channel interference. Verify non-DFS channel capacity supports the AP density before removing DFS from the DCA list.
- **Modifying live SSIDs during business hours.** Changes to SSID authentication type, VLAN assignment, or band restrictions disconnect all clients on that SSID. Flag as change-controlled.
- **Enabling 6 GHz without WPA3.** The 6 GHz band and Wi-Fi 7 certified deployments mandate WPA3; there is no WPA2 fallback. Ensure RADIUS infrastructure and client fleet support WPA3-Enterprise or WPA3-Personal (SAE) before activating 6 GHz SSIDs.
- **Mixing deployment modes on a single WLC without documented intent.** Mixing centralised and FlexConnect APs on the same WLC under the same Site Tag produces unpredictable VLAN behaviour. Document the mode per AP group.
- **Tuning RRM/AirMatch overrides without a measurement baseline.** Over-tuning (static channels, pinned power) often degrades RF compared to the platform default. Measure first; tune only when the default is measurably failing.
- **Upgrading all APs simultaneously.** Always stagger AP firmware upgrades (N+1 pattern or per-floor groups); upgrading all APs at once creates a complete wireless outage for the AP reboot window.

## Bottom line

Load the vendor reference that matches the platform in scope. For cross-platform or architectural questions, use the platform-selection table and `rf-design.md` for the RF fundamentals. All production-impacting changes follow the `multi-vendor-network-ops` nine-element contract. Security posture review is a separate concern owned by `wireless-security-audit`; call it explicitly when security is in scope.
