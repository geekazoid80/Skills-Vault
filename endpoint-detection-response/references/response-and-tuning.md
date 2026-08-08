# EDR response actions, tuning, and operational health

What you can do to a compromised endpoint, how to stop drowning in false positives, and how to keep the sensor fleet healthy and measurable.

## Response action taxonomy

Actions escalate by blast radius. Pick the smallest action that contains the threat.

| Action | Description | Availability |
|---|---|---|
| Process kill | Terminate a running process | All major platforms |
| File quarantine | Remove and vault a suspicious file | All major platforms |
| Host isolation | Cut all network except sensor comms | All major platforms |
| Rollback / remediation | Reverse attacker changes (registry, files) | SentinelOne 1-click, MDE AIR, CrowdStrike RTR |
| Remote shell | Live interactive session on the endpoint | RTR (CrowdStrike), Live Response (Carbon Black), Live Terminal (Cortex) |
| Memory forensics | Dump process memory for analysis | CrowdStrike RTR, CB Live Response, Elastic response |
| Network containment | Block specific IPs/domains without full isolation | Varies by platform |

Sequencing principle: surgical first (process kill, file quarantine), then isolating (host isolation, network containment), then investigative (remote shell, memory dump), and only then destructive recovery (rollback). Every isolating or destructive action needs a manual playbook and an approval gate before it is automated; automating a blunt action just makes a wrong call faster.

## False-positive sources

Common causes of noise:

- IT automation that mimics attacker behaviour (PSExec, scheduled tasks, remote management).
- Software updates triggering executable-write detections.
- Security tools triggering injection detections on each other.
- Legacy applications using insecure but legitimate patterns.

## Tuning and exclusion hygiene

Tuning strategies:

- Exclude by specific process path plus parent (be specific, never broad).
- Exclude by signed hash or certificate (preferred over path: paths can be abused).
- Context-based suppression (a known IT_ADMIN group running process X is expected).
- Threshold suppression (N occurrences within T seconds before alerting).

Exclusion hygiene rules:

- Document every exclusion with a justification and an owner.
- Review exclusions quarterly and remove stale ones.
- Never exclude an entire system directory: an attacker will drop a payload exactly there.
- Prefer signed-certificate exclusions over path exclusions.

The failure mode is an exclusion that is wider than it needs to be. A path exclusion on `C:\Windows\Temp` to silence one noisy updater hands every attacker a detection-free staging directory.

## Sensor health monitoring

A detection programme is only as good as deployment coverage. Track:

- Sensor version (keep patched).
- Last check-in time (find offline or disconnected endpoints).
- Policy assignment (correct policy per endpoint type).
- Prevention mode (confirm it is not stuck in detection-only when prevention was intended).
- Exclusion count per endpoint (outliers flag misconfiguration or tampering).

## Performance overhead

Typical endpoint overhead (indicative, varies by configuration):

- CrowdStrike: roughly 1 to 3 percent CPU, around 25 MB disk.
- MDE: roughly 1 to 5 percent CPU (scan-dependent), built into Windows.
- SentinelOne: roughly 1 to 3 percent CPU, around 100 MB disk.
- Wazuh: roughly 1 to 3 percent CPU, around 200 MB disk (depends on FIM and rule scope).

Performance levers: scope File Integrity Monitoring to critical directories only, schedule resource-intensive scans off-peak, filter telemetry at the sensor to cut volume, and exclude known-good high-volume processes from deep inspection (with the same exclusion hygiene as above).

## Detection-quality metrics

| Metric | Description | Target |
|---|---|---|
| Mean Time to Detect (MTTD) | Attack start to alert | < 1 hour for critical techniques |
| Mean Time to Respond (MTTR) | Alert to containment | < 4 hours for critical incidents |
| False-positive rate | Alerts that are not real threats | < 5 percent for tuned deployments |
| Detection coverage | Percent of ATT&CK techniques with a detection | > 70 percent for Enterprise techniques |
| Sensor deployment rate | Percent of endpoints with a healthy active sensor | > 99 percent |
| Alert-to-incident ratio | Alerts that escalate to incidents | Track the trend |

Measure before you claim coverage. "We have EDR" is not a coverage statement; an ATT&CK coverage percentage backed by atomic tests is.
