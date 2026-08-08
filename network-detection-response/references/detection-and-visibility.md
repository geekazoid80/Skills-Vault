# Network detection and visibility

The difference between IDS, IPS, and NSM; how detection is classified; how to get traffic to a sensor; and why east-west and encrypted traffic are the hard parts.

## IDS vs IPS vs NSM

### Intrusion Detection System (IDS)

Passively monitors traffic and alerts on suspicious patterns. Does not block. Fed by a SPAN/mirror port or a TAP.

- Pros: no impact on performance or availability, safe to deploy (cannot cause an outage), can analyse retrospectively.
- Cons: cannot block in real time, alert-only (needs a human or SOAR to act), alert volume causes fatigue without tuning.

### Intrusion Prevention System (IPS)

Deployed inline. Can drop packets, reset connections, or enforce policy in real time.

- Pros: active blocking of known threats, cuts attacker dwell time for detected threats.
- Cons: single point of failure without bypass/fail-open, adds latency (typically 10 to 100 microseconds for software IPS), a false positive blocks legitimate traffic. Tune thoroughly before enabling inline blocking.

### Network Security Monitor (NSM)

Focused on rich metadata capture and behavioural analysis rather than alerting. Zeek is the canonical NSM tool.

- IDS answers "Was this traffic malicious?"
- NSM answers "What happened on this network?", even without a signature match.

### Deployment decision framework

```
Is blocking required?
  Yes -> inline IPS (Suricata/Snort NFQ or AF_PACKET inline)
  No  -> passive IDS

Is forensic investigation a requirement?
  Yes -> add Zeek for metadata-rich logging alongside the IDS

What is the throughput?
  < 1 Gbps   -> single Suricata instance with AF_PACKET
  1 to 10 Gbps -> Suricata with PF_RING or multi-queue AF_PACKET
  > 10 Gbps  -> Zeek cluster + Suricata with DPDK or AF_PACKET workers
```

## Detection taxonomy

### By detection method

- **Signature-based:** matches known byte patterns, protocol fields, or behaviours. Fast, deterministic, low false-positive for covered threats; blind to zero-days and obfuscated variants. Formats: Suricata rules, Snort rules, YARA (file-based).
- **Protocol-anomaly:** compares observed behaviour against the RFC; flags violations that indicate exploitation or evasion. Suricata and Zeek both carry deep protocol parsers.
- **Behavioural/statistical:** baselines normal and alerts on deviation (unusual DNS volume, a new service on a host, beaconing regularity). Higher false-positive rate; needs a tuning period. Zeek scripting is the main mechanism.
- **Heuristic/ML:** models trained on labelled traffic; increasingly common commercially; need good training data and can be fooled by adversarial inputs.
- **Threat-intelligence:** matches network indicators against external feeds (Suricata datasets, Zeek Intelligence Framework). Covers only known-bad infrastructure.

### By traffic direction

- **Ingress (inbound):** internet-origin attacks (exploitation, scanning, DDoS, phishing payloads); highest noise, most rule coverage.
- **Egress (outbound):** C2 beaconing, exfiltration, DNS tunneling; often under-monitored, yet post-compromise activity is mostly egress.
- **Lateral (east-west):** attacker movement after the foothold; needs internal sensors or micro-segmentation visibility; the most forensically important traffic.

## The visibility problem

Modern networks fight five visibility challenges:

1. **Encryption:** 80 to 95 percent of traffic is TLS; payload inspection is limited without decryption.
2. **East-west blindness:** perimeter sensors miss internal lateral movement.
3. **Cloud workloads:** cloud-native traffic can bypass on-prem sensors entirely.
4. **High throughput:** 10/40/100 Gbps segments exceed software sensor capacity without tuning.
5. **Ephemeral workloads:** containers and VMs cycle faster than agent deployment.

### Visibility coverage model

| Layer | Data source | Coverage |
|---|---|---|
| Perimeter | Suricata/Snort inline + Zeek | North-south ingress/egress |
| Internal core | Zeek on core switch SPAN | East-west between VLANs/subnets |
| Data centre | Micro-segmentation (Illumio/Guardicore) | Workload-to-workload |
| Wireless | NAC + wireless controller logs | Client network access |
| Cloud | VPC flow logs + cloud-native IDS | Cloud workload traffic |
| DNS | Recursive resolver logging | All DNS activity |
| DHCP | DHCP server logs | IP-to-MAC-to-hostname mapping |

## Traffic-access methods

| Method | Pros | Cons | Use when |
|---|---|---|---|
| **Physical TAP** | Lossless, passive, no impact, cannot fail | Hardware cost | High-value segments where loss is unacceptable |
| **SPAN/mirror port** | No hardware needed | Switch CPU impact, oversubscription drops packets, not guaranteed lossless | Lower-priority or dev segments |
| **Inline (bump-in-wire)** | IPS capability, can block | Single point of failure, latency; needs hardware bypass for HA | Internet edge where blocking is required |
| **AF_PACKET (NIC bypass)** | High throughput, bypass on failure | Linux only | High-throughput Suricata |
| **Cloud VPC mirroring** | AWS/Azure/GCP support | Cost at scale, sampling | Cloud workload visibility |

**Packet/network brokers** (Gigamon, Ixia/Keysight) aggregate traffic from many TAPs/SPANs, then filter, deduplicate, and load-balance to multiple tools. Essential at scale: one tap feed shared across several sensors cuts cost.

## East-west vs north-south

**North-south** is perimeter traffic (internet-facing): highest threat exposure, most historical investment, richest rule coverage. Detection priority: exploitation, phishing payloads, scanning, DDoS, exfiltration to internet C2.

**East-west** is lateral, internal traffic: often 70 to 80 percent of total volume, historically trusted because "internal", and where most dwell time and damage happen post-breach. Detection priority: lateral movement (SMB, WMI, RDP, SSH), credential relay (NTLM, Kerberos anomalies), internal reconnaissance (port scans, LDAP enumeration), ransomware propagation. Detecting at the lateral-movement stage requires east-west visibility; without it, the only detection opportunity is initial access.

## The encrypted-traffic challenge

With most traffic encrypted, fingerprint rather than decrypt:

1. **TLS inspection proxy:** decrypt at the perimeter; legal and privacy considerations apply.
2. **JA3/JA4 fingerprinting:** client TLS fingerprint for C2 detection without decryption (Suricata supports this).
3. **Certificate analysis:** self-signed, expired, or suspicious issuers (Zeek ssl.log).
4. **Flow metadata:** volume, timing, and duration patterns in encrypted sessions.
5. **DNS analysis:** a pre-connection indicator; note that DNS-over-HTTPS creates a blind spot.
