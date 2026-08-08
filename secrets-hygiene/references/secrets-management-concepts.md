# Secrets management concepts

Deep reference for the secrets-management problem domain: the secret lifecycle, secret sprawl, choosing a manager, dynamic versus static secrets, rotation patterns, envelope encryption, and hardware security modules. The always-on handling rules (where secrets live, never-leak, probe vs use, leak response) stay in the `secrets-hygiene` SKILL.md body; this reference is the conceptual layer beneath them. For certificate and PKI concepts see `pki-concepts.md`.

## What is a secret

A secret is any credential or sensitive value that grants access to a resource: passwords and API keys, TLS/SSH private keys and certificates, database connection strings, OAuth client secrets and JWT signing keys, and encryption keys.

## Secret lifecycle

Every secret has a lifecycle that must be managed:

```
Generate -> Store -> Distribute -> Rotate -> Revoke -> Audit
```

- **Generation:** cryptographically random, adequate entropy, algorithm-appropriate length.
- **Storage:** encrypted at rest, access-controlled, audited.
- **Distribution:** encrypted in transit, least-privilege access, no plaintext in logs or env vars.
- **Rotation:** automated preferred, zero-downtime, versioned (the AWSPREVIOUS/AWSCURRENT pattern).
- **Revocation:** immediate effect, cascades to dependent systems.
- **Audit:** who accessed which secret, when, and from where.

## Secret sprawl: the core problem

Organisations accumulate secrets in many places:
- Hardcoded in source code (critical risk; scan with `git-secrets`, `truffleHog`, `gitleaks`).
- Environment variables without lifecycle management.
- Config files checked into version control.
- Shared spreadsheets or wikis.
- Multiple tools without a single source of truth.

A secrets-management strategy must address sprawl before optimising tooling.

## Choosing a secrets manager

| Dimension | Consideration |
|---|---|
| Deployment model | SaaS vs self-hosted vs cloud-native |
| Compliance requirements | FedRAMP, PCI-DSS, FIPS 140-3, SOC 2 |
| Dynamic vs static secrets | Dynamic secrets (short-lived, auto-generated) reduce exposure |
| Scale | Number of secrets, request throughput, replication needs |
| Developer experience | SDK support, CI/CD integrations, onboarding friction |
| Cost | Licensing model (per-secret, per-user, per-request, open source) |
| Existing cloud footprint | Azure -> AKV, AWS -> Secrets Manager/KMS, multi-cloud -> Vault/CyberArk |

## Dynamic vs static secrets

**Static secrets** are long-lived credentials stored and retrieved: lower complexity, higher risk from long exposure windows, and they require scheduled rotation.

**Dynamic secrets** are generated on demand with a TTL:
- The HashiCorp Vault database engine generates DB credentials valid for N minutes (see `hashicorp-vault-ops`).
- AWS IAM roles (STS) give temporary credentials to apps.
- They significantly reduce blast radius when compromised.
- Prefer dynamic secrets wherever the target system supports them.

## Secret rotation patterns

### Why rotation matters

Rotation limits the window of exposure if a credential is compromised. A secret rotated every 24 hours can only be exploited for up to 24 hours even if stolen immediately after rotation.

### Rotation strategies

- **Manual:** human-driven, error-prone, infrequent. Acceptable only for low-risk, low-count secrets with an SLA.
- **Scheduled:** automated on a calendar (for example every 30 days). Better, but still creates windows. Most secrets managers support this natively.
- **Event-driven:** rotated on a trigger (detected breach, employee departure, anomalous access). Requires integration with SIEM or threat detection.
- **Dynamic secrets (best):** a fresh secret is generated for each requester, valid for a short TTL. No rotation needed because secrets are effectively single-use. The Vault database engine is the canonical example.

### Zero-downtime rotation

Applications must tolerate credential rotation without restarting:

- **Versioned secrets (AWSCURRENT / AWSPREVIOUS):** generate the new secret as `AWSPENDING`, update the target system to accept it, promote `AWSPENDING` to `AWSCURRENT` (old becomes `AWSPREVIOUS`), keep a grace period where both are accepted, then revoke the old credential.
- **Blue-green credential rotation:** maintain two valid credentials at all times; rotate by retiring the older and issuing a new other-slot credential. No application restart required.
- **Connection-pool re-validation:** applications handle auth failures by re-fetching credentials, using a circuit breaker plus retry with backoff on DB auth failure; health checks detect stale credentials.

### Rotation by secret type

| Secret type | Recommended TTL | Rotation mechanism |
|---|---|---|
| Database passwords | 24h (dynamic) or 30d | Vault DB engine / AWS SM Lambda |
| API keys | 90d (static) | Custom Lambda or Vault Agent |
| TLS certificates | 90d (ACME) or shorter | cert-manager / ACME renewal (see `pki-concepts.md`) |
| SSH host keys | Annual or on compromise | Manual plus automation |
| JWT signing keys | 7-30d | JWKS endpoint rotation |
| Cloud IAM credentials | Avoid static; use roles | STS / managed identity |

The always-on `secrets-hygiene` rule "static credentials track expiry; raise an urgent rotate-in-place ticket seven days before expiry" applies on top of these mechanisms.

