# Scope and management

This is the discipline that keeps nmap a defensive tool: a hard scope boundary, an audit trail, safe handling of custom flags, and a persisted scan history for comparison.

## Scope enforcement

Every target is validated against a CIDR allowlist before nmap runs; an out-of-scope target is hard-rejected, not scanned. A sensible default allowlist is the private and loopback space only:

- `127.0.0.0/8` (loopback)
- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` (RFC1918)
- `fd00::/8` (IPv6 ULA)

Widen it only to ranges you own or are explicitly authorised to test, and record that authorisation. The allowlist is the technical expression of "authorised use only": it makes an accidental or unauthorised scan fail closed.

## Audit logging

Every scan, including custom scans, is recorded in an audit log: who ran it, when, the target, the tool, and the result. This is both a compliance record and the basis for the scan-history workflow below. Treat scanning of production networks as a change that the detection team should be aware of, so an authorised scan is not mistaken for an attack (see `network-detection-response`).

## Custom scans and safety

For flags not covered by the dedicated scan types, a custom-scan path takes raw nmap flags but blocks the dangerous ones:

```bash
# aggressive scan with version detection
nmap -A -T4 <target>
# specific ports with a timing template, only open ports reported
nmap -sS -p 22,80,443 -T3 --open <target>
```

Blocked in the custom path:

- **Shell metacharacters** (`;`, `&`, `|`, backtick, `$`): shell injection is rejected.
- **Output-writing flags** (`-oN`, `-oX`, `-oG`, `-oA`): no writing arbitrary files.
- **Path-based flags** (`--datadir`, `--servicedb`, `--script` with a path): use the dedicated NSE-script path instead.

The target is supplied separately and validated against the allowlist; do not embed it in the flags.

## Scan history

Scans persist with a scan id and are retrievable without re-scanning:

- **List recent scans:** returns newest-first with scan id, timestamp, tool, and target.
- **Retrieve by id:** returns the full original result.

## Before/after change comparison

The strongest operational use of the history is verifying a change did exactly what was intended:

1. **Baseline:** scan before the change, note the scan id.
2. **Make the change** (firewall rule, service deploy, hardening).
3. **Rescan** the same target the same way.
4. **Compare:** retrieve both scans and diff the open ports and services.

A firewall change that was supposed to close port 23 should show port 23 open in the baseline and closed in the post-change scan, with nothing else changed. An unexpected delta (a port that opened, a new service) is a finding. This pairs naturally with `acl-rule-analysis` for validating that a rule does what the rulebase says it does.
