# Active recon and fingerprinting

These techniques send traffic to the target (DNS queries, HTTP requests). They are still recon, not exploitation, but they require the same authorisation confirmation as any other active step and the same politeness discipline.

## Subdomain brute-forcing (when passive sources aren't enough)

If certificate transparency and passive DNS leave obvious gaps (a naming convention suggests more subdomains than were found), a wordlist-driven brute-force DNS resolution pass can fill them in. Use a curated wordlist (common environment prefixes: dev, staging, uat, vpn, mail, autodiscover; common service names) rather than an exhaustive dictionary, and rate-limit resolution requests. A brute-force pass against the target's own authoritative nameservers at high concurrency can degrade their DNS service; prefer resolving against a public resolver (which the target does not operate) unless internal-only names are specifically being sought.

## Live-host validation

Not every name discovered (via CT logs, passive DNS, or brute-force) is still live. Validate by attempting an HTTP(S) connection (a lightweight HEAD or GET request) to each candidate host on common ports (80, 443, and any others explicitly in scope). Record: does it resolve, does it respond, what status code, is there a redirect and to where (a redirect to a different, possibly out-of-scope domain is itself worth noting for the attribution step). This single pass typically eliminates a large fraction of stale CT-log and passive-DNS entries.

## Technology fingerprinting

For each live host, identify the technology stack from passive signals in the HTTP response: server header, response headers characteristic of a specific framework or CMS, favicon hash (a distinctive favicon hash can identify a specific product even when other headers are stripped), TLS certificate issuer and SAN list, and visible page content (a login page's markup often reveals the product). This is passive-to-the-target (a single normal-looking HTTP request) but active in the sense of directly touching the host; it stays well inside recon, never attempting to exploit anything the fingerprint reveals.

Feed fingerprint results into `nvd-cve` later (once this skill's job is done) to check whether the identified version has known CVEs; that step belongs to `vulnerability-management`/`nvd-cve`, not this skill.

## Screenshot triage

For an engagement covering dozens or hundreds of live hosts, a screenshot of each host's rendered homepage (or login page) enables fast visual triage: spotting an obviously outdated admin panel, a default installation page that was never configured, or a login form worth prioritising for the enumeration phase, far faster than reading raw HTTP responses one at a time. Screenshot tools operate as a normal browser would (a single page load); they do not warrant separate authorisation beyond the live-host validation step already covers, but still count toward the same rate-limiting discipline (don't screenshot the same host repeatedly, batch requests with reasonable concurrency).

## Content discovery (careful, rate-limited)

Directory/endpoint brute-forcing (checking whether `/admin`, `/api`, `/.git`, `/backup.zip`, and similar common paths exist) can reveal exposed management interfaces, source-control leakage, or forgotten backup files. This is the most "attack-shaped" recon technique and needs the tightest discipline:

- Use a curated, purpose-built wordlist (common sensitive paths), not an exhaustive brute-force of every possible string.
- Rate-limit aggressively; a fast, high-concurrency content-discovery scan is difficult for a target's own monitoring to distinguish from an actual attack, and can trip their WAF/rate-limiting in ways that affect real users.
- Stop at existence/status-code confirmation. Finding that `/.git/` returns a 200 is the recon finding; actually cloning the exposed repository to inspect its contents is enumeration/exploitation territory that belongs in `penetration-testing`'s later phases under the same RoE, not this skill.

## Output: the normalised asset list

Every technique above should write into one normalised record per asset: hostname, resolved IP(s), live (yes/no), HTTP status/redirect chain, identified technology stack, screenshot reference (file path or hash), and the source technique(s) that found it. This is the deliverable `tooling-landscape.md` describes chaining tools to produce, and what `attack-surface-management` or `penetration-testing` consumes next.
