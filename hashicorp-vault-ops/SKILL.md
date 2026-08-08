---
name: hashicorp-vault-ops
description: "Use for HashiCorp Vault operations and architecture across Community, Enterprise, and HCP Vault Dedicated: seal and unseal (Shamir secret sharing and auto-unseal via cloud KMS or HSM), storage backends (Raft integrated storage, Consul, cloud object stores), secret engines (KV v2, database dynamic credentials, PKI certificate authority, transit encryption-as-a-service, AWS/Azure/GCP, SSH, TOTP, AD), auth methods (token, AppRole, Kubernetes, OIDC/JWT, AWS IAM, LDAP), policies (HCL path-based, templated, Sentinel EGP/RGP), Vault Agent, Vault Secrets Operator (VSO), audit devices, replication (performance and DR), namespaces, leases, and HA cluster operations. References: architecture.md, best-practices.md, secrets-engines-and-auth.md. Triggers include \"HashiCorp Vault\", \"vault seal\", \"vault unseal\", \"vault operator init\", \"secret engine\", \"KV v2\", \"dynamic secrets\", \"AppRole\", \"SecretID\", \"Vault Agent\", \"Vault Secrets Operator\", \"VSO\", \"transit encryption\", \"Vault PKI\", \"Raft storage\", \"integrated storage\", \"auto-unseal\", \"vault policy\", \"vault namespace\", \"Vault replication\", \"Vault Enterprise\", \"Vault Agent template\". For secret-handling hygiene and the secrets-management plus PKI concept layer see secrets-hygiene; for Vault as a certificate issuer alongside the Kubernetes controller and ACME CA see cert-manager and lets-encrypt; for the cloud IAM that Vault auth methods federate with see aws-iam, gcp-iam, entra-id."
license: MIT
metadata:
  version: 1.0.0
---

# HashiCorp Vault ops

