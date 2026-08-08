# Risk analysis

## Attack surface summary dashboard

The built-in summary groups the discovered surface into:

- **Exposed services by category:** web, email, VPN, developer portals, remote access.
- **SSL/TLS issues:** expired certificates, certificates expiring within 30 days, weak cipher suites, self-signed certificates.
- **Open vulnerabilities:** CVEs on detected software versions.
- **Observations:** policy violations such as open RDP or exposed admin panels.

This is the outside-in equivalent of an internal posture summary: it shows what an attacker sees, not what the CMDB lists.

## Insight Cards

Insight Cards are pre-built risk findings grouped by observation category. Common observations:

- RDP accessible from the internet.
- SSH open to all source IPs.
- FTP services exposed.
- Databases exposed (MySQL, MSSQL, MongoDB, Postgres, Redis).
- Kubernetes API publicly accessible.
- Expired SSL certificates.
- CVEs on web-server versions.
- Outdated frameworks (phpMyAdmin, old Tomcat).
- Admin interfaces reachable without authentication (phpMyAdmin, Jenkins, GitLab).

Each maps to a concrete attack-surface-reduction action: shut the service, restrict the source range, renew the certificate, or patch the version.

## CVE integration

Defender EASM maps a detected software version to known CVEs and shows the CVE ID, CVSS score, and affected technology, filterable by severity and CISA KEV status. For example: "Apache 2.4.49 detected on a.b.c.d, CVE-2021-41773 (CVSS 9.8, KEV)".

This is the point where EASM hands off to vulnerability management. Defender EASM tells you an exposed service appears to run an affected version; confirm and prioritise the finding, run a credentialed scan against the host, and track the fix under an SLA in `vulnerability-management`. EASM identifies exposure and likely-affected versions; it is not the system of record for vulnerability remediation, and the CVE lookup itself is `nvd-cve`.
