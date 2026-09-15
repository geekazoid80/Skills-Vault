---
name: external-attack-surface-recon
description: "Use for a tactical, tool-agnostic external reconnaissance / OSINT sweep against an authorised target: chaining subdomain enumeration, certificate-transparency queries, passive DNS, WHOIS/RDAP, live-host probing, technology fingerprinting, screenshot triage, and careful rate-limited content discovery into a normalised external-footprint asset list. This is a one-off or engagement-scoped recon workflow, not a standing EASM programme. Covers the passive-first discipline (exhaust passive sources before any active technique), the recon chain pattern (seed domains to normalised asset list), politeness/rate-limiting so recon isn't mistaken for an attack, and open-source recon tooling orientation (Amass, Subfinder, httpx, gowitness and similar, named for orientation only). References passive-recon-techniques.md, active-recon-and-fingerprinting.md, tooling-landscape.md; ships a recon-chain orchestration script that refuses to run without an explicit authorisation flag. Triggers include \"external recon\", \"OSINT sweep\", \"subdomain enumeration\", \"what's our external footprint\", \"recon phase\", \"passive DNS\", \"certificate transparency\", \"technology fingerprinting\", \"screenshot the external assets\", \"content discovery\". NOT for a standing EASM programme or platform selection (see attack-surface-management, defender-easm); NOT for active port/service scanning once scope is confirmed (see nmap-scanning); NOT for vulnerability scoring or prioritisation of what's found (see vulnerability-management, nvd-cve); NOT for the engagement-scoping and authorisation methodology this skill's active steps depend on (see penetration-testing, this skill's recon-phase companion, which owns the written-authorisation requirement this skill inherits and never re-litigates)."
license: MIT
metadata:
  version: 1.0.0
---

# External attack surface recon

