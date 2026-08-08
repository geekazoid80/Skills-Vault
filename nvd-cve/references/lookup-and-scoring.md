# Lookup and scoring

## The NVD REST API

The NIST National Vulnerability Database exposes a REST API (`services.nvd.nist.gov/rest/json`) with two operations that matter for lookup: fetch a single CVE by ID, and search by keyword. The `marcoeg/mcp-nvd` MCP server wraps these as `get_cve` and `search_cve` tools for agent use.

### Get a CVE by ID

Returns one CVE in full.

- `cve_id` (required): the identifier, for example `CVE-2023-20198`.
- `concise` (optional, default false): brief output (ID, description, CVSS score only).

A full record contains:

- CVSS v3.1 and v2.0 scores, severity, and the vector string.
- Exploitability and impact sub-scores.
- CWE weakness identifiers.
- References, each tagged (Vendor Advisory, Patch, Exploit, etc.).
- Affected configurations as CPE entries.

### Search by keyword

Returns matching CVEs plus a total count.

- `keyword` (required): a product and version ("Cisco IOS XE 17.9", "NX-OS 10.2", "OpenSSL 3.0") or a feature phrase.
- `exact_match` (optional, default false): require an exact keyword match.
- `concise` (optional, default false): brief output per CVE.
- `results` (optional, default 10, max 2000): how many to return.

Always confirm that the affected-CPE entries in a returned CVE actually match the product and version you care about; a broad keyword can surface CVEs for an unrelated product line.

## CVSS severity to action timeline

NVD supplies the CVSS score; map it to a default action timeline (the fuller, KEV/EPSS-aware prioritisation lives in `vulnerability-management`):

| CVSS score | Severity | Default action |
|---|---|---|
| 9.0 to 10.0 | Critical | immediate remediation |
| 7.0 to 8.9 | High | remediate within one change window |
| 4.0 to 6.9 | Medium | remediate in the next maintenance window |
| 0.1 to 3.9 | Low | document and track |

This is the technical-severity baseline only. A KEV entry or a high EPSS score overrides it upward, and a missing precondition (the CVE needs a feature you do not run) pushes it down; that layering is `vulnerability-management`'s job.

## API key and rate limits

The NVD API works without a key at a low request rate; an API key raises the limit substantially and is recommended for any batch or fleet-wide use. The key is a credential: store it in the secret store and reference it from the environment, never inline in a script or a saved query (see `secrets-hygiene`). The `marcoeg/mcp-nvd` wrapper reads the key from the environment.
