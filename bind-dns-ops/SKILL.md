---
name: bind-dns-ops
description: "Use for BIND (ISC Berkeley Internet Name Domain) implementation, configuration, and troubleshooting on Linux/Unix. Covers named.conf structure, zone file syntax, primary/secondary (master/slave) zone setup, views (split-horizon), RPZ (Response Policy Zones), KASP/DNSSEC automated signing, catalog zones, ACLs, TSIG, forwarders, and recursion controls. References: architecture.md, diagnostics.md. Triggers include \"named.conf\", \"zone file\", \"BIND views\", \"RPZ\", \"KASP\", \"rndc\", \"TSIG\", \"catalog zones\", \"dig\", \"named-checkconf\", \"DNSSEC signing\", \"named-checkzone\", \"BIND 9.18\", \"BIND 9.20\", \"QP-trie\", \"zone templates\", \"auto-dnssec\", \"inline-signing\", \"split-horizon DNS\", \"forwarders\", \"allow-recursion\", \"allow-transfer\", \"dnssec-policy\", \"BIND DoT\". For DNS architecture, DNSSEC design, and cross-platform comparison see dns-network-ops."
license: MIT
metadata:
  version: 1.0.0
---

# BIND DNS ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: bind-dns-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers BIND-specific implementation on Linux/Unix: writing and validating named.conf, authoring zone files, configuring views, DNSSEC with KASP, RPZ threat blocking, TSIG zone-transfer authentication, catalog zones, and rndc management. The conceptual layer (resolution flow, DNSSEC design, platform selection, cross-platform comparison) lives in `dns-network-ops`.

## When to use

- Writing or reviewing a named.conf: options block, ACLs, logging, TSIG keys, zone stanzas.
- Configuring split-horizon DNS with BIND views (internal/external).
- Setting up DNSSEC with KASP (`dnssec-policy`) or reviewing a key rollover.
- Deploying RPZ for threat blocking or DNS sinkholing on BIND.
- Configuring TSIG for authenticated zone transfers or dynamic updates.
- Setting up catalog zones for automated secondary zone provisioning.
- Troubleshooting BIND: named-checkconf, named-checkzone, rndc commands, query logging, dig analysis.
- Planning or executing a 9.18 to 9.20 upgrade (auto-dnssec removal, QP-trie, zone templates).

## When not to use

- **DNS architecture, DNSSEC design, or cross-platform selection**: use `dns-network-ops`.
- **Recursive-resolver-only hardening, DNSSEC validation, or privacy features on a validating caching resolver**: use `unbound-dns-ops`.
- **PowerDNS authoritative server, SQL/LDAP backends, or REST API DNS automation**: use `powerdns-ops`.
- **Windows DNS, AD-integrated zones, DNS policies, or PowerShell DNS**: use `windows-dns-ops`.
- **TSIG/DNSSEC key generation and secret handling**: apply `secrets-hygiene` alongside this skill.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and configuration | named.conf top-level statements; options block; ACLs; views (split-horizon); zone file syntax; primary/secondary setup; KASP/DNSSEC signing; RPZ; TSIG; catalog zones; RRL; version notes for 9.18 and 9.20 | `references/architecture.md` |
| Diagnostics and troubleshooting | rndc command reference; named-checkconf and named-checkzone; dig query patterns; query logging; statistics channels; Prometheus integration; common failure modes and fixes | `references/diagnostics.md` |

## Core concepts

### Classify first

Before writing any configuration, identify two things:

1. **Role**: authoritative-only, recursive-only, or combined? Run separate BIND instances for each role in production; a combined instance increases the attack surface and complicates ACL design.
2. **Version**: 9.18 (ESV, long-term support) or 9.20 (current stable, significant breaking changes). The right answer determines which configuration directives are valid. See the "Version notes" section in `references/architecture.md`.

### named.conf structure

Every named.conf follows a defined statement order. The options block sets global defaults; ACLs and keys defined before any view are global; zones and views override the global defaults. See `references/architecture.md` for the full statement listing and key options.

### Views (split-horizon)