> **Skill marker**: When applying this skill, begin your reply with `[skill: external-attack-surface-recon]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the tactical, tool-agnostic recon/OSINT workflow: how to actually run an external-footprint sweep against a target, chaining passive and light-active techniques into a normalised asset list. It is deliberately narrower than `attack-surface-management`, which owns the standing EASM programme (seeds, cadence, attribution review, platform selection). This skill is the one-off or engagement-scoped companion: the recon phase of an authorised `penetration-testing` engagement, or a lightweight "what does our footprint look like today" sweep without standing up a full EASM platform.

## When to use

- Running the reconnaissance phase of an authorised VA/PT engagement.
- A one-off "what is our external footprint today" sweep for a domain or organisation.
- Validating a specific domain/subdomain surface without standing up a full EASM platform or programme.
- Producing a normalised asset list to feed into `attack-surface-management`'s attribution step or `penetration-testing`'s enumeration phase.

## When not to use

- **Standing EASM programme design, cadence, or platform selection**: use `attack-surface-management` for the vendor-neutral programme, `defender-easm` for Microsoft's platform specifically. This skill is a sweep, not a programme.
- **Active port/service scanning once the scope is confirmed**: use `nmap-scanning`. Recon here stays at the passive/light-active layer (DNS, certificates, HTTP fingerprinting); a full port sweep of confirmed hosts is that skill's job.
- **Vulnerability scoring or prioritisation of anything found**: use `vulnerability-management` and `nvd-cve`. This skill stops at "here is the external footprint", not "here is what's exploitable".
- **Deciding whether the recon is authorised in the first place**: use `penetration-testing`. This skill inherits the authorisation the RoE establishes; it never grants itself permission to enumerate a target that hasn't been authorised.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Passive recon | certificate transparency, passive DNS, WHOIS/RDAP, search-engine dorking, code-repo leakage search, cloud-bucket naming patterns | `references/passive-recon-techniques.md` |
| Active recon + fingerprinting | live-host HTTP probing, technology fingerprinting, screenshot pipelines, rate-limited content discovery | `references/active-recon-and-fingerprinting.md` |
| Tooling orientation | open-source recon tool landscape, chaining pattern, output normalisation | `references/tooling-landscape.md` |

## Core model (condensed)

**Authorisation is inherited, never re-derived here.** This skill does not decide whether a target may be enumerated; `penetration-testing`'s rules-of-engagement gate (or an estate's own local companion skill, where one exists) already decided that. If no authorisation can be confirmed for a given scope, stop and ask rather than proceeding on the assumption that "it's just recon, not exploitation" makes it exempt.

**Exhaust passive sources before any active technique touches the target.** Certificate transparency logs, passive DNS databases, WHOIS/RDAP, search-engine dorking, and code-repository leakage search reveal a large share of an organisation's external footprint without a single packet reaching the target. Only move to active techniques (live-host probing, content discovery) once the passive pass is exhausted.

**The recon chain has a fixed shape.** Seed domains/org names → subdomain enumeration (passive first, brute-force only if needed and authorised) → live-host validation (which discovered names actually resolve and respond) → technology fingerprinting (what's running) → screenshot capture for fast visual triage across dozens or hundreds of hosts → careful, rate-limited content discovery on the hosts that warrant deeper look → a normalised asset list as the output. Each stage's output is the next stage's input; do not skip straight to content discovery against unvalidated names.

**Politeness is a technical requirement, not just courtesy.** Aggressive brute-force DNS enumeration, unthrottled content discovery, or high-concurrency probing against production infrastructure can degrade the target's service or trip its own defensive tooling, turning an authorised recon sweep into something that looks and feels like an attack to the target's SOC. Rate-limit, respect documented API limits on cert-transparency/passive-DNS services, and prefer passive data over brute force whenever the passive data is sufficient.

**The output is an attributable asset list, not a raw tool dump.** Normalise findings from every tool/technique into one list (hostname, resolved IP, live/dead, technology stack, screenshot reference, source technique) before handing it to `attack-surface-management` for attribution or `penetration-testing` for enumeration. A pile of separate tool outputs is not a deliverable.

**Anti-patterns:** running active techniques before exhausting passive sources; brute-forcing subdomains at a rate that risks degrading the target's DNS infrastructure; treating this skill's output as a vulnerability finding rather than a footprint inventory; skipping the authorisation check because "it's just recon".

## Reference router

| Need | Load |
|---|---|
| Certificate transparency, passive DNS, WHOIS/RDAP, dorking, code-leak search, cloud-bucket naming | `references/passive-recon-techniques.md` |
| Live-host probing, technology fingerprinting, screenshot pipelines, rate-limited content discovery | `references/active-recon-and-fingerprinting.md` |
| Open-source tool landscape, chaining pattern, output normalisation | `references/tooling-landscape.md` |

## Cross-references

- `attack-surface-management`: the standing EASM programme this skill's one-off sweep feeds into for ongoing attribution and monitoring. Reciprocal reference: that skill names this one as the tactical execution layer for a bounded sweep.
- `defender-easm`: the platform-specific implementation if the organisation runs a standing Defender EASM programme; this skill is useful even without one.
- `nmap-scanning`: the next step once live hosts are confirmed and scope allows active port/service scanning.
- `penetration-testing`: this skill's engagement companion; owns the authorisation this skill inherits and the phases this skill's output feeds (enumeration).
- `vulnerability-management` / `nvd-cve`: where a discovered asset's exposed service goes next for CVE lookup and prioritisation.
- `secrets-hygiene`: API keys for certificate-transparency or passive-DNS services (e.g. Censys, SecurityTrails) live in the secret store, never inline in a recon script.

## Red flags

- About to run a brute-force subdomain enumeration or high-concurrency content discovery before checking whether passive sources already answer the question.
- About to enumerate a target with no confirmed authorisation, on the reasoning that recon is "not really testing".
- About to run this skill's active techniques at a rate that could degrade the target's own infrastructure.
- About to hand over raw, un-normalised tool output instead of one attributable asset list.
- About to treat a discovered asset as a vulnerability finding rather than a footprint entry that still needs `vulnerability-management`'s assessment.

## Bottom line

Recon is a chain, not a tool list: exhaust passive sources first, validate before fingerprinting, fingerprint before screenshotting, and rate-limit every active step so the sweep never looks like an attack to the target's own defences. This skill never grants its own authorisation; it inherits whatever `penetration-testing`'s rules of engagement (or an estate's own local companion skill) already established, and stops to ask if that authorisation cannot be confirmed. The output is one normalised, attributable asset list feeding `attack-surface-management`'s attribution step or `penetration-testing`'s enumeration phase, not a pile of raw tool dumps.
