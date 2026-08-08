---
name: cert-manager
description: "Use for cert-manager, the CNCF graduated Kubernetes add-on for X.509 certificate lifecycle management: Certificate resources, Issuer and ClusterIssuer configuration (ACME, Vault PKI, CA, Venafi, self-signed), DNS-01 and HTTP-01 and TLS-ALPN-01 ACME solvers (Route 53, Azure DNS, Cloud DNS, Cloudflare), trust-manager for CA bundle distribution across namespaces, and the cert-manager CSI driver for ephemeral certificate volumes. References: architecture.md (issuer types, Certificate spec, ingress auto-cert, trust-manager, CSI driver), operations.md (Helm installation, troubleshooting, forced renewal). Triggers include \"cert-manager\", \"Kubernetes certificates\", \"ClusterIssuer\", \"Issuer\", \"Certificate resource\", \"CertificateRequest\", \"ACME solver\", \"cert-manager ACME\", \"cert-manager Vault issuer\", \"trust-manager\", \"cert-manager CSI\", \"certificate renewal Kubernetes\", \"DNS-01 solver\", \"HTTP-01 solver\", \"ingress TLS annotation\", \"wildcard certificate Kubernetes\". Cross-skill boundaries: Let's Encrypt is the canonical public ACME CA that ClusterIssuers point at (see lets-encrypt); Vault's PKI engine is an alternative issuer (see hashicorp-vault-ops); certificate private-key handling and ACME account keys are secrets (see secrets-hygiene, which also owns the PKI concept layer including X.509, CA hierarchy, ACME protocol, and revocation); certificate validity windows and renewal timing reason about expiry in UTC (see utc-timestamps)."
license: MIT
metadata:
  version: 1.0.0
---

# cert-manager