Views match clients by address or TSIG key and serve different zone data per match. Once any view is declared, every zone must live inside a view. First-match wins: place the most specific `match-clients` first. See `references/architecture.md` for a working example.

### DNSSEC with KASP

`dnssec-policy` (KASP) is the current recommended method. The built-in `default` policy (ECDSAP256SHA256 CSK, 1-year lifetime) is suitable for most deployments. KSK rollovers are semi-automated: KASP manages key timing, but the operator must submit the new DS record to the parent zone and confirm receipt with `rndc dnssec -checkds`. See `references/architecture.md` for KASP configuration and `references/diagnostics.md` for the rndc DNSSEC key management commands.

### RPZ

RPZ intercepts DNS responses and applies a policy action (NXDOMAIN, NODATA, DROP, PASSTHRU, CNAME redirect) based on a trigger (query name, client IP, response IP, nameserver name, nameserver IP). Use `servfail-until-ready yes` in production to prevent unprotected queries during RPZ zone load.

### TSIG

TSIG provides HMAC-based authentication for zone transfers and dynamic updates. Use `hmac-sha256` as the minimum algorithm. Generate keys with `tsig-keygen`; store the base64 secret out of version control per `secrets-hygiene`.

## Cross-references

- `dns-network-ops`: DNS architecture, DNSSEC design, cross-platform selection, zone transfer concepts, and the broader DNS family skill set.
- `multi-vendor-network-ops`: production-change contract (assumptions, pre-checks, execution, post-checks, rollback). Apply to every DNSSEC key rollover, TTL change, and named.conf change in production.
- `unbound-dns-ops`: validating, caching recursive resolver; use alongside BIND authoritative for a split authoritative/recursive deployment.
- `secrets-hygiene`: TSIG shared secrets, DNSSEC private key files, and dynamic-update credentials must never be inlined in scripts or committed to repositories.
- `utc-timestamps`: SOA serials (YYYYMMDDnn convention), DNSSEC key timing (publish/activate/retire windows), and query log analysis must be reasoned in UTC.
- `oncall-runbooks`: DNSSEC rollover failure, zone-transfer outage, RPZ feed failure, and named process crash runbooks.
- `systematic-debugging`: structured fault-isolation approach for complex BIND failures (DNSSEC validation loops, view mis-matching, zone-loading races).

## Red flags

- **Recursion open to the internet.** `recursion yes` without `allow-recursion { internal; };` turns BIND into a DNS amplification weapon. Always scope recursion to trusted ACLs.
- **`auto-dnssec` in a config targeting 9.20.** `auto-dnssec` was removed in 9.20; named will refuse to start. Migrate to `dnssec-policy` before upgrading.
- **KSK rollover without DS confirmation.** KASP manages key timing, but the DS record must be submitted to the parent zone and confirmed. Skipping `rndc dnssec -checkds` leaves the zone in a broken trust chain after the old KSK retires.
- **Views defined but some zones still outside views.** Once any view exists, every zone (including root hints, localhost, and loopback) must be inside a view or named will fail to start.
- **RPZ without `servfail-until-ready yes`.** Without this flag (9.20+), BIND serves unfiltered responses during the RPZ zone load window at startup. Production RPZ deployments must enable it.
- **TSIG key stored in zone files or committed to Git.** The TSIG base64 secret is a credential; apply `secrets-hygiene` discipline: environment variable, vault injection, or a file readable only by the named user.
- **Single authoritative server per zone.** Always run at least two authoritative servers. Single-server DNS is a critical single point of failure.
- **Zone file edits without serial increment.** Secondaries compare SOA serials to detect changes. A zone file edit without a serial bump is invisible to secondaries.

## Bottom line

Classify the role (authoritative/recursive/combined) and the BIND version (9.18/9.20) before writing any configuration. Load `references/architecture.md` for named.conf structure, views, KASP, RPZ, and TSIG detail. Load `references/diagnostics.md` for rndc, validation commands, and troubleshooting workflows. Route architecture and design decisions to `dns-network-ops`. Treat every production named.conf change and DNSSEC key rollover as a change-controlled operation under the `multi-vendor-network-ops` contract.
