# Platform selection

Choosing a SIEM and a SOAR against requirements. Selection is never one-size-fits-all: weigh cloud footprint, log volume, budget, team maturity, and existing tooling. The vendor names below are routing context, not endorsements; this vault keeps the vendor deep-dives refer-only.

## Gather context first

Before recommending anything, establish: primary cloud (AWS/Azure/GCP/multi/on-prem), log volume (GB/day or EPS), retention needs, team size and skill, budget model tolerance (ingestion vs node vs flat), compliance requirements, and the tooling already in place (especially EDR and ticketing, which anchor natural pairings).

## SIEM platform comparison

| Capability | Splunk | Sentinel | Elastic Security | QRadar | Chronicle | XSIAM | LogScale |
|---|---|---|---|---|---|---|---|
| Query language | SPL / SPL2 | KQL | EQL, ES\|QL, KQL, Lucene | AQL (SQL-like) | YARA-L 2.0 | XQL | LQL |
| Normalisation | CIM | ASIM | ECS | QID + DSM | UDM | XDM | Custom |
| Deployment | On-prem, cloud, hybrid | Cloud-native (Azure) | On-prem, cloud, hybrid | On-prem (SaaS divested) | Cloud-native (GCP) | Cloud-native | Cloud, self-hosted |
| Pricing | Ingestion (GB/day) or workload | Ingestion + retention | Node-based or ingestion | EPS (events/sec) | Flat (per user) | Ingestion + compute | Ingestion (GB/day) |
| Built-in SOAR | Splunk SOAR (separate) | Playbooks (Logic Apps) | Response actions (limited) | QRadar SOAR (separate) | SOAR module | Automation Center | Falcon Fusion |
| ML / AI | MLTK, predictive | Fusion ML, UEBA, Copilot | ML anomaly jobs | Anomaly detection | Duet AI, Mandiant TI | XSIAM Copilot, ML clustering | Statistical functions |
| Strengths | Mature ecosystem, SPL power, Splunkbase | Azure integration, cost tiers, Defender XDR | Open-source core, EQL sequences, flexible | Automatic offense grouping, AQL familiarity | Unlimited retention, retroactive rules, Mandiant TI | Converged SIEM+SOAR+XDR, AI-first | High-volume streaming, index-free, real-time |
| Weaknesses | Cost at scale, complexity | Azure-centric, KQL learning curve | Operational overhead (self-managed) | Aging platform, SaaS discontinued | GCP-centric, limited customisation | Vendor lock-in, emerging maturity | Smaller ecosystem, limited SOAR |

### SIEM decision tree

```
What is your primary cloud?
  Azure-heavy  -> Microsoft Sentinel (native Defender XDR, Entra, M365)
  GCP-heavy    -> Chronicle / Google SecOps (native GCP, Mandiant TI)
  AWS-heavy    -> Splunk Cloud, Elastic, or XSIAM (no dominant AWS-native SIEM)
  Multi-cloud / on-prem:
        Budget priority           -> Elastic Security (open-source core) or LogScale (competitive pricing)
        Mature SOC, complex needs -> Splunk (deepest ecosystem, SPL power)
        Converged SOC platform    -> XSIAM (SIEM + SOAR + XDR in one)
        High-volume, real-time    -> LogScale (streaming, index-free)
```

## SOAR platform comparison

| Capability | XSOAR | Splunk SOAR | Sentinel Playbooks | Tines | Torq |
|---|---|---|---|---|---|
| Vendor | Palo Alto | Cisco/Splunk | Microsoft | Tines | Torq |
| Architecture | Server (on-prem/cloud) | Container (on-prem/cloud) | Cloud-native (Logic Apps) | Cloud-native (SaaS) | Cloud-native (SaaS) |
| Integrations | 900+ | 300+ apps, 2,800+ actions | 200+ connectors | Unlimited (HTTP) | 200+ native |
| Playbook design | YAML/Python + visual | Visual drag-and-drop | Logic Apps designer | No-code (stories) | Visual + AI-assisted |
| Scripting | Python, PowerShell | Python | Logic Apps expressions | Transform actions | Python (optional) |
| Case management | Built-in (war rooms) | Built-in (containers) | Sentinel incidents | External | Built-in |
| AI features | Limited | Limited | Copilot for Security | AI actions | AI copilot, case summary |
| Pricing | Per-endpoint or per-action | Per-action or enterprise | Per Logic App execution | Free (team) / paid (enterprise) | Per-automation volume |
| Best paired with | Cortex XDR, XSIAM | Splunk Enterprise/ES | Sentinel, Defender XDR | Any SIEM (agnostic) | Any SIEM (agnostic) |

### SOAR selection guide

```
What is your primary SIEM?
  Splunk / Splunk ES   -> Splunk SOAR (native); consider XSOAR if using Cortex XDR
  Microsoft Sentinel   -> Sentinel Playbooks (native, zero integration effort)
  Cortex XSIAM         -> Automation Center (built-in, XSOAR heritage)
  Any / multi-SIEM     -> Tines (agnostic, no-code) or Torq (AI-driven) or XSOAR (most integrations)
  Budget-constrained   -> Tines Community Edition (free) or Sentinel Playbooks (if on Azure)
```

The SIEM usually anchors the SOAR choice: native pairings cut integration effort to near zero, while vendor-agnostic SOAR (Tines, Torq, XSOAR) wins for multi-SIEM estates or when you want portability.

## Cross-references

- `siem-soar-investigation`: the umbrella; condensed core and routing.
- `references/soar-automation.md`: once a SOAR is chosen, the playbook patterns and maturity model that make it pay off.
- `references/normalisation-and-onboarding.md`: the ingestion-cost model that the pricing column above turns into a budget.
- `cloud-platform-selection`: the cloud-footprint decision that often anchors the SIEM choice.
