---
name: lets-encrypt
description: "Use for Let's Encrypt free TLS certificates and the ACME protocol ecosystem outside Kubernetes: certbot (nginx/Apache/standalone/webroot modes, DNS-01 plugins, renewal hooks), acme.sh (pure Bash, 150+ DNS providers), built-in ACME servers (Caddy auto-TLS, Traefik certificatesResolvers), LEGO and step CLI, HTTP-01/DNS-01/TLS-ALPN-01 challenge mechanics, 90-day and 6-day and 45-day certificate lifetimes, rate limits and staging environment, wildcard certificates, renewal automation, and production checklists. References: architecture.md (client comparison, challenge mechanics, rate-limit tables, cert profiles and lifetimes, Caddy/Traefik configs, automation patterns, common issue fixes, production checklist). Triggers include \"Let's Encrypt\", \"certbot\", \"acme.sh\", \"ACME\", \"free TLS\", \"LEGO\", \"Certify The Web\", \"short-lived certificate\", \"6-day certificate\", \"ACME challenge\", \"DNS-01 challenge\", \"HTTP-01 challenge\", \"wildcard certificate\", \"certbot renew\", \"acme.sh renew\", \"Let's Encrypt rate limit\", \"staging Let's Encrypt\", \"Caddy TLS\", \"Traefik ACME\", \"Let's Encrypt certbot nginx\", \"CAA record\". Cross-skill boundaries: cert-manager is the Kubernetes ACME client that consumes Let's Encrypt as a ClusterIssuer backend (see cert-manager); Vault's PKI engine can act as a private ACME CA and is an alternative for internal certificates (see hashicorp-vault-ops); ACME account keys and DNS API tokens used by DNS-01 solvers are secrets (see secrets-hygiene, which also owns the PKI concept layer including X.509, CA hierarchy, ACME protocol deep-dive, revocation, and CT logs); certificate expiry windows and renewal timing reason about UTC (see utc-timestamps)."
license: MIT
metadata:
  version: 1.0.0
---

# Let's Encrypt