## Envelope encryption

### The problem

You cannot store encryption keys alongside the data they protect, and you cannot re-encrypt terabytes of data every time a key rotates.

### The pattern

```
Key Management Service
  Key Encryption Key (KEK / CMK), lives in an HSM, never exported
     | encrypt/decrypt the DEK
     v
Application / storage layer
  Plaintext --encrypt with DEK (Data Encryption Key)--> Ciphertext
  DEK --encrypt with KEK--> Encrypted DEK
  Store { Ciphertext + Encrypted DEK } together
```

### Key rotation without re-encryption

When the KEK is rotated: fetch each item's encrypted DEK, decrypt it with the old KEK, re-encrypt it with the new KEK, and store the new encrypted DEK. The actual ciphertext is never touched. Rotation is then O(number of unique data objects), not O(data size).

Used by AWS KMS, Azure Key Vault, GCP KMS, and the HashiCorp Vault transit engine.

```
# AWS KMS pattern
GenerateDataKey(KeyId=CMK_ARN) -> { Plaintext: DEK_bytes, CiphertextBlob: encrypted_DEK }
Use the plaintext DEK to encrypt data with AES-256-GCM
Immediately zero/discard the plaintext DEK from memory
Store CiphertextBlob alongside the ciphertext
# To decrypt: Decrypt(CiphertextBlob) -> plaintext DEK, then decrypt the ciphertext
```

The Vault transit engine provides this as a service so applications never see the key (`transit/encrypt/my-key`, `transit/decrypt/my-key`, `rewrap` for re-encrypting to the latest key version). See `hashicorp-vault-ops`.

## Hardware security modules (HSMs)

### What an HSM provides

1. **Key protection:** private keys are generated inside the HSM and never exported in plaintext.
2. **Cryptographic operations:** signing, encryption, and decryption happen inside the hardware.
3. **Tamper evidence and resistance:** a physical attack destroys the keys.
4. **Audit:** all operations are logged with operator identity.

### FIPS 140-3 levels

| Level | Requirement |
|---|---|
| Level 1 | Correct cryptographic algorithms, no physical requirements |
| Level 2 | Tamper-evident (seals/coatings), role-based authentication |
| Level 3 | Tamper-resistant (zeroises on attack), identity-based auth, physical security |
| Level 4 | Complete envelope protection, detects environmental attacks |

Cloud services typically provide Level 3: AWS CloudHSM, Azure Managed HSM, Azure Key Vault Premium (multi-tenant HSM), and GCP Cloud HSM.

### HSM vs software key store

| Concern | HSM | Software (for example Vault Shamir) |
|---|---|---|
| Key extraction | Physically impossible | Possible if the host is compromised |
| Performance | Hardware-accelerated crypto | CPU-bound |
| Cost | Significant | Low |
| Compliance | PCI-DSS, FedRAMP High | Generally insufficient for HSM-mandated controls |
| Operational complexity | High (quorum management, backup) | Lower |

### When an HSM is required

Payment card data (PCI-DSS Requirement 3.5), FedRAMP High or DoD IL4+ workloads, eIDAS qualified signatures, code signing for critical infrastructure, and any control requiring hardware-based key storage.

## Zero-trust secret distribution

Applications should never hold long-lived static credentials. Use platform identity instead:
- **Kubernetes:** projected service-account tokens plus the CSI driver, Vault Agent, or the External Secrets Operator.
- **AWS EC2/ECS/Lambda:** IAM instance/task/execution roles (STS temporary creds).
- **Azure:** managed identity (system-assigned or user-assigned).
- **GCP:** workload identity.

### External Secrets Operator (ESO)

A Kubernetes-native way to sync secrets from external stores (Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, 1Password, Doppler, Infisical) into Kubernetes Secrets. Preferred over vendor-specific operators when several backends are in use.

### GitOps and secrets

Secrets and GitOps are inherently in tension because git repositories are not secret stores. Approaches:
- **SOPS:** encrypt secret files, store the encrypted form in git, decrypt at deploy time.
- **Sealed Secrets:** Kubernetes-specific, encrypt with the cluster public key.
- **External Secrets Operator:** reference secrets in git, fetch them at runtime from the store.
- **Vault with ArgoCD/Flux:** the ArgoCD Vault Plugin or Vault sidecar injection.

## Audit and compliance

All secrets managers should provide access logs with caller identity, timestamp, and secret identifier; an immutable, tamper-evident audit trail; alerts on anomalous access patterns; and secret inventory and age reporting.

## Common anti-patterns

| Anti-pattern | Risk | Remedy |
|---|---|---|
| Hardcoded credentials in source | Critical; exposed in git history | Rotate immediately, use pre-commit hooks |
| Secrets in environment variables | Exposed in the process list and logs | Use a secrets manager with in-memory injection |
| Shared service accounts | No individual accountability | Per-application credentials with machine identity |
| No secret rotation | Long exposure window after a breach | Automate rotation, enforce a max age |
| No audit logging | Breach undetectable | Enable audit on all secret stores |
| Over-broad IAM policies | Blast radius too wide | Least privilege, per-app credentials |
| Self-rolled encryption | Crypto errors, key-management failures | Use a proven KMS or secrets manager |
