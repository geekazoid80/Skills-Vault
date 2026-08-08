# Detection engineering

Turning threat knowledge into tuned, measured, version-controlled detections. Platform-agnostic methodology; the SIGMA format keeps the logic portable across SIEMs.

## Detection-engineering lifecycle

```
1. Threat intelligence   ->  What threats target our environment?
2. Data-source mapping   ->  Do we have visibility? (MITRE ATT&CK data sources)
3. Detection logic       ->  Write rules (platform-native or SIGMA)
4. Testing and validation->  Atomic Red Team, Caldera, manual simulation
5. Tuning                ->  Reduce false positives, add exceptions, refine thresholds
6. Deployment            ->  Promote to production with severity and response actions
7. Metrics and maintenance-> Track coverage, MTTD, alert fidelity, rule decay
```

The loop never closes: rules decay as environments and attacker tradecraft change. Schedule periodic re-validation, not just one-time authoring.

## Correlation rule types

| Type | Description | Example |
|---|---|---|
| Single-event | One event matches a condition | Failed login from a blocked country |
| Threshold | Count exceeds a limit in a window | > 10 failed logins in 5 minutes |
| Sequence | Events occur in a specific order | Login -> privilege escalation -> data access within 1 hour |
| Aggregation | Statistical anomaly in grouped events | User accessing 10x more files than peer group |
| Absence | An expected event does not occur | No heartbeat from a critical server in 10 minutes |
| Temporal proximity | Related events across sources in a window | VPN login from country A and badge swipe in country B within 2 hours |

### Correlation best practices

1. Start with high-fidelity, low-volume rules. A rule firing once a week at 90% true-positive beats one firing 100 times a day at 5%.
2. Correlate across data sources. Single-source detections are easy to evade; EDR plus identity plus network is harder to bypass.
3. Use risk-based alerting. Assign risk points per event; alert when an entity's cumulative score crosses a threshold.
4. Include context in every alert: what happened, who/what was involved, when, where (asset, segment), why it matters (ATT&CK technique), and suggested next steps.
5. Version-control detections. Git for history, CI/CD for deployment, peer review for changes.

## SIGMA rule language

SIGMA is the vendor-agnostic detection format. One rule compiles to many platforms.

### Rule structure

```yaml
title: Descriptive name of the detection
id: UUID (globally unique, persistent)
related:
    - id: UUID-of-related-rule
      type: derived | obsoletes | merged | renamed | similar
status: test | stable | experimental | deprecated | unsupported
description: What this rule detects and why
references:
    - https://link-to-threat-research
author: Author name
date: YYYY/MM/DD
modified: YYYY/MM/DD
tags:
    - attack.execution          # tactic
    - attack.t1059.001          # technique
logsource:
    category: process_creation | network_connection | file_event | ...
    product: windows | linux | macos | ...
    service: sysmon | security | ...
detection:
    selection:
        FieldName|modifier: value
    filter:
        FieldName: value_to_exclude
    condition: selection and not filter
fields:
    - CommandLine
    - ParentImage
falsepositives:
    - Legitimate admin tool usage
level: informational | low | medium | high | critical
```

### SIGMA modifiers

| Modifier | Meaning | Example |
|---|---|---|
| `contains` | Substring match | `CommandLine\|contains: '-enc'` |
| `startswith` | Prefix match | `Image\|startswith: 'C:\Temp'` |
| `endswith` | Suffix match | `Image\|endswith: '.ps1'` |
| `all` | All listed values must match | `CommandLine\|contains\|all:` then a list |
| `base64` | Match a base64-encoded value | `CommandLine\|base64: 'malicious string'` |
| `re` | Regular expression | `CommandLine\|re: '.*-e[nc]{0,3}o.*'` |
| `cidr` | CIDR range match | `DestinationIp\|cidr: '10.0.0.0/8'` |
| `windash` | Match Windows dash variants (-, /) | `CommandLine\|windash\|contains: '-bypass'` |

### Worked example