> **Skill marker**: When applying this skill, begin your reply with `[skill: lets-encrypt]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Let's Encrypt is a free, automated, publicly trusted certificate authority operated by the Internet Security Research Group (ISRG). It issues domain-validated X.509 certificates via the ACME protocol. The canonical clients are certbot (EFF-maintained, widely packaged), acme.sh (pure Bash, broad DNS provider support), and built-in ACME support in Caddy and Traefik. Kubernetes workloads use cert-manager as the ACME client rather than certbot directly.

## When to use

- Obtaining or renewing Let's Encrypt certificates on bare-metal servers, VMs, or container hosts running nginx, Apache, HAProxy, or any other TLS terminator.
- Choosing and configuring an ACME client (certbot, acme.sh, Caddy, Traefik, LEGO, step CLI).
- Selecting and troubleshooting ACME challenge types (HTTP-01, DNS-01, TLS-ALPN-01).
- Understanding certificate lifetimes (90-day, 6-day, 45-day) and their renewal automation implications.
- Navigating rate limits: identifying which limit was hit, using staging, and requesting exceptions.
- Issuing wildcard certificates (DNS-01 required).
- Writing renewal hooks to reload services after cert rotation.

## When not to use

- **Kubernetes TLS certificates managed by cert-manager**: use `cert-manager`. cert-manager is the Kubernetes ACME client; it points its ACME ClusterIssuer `server:` field at the Let's Encrypt directory URL. This skill covers the protocol, clients, and out-of-Kubernetes usage.
- **Private ACME CA or Vault PKI engine as the issuer**: use `hashicorp-vault-ops`.
- **ACME protocol internals, X.509 structure, CA hierarchy, revocation, CT logs**: use `secrets-hygiene`. That skill owns the PKI concept layer at `secrets-hygiene/references/pki-concepts.md`.
- **Certificate expiry arithmetic and renewal scheduling in UTC**: use `utc-timestamps`.

## Classify the request first

| Class | Examples | Where depth lives |
|---|---|---|
| Client selection and install | certbot vs acme.sh vs Caddy built-in vs Traefik | `references/architecture.md` (client comparison table) |
| Certificate issuance | certbot --nginx, acme.sh --issue, standalone, webroot | `references/architecture.md` |
| Challenge type selection | HTTP-01 (port 80), DNS-01 (wildcard, no port 80), TLS-ALPN-01 | `references/architecture.md` (challenge mechanics) |
| Renewal automation | systemd timer, cron, renewal hooks (deploy/pre/post) | `references/architecture.md` |
| Rate limits | hit a limit, use staging, exception requests | `references/architecture.md` (rate-limit table) |
| Certificate lifetime | 90-day default, 6-day short-lived, 45-day opt-in | `references/architecture.md` |
| Wildcard certificates | DNS-01 required; `*.example.com` coverage | `references/architecture.md` |
| Troubleshooting | port 80 blocked, DNS propagation, CAA records, renewal not firing | `references/architecture.md` |

## Core model (condensed)

Let's Encrypt issues Domain Validated certificates. Validation proves control of the domain, not the identity of the organisation. Three challenge types are defined by the ACME protocol:

| Challenge | Proves control via | Port required | Wildcard support |
|---|---|---|---|
| HTTP-01 | Serving a token at `/.well-known/acme-challenge/<token>` | 80 | No |
| DNS-01 | Publishing a TXT record at `_acme-challenge.<domain>` | None | Yes |
| TLS-ALPN-01 | Responding to a TLS handshake on port 443 with an `acmeValidation` cert | 443 | No |

Certificate lifetime options:

| Profile | Lifetime | Renewal cadence | Available since |
|---|---|---|---|
| Default (90-day) | 90 days | Every ~60 days | Always |
| Short-lived (6-day) | 6 days | Every ~4 days | March 2025 |
| 45-day opt-in | 45 days | Every ~30 days | May 2026 |

6-day certificates require fully automated renewal. They eliminate the OCSP dependency (the cert expires before a revocation signal could be acted upon). Use them only when automation is solid end-to-end.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Everything | Client comparison table, challenge mechanics and timing, rate-limit tables, cert profile and lifetime details, certbot commands (nginx/Apache/standalone/webroot/DNS-01), acme.sh commands, certbot DNS plugins, Caddy config, Traefik config, renewal hooks (deploy/pre/post), common issue fixes (port 80 blocked, DNS propagation, CAA records, renewal not firing), production checklist | `references/architecture.md` |

## Cross-references

- `cert-manager`: the Kubernetes ACME client. cert-manager's ACME ClusterIssuer points its `server:` field at the Let's Encrypt directory URL. This skill covers everything outside Kubernetes; that skill covers the in-cluster certificate lifecycle controller.
- `hashicorp-vault-ops`: Vault's PKI secret engine is an alternative issuer for private, internal certificates. Vault 1.14+ can also act as an ACME provider, allowing certbot and acme.sh to obtain certificates from a private CA using the same workflow as Let's Encrypt.
- `secrets-hygiene`: DNS-01 solver API tokens (Cloudflare, Route 53, etc.) and ACME account private keys are secrets. The PKI concept layer (X.509 structure, chain of trust, CA hierarchy, ACME protocol mechanics, OCSP, CRL, CT logs) lives in `secrets-hygiene/references/pki-concepts.md`.
- `utc-timestamps`: certificate `notBefore`/`notAfter` windows, the two-thirds renewal trigger (~60-day mark on a 90-day cert), and renewal-failure alert thresholds all reason in UTC.

## Red flags

- **Testing against the production Let's Encrypt endpoint.** Use the staging endpoint first (`https://acme-staging-v02.api.letsencrypt.org/directory`). Production rate limits are strict; hitting the Duplicate Certificate limit (5 identical cert sets per week) blocks issuance for 7 days.
- **HTTP-01 with an HTTPS redirect that intercepts `/.well-known/acme-challenge/`.**  The challenge path must be served over plain HTTP before the redirect fires. nginx and Apache must serve the challenge location block first.
- **DNS-01 with low-TTL TXT records and insufficient propagation wait.** Validation servers check from multiple vantage points. If the TXT record hasn't propagated globally, validation fails. Allow 60-120 s on slow resolvers.
- **6-day certificates without tested automation.** If renewal fails once, the cert is invalid within days. Confirm the full renewal pipeline works end-to-end in staging before switching.
- **Missing CAA records.** If you have CAA records that don't include `letsencrypt.org`, Let's Encrypt will refuse to issue. Add `issue "letsencrypt.org"` and `issuewild "letsencrypt.org"` records.
- **No reload hook after renewal.** Certbot and acme.sh renew the certificate but do not automatically signal the web server. Without a deploy hook, the running server keeps serving the old (eventually expiring) cert.
- **Storing the ACME account key or DNS API token in source control.** These are credentials; see `secrets-hygiene` for where they belong.

## Bottom line

Choose the challenge type first: DNS-01 for wildcards or environments without port 80; HTTP-01 for single-host servers with port 80 reachable. Choose the client: certbot for standard Linux servers; acme.sh for pure-Bash or broad DNS provider support; Caddy or Traefik built-in for those stacks. Always test with staging. Automate renewal with a deploy hook that reloads the service. For Kubernetes, use `cert-manager` instead. For private CAs, use `hashicorp-vault-ops`.
