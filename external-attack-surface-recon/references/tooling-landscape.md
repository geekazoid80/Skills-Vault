# Tooling landscape

Named for orientation only; none of these is endorsed over another, and the recon-chain pattern matters more than any specific tool. Substitute equivalents freely as long as the pattern (passive-first, validate, fingerprint, screenshot, careful content discovery, normalise) is preserved.

## Subdomain enumeration

- **Amass** (OWASP project) — combines passive sources (CT logs, passive DNS, WHOIS, many API-backed data sources) with active DNS resolution and brute-forcing in one tool; the most comprehensive single option, at the cost of needing several API keys configured to reach its full passive coverage.
- **Subfinder** (ProjectDiscovery) — passive-source aggregation focused on speed and simplicity; a lighter alternative to Amass's passive mode when a quick pass is enough.
- **assetfinder** — a minimal passive-source tool, useful as a fast first pass or for chaining into other tools.

## Live-host validation and fingerprinting

- **httpx** (ProjectDiscovery) — takes a list of hostnames, resolves and probes each over HTTP(S), and reports status code, title, technology fingerprint (via Wappalyzer-style detection), and response headers in one pass. The natural next step after subdomain enumeration.
- **Wappalyzer** (CLI or library form) — technology fingerprinting specifically, useful standalone or as a cross-check against `httpx`'s built-in detection.

## Screenshot triage

- **gowitness** / **EyeWitness** — take a list of live hosts and produce a screenshot gallery (often as a single browsable HTML report), the standard way to triage a large host list visually.

## Content discovery

- **ffuf** / **feroxbuster** — fast, wordlist-driven content discovery with built-in rate-limiting flags; always set an explicit rate limit rather than relying on the tool's default, which is tuned for speed, not politeness.
- **Nuclei** (ProjectDiscovery) — template-driven scanning; for recon purposes, restrict to its passive/detection-only template categories (technology detection, exposed-panel detection) rather than its vulnerability-exploitation templates, which belong to `penetration-testing`'s later phases under full RoE authorisation.

## Chaining pattern

A typical chain, each stage's output piped into the next:

```
seed domains
  -> subfinder / amass (passive)      -> candidate subdomain list
  -> httpx                            -> live hosts + status + tech fingerprint
  -> gowitness                        -> screenshot gallery keyed to live hosts
  -> ffuf (rate-limited, curated list) -> content-discovery hits on hosts that warrant it
  -> normalise into one asset record per host
```

Each arrow is a manual review point, not an automatic pass-through: review the subdomain list before probing (drop anything obviously out of scope), review the live-host list before content discovery (only run content discovery against hosts the engagement actually needs deeper coverage on, not every live host indiscriminately).

## Output normalisation

Whatever tools are used, converge on one record schema before handing results onward (a CSV or JSON list is enough): `hostname, resolved_ip, live, status_code, redirect_to, technology, screenshot_ref, source_technique`. This is what makes the sweep's output usable by `attack-surface-management`'s attribution review or `penetration-testing`'s enumeration phase, instead of five different tools' incompatible output formats.

## API keys and rate limits

Amass, Subfinder, and several passive-DNS sources reach significantly more data with an API key configured (Censys, SecurityTrails, VirusTotal, Shodan). Store every such key per `secrets-hygiene` (never inline in a script or committed to a repo), and respect each service's documented rate limit; a free-tier API key hammered past its limit gets throttled or revoked mid-engagement.
