# Passive recon techniques

Passive techniques never send traffic to the target; they query third-party data sources that already observed the target. Always exhaust these before any active step.

## Certificate transparency (CT) logs

Every publicly-trusted TLS certificate is logged to public CT logs (crt.sh, Censys' CT search, Google's CT search). Querying `%.example.com` against crt.sh or equivalent reveals every subdomain that has ever had a certificate issued, including forgotten dev/staging hosts and wildcard-certificate names. This is usually the single highest-yield passive source; run it first.

Caveats: wildcard certificates hide the specific subdomain names actually in use behind them; a certificate having existed does not mean the host is still live (feed results into the active-recon live-host validation step before treating anything as current).

## Passive DNS

Passive DNS databases (SecurityTrails, Farsight/DNSDB, VirusTotal's passive DNS, Censys) record historical DNS resolutions observed by sensors across the internet, without querying the target's own nameservers. This surfaces subdomains that never got a certificate (internal-only names that leaked, old A records) and historical IP assignments useful for spotting infrastructure moves (e.g. migration to a new cloud provider, a previously-shared IP now dedicated).

## WHOIS / RDAP

WHOIS (and its structured successor, RDAP) on the apex domain(s) and any IP ranges reveals registrant organisation, name servers, and (increasingly redacted post-GDPR) contact details. More useful today for confirming domain ownership/attribution and name-server infrastructure than for contact harvesting. Cross-reference ASN ownership (via a routing registry lookup, e.g. RIPEstat, Team Cymru's IP-to-ASN, or `whois -h whois.radb.net`) to map IP ranges genuinely owned or leased by the organisation, which is the attribution input `attack-surface-management` needs downstream.

## Search-engine dorking

Targeted search-engine queries (`site:example.com filetype:pdf`, `site:example.com inurl:admin`, `intitle:"index of" site:example.com`) surface indexed content the organisation may not realise is public: exposed directory listings, leaked internal documents, forgotten admin panels that got crawled before being locked down. Keep dorking queries narrowly scoped to the confirmed-in-scope domains; broader dorking (searching for the organisation's name without a domain qualifier) strays toward Human-channel OSINT, which needs its own explicit authorisation per `penetration-testing`'s channel model.

## Code-repository leakage search

Public code hosting (GitHub, GitLab, npm/PyPI package metadata) and code-search engines (grep.app, publicwww) can surface accidentally-committed internal hostnames, API endpoints, or configuration referencing internal infrastructure, particularly in a former employee's personal repos or in a public fork of an internal tool. Search for the organisation's domain names, distinctive internal hostnames, and known internal package/service naming patterns.

## Cloud storage bucket naming patterns

Public cloud storage (S3, GCS, Azure Blob) buckets are frequently named predictably (`<org>-backups`, `<org>-prod-assets`, `<org>-<project>-uploads`). A passive naming-pattern sweep (checking whether predictable bucket names resolve and are publicly listable) using each provider's own listing API is still a passive/read-only technique as long as it only checks existence and public-read permissions, never writes. Treat a bucket that IS listable as a finding to attribute and report immediately, not an invitation to enumerate its full contents beyond confirming exposure.

## Recording sources

For every asset discovered, record which passive source produced it. This matters for two reasons: attribution review (a WHOIS-confirmed ASN carries more attribution confidence than a single CT-log hit) and for `attack-surface-management`'s false-positive reduction step downstream, which needs to know how a candidate asset was found in order to weigh it.
