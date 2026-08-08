---
name: web-application-firewall
description: "Use for the web application firewall (WAF) and WAAP discipline: protecting web applications and APIs at layer 7 by inspecting HTTP requests and responses for OWASP Top 10 attacks. Covers rule management and the OWASP Core Rule Set (CRS), detection versus prevention (blocking) modes, anomaly scoring and paranoia levels, false-positive tuning with targeted exclusions, custom rules and virtual patching, and the wider WAAP scope of DDoS mitigation, bot management, rate limiting, and API protection, plus deployment models (reverse proxy, inline, cloud and CDN edge) and monitoring and logging. Triggers include \"WAF\", \"web application firewall\", \"WAAP\", \"OWASP Core Rule Set\", \"CRS\", \"ModSecurity\", \"paranoia level\", \"anomaly scoring\", \"virtual patching\", \"false positive tuning\", \"managed rules\", \"custom WAF rule\", \"bot management\", \"rate limiting\", \"DDoS mitigation\", \"API protection\", \"detection mode\", \"blocking mode\". References rules-and-tuning.md and waap-and-operations.md. Do NOT use for: vendor-neutral application security strategy and where a WAF sits across build, test, deploy, and runtime (see application-security); layer 3/4 network firewall policy and rule-base auditing (see cisco-firewall-audit, fortigate-firewall-audit, palo-alto-firewall-audit, checkpoint-firewall-audit, sophos-firewall-audit, bsd-firewall-audit); network-layer DDoS, IDS/IPS, and detection (see network-detection-response)."
license: MIT
metadata:
  version: 1.0.0
---

# Web application firewall