```yaml
title: Suspicious PowerShell Download Cradle
id: 3b6ab547-8ec2-4991-b9d2-2b06702a48d7
status: stable
description: Detects PowerShell download cradles commonly used by attackers
logsource:
    category: process_creation
    product: windows
detection:
    selection:
        CommandLine|contains|all:
            - 'powershell'
            - 'Net.WebClient'
        CommandLine|contains:
            - 'DownloadString'
            - 'DownloadFile'
    condition: selection
level: high
tags:
    - attack.execution
    - attack.t1059.001
```

Compiles, for instance, to Splunk SPL (`CommandLine="*powershell*Net.WebClient*DownloadString*"`), Sentinel KQL (`has_all(...) and has_any(...)`), Elastic EQL (process-creation match), QRadar AQL (normalised-field SQL), and Chronicle YARA-L (`target.process.command_line` conditions).

### SIGMA backends

Use pySigma plus sigma-cli (the successor to sigmac):

```bash
sigma convert -t splunk -p sysmon rule.yml          # Splunk SPL
sigma convert -t microsoft365defender rule.yml      # Sentinel KQL
sigma convert -t lucene rule.yml                     # Elastic (Lucene)
sigma convert -t qradar rule.yml                     # QRadar AQL
```

## MITRE ATT&CK mapping

Map detections to ATT&CK to measure coverage and find gaps.

1. Identify relevant techniques. Not all 200+ apply; filter by platform (Windows, Linux, cloud, network) and threat profile.
2. Map data sources. Each technique lists the data sources it needs; verify you collect them.
3. Write multiple detections per technique (different sources, different fidelity).
4. Track coverage with ATT&CK Navigator; visualise gaps and prioritise them.

## Detection quality tiers

| Tier | Basis | Characteristics |
|---|---|---|
| Tier 1 | IOC-based (IPs, hashes, domains) | Fast to create, trivially evaded, short shelf life |
| Tier 2 | Behavioural signatures (tool/technique patterns) | Medium effort, moderate evasion resistance |
| Tier 3 | Behavioural analytics (anomalous behaviour) | High effort, hard to evade, higher false-positive rate |
| Tier 4 | ML-driven (deviation from baseline) | Highest effort, needs training data, best for novel threats |

Mature programmes invest mostly in Tier 2 and Tier 3.

## Detection-as-code

Treat rules like software: a repository, tests, conversion pipelines, and CI.

```
detection-rules/
|-- rules/
|   |-- windows/process_creation/powershell_download_cradle.yml
|   |-- windows/registry/run_key_persistence.yml
|   |-- cloud/aws/iam_user_created.yml
|   `-- cloud/azure/conditional_access_disabled.yml
|-- tests/
|   `-- test_powershell_download_cradle.py
|-- pipelines/
|   |-- splunk_pipeline.yml
|   `-- sentinel_pipeline.yml
`-- .github/workflows/deploy-detections.yml
```

Workflow: author -> peer review -> automated testing (`sigma validate`, `sigma convert`) -> deploy to SIEM -> monitor fidelity metrics.

## SOC maturity model

| Level | Characteristic | Detection | Response | Metrics |
|---|---|---|---|---|
| 1 Initial | Ad hoc, reactive | Vendor defaults only | Manual, inconsistent | None |
| 2 Managed | Basic processes | Tuned vendor rules, some custom | Documented playbooks | MTTD, MTTR tracked |
| 3 Defined | Detection-engineering programme | SIGMA-based, ATT&CK-mapped, version-controlled | SOAR-assisted | Fidelity, coverage tracked |
| 4 Measured | Metrics-driven improvement | Continuous purple-team testing, ML enrichment | Automated triage and response for common scenarios | Full SOC KPI dashboard |
| 5 Optimised | Threat-informed defence | TI-driven priorities, hypothesis-driven hunting | Mostly automated, human review for complex cases | Continuous improvement cycle |

## Cross-references

- `siem-soar-investigation`: the umbrella; condensed core and routing.
- `references/normalisation-and-onboarding.md`: detections are only as good as the normalised fields they match on.
- `references/network-log-forensics.md`: hunting and timeline construction that turn a hypothesis into evidence.
