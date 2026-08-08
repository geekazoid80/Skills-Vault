# Platform selection

EASM platforms differ mainly in discovery breadth, attribution accuracy, and how well they integrate with the rest of the security stack. Settle what the programme must do (pure discovery, discovery plus remediation workflow, or discovery correlated with internal telemetry) before choosing.

## EASM platform profiles

| Platform | Best fit | Signature characteristics |
|---|---|---|
| **Microsoft Defender EASM** | Microsoft and Azure-centric shops, integration with Defender for Cloud | external asset discovery and inventory, Azure-native, risk prioritisation, feeds Defender for Cloud; per-vendor operations in `defender-easm` |
| **Palo Alto Cortex Xpanse** | organisations wanting discovery plus automated remediation | internet-wide active discovery, exposure prioritisation, automated remediation via Cortex XSOAR, integration with Cortex XDR and Prisma Cloud |
| **CrowdStrike Falcon Surface** | existing CrowdStrike Falcon customers | external discovery correlated with Falcon endpoint (EDR) data, exposure scoring, attack-surface reduction tied to the endpoint estate |
| **Censys** | teams wanting both an EASM platform and a research/hunting tool | internet-wide scanning infrastructure (ZMap/ZGrab heritage), certificate-transparency analysis, the enterprise ASM platform plus Censys Search for open research |
| **Shodan** | lightweight, research-led, or budget-constrained discovery | the original internet-wide scan index; strong for ad-hoc exposure checks and seeding, less of a managed EASM workflow |

Only Microsoft Defender EASM has a per-vendor vault skill (`defender-easm`); the others are named here as routing context. Censys and Shodan double as the internet-wide scan data that underpins discovery (see `discovery-and-attribution.md`).

## Evaluation criteria

| Criterion | Questions to ask |
|---|---|
| Discovery breadth | how complete is the internet scan, and how often does it refresh (daily matters) |
| Attribution accuracy | how well does it tie discoveries back to your org, and what is the false-positive rate |
| Asset context | does it surface technology stack, open ports, and SSL detail, not just a hostname |
| VM integration | can it feed new assets to the scanner automatically (the EASM-to-VM loop) |
| EDR / telemetry correlation | can it correlate external exposure with internal endpoint data |
| Remediation workflow | does it track remediation and integrate with ITSM |
| Subsidiary / acquisition support | can it monitor multiple legal entities and attribute correctly |
| Cloud coverage | does it discover cloud-specific exposure (public storage, exposed managed databases) |

## Decision method

1. **Decide the job.** Pure discovery and inventory, discovery plus automated remediation, or discovery correlated with internal telemetry. This is the biggest fork (Xpanse leans remediation, Falcon Surface leans EDR correlation, Defender EASM leans Azure integration).
2. **Weigh the existing stack.** A CrowdStrike or Palo Alto or Microsoft shop gains disproportionate value from the matching EASM through shared data and workflow.
3. **Test attribution on your own estate.** Run a trial against your real domains and ASNs and measure the false-positive rate; this, not the marketing breadth number, predicts whether the team will trust it.
4. **Confirm the VM integration path** exists before buying, because the EASM-to-VM loop is where the value is realised.

## Routing out

- Configuring and operating Microsoft Defender EASM: `defender-easm`.
- Scanning and remediating the assets EASM discovers: `vulnerability-management` (and its per-vendor scanner skills).
- Active scanning of a scope you own: `nmap-scanning`.
- The CVE lookup behind an exposed-service finding: `nvd-cve`.
