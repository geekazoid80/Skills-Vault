# Network detection and control platform selection

Comparisons across the three categories: IDS/IPS, NAC, and micro-segmentation. The platforms below are named as routing context only; the vault keeps the generic methodology and skips the vendor deep-dives. Validate capability claims against current vendor documentation.

## IDS/IPS

Passive (IDS) or inline (IPS) analysis of traffic for malicious patterns.

| Technology | Mode | Primary strength | Best for |
|---|---|---|---|
| **Suricata** | IDS/IPS/NSM | Performance, EVE JSON, protocol parsers | High-throughput, structured logging, SIEM integration |
| **Snort 3** | IDS/IPS | Talos rules, OpenAppID, hyperscan | Cisco ecosystem, Talos threat-intel subscribers |
| **Zeek** | Passive NSM | Protocol analysis, scripting, structured logs | Network forensics, threat hunting, behavioural analytics |

Decision factors:

- **Throughput:** Suricata is multi-threaded and scales better than Snort on multi-core hardware.
- **Detection approach:** rules-based (Suricata/Snort) vs behavioural/scripting (Zeek). Deploy both for full coverage.
- **Logging:** Zeek produces richer metadata; Suricata EVE JSON covers alerts plus metadata.
- **Operational maturity:** Snort has the largest community and simplest rules; Zeek requires scripting skill.
- **SIEM fit:** all three integrate with the major SIEMs; verify connector quality for your platform.

A well-tuned open-source deployment often outperforms a poorly tuned commercial appliance. Tuning matters more than the badge.

## Network access control (NAC)

Controls which devices connect, by identity, posture, and policy.

| Technology | Vendor | Primary strength | Best for |
|---|---|---|---|
| **Cisco ISE** | Cisco | Comprehensive 802.1X, TrustSec SGT, pxGrid | Cisco environments, large enterprise |
| **Aruba ClearPass** | HPE/Aruba | Multi-vendor support, OnGuard posture, API | Mixed-vendor networks, Aruba wireless |
| **FortiNAC** | Fortinet | Agentless profiling, FortiGate integration | Fortinet-heavy environments, OT/IoT |

Decision factors:

- **Network vendor:** ISE is strongest in Cisco shops; ClearPass excels in mixed-vendor estates.
- **OT/IoT presence:** all three profile IoT; FortiNAC has strong agentless options.
- **Posture assessment:** ISE (AnyConnect), ClearPass (OnGuard), FortiNAC (persistent or dissolvable agents).
- **Cloud NAC:** ISE has cloud-delivered options; all support RADIUS cloud proxies.

## Micro-segmentation

Granular east-west segmentation enforced at the workload level, independent of topology.

| Technology | Vendor | Approach | Best for |
|---|---|---|---|
| **Illumio** | Illumio | VEN agent + PCE, label-based policy, OS firewall enforcement | Enterprise data centres, zero-trust segmentation |
| **Guardicore** | Akamai | Agent and agentless, process-level, deception | Mixed environments, incident-response visibility |

Decision factors:

- **Environment:** both work in hybrid; Illumio CloudSecure and Guardicore both support cloud workloads.
- **Deception:** Guardicore Centra includes honeypot/deception; Illumio does not natively.
- **Policy model:** Illumio's label-based model (role/app/env/loc) is more structured; Guardicore is more flexible.
- **Agent vs agentless:** Guardicore supports agentless (network-based visibility); Illumio requires the VEN agent.

## Putting the three together

These categories are complementary, not competing:

- **IDS/IPS + NSM** answer "is this traffic malicious, and what happened?"
- **NAC** answers "should this device be on the network at all?"
- **Micro-segmentation** answers "should these two workloads be allowed to talk?"

A mature programme runs all three and feeds their telemetry into `siem-soar-investigation` for correlation, with `endpoint-detection-response` covering the host view the wire cannot see.