> **Skill marker**: When applying this skill, begin your reply with `[skill: hashicorp-vault-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the operations and architecture entry point for HashiCorp Vault across all editions: Community (BSL 1.1), Enterprise, and HCP Vault Dedicated. It owns Vault-the-product: how the server seals and unseals, how secret engines and auth methods are wired, how policies gate access, and how a Raft cluster is operated and recovered. Deep usage and internals live in the three references below.

> **Note:** HCP Vault Secrets (the SaaS key-value store) reaches end of life in July 2026. The migration path is HCP Vault Dedicated or self-managed Vault.

## When to use

- Operating a Vault server or cluster: init, seal/unseal, Raft join, backup and restore, upgrade, lease cleanup, break-glass root regeneration.
- Configuring secret engines (KV v2, database, PKI, transit, cloud, SSH) and choosing the right engine for a use case.
- Configuring auth methods (AppRole, Kubernetes, OIDC, AWS IAM, LDAP) and selecting the right one for an environment.
- Designing policies (HCL path-based, templated, or Sentinel) under least privilege.
- Integrating Vault with Kubernetes via Vault Agent or the Vault Secrets Operator.
- Planning HA architecture, replication (performance and DR), namespaces, capacity, and telemetry.

## When not to use

- **Secret-handling hygiene** (where secrets live, gitignored files, never-leak rules, leak response): use `secrets-hygiene`. That skill also carries the secrets-management and PKI concept layer (chain of trust, CA hierarchy, key types, revocation).
- **Certificate issuance via the Kubernetes controller or the public ACME CA**: use `cert-manager` and `lets-encrypt`. Vault's own PKI engine is covered here; the wider certificate-issuance ecosystem is those skills.
- **Cloud IAM design** that Vault auth methods or dynamic-credential engines federate with: use `aws-iam`, `gcp-iam`, `entra-id`.

## Classify the request first

Every Vault request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Operations | seal, unseal, init, Raft join, backup, upgrade, lease tidy, break-glass | `references/architecture.md` (operational procedures) |
| Secret engine | KV v2, database creds, PKI, transit, cloud creds | `references/secrets-engines-and-auth.md` |
| Auth method | AppRole, Kubernetes, OIDC, AWS IAM, LDAP | `references/secrets-engines-and-auth.md` |
| Policy / RBAC | HCL paths, capabilities, templated, Sentinel | `references/secrets-engines-and-auth.md` + `references/best-practices.md` |
| Architecture / HA | Raft consensus, replication, namespaces, plugins, sizing | `references/architecture.md` |
| Pattern / design | engine selection, policy design, PKI deployment, Agent vs VSO | `references/best-practices.md` |

Then identify the **edition**: Community vs Enterprise (namespaces, replication, Sentinel, HSM auto-unseal, FIPS) vs HCP Vault Dedicated. Many features below are Enterprise-only.

## Core model (condensed)

Vault encrypts everything through a **barrier** (AES-256-GCM) keyed by a root key. On startup Vault is **sealed**: the root key is not in memory and no operation works except unseal. Shamir secret sharing splits the root key into N shares needing K to reconstruct (default 5/3); **auto-unseal** delegates root-key protection to a cloud KMS or HSM so a restart does not need manual key entry.

The storage backend sees only opaque encrypted blobs. **Raft integrated storage** is the recommended default: built-in HA, no external dependency, quorum-acknowledged writes. Production needs an odd node count (3 tolerates 1 failure, 5 tolerates 2).

Quick reference for the two surfaces you wire most:

| Secret engine | Generates | Use when |
|---|---|---|
| KV v2 | Versioned static key-value | Application config |
| database | Dynamic, auto-revoked DB creds | Per-app least-privilege database access |
| pki | Short-lived certificates (full CA) | Internal TLS/mTLS, ACME provider |
| transit | Encryption-as-a-service (no key in app) | App-layer encryption, no key handling |
| aws / azure / gcp | Dynamic cloud credentials | On-demand scoped cloud access |

| Auth method | Binds identity to | Use when |
|---|---|---|
| kubernetes | Service account + namespace | Pods |
| aws (iam) | IAM role/principal | EC2/ECS/Lambda |
| jwt (OIDC) | CI claims (repo/branch) | GitHub Actions and modern CI |
| oidc | SSO identity (email/groups) | Human users |
| approle | RoleID + SecretID | Last resort with no platform identity |

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Architecture internals and operations | Barrier, Raft consensus and cluster sizing, storage-backend comparison, replication (performance and DR), namespaces, plugin system, token architecture, request pipeline, leases, performance and capacity planning, telemetry, backup/restore, upgrade, break-glass | `references/architecture.md` |
| Best practices and design patterns | Secret-engine selection, KV/database/transit patterns, auth-method selection, AppRole SecretID protection, policy design and least privilege, Sentinel, PKI production deployment, audit configuration, Vault Agent vs VSO, HA network and health endpoints, common misconfigurations | `references/best-practices.md` |
| Secret engines and auth methods (usage) | CLI and API usage for KV v2, database, PKI, transit, cloud engines; auth methods (token, AppRole, Kubernetes, OIDC, AWS IAM); policy HCL; Vault Agent config and templates; Vault Secrets Operator manifests; audit devices; Enterprise feature map | `references/secrets-engines-and-auth.md` |

## Cross-references

- `secrets-hygiene`: the always-on discipline for where secrets live and never-leak rules, and the home for the secrets-management plus PKI concept layer (chain of trust, CA hierarchy, key types, revocation, CT logs). Vault is one store the probe table references (`vault kv get -field=value PATH > /dev/null`).
- `cert-manager`: the Kubernetes controller that can use Vault's PKI engine as an issuer. Vault owns the engine; cert-manager owns the in-cluster certificate lifecycle.
- `lets-encrypt`: the public ACME CA. Vault's PKI engine can itself act as an ACME provider (1.14+); the public-CA path belongs to that skill.
- `aws-iam`, `gcp-iam`, `entra-id`: the cloud IAM that Vault auth methods bind to and that the dynamic cloud-credential engines issue against.
- `utc-timestamps`: lease TTLs, token max-TTL, certificate validity windows, and key rotation timing reason about expiry in UTC.

## Red flags

- **Root token in use.** The initial root token is for setup only. Create admin tokens with policies, then revoke the root token.
- **No audit devices.** Vault without audit logging fails compliance and hides breaches. Enable file plus syslog, and remember Vault blocks if all audit devices fail (use two, or fallback mode).
- **Shamir shares held by one custodian.** No redundancy and a single point of compromise. Distribute shares to separate custodians per a key-custodian runbook.
- **No auto-unseal in production.** Every restart then needs manual quorum unseal. Configure cloud KMS or HSM auto-unseal.
- **Wildcard sudo policy** (`path "*" { capabilities = ["sudo"] }`). Write least-privilege path policies instead.
- **Vault in dev mode in production** (`vault server -dev`). It is unsealed, in-memory, and non-persistent.
- **Tokens with no TTL.** Always set `ttl` and `max_ttl`; rely on leases and renewal, not immortal tokens.
- **Single-node Raft for production.** No failure tolerance. Use an odd cluster of 3 or 5.

## Bottom line

Classify the request as operations, secret engine, auth method, policy, architecture, or pattern, then identify the edition. Load `architecture.md` for internals and cluster operations, `secrets-engines-and-auth.md` for hands-on engine and auth usage, and `best-practices.md` for selection and design under least privilege. Treat seal/unseal, replication, and PKI as change-controlled operations, and never run a production Vault on a root token or without audit devices.
