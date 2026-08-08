# Network forensics and threat hunting

Reconstructing what happened on the wire: evidence sources, a repeatable investigation method, retention, per-protocol detection patterns, and how network detection maps to ATT&CK.

## Forensic evidence sources

| Source | Tool | Strength | Cost |
|---|---|---|---|
| Full packet capture (PCAP) | Zeek, Suricata, tcpdump | Complete record, session reconstruction, payload recovery | ~450 GB/hour at 1 Gbps continuous |
| Flow data (NetFlow/IPFIX/sFlow) | Router/switch, flow collectors | 50 to 100x more storage-efficient than PCAP | Cannot reconstruct sessions or payloads |
| Zeek logs | Zeek | Structured application-layer metadata, best balance | 1 to 5 percent of PCAP volume |
| IDS/IPS alerts | Suricata, Snort | High-signal events with rule context | Only matched traffic, not background |

Practical stance: PCAP on high-value segments with rolling 24 to 72 hour retention; Zeek logs everywhere for the metadata; flow data for long-term retention and anomaly baselining; IDS alerts for high-signal triggers. Zeek is the workhorse: rich forensic value at manageable storage cost.

## Investigation methodology

**Phase 1: scoping.** Define the time window, identify known-compromised IPs/hostnames, establish initial indicators (a malware domain, a C2 IP, a suspicious process from EDR).

**Phase 2: connection analysis.** Review Zeek conn.log for all connections to and from affected hosts. Look for new external connections post-compromise (beaconing intervals, new destinations) and internal connections from the compromised host (lateral movement candidates).

**Phase 3: protocol deep-dive.**

- DNS: new domains post-compromise, high-entropy names, TXT queries (exfiltration).
- HTTP/HTTPS: unusual user agents, POSTs to new destinations, large response sizes.
- SMB: new share access, named-pipe usage (lateral-movement tool indicators).
- Kerberos/NTLM: service-ticket requests (Kerberoasting), NTLM on non-domain hosts.

**Phase 4: timeline correlation.** Merge the network timeline with endpoint telemetry (EDR process tree, file events). Attacker activity should line up across network and host; gaps in host logging are often filled by network evidence. This is where `endpoint-detection-response` and this skill meet.

**Phase 5: IOC extraction.** Document new IOCs for blocking and sharing: file hashes (Zeek files.log, Suricata file-store), C2 IPs, domains, URLs, JA3 hashes, certificate fingerprints.

## Retention guidance

| Data type | Minimum | Recommended |
|---|---|---|
| IDS/IPS alerts | 90 days | 1 year |
| Flow data | 90 days | 1 year |
| Zeek logs | 30 days | 90 days |
| PCAP (full) | 24 to 72 hours | 7 days (high-value segments) |
| DNS logs | 30 days | 90 days |

## Per-protocol detection patterns

**DNS:** C2 tunneling (high-entropy subdomains, long query strings, TXT queries), DGA (many NX domains from one host), fast-flux (rapidly changing A records), DNS-over-HTTPS (bypasses traditional DNS monitoring).

**HTTP/HTTPS:** C2 beaconing (regular-interval connections to the same destination), exfiltration (large POSTs, encoded data in URIs or headers), malware staging (executable downloads, MIME/extension mismatch), domain fronting (TLS SNI differs from HTTP Host header).

**SMB:** lateral movement (new C$/ADMIN$/IPC$ connections from non-admin hosts), ransomware (mass file rename/access), named pipes (used by Cobalt Strike, Metasploit, and similar).

**Kerberos:** Kerberoasting (AS-REQ for service tickets with RC4 from unusual hosts), pass-the-ticket (service-ticket use from an unexpected source IP), golden/silver ticket (anomalous lifetimes or encryption types).

**NTLM:** pass-the-hash (NTLM auth from an unexpected source), NTLM relay (auth forwarding to a different target). NTLM should be largely absent in modern environments that negotiate Kerberos.

## MITRE ATT&CK network coverage

| Tactic | Network indicators | Detection tools |
|---|---|---|
| Initial Access | Exploit traffic, phishing payloads, drive-by | Suricata/Snort rules (ET rules) |
| Execution | C2 beacon patterns, staged payloads over HTTP/HTTPS | Suricata JA3/JA4, DNS anomalies |
| Persistence | DNS-based C2, beacon regularity | Zeek DNS log analysis, beacon detection |
| Lateral Movement | SMB/RPC lateral, pass-the-hash, WMI | Suricata SMB rules, Zeek smb.log/ntlm.log |
| Command and Control | C2 protocols, domain fronting, DNS tunneling | Suricata C2 rules, Zeek DNS analysis |
| Exfiltration | Large outbound transfers, DNS exfil, HTTPS exfil | Zeek conn.log volume anomalies, DNS TXT |
| Credential Access | Kerberoasting, NTLM capture, credential spray | Zeek kerberos.log/ntlm.log, failed auth |
| Discovery | Network scanning, ARP and ICMP sweeps | Suricata scan detection, Zeek scan scripts |

### Detection coverage tiers

```
Tier 1: known threats     -> Suricata/Snort rules (ET Open/Pro, Talos)
Tier 2: protocol analysis -> Zeek logs (all protocol metadata)
Tier 3: behavioural       -> SIEM correlation across Zeek + IDS alerts
Tier 4: threat hunting    -> Zeek + PCAP for analyst-driven investigation
```

## The attacker's east-west playbook

Understanding the pattern is what makes lateral-movement detection possible:

1. **Initial foothold:** external-facing system compromised (a north-south event).
2. **Local reconnaissance:** ARP scan, net commands, LDAP queries.
3. **Credential theft:** LSASS dump, Kerberoasting, NTLM capture.
4. **Lateral movement:** pass-the-hash, pass-the-ticket, RDP, SMB, WMI.
5. **Privilege escalation:** domain-controller targeting, ACL abuse.
6. **Objectives:** ransomware staging, data collection, persistence.

Detection at steps 2 to 5 requires east-west visibility. Without it, initial access (step 1) is the only opportunity, and by the time impact (step 6) shows on the perimeter it is too late.
