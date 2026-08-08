---
name: nvd-cve
description: "Use for looking up CVEs in the NIST National Vulnerability Database (NVD): finding a vulnerability by CVE ID or by keyword, reading the CVSS v3.1/v2.0 scores and vector, CWE weaknesses, affected configurations (CPE), and remediation references, and correlating a software version against known CVEs. Covers the NVD REST API (get a CVE by ID, search by keyword, the concise and results parameters, the API key and rate limits), what a CVE record contains, the CVSS severity-to-action-timeline mapping, the network-device vulnerability-audit workflow (extract running version, search NVD by version, pull details for Critical/High, correlate CVE prerequisites against the running configuration for true exposure, produce a report), fleet-wide version-to-CVE scanning and the vulnerability matrix, feature-keyword searches (SNMP/BGP/SSH CVEs), and recording scans in an audit trail. The marcoeg/mcp-nvd MCP server wraps the NVD API for agent use. References lookup-and-scoring.md, correlation-and-reporting.md. Triggers include \"CVE\", \"look up a CVE\", \"NVD\", \"National Vulnerability Database\", \"CVE lookup\", \"search CVE\", \"get_cve\", \"search_cve\", \"CVE by keyword\", \"CVSS score lookup\", \"does this version have known vulnerabilities\", \"software version CVE\", \"CVE for IOS-XE\", \"feature CVE search\". For the vendor-neutral VM programme that decides how to prioritise and remediate what the lookup returns see vulnerability-management; for active host and port scanning see nmap-scanning; for external attack surface discovery see attack-surface-management; for network-device PSIRT-advisory assessment see multi-vendor-network-ops and the firewall-audit skills; for NVD API-key handling see secrets-hygiene."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# NVD CVE lookup

> **Skill marker**: When applying this skill, begin your reply with `[skill: nvd-cve]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill looks up vulnerabilities in the NIST National Vulnerability Database: query a CVE by ID, search by keyword, read the CVSS scores and affected configurations, and correlate a running software version against known CVEs. It is the lookup tool; deciding how to prioritise and remediate what it returns is `vulnerability-management`.

## When to use

- Looking up a specific CVE by ID (advisory follow-up, incident response).
- Searching NVD by keyword or by a software product and version.
- Reading a CVE's CVSS score, vector, CWE, affected CPEs, and references.
- Auditing a network device: mapping its running version to known CVEs and judging real exposure.
- Running a fleet-wide version-to-CVE scan and producing a vulnerability matrix.

## When not to use

- **Deciding how to prioritise or remediate** (KEV/EPSS layering, SLA, exception process): use `vulnerability-management`. This skill returns the data; that one decides what to do with it.
- **Active scanning to find what versions are running** (port and service scanning): use `nmap-scanning`.
- **External internet-facing asset discovery**: use `attack-surface-management`.
- **A full commercial scanner's CVE enrichment** (Tenable/Qualys/Rapid7 do their own NVD + KEV + EPSS enrichment): use the vendor skills; this is the standalone NVD lookup.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Lookup + scoring | get a CVE by ID, search by keyword, the NVD REST API and parameters, what a record contains, CVSS severity-to-timeline mapping, API key and rate limits | `references/lookup-and-scoring.md` |
| Correlation + reporting | the version-to-CVE audit workflow, exposure correlation against running config, fleet-wide matrix, feature-keyword searches, audit trail | `references/correlation-and-reporting.md` |

## Core model (condensed)

**Two query modes.** `get_cve` by ID returns one CVE in full (CVSS v3.1 and v2.0, exploitability and impact sub-scores, CWE, tagged references, affected CPEs); `search_cve` by keyword returns matching CVEs with a total count, with `concise` for brief output and `results` to cap the count. A keyword can be a product and version ("Cisco IOS XE 17.9.4", "OpenSSL 3.0") or a feature ("Cisco SNMP remote code execution").

**The NVD score is a starting point, not the priority.** NVD gives you CVSS and the affected configurations; it does not tell you whether the vulnerability is being exploited or whether your asset is actually exposed. Layer KEV and EPSS and asset context on top (that reasoning lives in `vulnerability-management`), and for a device, correlate the CVE's prerequisites against the running configuration.

**Exposure correlation is what makes the lookup useful.** A CVE that needs the HTTP server enabled is not exploitable on a device where `ip http server` is absent. The audit workflow is: extract the running version, search NVD for version-specific CVEs, pull details for everything Critical/High, then check each CVE's precondition against the running config to mark it genuinely exposed or not. That turns a raw CVE list into a real, prioritised exposure report.

**Tool wrapper.** The `marcoeg/mcp-nvd` MCP server wraps the NVD REST API as `get_cve` and `search_cve` tools for agent use; an NVD API key raises the rate limit and is a credential (keep it in the secret store).

## Reference router

| Need | Load |
|---|---|
| NVD REST API (get by ID, search by keyword, concise/results parameters), CVE record contents, CVSS severity-to-action-timeline mapping, API key and rate limits, the marcoeg/mcp-nvd wrapper | `references/lookup-and-scoring.md` |
| The version-to-CVE vulnerability-audit workflow, exposure correlation against running config, fleet-wide scan and vulnerability matrix, feature-keyword searches, audit-trail recording | `references/correlation-and-reporting.md` |

## Cross-references

- `vulnerability-management`: the VM programme that prioritises (KEV/EPSS/CVSS, asset context) and remediates what this lookup returns. Reciprocal reference.
- `nmap-scanning`: active scanning that discovers the running services and versions this skill then looks up.
- `attack-surface-management`: external exposed-service discovery; the CVE behind an exposed version is looked up here.
- `multi-vendor-network-ops`, `cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`: network-device assessment that pairs NVD lookups with vendor PSIRT advisories and running-config correlation.
- `secrets-hygiene`: the NVD API key lives in the secret store, never inline.

## Red flags

- About to treat a raw NVD CVSS score as the remediation priority without KEV/EPSS/asset context (route to `vulnerability-management`).
- About to report a device "vulnerable" to a CVE without checking the CVE's precondition against the running configuration.
- About to put an NVD API key inline in a script instead of the secret store.
- About to run a broad keyword search and act on it without confirming the product/version actually matches the affected CPEs.

## Bottom line

Use `get_cve` for a known ID and `search_cve` for a product, version, or feature. Read the CVSS, CWE, and affected CPEs, but treat the score as a starting point: correlate the CVE's prerequisites against the running configuration for true exposure, and route prioritisation and remediation to `vulnerability-management`. Keep the NVD API key in the secret store.
