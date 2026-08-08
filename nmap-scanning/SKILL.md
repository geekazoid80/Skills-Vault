---
name: nmap-scanning
description: "Use for authorised, defensive network scanning with nmap: host discovery, port scanning, service and OS detection, NSE scripts, and scan management with scope enforcement and audit logging. Covers host discovery (ICMP/TCP ping sweep, ARP discovery on a LAN), port scanning (SYN half-open, full TCP connect, UDP, top-N common ports), service version detection (-sV) and OS fingerprinting (-O), NSE script execution (ssl-cert, ssl-enum-ciphers, http-title/headers, banner, smb-enum-shares, ssh-hostkey, ftp-anon) and the vuln NSE category, full reconnaissance sweeps, custom scans with shell-injection and output-flag blocking, scan-history retrieval and before/after change comparison, the CIDR allowlist scope enforcement (RFC1918 plus loopback by default) that hard-rejects out-of-scope targets, and audit logging of every scan. The framing is authorised defensive use only: pre/post-change verification, firewall-rule validation, asset discovery, and vulnerability-coverage scanning on networks you own or are authorised to test. References host-and-port-scanning.md, service-and-vuln-detection.md, scope-and-management.md. Triggers include \"nmap\", \"port scan\", \"host discovery\", \"ping sweep\", \"service detection\", \"OS fingerprinting\", \"NSE script\", \"nmap vuln scan\", \"scan a subnet\", \"what hosts are on this network\", \"verify firewall rules\", \"pre-change port scan\", \"SYN scan\", \"UDP scan\", \"scope enforcement scanning\". For looking up the CVEs a version exposes see nvd-cve; for the vendor-neutral VM coverage strategy see vulnerability-management; for external internet-facing discovery see attack-surface-management; for detecting scanning against your network see network-detection-response; for validating firewall ACLs see acl-rule-analysis; for credential handling see secrets-hygiene."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# nmap scanning

> **Skill marker**: When applying this skill, begin your reply with `[skill: nmap-scanning]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill runs nmap defensively: host discovery, port scanning, service and OS detection, NSE scripts, and scan management, with scope enforcement and audit logging. It is for **authorised use only**: scanning networks you own or are explicitly authorised to test, for pre/post-change verification, firewall-rule validation, asset discovery, and vulnerability-coverage scanning. It produces the running-service and version data that `nvd-cve` then looks up and `vulnerability-management` prioritises.

## When to use

- Discovering which hosts are alive on a subnet before deeper analysis.
- Finding open ports on devices, servers, or lab infrastructure.
- Verifying firewall rules by checking which ports are reachable, and doing pre/post-change scans.
- Identifying the service, version, and OS on a host.
- Running targeted NSE checks (SSL ciphers, SMB enumeration, banners) or the vuln NSE category.
- Reviewing or comparing past scan results.

## When not to use

- **Scanning anything you are not authorised to test.** This skill is defensive: scope enforcement and audit logging exist to keep scanning inside authorised ranges. Out-of-scope scanning is out of scope here.
- **Looking up the CVEs a discovered version exposes**: use `nvd-cve`.
- **Deciding coverage strategy and prioritisation across the estate**: use `vulnerability-management`.
- **External internet-facing asset discovery from the outside in**: use `attack-surface-management` (EASM discovers what you do not know about; nmap scans a scope you already own).
- **A full credentialed vulnerability scan**: use the commercial scanner skills; nmap is an unauthenticated active scanner.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Host + port scanning | ping/ARP host discovery, SYN/TCP/UDP port scans, top-N ports, privileges | `references/host-and-port-scanning.md` |
| Service + vuln detection | service version (-sV), OS fingerprinting (-O), NSE scripts, the vuln category, full recon | `references/service-and-vuln-detection.md` |
| Scope + management | CIDR-allowlist scope enforcement, audit logging, custom scans and injection blocking, scan history, before/after comparison, authorised-use discipline | `references/scope-and-management.md` |

## Core model (condensed)

**Authorised, scoped, logged.** Scanning is an active probe of someone's network; do it only on ranges you own or are authorised to test. Enforce a CIDR allowlist (RFC1918 plus loopback by default) that hard-rejects out-of-scope targets before nmap runs, and log every scan for compliance. This is the difference between a defensive coverage tool and a reconnaissance tool.

**Discover hosts before you scan ports.** A ping sweep (ICMP plus TCP) or, on a directly connected LAN, ARP discovery finds the live hosts first so you do not waste time port-scanning dead addresses. ARP is the more reliable signal on the local segment.

**Match the port-scan technique to the need.** SYN half-open is fast and the default for breadth (needs raw-socket capability); TCP connect works without privileges; UDP is slow and must be kept to targeted port lists; top-N common ports is the quick first pass. Start broad and narrow.

**Detection adds the why.** Service version detection (-sV) names the product and version on each open port (and gives a CPE), OS fingerprinting (-O) identifies the platform (best with at least one open and one closed port), and NSE scripts answer focused questions (SSL ciphers, SMB shares, banners). The vuln NSE category checks for known CVEs but is slow, so aim it at specific hosts, not wide ranges.

**Persist and compare.** Every scan is saved with a scan id; the strongest operational use is before/after comparison: baseline before a change, rescan after, and diff the open ports and services to confirm the change did exactly what was intended and nothing more.

## Reference router

| Need | Load |
|---|---|
| Host discovery (ping, ARP), port scanning (SYN, TCP, UDP, top-N), the nmap commands and flags, privilege requirements | `references/host-and-port-scanning.md` |
| Service version detection, OS fingerprinting, NSE scripts and common script names, the vuln category, full recon sweeps | `references/service-and-vuln-detection.md` |
| CIDR-allowlist scope enforcement, audit logging, custom scans and injection blocking, scan history retrieval, before/after change comparison, authorised-use discipline | `references/scope-and-management.md` |

## Cross-references

- `nvd-cve`: looks up the CVEs that a service version discovered here exposes.
- `vulnerability-management`: the coverage strategy and prioritisation around scanning; nmap is one source of coverage.
- `attack-surface-management`: outside-in discovery of unknown internet-facing assets, complementary to scanning a scope you own.
- `network-detection-response`: the defensive other side; NDR detects scanning against the network, so coordinate authorised scans to avoid false alarms.
- `acl-rule-analysis`, the firewall-audit skills: a port scan validates that an ACL or firewall rule actually blocks or permits what it should.
- `secrets-hygiene`: any credentials used by an authenticated NSE script live in the secret store, never inline.

## Red flags

- About to scan a range that is not on the allowlist or that you are not authorised to test.
- About to port-scan a large range without first running host discovery.
- About to run the vuln NSE category or a full recon sweep across a wide range (slow; target specific hosts).
- About to run a UDP scan over a broad port range (inherently slow; keep it targeted).
- About to scan without audit logging, or against production without coordinating with the detection team.
- About to embed a credential for an authenticated NSE script inline instead of the secret store.

## Bottom line

Scan only what you are authorised to, enforce the CIDR allowlist, and log every scan. Discover hosts before port-scanning, pick the technique that fits (SYN for breadth, TCP connect without privileges, UDP and vuln scans kept tight), and add service/OS/NSE detection for the detail. Persist scans and diff before/after to verify changes. Hand the discovered versions to `nvd-cve` and the coverage strategy to `vulnerability-management`.