> **Skill marker**: When applying this skill, begin your reply with `[skill: cert-manager]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

cert-manager is the CNCF graduated Kubernetes add-on for automated X.509 certificate lifecycle management. It introduces Certificate, Issuer, and ClusterIssuer custom resources; watches them; and drives issuance, rotation, and renewal against any configured backend. It is the primary tool for TLS in Kubernetes regardless of whether the backend is a public ACME CA (Let's Encrypt, ZeroSSL), an internal CA, HashiCorp Vault's PKI engine, or a Venafi policy server.

## When to use

- Creating or renewing TLS certificates on Kubernetes workloads and Ingress resources.
- Configuring Issuer or ClusterIssuer resources for ACME, Vault, CA, Venafi, or self-signed backends.
- Troubleshooting a Certificate stuck in Pending, a Challenge not completing, or a CertificateRequest that never progresses.
- Distributing a CA trust bundle to multiple namespaces via trust-manager.
- Mounting short-lived certificates directly into pods via the CSI driver (no Kubernetes Secret created).
- Installing cert-manager via Helm and verifying the installation.

## When not to use

- **ACME protocol internals, certbot/acme.sh on bare metal, rate limits, 6-day certs**: use `lets-encrypt`. That skill covers the ACME CA and its clients outside Kubernetes; this skill covers cert-manager as the Kubernetes ACME client.
- **Vault PKI engine configuration and PKI operational procedures**: use `hashicorp-vault-ops`. This skill covers only the cert-manager Vault issuer block; Vault internals live in that skill.
- **Secret-handling hygiene, PKI concept layer (X.509, CA hierarchy, ACME protocol deep-dive, revocation, CT logs)**: use `secrets-hygiene`.
- **Certificate expiry windows and renewal timing in UTC arithmetic**: use `utc-timestamps`.

## Classify the request first

| Class | Examples | Where depth lives |
|---|---|---|
| Installation | Helm install, CRD install, verify pods | `references/operations.md` |
| Issuer configuration | ACME, Vault, CA, Venafi, self-signed ClusterIssuer | `references/architecture.md` |
| Certificate resources | Certificate spec, dnsNames, duration, renewBefore, privateKey rotation | `references/architecture.md` |
| Solver configuration | HTTP-01 ingress, DNS-01 provider (Route 53, Cloudflare, Azure, GCP) | `references/architecture.md` |
| trust-manager | Bundle resources, namespace selector, ConfigMap distribution | `references/architecture.md` |
| CSI driver | Ephemeral cert volumes, short-lived per-pod certs | `references/architecture.md` |
| Troubleshooting | Certificate not ready, challenge failing, Vault issuer errors, stuck Pending | `references/operations.md` |

Then identify:
- **Issuer scope**: `Issuer` (namespace-scoped, can only issue into its own namespace) vs `ClusterIssuer` (cluster-wide, can issue into any namespace). Always confirm scope before writing YAML.
- **Environment**: cloud (GKE, EKS, AKS, with managed DNS and cloud IAM) vs on-prem (affects DNS-01 solver choice and Ingress class).

## Core model (condensed)

cert-manager introduces these CRDs:

| Resource | Role |
|---|---|
| `ClusterIssuer` / `Issuer` | Declares the backend (ACME, Vault, CA, Venafi, self-signed) and credentials |
| `Certificate` | Declares the desired certificate (dnsNames, duration, secretName) against an issuer |
| `CertificateRequest` | Intermediate: created by cert-manager; holds the CSR sent to the issuer |
| `Order` | ACME only: tracks an ACME order lifecycle |
| `Challenge` | ACME only: one per domain per order; tracks HTTP-01 or DNS-01 challenge |

Issuance flow for ACME:
```
Certificate -> CertificateRequest -> Order -> Challenge(s) -> Secret (tls.crt, tls.key)
```

Issuance flow for Vault/CA/Venafi:
```
Certificate -> CertificateRequest -> Secret (tls.crt, tls.key)
```

Ingress auto-cert: annotate an Ingress with `cert-manager.io/cluster-issuer` (or `cert-manager.io/issuer`). cert-manager reads the TLS stanza and creates the Certificate resource automatically.

Renewal: cert-manager renews at `renewBefore` before expiry. Default `duration` is 90 days; default `renewBefore` is 30 days. The `rotationPolicy: Always` option rotates the private key on every renewal (recommended).

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Issuer types and deep YAML | ACME (Let's Encrypt staging and production), DNS-01 solver providers (Route 53, Azure DNS, Cloud DNS, Cloudflare), Vault PKI issuer with Kubernetes auth, CA issuer, Venafi issuer, self-signed issuer and CA bootstrap, Certificate resource full spec with status/conditions, Ingress auto-cert annotation, trust-manager Bundle resource and pod mount, CSI driver volume attributes | `references/architecture.md` |
| Installation and operations | Helm install and CRD flag, verify pods, installation test with self-signed, troubleshooting (Certificate not ready, HTTP-01/DNS-01/Vault failures, stuck Pending), forcing manual renewal with cmctl | `references/operations.md` |

## Cross-references

- `lets-encrypt`: Let's Encrypt is the canonical public ACME CA. cert-manager's ACME ClusterIssuer points its `server:` field at the Let's Encrypt directory URL. For the ACME protocol internals, certbot/acme.sh on bare metal, rate limits, 6-day certs, and staging environment guidance, see that skill.
- `hashicorp-vault-ops`: Vault's PKI secret engine is an alternative issuer to ACME. cert-manager has a native Vault issuer block (server, path, Kubernetes auth role). Vault's PKI engine can also act as an ACME provider (Vault 1.14+). Vault internals, PKI engine configuration, and cluster operations live in that skill.
- `secrets-hygiene`: certificate private keys, DNS-01 solver API tokens, and ACME account keys (`privateKeySecretRef`) are secrets. The PKI concept layer (X.509 structure, chain of trust, CA hierarchy, ACME protocol mechanics, OCSP, CRL, CT logs) lives in `secrets-hygiene/references/pki-concepts.md`.
- `utc-timestamps`: certificate validity windows, `duration`, `renewBefore`, and renewal timing all reason about expiry in UTC. Use that skill for any arithmetic over certificate lifetimes.

## Red flags

- **`letsencrypt-prod` issuer during testing.** Always use the staging issuer first. Production rate limits are low; a failed batch of Certificate resources exhausts them fast.
- **HTTP-01 solver with port 80 blocked.** The Let's Encrypt validation server must reach port 80 on the domain. If the firewall blocks 80, switch to DNS-01.
- **`Issuer` when `ClusterIssuer` is needed.** An `Issuer` can only issue Certificates in its own namespace. Cross-namespace issuance requires a `ClusterIssuer`.
- **ACME account key stored in a namespace the issuer doesn't own.** `privateKeySecretRef` must be readable by the cert-manager service account.
- **No `rotationPolicy: Always`.** Without it, the private key never rotates on renewal. Rotate keys to limit exposure window.
- **trust-manager Bundle without namespace selector.** Without `namespaceSelector`, the bundle only syncs to the cert-manager namespace. Add the label to every namespace that needs the CA bundle.
- **CSI driver for long-lived workloads.** CSI certificates are ephemeral and renew automatically; if the pod restarts the cert is regenerated. Fine for short-lived services; verify the application handles cert rotation without a full restart.

## Bottom line

Classify as installation, issuer configuration, Certificate resource, solver, trust-manager, CSI, or troubleshooting. Confirm Issuer vs ClusterIssuer scope and cloud vs on-prem environment. Load `references/architecture.md` for issuer YAML, Certificate spec, and trust-manager; load `references/operations.md` for Helm install, troubleshoot procedures, and forced renewal. Always test with staging issuers before pointing at production ACME servers. For the concept layer (ACME internals, CA hierarchy, revocation), route to `secrets-hygiene`.
