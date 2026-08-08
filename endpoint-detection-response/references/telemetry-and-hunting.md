# EDR telemetry, the detection-engineering lifecycle, and threat hunting

What an endpoint sensor collects, how that data flows to the backend, the difference between telemetry and detection, and how to turn threat knowledge into tuned, hunted-against detections.

## Event types collected by EDR sensors

Process telemetry:

- Process creation (image path, command line, parent PID, user context, hash).
- Process termination.
- Process injection events.
- Remote-thread creation in another process.

File-system telemetry:

- File create / modify / delete / rename.
- Executable writes (new PE files on disk).
- Script-file creation (.ps1, .vbs, .js, .bat).
- Alternate Data Stream (ADS) creation.

Network telemetry:

- DNS queries and responses.
- Network connections (source/dest IP, port, protocol, owning process).
- HTTP/HTTPS metadata where available (requires TLS inspection or process-level hooks).

Registry telemetry:

- Key create / modify / delete.
- Persistence-relevant writes (Run, RunOnce, Services, Scheduled Tasks).

Authentication telemetry:

- Logon events (type, source, user).
- Privilege-use events.
- Token manipulation.

Memory telemetry (deep platforms):

- Memory allocation in a remote process.
- Executable memory mapped outside known modules.
- Reflective PE loading.

## Telemetry pipeline

```
Endpoint sensor
      |
      | (kernel hooks, ETW, eBPF)
      v
Event collection and filtering
      |
      | (TLS / encrypted channel)
      v
Cloud backend / SIEM ingest
      |
      +--> Detection engine (real-time rules + ML)
      |          |
      |          v
      |       Alerts / incidents
      |
      +--> Telemetry store (raw events, queryable)
                 |
                 v
            Threat-hunting interface
```

Architectural levers:

- **Sensor-side filtering** cuts bandwidth but can drop the telemetry hunting needs; some platforms let you raise verbosity.
- **Cloud-native vs on-prem:** cloud-native platforms (Falcon, MDE) offload processing; on-prem (Wazuh) needs local infrastructure.
- **Streaming vs batch:** real-time detections need low-latency streaming; hunting queries run against the stored telemetry.

## Telemetry is not detection

Telemetry is the raw event record. Detection is an alert generated when telemetry matches a rule or model. A sensor can collect an event and never alert on it, which matters for:

- Threat hunting (searching telemetry for IOCs after the fact).
- Forensic investigation (reconstructing the attack timeline).
- Compliance (demonstrating the data was collected).

Typical telemetry retention (defaults, tier-dependent):

- CrowdStrike Falcon Insight: 90 days.
- Defender MDE Advanced Hunting: 30 days.
- SentinelOne Deep Visibility: 90 days (Complete tier).
- Elastic: configurable, bounded by cluster storage.
- Wazuh: configurable, bounded by indexer storage.

## Detection-engineering lifecycle

### Phase 1: detection hypothesis

Start from a threat-model question: "How would an attacker achieve technique X here?" Sources: ATT&CK technique descriptions, threat-intel reports, red/purple-team findings, incident post-mortems, security research.

### Phase 2: data-availability assessment

Before writing logic: is the telemetry being collected? Are the fields populated and reliable? What is the baseline frequency of this event? What is the signal-to-noise ratio?

### Phase 3: detection-logic development

Rule formats by platform (named as routing context only):

- CrowdStrike: custom IOA rules (behavioural), custom IOC indicators.
- MDE: custom detection rules (KQL), custom indicators.
- SentinelOne: STAR rules (Storyline Active Response), IOC watchlists.
- Elastic: detection rules (EQL, KQL, threshold, ML).
- Wazuh: XML rules with decoders.

Rule-quality checklist:

- Does it catch the technique reliably?
- What is the expected production false-positive rate?
- Does the logic use indexed fields where possible?
- Has it been tested against real malware samples?
- Is severity calibrated, and is response guidance attached?

### Phase 4: testing and validation

- **Atomic testing:** Atomic Red Team for single-technique simulation.
- **Adversary simulation:** full kill chain with a red team or framework.
- **Purple-team exercises:** collaborative red/blue with live detection feedback.
- **Replay testing:** replay historical attack telemetry against new rules.

### Phase 5: tuning and maintenance

Treat detections as code: version control, peer review, and CI for rule changes. Tuning is covered in depth in `response-and-tuning.md`; the point here is that the lifecycle never ends at deployment.

## Threat hunting

Hunting is hypothesis-driven search across stored telemetry, not waiting for an alert. A hunt:

1. Starts from a hypothesis (an ATT&CK technique, a threat-intel report, an anomaly).
2. Queries telemetry for the behaviour, not just known IOCs (process lineage, command lines, injection, credential access).
3. Triages hits with context (is this IT automation, or an attacker?).
4. Promotes a confirmed pattern into a new detection rule so the next occurrence alerts automatically.

Good hunting depends on telemetry depth and retention: you cannot hunt for what the sensor did not record or has already aged out. When the hypothesis spans host plus network plus identity, the hunt reaches into the network-detection-response and siem-soar-investigation surfaces, because the endpoint only holds part of the chain.