> **Skill marker**: When applying this skill, begin your reply with `[skill: web-application-firewall]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers web application firewalls (WAF) and the broader WAAP (web application and API protection) category. A WAF protects web applications and APIs at layer 7 by inspecting HTTP and HTTPS requests and responses, understanding application context (headers, cookies, body, URLs, parameters) and blocking attacks such as SQL injection, cross-site scripting, and the rest of the OWASP Top 10. WAAP extends that base with DDoS mitigation, bot management, rate limiting, and API-specific protection. The reasoning here outlasts any one product: rule management, detection versus prevention, false-positive tuning, and deployment shape carry across Akamai, AWS WAF, Cloudflare WAF, F5, and open-source ModSecurity alike, so vendor-specific console steps are not the subject.

## The layer 7 versus layer 3/4 boundary

A WAF is a layer 7 control and is distinct from a network (layer 3/4) firewall. The two inspect different things, block different attacks, and do not substitute for one another.

| Aspect | Network firewall (layer 3/4) | WAF (layer 7) |
|---|---|---|
| Layer | IP and TCP/UDP | HTTP, HTTPS, WebSocket |
| Inspects | IP addresses, ports, protocols | HTTP headers, body, cookies, URLs, parameters |
| Understands | Packet headers | Application context |
| Blocks | Port scans, IP spoofing, disallowed services | SQL injection, XSS, the OWASP Top 10 |
| TLS termination | Not required | Required to inspect HTTPS |

A WAF does not replace a network firewall, and a network firewall cannot see the application-layer attacks a WAF exists to stop. Deploy both. Layer 3/4 firewall policy design and rule-base auditing belong to the firewall-audit family (`cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`, `sophos-firewall-audit`, `bsd-firewall-audit`); network-layer DDoS, IDS/IPS, and detection belong to `network-detection-response`.

## When to use

- Managing WAF rules: choosing managed rule sets, adjusting the OWASP Core Rule Set (CRS) paranoia level, and writing custom rules.
- Deciding between detection (monitor) and prevention (blocking) mode, and phasing the transition from one to the other.
- Diagnosing and tuning false positives so legitimate traffic stops being blocked, using targeted exclusions rather than broad rule disablement.
- Virtual patching: shielding a known application vulnerability with a WAF rule while the code fix is developed and deployed.
- Reasoning about WAAP scope: DDoS mitigation at layer 7, bot management, rate limiting, and API protection (schema validation, per-endpoint limits, token checks).
- Choosing a deployment model (reverse proxy, inline gateway, cloud or CDN edge, out-of-band monitoring) for a given traffic profile and availability requirement.
- Setting up WAF monitoring and logging, and forwarding the logs to a SIEM as security telemetry.

## When not to use

- **Vendor-neutral application security strategy and where a WAF fits across the lifecycle**: route up to `application-security`. That skill owns the OWASP Top 10 as a risk map, the secure SDLC, and how SAST, DAST, SCA, and a WAF compose across build, test, deploy, and runtime. A WAF is the runtime lens; the strategy that places it there lives up the tree. A WAF is a compensating runtime control, never a substitute for fixing the code.
- **Layer 3/4 network firewall policy and rule-base auditing**: use the firewall-audit family: `cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`, `sophos-firewall-audit`, `bsd-firewall-audit`. A WAF operates at layer 7 and is a different control from a packet-filtering firewall; see the boundary table above.
- **Network-layer DDoS, IDS/IPS, and detection**: use `network-detection-response`. Volumetric layer 3/4 attacks, intrusion detection and prevention on the network, and network telemetry analysis are its subject. This skill covers layer 7 application-layer DDoS at the WAF only.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Rules and tuning | managed rule sets, the OWASP CRS, paranoia levels and anomaly scoring, detection versus blocking mode, false-positive tuning, custom rules and exclusions, virtual patching | `references/rules-and-tuning.md` |
| WAAP and operations | layer 7 DDoS mitigation, bot management, rate limiting, API protection, deployment models, monitoring and logging, SIEM integration | `references/waap-and-operations.md` |

## Core model (condensed)

**A WAF inspects the application layer, so it must terminate TLS.** To read HTTP headers, cookies, and bodies the WAF has to see the plaintext, which means it terminates (or is given visibility into) the TLS session. That single fact drives the deployment models: the WAF sits in the request path as a reverse proxy or inline gateway, or lives at the cloud and CDN edge where TLS already terminates.

**Detection first, then prevention.** A WAF runs in detection (monitor) mode, where it logs violations without blocking, or prevention (blocking) mode, where it rejects offending requests. The safe rollout is always the same shape: start in detection, analyse the logs for false positives, tune, then enable blocking on high-confidence rules first and the rest after tuning. Turning on blocking for every rule on day one blocks legitimate traffic and gets the WAF switched off.

**The OWASP Core Rule Set is the industry baseline.** The OWASP CRS (the open-source rule set maintained by the OWASP project, historically paired with ModSecurity) uses anomaly scoring rather than block-on-any-match: each matched rule adds to a score and the request is blocked only when the total crosses a threshold. Paranoia levels PL1 to PL4 trade coverage against false positives, higher levels activate more rules and catch more but demand more tuning. Most commercial and cloud WAFs ship CRS-derived managed rules.

**False positives are the primary operational cost.** Legitimate input that looks like an attack (an apostrophe in "O'Brien", SQL-like text in a search box, a complex admin query) trips signature rules. The discipline is to identify the specific rule and location, then write a targeted exclusion (this rule, this path, this parameter) rather than disable the rule globally, and to document why each exclusion exists.

**Virtual patching buys time, it does not replace the fix.** When a vulnerability is known but the code fix is not yet deployed, a WAF rule can shield the specific attack pattern at runtime. That is a compensating control with an expiry: the real remediation is the code change, and the virtual patch is removed once the fix ships.

**WAAP is the WAF plus the traffic-shaping controls around it.** DDoS mitigation at layer 7, bot management, rate limiting, and API protection are not the core signature engine but ride alongside it on the same request path. Rate limiting and challenges (CAPTCHA, JavaScript) are the shared mechanism across bot defence and application-layer DDoS.

**Anti-patterns:** enabling blocking mode on every rule at once with no detection-mode soak; disabling a whole rule globally to clear one false positive instead of a targeted exclusion; leaving a virtual patch in place as if it were the fix; treating the WAF as a reason not to fix the code; running the WAF with logs no one reads; assuming a WAF replaces the network firewall (or vice versa); ignoring the API surface because the WAF "covers the web app".

## Reference router

| Need | Load |
|---|---|
| Rule management, the OWASP CRS, paranoia levels and anomaly scoring, detection versus blocking mode, false-positive tuning, custom rules and exclusions, virtual patching | `references/rules-and-tuning.md` |
| WAAP scope (layer 7 DDoS, bot management, rate limiting, API protection), deployment models, monitoring, logging, and SIEM integration | `references/waap-and-operations.md` |

## Cross-references

- `application-security`: the vendor-neutral AppSec entry point that owns the OWASP Top 10 as a risk map and places SAST, DAST, SCA, and a WAF across the lifecycle. This skill is the runtime WAF depth; route strategy and lifecycle placement up there.
- `cisco-firewall-audit`, `fortigate-firewall-audit`, `palo-alto-firewall-audit`, `checkpoint-firewall-audit`, `sophos-firewall-audit`, `bsd-firewall-audit`: the layer 3/4 network firewall policy and rule-base audit family. A WAF is a distinct layer 7 control; packet-filtering policy and rule-base hygiene live there.
- `network-detection-response`: network-layer DDoS, IDS/IPS, and detection. This skill covers only the layer 7 application-layer DDoS handled at the WAF.

Named in prose but never linked: Akamai, AWS WAF, Cloudflare WAF, and F5 are the common commercial and cloud WAF and WAAP platforms. They are named as concepts to orient the reader; product console configuration is out of scope and each vendor's own documentation is authoritative.

## Red flags

- About to enable blocking mode on every rule at once with no detection-mode soak and no false-positive analysis.
- About to disable a whole rule globally to clear a single false positive instead of writing a targeted exclusion scoped to the path and parameter.
- About to leave a virtual patch in place indefinitely as if it were the remediation, rather than removing it once the code fix ships.
- About to present a WAF as a reason not to fix the underlying vulnerability in the application code.
- About to treat the WAF as a replacement for the network firewall, or the network firewall as a replacement for the WAF: they are different layers and both are needed.
- About to run the WAF without forwarding logs anywhere or reviewing them, so attacks and false-positive spikes go unseen.
- About to protect the web UI while leaving the API surface (schema, per-endpoint limits, token validation) unprotected.
- About to score findings and set remediation SLAs here instead of routing programme design to `vulnerability-management` via `application-security`.

## Bottom line

A WAF protects web applications and APIs at layer 7 by inspecting HTTP traffic for the OWASP Top 10, and it is a distinct control from a layer 3/4 network firewall: deploy both. Roll it out in detection mode, tune false positives with targeted exclusions built on the OWASP Core Rule Set's anomaly scoring and paranoia levels, then move to blocking. Use virtual patching as a time-boxed compensating control, never as a substitute for the code fix. WAAP wraps the WAF with layer 7 DDoS mitigation, bot management, rate limiting, and API protection across reverse-proxy, inline, and cloud or CDN-edge deployments, and its logs are security telemetry that belong in a SIEM. Route AppSec strategy to `application-security`, layer 3/4 firewall policy to the firewall-audit family, and network-layer DDoS and IDS/IPS to `network-detection-response`.
