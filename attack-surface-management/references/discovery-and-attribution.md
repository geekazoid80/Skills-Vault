# Discovery and attribution

EASM has two jobs: find internet-facing assets the way an attacker would, and decide which of them are genuinely yours. Enumeration is the easy half; attribution is where a programme succeeds or drowns in noise.

## Discovery methods

An EASM tool combines several techniques, each surfacing a different slice of the surface:

1. **Domain and subdomain enumeration.** Start from known apex domains and enumerate subdomains via DNS brute force, passive DNS databases, certificate transparency logs, and (where misconfigured) zone transfers. Subdomains like `dev.api.company.com` or `vpn-old.company.com` are where forgotten services hide.
2. **Certificate transparency logs.** Every publicly trusted TLS certificate is logged (queryable via crt.sh and similar). The subject and SAN fields reveal hostnames and, by association, IPs, including for services not linked anywhere.
3. **IP range and BGP/ASN ownership.** Map the IP space the organisation owns or announces (its ASNs, allocated ranges) and scan it for live services. Cloud-assigned IPs complicate this because they are ephemeral and not in classic WHOIS.
4. **WHOIS / RDAP.** Ownership data for domains and IP ranges, used both as a seed and as an attribution signal.
5. **Passive DNS.** Historical resolution data shows hostnames that once pointed at your IPs even if they no longer resolve, surfacing decommissioned-but-not-really assets.
6. **Internet-wide scan data.** Services such as Shodan, Censys, and FOFA index the reachable internet continuously; EASM tools leverage or replicate this so they do not have to scan the whole internet themselves.
7. **Web crawling.** Following links, JavaScript-embedded endpoints, and referenced APIs to discover assets that enumeration alone misses.
8. **Correlation.** Linking a discovered asset back to the organisation through certificate subjects, HTML and favicon fingerprints, technology stacks, and email addresses embedded in certificates.

## Asset types discovered

- Domains and subdomains, including internal-sounding and staging names exposed by accident.
- IP addresses and CIDR ranges, including cloud-assigned addresses.
- Web applications and APIs, including dev, test, and staging environments never meant to be public.
- Open ports and exposed services: RDP, SSH, databases, management interfaces reachable from the internet.
- SSL/TLS certificates, including expired, expiring, self-signed, and weak-cipher ones.
- Public cloud storage: world-readable S3 buckets, Azure blobs, GCS buckets.
- Code repositories and artefacts leaking source or secrets.
- Third-party and SaaS services standing in for the organisation (shadow IT).

## Attribution and false-positive reduction

Discovery returns a superset; not all of it is yours, and accepting it blindly destroys the programme's credibility. Attribution decides what enters the monitored inventory:

- **Strong signals:** the asset sits in an IP range or ASN you own; a TLS certificate names your domain in the subject or SAN; WHOIS lists your organisation.
- **Weaker signals (corroborate before accepting):** shared technology fingerprint, brand strings in page content, a favicon hash that matches your estate, an email domain in a certificate. Any one alone produces false positives (a shared CDN IP, a SaaS tenant, a partner site).
- **Review then accept.** A human or a tuned rule reviews discovered assets, rules out the not-yours, and accepts the genuine ones into monitoring with a baseline exposure score. Acquisitions and subsidiaries need explicit seeding so their estate is attributed to the right entity.
- **Track the false-positive rate** as a programme metric. A rising FP rate means attribution rules need tuning before the team learns to ignore the alerts.

The output of this stage is a trustworthy, attributed inventory of what is genuinely exposed, ready for the workflows in `workflows-and-integration.md`.
