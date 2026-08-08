# Workflows and integration

Discovery and attribution produce an inventory; these workflows turn it into reduced risk. The recurring failure is building the inventory and stopping there.

## Initial discovery and asset acceptance

1. **Seed.** Provide the known starting points: apex domains, IP ranges, ASNs, company and subsidiary names, acquisition entities.
2. **Discovery run.** The tool enumerates internet assets from the seeds using the methods in `discovery-and-attribution.md`.
3. **Attribution review.** Validate that discovered assets belong to the organisation; rule out false positives (shared CDN IPs, partner sites, unrelated SaaS tenants).
4. **Asset acceptance.** Accept genuine assets into the monitored inventory.
5. **Risk baseline.** Establish an initial exposure score so later change is measurable.

## Continuous monitoring and drift detection

The external surface changes daily, so monitoring is continuous, not a scheduled scan:

- **Re-scan** all accepted assets on a continuous cadence.
- **Alert on the deltas**, not the steady state: a new asset attributed to the org, a newly opened port, an SSL certificate expiring, a new vulnerability on an exposed service.
- **Detect drift:** a service that was closed is open again, a hardening change was reverted, a decommissioned asset reappeared. Drift is where carefully reduced exposure quietly comes back.

## The EASM-to-VM feedback loop

This loop is the reason EASM exists; without it the inventory is inert:

1. EASM discovers and attributes a new internet-exposed host.
2. An alert is raised to the vulnerability-management team (a ServiceNow ticket, a Slack message).
3. The VM team adds the host to the scanner (`vulnerability-management` routes to the per-vendor scanner skills).
4. A credentialed vulnerability scan runs against it.
5. Findings are managed in the VM platform under the standard SLA (severity, asset criticality, exposure; see the SLA framework in `vulnerability-management`).
6. EASM keeps monitoring the external exposure while VM owns the vulnerability fix.

EASM provides the "what is exposed" layer; VM provides the "how vulnerable is it" layer. Each is weaker alone: VM scans only what it is told about, and EASM finds exposure but does not assess depth.

## Attack surface reduction

Cataloguing exposure is not the goal; reducing it is. The outcomes that matter:

- **Minimise exposure:** shut down services that should never have been public (an exposed database, a forgotten admin panel, a stale dev box).
- **Harden what stays:** ensure everything that must be exposed has MFA, current patches, and correct TLS.
- **Track exposure debt:** maintain a deliberate record of what is exposed and why, so exposure is a decision, not an accident.
- **Be CVE-drop ready:** when a new critical CVE lands, answer in minutes whether any exposed service runs the affected software, rather than discovering it when it is exploited.

## Exposure management (CTEM) positioning

EASM is the discovery engine that lets vulnerability management grow into Gartner's Continuous Threat Exposure Management. Traditional VM manages known assets and CVEs; CTEM widens the lens to the exposure a real attacker would actually use, which necessarily includes the unknown internet-facing asset EASM surfaces. The practical maturity step is to make the EASM-to-VM loop above automatic and continuous, so the programme is measured by exposure reduced and attack paths eliminated, not by the size of the asset list.
