# Matrix structure and data sources

## The matrix itself

MITRE ATT&CK organises adversary behaviour into three domains, each with its own matrix:

- **Enterprise**: the default domain for most organisations: Windows, macOS, Linux, cloud (Azure AD/Entra ID, AWS, GCP, Office 365, SaaS, containers, network devices).
- **Mobile**: Android and iOS-specific techniques.
- **ICS**: industrial control systems and OT-specific techniques (distinct tactics from Enterprise, e.g. "Impair Process Control", "Inhibit Response Function").

Most detection-engineering work in a standard IT estate lives in Enterprise. Confirm which domain applies before mapping anything; an ICS technique ID means nothing against a Windows fleet and vice versa.

Within a domain, the hierarchy is **Tactic → Technique → Sub-technique**:

- A **tactic** is the adversary's goal (why): Reconnaissance, Resource Development, Initial Access, Execution, Persistence, Privilege Escalation, Defense Evasion, Credential Access, Discovery, Lateral Movement, Collection, Command and Control, Exfiltration, Impact (14 tactics in Enterprise, ID-prefixed `TA00xx`).
- A **technique** is how the goal is achieved: `T1059` (Command and Scripting Interpreter).
- A **sub-technique** is a specific implementation: `T1059.001` (PowerShell), `T1059.003` (Windows Command Shell), `T1059.006` (Python).

Always map at sub-technique granularity where one exists. "We cover T1059" is close to meaningless when the sub-techniques span PowerShell, WMI, AppleScript, and Python, each with different telemetry and different detections.

## Data sources and data components

ATT&CK's data-source model is the bridge between "what we log" and "what we can detect". Each technique lists the **data components** that would evidence it, e.g.:

- `Process: Process Creation`, proving most Execution and Persistence techniques.
- `Command: Command Execution`, proving shell/scripting techniques (T1059.*).
- `Network Traffic: Network Connection Creation` and `Network Traffic: Network Traffic Flow`, proving Command and Control and Exfiltration techniques.
- `Logon Session: Logon Session Creation`, proving Initial Access and Lateral Movement via valid accounts (T1078, T1021).
- `Cloud Service: Cloud Service Modification`, proving cloud persistence and defense-evasion techniques (disabling logging, modifying IAM policy).

Before scoring a technique's coverage, confirm the data component actually reaches your SIEM/EDR/NDR. A technique can look "Partial" on paper because the rule exists, while the underlying log source was silently disabled weeks ago; verify against live telemetry, not the rule catalogue.

## Building an ATT&CK Navigator layer

[ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator/) is the standard visualisation: a JSON "layer" file scores every technique on a colour/score scale and renders it over the matrix.

Layer JSON shape (schema v4.5, current as of ATT&CK v15/v16):

```json
{
  "name": "Enterprise coverage - 2026-Q3",
  "versions": { "attack": "16", "navigator": "4.9.1", "layer": "4.5" },
  "domain": "enterprise-attack",
  "description": "Detection coverage scored None/Partial/Good from validated telemetry.",
  "techniques": [
    { "techniqueID": "T1059.001", "score": 100, "color": "", "comment": "EDR + SIEM rule, atomic-tested 2026-08-01" },
    { "techniqueID": "T1021.001", "score": 50, "color": "", "comment": "RDP logon telemetry present, no tuned rule yet" }
  ],
  "gradient": {
    "colors": ["#ff6666", "#ffe766", "#66b32e"],
    "minValue": 0,
    "maxValue": 100
  },
  "legendItems": [
    { "label": "None (0)", "color": "#ff6666" },
    { "label": "Partial (50)", "color": "#ffe766" },
    { "label": "Good (100)", "color": "#66b32e" }
  ]
}
```

Use `score` with the shared `gradient`, not per-technique `color`, so the legend stays consistent as scores change. `generate_navigator_layer.py` (bundled with this skill) builds this file from a simple CSV so the layer can be regenerated every time coverage is re-scored, rather than hand-edited.

## Versioning discipline

ATT&CK releases roughly twice a year (e.g. v15 → v16), adding, retiring, and splitting techniques. A Navigator layer built against v14 silently drifts as sub-techniques are added under existing parents. Re-check the current version at `https://attack.mitre.org/resources/updates/` at each re-baseline (see `validation-and-maturity.md` for cadence) and note the `versions.attack` field in every layer so staleness is visible at a glance.
