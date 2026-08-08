# Correlation and reporting

The value of an NVD lookup is not the CVE list; it is the exposure judgement on top of it. A device running an affected version is only at risk if the vulnerable feature is actually enabled.

## The version-to-CVE audit workflow

1. **Extract the running version.** From a device health check (for example `show version` on Cisco IOS-XE/NX-OS), read the software version and hardware model.
2. **Search NVD by version.** `search_cve` with the product and version as the keyword (for example "Cisco IOS XE 17.9.4", results 20).
3. **Pull details for Critical/High.** For each CVE with CVSS >= 7.0, `get_cve` by ID to read the precondition and the references.
4. **Correlate exposure against the running config.** For each CVE, check whether its precondition is present:

   | CVE | Requires | Running config | Exposed? |
   |---|---|---|---|
   | CVE-2023-20198 | HTTP/HTTPS server enabled | `ip http server` present | YES |
   | CVE-2023-20273 | Web UI accessible | `ip http secure-server`, no ACL | YES |
   | (example) | OSPF enabled | no `router ospf` | NO |

5. **Produce the report**, marking each CVE confirmed-exposed or not, with the remediation (upgrade target, or the config change that removes exposure):

   ```
   Vulnerability audit -- 2026-06-18
   Device: R1 | IOS-XE 17.9.4a
   CRITICAL (CVSS >= 9.0):
     CVE-2023-20198 (10.0) -- Web UI privilege escalation
       Exposure: CONFIRMED (ip http server enabled)
       Remediation: upgrade to a fixed release, or disable ip http server
   Summary: 1 CRITICAL exposed, ...
   ```

## Feature-keyword searches

When auditing a specific feature rather than a whole version, search by the feature:

- SNMP: `search_cve` keyword "Cisco SNMP remote code execution".
- BGP: keyword "Cisco BGP denial of service".
- SSH: keyword "Cisco IOS SSH vulnerability".

Pair these with the running-config check so a feature you do not run does not inflate the report.

## Fleet-wide scan and matrix

For a fleet, discover the running version on each device, then batch-search NVD for each unique version and roll the counts into a matrix:

```
+--------+------------------+----------+------+-----+--------+
| Device | Version          | CRITICAL | HIGH | MED | Action |
+--------+------------------+----------+------+-----+--------+
| R1     | IOS-XE 17.9.4a   | 2        | 3    | 5   | URGENT |
| R2     | IOS-XE 17.12.1   | 0        | 1    | 2   | PLAN   |
| SW1    | IOS-XE 16.12.4   | 5        | 8    | 12  | URGENT |
+--------+------------------+----------+------+-----+--------+
```

This is a coverage exercise: an unscanned device version is an unknown, so track which devices were assessed and when.

## Audit trail

Record each scan (device, version, CVE counts, which Criticals were confirmed exposed, and the remediation) in whatever audit log the environment uses, so the assessment is reproducible and the exposure decisions are documented for compliance. Dates in the record follow the UTC-correct convention; see `utc-timestamps`.
