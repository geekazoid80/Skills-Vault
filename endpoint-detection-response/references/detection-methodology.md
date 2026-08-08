# EDR detection methodology

How endpoint detection actually decides something is malicious, how to map and measure that against MITRE ATT&CK, and where EDR sits relative to EPP, XDR, and MDR.

## Signature-based detection (IOC-driven)

Indicators of Compromise (IOC) are artifacts that document a known breach. They are retrospective: they describe what was used in an attack that has already been seen.

Types of IOC:

- File hashes (MD5, SHA1, SHA256): exact file identity.
- IP addresses: known C2 servers, scanners.
- Domain names: malicious domains, DGA output.
- URLs: phishing pages, payload delivery endpoints.
- Registry keys: persistence mechanisms.
- Mutex names: malware-specific synchronisation objects.
- YARA rules: byte-pattern matching inside file content.

Strengths: deterministic (match equals known bad), low false-positive rate with high-quality IOCs, cheap at scale, easy to share via STIX/TAXII, MISP, and threat-intel feeds.

Weaknesses: evaded by recompile, repack, or rename; no coverage of living-off-the-land (LOLBin) attacks; goes stale fast as C2 infrastructure rotates; no detection of novel threats; hash matching fails against polymorphic or metamorphic malware.

## Behavioural detection (IOA-driven)

Indicators of Attack (IOA) focus on adversary intent and behaviour, not the specific tool or file. An IOA detects what the attacker is trying to do regardless of how they do it.

Behavioural primitives:

- Process lineage (parent/child relationships).
- Command-line argument inspection.
- Memory injection patterns (process hollowing, DLL injection, reflective loading).
- API-call sequences (OpenProcess + WriteProcessMemory + CreateRemoteThread equals injection).
- File-system access patterns (mass encryption equals ransomware).
- Network behaviour (beaconing intervals, encoded traffic, unusual ports).
- Registry modification patterns (Run keys, scheduled-task creation).
- Credential-access patterns (LSASS reads, SAM access, DCSync).

Strengths: detects novel attacks built on known techniques, resists simple obfuscation (same behaviour, different tool), catches LOLBin abuse (mshta.exe, regsvr32.exe, certutil.exe) and fileless in-memory payloads.

Weaknesses: needs tuning to control false positives, more expensive (context tracking required), coverage depends on sensor depth, and evasion is still possible by varying the technique (userland vs kernel injection).

## Machine learning and threat intelligence

- **ML / heuristics:** statistical models trained on malicious and benign samples; generalise to new variants but vary in quality and explainability.
- **Threat-intelligence correlation:** enriches detections with external context (actor attribution, campaign tracking). Implemented as Threat Graph (CrowdStrike), Threat Analytics (MDE), Unit 42 (Palo Alto), and similar.

## Detection hierarchy (most reliable to most noisy)

1. IOC match on a high-confidence feed (low false-positive, low coverage).
2. Behavioural IOA with corroborating context (medium false-positive, high coverage).
3. ML anomaly score above threshold (varies by model quality).
4. Heuristic rule match (depends on rule quality).
5. Telemetry anomaly / outlier (needs baselining, high false-positive possible).

## MITRE ATT&CK for EDR

ATT&CK documents adversary tactics, techniques, and sub-techniques observed in the wild and gives a common language for describing behaviour.

Enterprise tactics:

| Tactic | ID | Goal |
|---|---|---|
| Reconnaissance | TA0043 | Gather information before the attack |
| Resource Development | TA0042 | Establish attack infrastructure |
| Initial Access | TA0001 | Get into the environment |
| Execution | TA0002 | Run malicious code |
| Persistence | TA0003 | Survive reboots |
| Privilege Escalation | TA0004 | Gain higher permissions |
| Defense Evasion | TA0005 | Avoid detection |
| Credential Access | TA0006 | Steal credentials |
| Discovery | TA0007 | Map the environment |
| Lateral Movement | TA0008 | Move through the network |
| Collection | TA0009 | Gather data of interest |
| Command and Control | TA0011 | Communicate with compromised systems |
| Exfiltration | TA0010 | Steal data |
| Impact | TA0040 | Disrupt operations (ransomware, wiper) |

### High-value techniques for endpoint coverage

Execution (TA0002), highest detection priority:

- T1059.001 PowerShell: `powershell.exe -enc`, `Invoke-Expression`, `-nop -w hidden`.
- T1059.003 Windows command shell: `cmd.exe /c`, unusual parent processes.
- T1059.005 Visual Basic: mshta.exe running VBS.
- T1059.007 JavaScript: wscript.exe, cscript.exe.
- T1047 WMI: `wmic process call create`.
- T1053 Scheduled tasks: `schtasks /create`.

Defense Evasion (TA0005), hardest to detect:

- T1055 Process injection (all sub-techniques).
- T1036 Masquerading (process names mimicking system binaries).
- T1070.001 Clear Windows event logs.
- T1562.001 Impair defenses (disabling AV/EDR).
- T1218 Signed binary proxy execution (LOLBins).
- T1027 Obfuscated files (encoding, packing, encryption).

Credential Access (TA0006), high impact:

- T1003.001 OS credential dumping: LSASS memory.
- T1003.002 SAM database.
- T1558 Steal or forge Kerberos tickets (pass-the-ticket, Kerberoasting).
- T1552 Unsecured credentials in files or registry.

### Coverage evaluation process

1. Define the threat model: which actors target your industry?
2. Map those actors' TTPs with ATT&CK Navigator.
3. Read the published MITRE ATT&CK evaluations for candidate platforms.
4. Run purple-team exercises to validate actual coverage.
5. Prioritise gaps by impact (technique criticality times frequency).
6. Treat vendor coverage claims as marketing; validate independently.

## EDR vs EPP vs XDR vs MDR

- **EPP (Endpoint Protection Platform):** prevention-first, NGAV, blocks at execution. The wall.
- **EDR (Endpoint Detection and Response):** detection and response for what gets past the wall; endpoint-centric telemetry (process, file, registry, network from the host view).
- **XDR (Extended Detection and Response):** correlation across endpoint, network, cloud, identity, and email; reduces alert fatigue by merging related signals into one incident.
- **MDR (Managed Detection and Response):** a managed-service wrapper (human SOC) around EDR or XDR; OverWatch, Sophos MDR, Vigilance, Unit 42 MXDR.

### EDR blind spots that drive XDR

EDR alone misses:

- Network-based lateral movement (no agent on network devices).
- Cloud workload attacks where no agent is deployed.
- Identity attacks with no endpoint artifact (Kerberos abuse inside AD).
- Email-delivered threats (a phishing link clicked in a browser leaves minimal endpoint signal).

### Cross-domain example (phishing to ransomware)

1. Email gateway: phishing email with an Office attachment delivered (email telemetry).
2. Endpoint: Word.exe spawns PowerShell (endpoint telemetry, EDR catches this).
3. Network: outbound connection to a C2 IP (network telemetry).
4. Identity: lateral movement with stolen credentials (identity telemetry).
5. Endpoint: mass file encryption (endpoint telemetry, EDR catches this).

XDR correlates steps 1 to 5 into one incident. EDR alone sees only steps 2 and 5 and leaves the rest to manual correlation. This is why the SIEM/SOAR and network-detection-response skills are siblings to this one, not afterthoughts.
