# SOAR automation

Security orchestration, automation, and response: what to automate, how to design playbooks, how to measure return, and how SOAR wires into the rest of the stack. Platform-agnostic; pairings to specific SOAR products live in `platform-selection.md`.

## When to use SOAR

SOAR adds value when:

- Alert volume exceeds analyst capacity (roughly > 100 alerts/day with < 5 analysts).
- Repetitive triage steps can be codified (IOC lookup, asset enrichment, user context).
- Response actions are well defined (block IP, disable account, isolate endpoint).
- Multiple tools need orchestration (SIEM + EDR + firewall + ticketing).

SOAR does not replace:

- Human judgement for complex incidents.
- Good detection engineering. Automating bad detections is counterproductive.
- A defined process. You must have a manual playbook before you automate it.

## What to automate first

Prioritise by: high volume, repetitive, well defined, low risk of error.

| Priority | Use case | Type | Expected return |
|---|---|---|---|
| P1 | Phishing triage (URL/attachment analysis, detonation, verdict) | Enrichment + triage | 60-80% analyst time saved |
| P2 | IOC enrichment (IP, domain, hash reputation) | Enrichment | 5-10 min saved per alert |
| P3 | Alert dedup and grouping | Triage | 30-50% alert-volume reduction |
| P4 | Account lockout/disable for confirmed compromise | Containment | MTTR from hours to minutes |
| P5 | Endpoint isolation for confirmed malware | Containment | Immediate containment |
| P6 | Ticket creation and SLA tracking | Notification | Consistent process |
| P7 | Compliance evidence collection | Reporting | Audit readiness |

## Playbook design patterns

| Pattern | Purpose | Example |
|---|---|---|
| Enrichment | Gather context from many sources | Query TI, look up asset, check user risk |
| Triage | Automated decision on alert validity | Known-FP pattern -> auto-close; else escalate |
| Containment | Execute response actions | Isolate endpoint, block hash, disable user |
| Notification | Alert humans on the right channel | Slack, PagerDuty, email, ticketing |
| Full lifecycle | Enrich -> triage -> contain -> notify -> document | End-to-end for specific alert types |

### Pattern 1: enrichment

```
Alert received
   -> Extract IOCs (IPs, domains, hashes, URLs)
   -> Parallel enrichment:
        - VirusTotal lookup
        - AbuseIPDB check
        - WHOIS / DNS lookup
        - Internal asset lookup (CMDB)
        - Internal identity lookup (AD / HR)
   -> Aggregate results
   -> Calculate risk score
   -> Update alert with enrichment data
```

### Pattern 2: triage decision

```
Enriched alert
   -> Check known-false-positive patterns:
        - Source in allowlist?        -> auto-close
        - Known testing activity?     -> auto-close
        - Previously investigated?    -> auto-close
   -> (not auto-closed) Check severity indicators:
        - IOC in threat intel?        -> escalate HIGH
        - Target is critical asset?   -> escalate HIGH
        - User is VIP / admin?        -> escalate HIGH
   -> Route to tier:
        - HIGH   -> Tier 2 + page on-call
        - MEDIUM -> Tier 1 queue
        - LOW    -> auto-close with documentation
```

### Pattern 3: containment

```
Confirmed incident (analyst-approved, or auto for critical)
   -> Containment actions (parallel):
        - Isolate endpoint (EDR API)
        - Disable user account (IAM API)
        - Block malicious IP (firewall API)
        - Block malicious domain (DNS / proxy API)
        - Quarantine email (email gateway API)
   -> Verify containment (isolation status, account disabled, block applied)
   -> Notify stakeholders (security team, IT ops ticket, management if critical)
```

Gate containment behind approval unless the confidence is high and the action is reversible. Automating an irreversible action on a false positive is its own incident.

## Automation maturity model

| Level | Description | Characteristics |
|---|---|---|
| 1 Manual | No automation | Analysts triage every alert by hand, copy-paste between tools |
| 2 Scripted | Ad hoc scripts | Python for common tasks, no central orchestration |
| 3 Orchestrated | SOAR deployed | Enrichment playbooks, some triage automation, manual containment |
| 4 Automated | Triage + containment automated | Auto-triage for common types, semi-automated containment with approval |
| 5 Autonomous | AI-assisted full lifecycle | ML-driven triage, auto-containment for high-confidence threats, human oversight for edge cases |

## Measuring return

| Metric | Formula | Target |
|---|---|---|
| Time saved per alert | manual triage time - automated triage time | > 10 min per alert |
| Automation rate | alerts handled without humans / total alerts | > 40% |
| MTTR reduction | pre-SOAR MTTR - post-SOAR MTTR | > 50% reduction |
| Analyst capacity | alerts handled per analyst per day | > 2x improvement |
| Playbook success rate | successful executions / total executions | > 95% |
| FTE savings | time saved per month / FTE hours per month | calculate dollar value |

## Integration architecture

```
SIEM alert
   -> SOAR ingestion (webhook, API poll, syslog)
   -> Playbook engine
        - Enrichment APIs (TI, CMDB, identity, GeoIP)
        - Decision logic (thresholds, allow/block lists, ML scores)
        - Response APIs (EDR, firewall, IAM, email gateway)
        - Ticketing (ServiceNow, Jira, internal ITSM)
   -> Case management / war room
   -> Metrics and reporting
```

## Cross-references

- `siem-soar-investigation`: the umbrella; condensed core and routing.
- `references/platform-selection.md`: pairing a SOAR platform to your SIEM and team.
- `oncall-runbooks`: notification steps carry the runbook URL; do not page without naming the procedure.
- `secrets-hygiene`: every integration credential (EDR, firewall, IAM, email gateway API key) lives in the secret store, never in a playbook definition.
- `endpoint-detection-response`, `network-detection-response`: the response APIs containment playbooks call.
