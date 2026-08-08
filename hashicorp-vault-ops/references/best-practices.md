# HashiCorp Vault best practices

Operational patterns for secret-engine selection, auth-method selection, policy design, audit compliance, dynamic secrets, transit encryption, PKI, Vault Agent, and Kubernetes integration.

## Secret-engine selection guide

| Use case | Engine | Why |
|---|---|---|
| Application config (static) | KV v2 | Versioned, soft-delete, metadata |
| Database credentials | database | Dynamic, auto-revoked, least privilege |
| Internal TLS/mTLS | pki | Full CA, short-lived certs, auto-renewal |
| Encryption service | transit | No key management in app code |
| AWS credentials | aws | Dynamic STS or IAM user, scoped policies |
| Azure credentials | azure | Dynamic service principals |
| GCP credentials | gcp | Dynamic service accounts |
| SSH access | ssh | Signed SSH certificates (OTP or CA mode) |
| TOTP tokens | totp | Second-factor generation |
| Active Directory | ad | Service-account password rotation |

### KV v2 best practices

Path structure: organise by `<environment>/<team>/<service>/<secret-type>`.

```
secret/data/prod/platform/api-gateway/tls
secret/data/prod/platform/api-gateway/config
secret/data/staging/team-a/payments/db-creds
```

Versioning: set `max_versions` to 10 or fewer to control storage growth.
```bash
vault kv metadata put -max-versions=10 secret/prod/myapp/config
```

Secret metadata: use custom metadata to document secrets.
```bash
vault kv metadata put \
    -custom-metadata=owner="platform-team" \
    -custom-metadata=rotation-policy="30d" \
    -custom-metadata=last-rotated="2025-01-01" \
    secret/prod/myapp/config
```

Check-and-set (CAS): prevent accidental overwrites by requiring a version match.
```bash
vault kv put -cas=3 secret/prod/myapp/config key=value
# Fails if current version is not 3
```

### Database engine best practices

1. Use least-privilege creation statements: grant only the permissions the application needs.
2. Set a short default TTL: 1-4 hours for most apps, longer for batch jobs.
3. Use static roles for legacy apps that cannot handle rotating credentials:

```bash
vault write database/static-roles/legacy-app \
    db_name=my-postgres \
    username="legacy_app" \
    rotation_period=24h
```

4. Connection management: set `max_open_connections` and `max_idle_connections` to avoid overwhelming the database.
5. Rotate root credentials: rotate the Vault admin credentials after configuration.
```bash
vault write -f database/rotate-root/my-postgres
```

### Transit engine best practices

1. Never export keys: keep `exportable=false` (the default).
2. Set a minimum decryption version to retire old key material.
```bash
vault write transit/keys/my-key/config min_decryption_version=3
```
3. Use batch operations for high-throughput encryption.
```bash
vault write transit/encrypt/my-key \
    batch_input='[{"plaintext":"dGVzdA=="},{"plaintext":"dGVzdDI="}]'
```
4. Key-type selection:
   - `aes256-gcm96`: default, symmetric, fastest, for data encryption.
   - `rsa-4096`: asymmetric, for key wrapping or external interop.
   - `ed25519`: for signing and verification (not encryption).
5. Convergent encryption: if the same plaintext must produce the same ciphertext (for deduplication or lookup), use `convergent_encryption=true` with `derived=true`. Understand the trade-off: it reveals whether two plaintexts are equal.

## Auth-method selection guide

| Environment | Recommended auth method | Rationale |
|---|---|---|
| Kubernetes pods | kubernetes | Bound to SA and namespace; no secret management |
| AWS EC2/ECS/Lambda | aws (iam type) | Bound to IAM role; no long-lived creds |
| Azure VMs/AKS | azure | Bound to managed identity |
| GCP | gcp | Bound to service account |
| CI/CD (GitHub Actions) | jwt (OIDC) | Bound to repo/branch claims |
| CI/CD (Jenkins) | jwt or approle | JWT preferred for modern Jenkins |
| Human users (SSO) | oidc | SSO with Okta/Azure AD/Google |
| Human users (legacy) | ldap | Active Directory integration |
| No platform identity | approle | Last resort; manage SecretID delivery carefully |

### AppRole SecretID security

SecretID is effectively a password. Protect it:
- Use `secret_id_ttl` to limit validity (10-60 minutes for bootstrap).
- Use `secret_id_num_uses=1` for one-time use (recommended).
- Wrap the SecretID in a Cubbyhole response-wrapping token:

```bash
# Wrap SecretID in a one-time-use token
vault write -wrap-ttl=60s -f auth/approle/role/my-app/secret-id
# Returns: wrapping_token (deliver this, not the SecretID)

# App unwraps the token to get the SecretID
VAULT_TOKEN=<wrapping_token> vault unwrap
```

### Kubernetes auth best practices

1. Bind to specific namespaces and service accounts.
2. Use `token_bound_cidrs` to restrict token use to pod IP ranges.
3. Configure token TTLs to match the longest-running operations.
4. Enable `token_no_default_policy` for strict policy management.

```bash
vault write auth/kubernetes/role/my-app \
    bound_service_account_names=my-sa \
    bound_service_account_namespaces=production \
    token_policies="my-app-policy" \
    token_ttl=20m \
    token_max_ttl=30m \
    token_no_default_policy=true
```

## Policy design best practices

### Principle of least privilege

Write policies that grant the minimum required access:

```hcl
# GOOD: specific path, specific capabilities
path "secret/data/prod/myapp/config" {
  capabilities = ["read"]
}

# BAD: wildcard with write
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

### Policy naming conventions

```
<environment>-<team>-<service>-<role>

prod-platform-api-gateway-read
staging-team-a-payments-admin
shared-database-app-creds
```

### Policy structure template

```hcl
# Description: Read-only access for myapp in production
# Owner: platform-team
# Last reviewed: 2025-01-01

# Application secrets
path "secret/data/prod/myapp/*" {
  capabilities = ["read"]
}

path "secret/metadata/prod/myapp/*" {
  capabilities = ["list"]
}

# Dynamic database credentials
path "database/creds/prod-myapp-role" {
  capabilities = ["read"]
}

# PKI certificate issuance
path "pki_int/issue/myapp" {
  capabilities = ["update"]
}

# Token self-management
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}
```

### Sentinel policies (Enterprise)

Endpoint Governing Policies (EGP) and Role Governing Policies (RGP) provide fine-grained control beyond path matching:

```python
# Sentinel: enforce MFA for deletion
import "strings"

main = rule {
  request.operation is not "delete" or
  identity.entity.mfa_methods contains "totp"
}
```

## Vault PKI engine: production deployment

### Certificate authority hierarchy

Never use Vault as a root CA in production. Use Vault as an intermediate CA:

```
Offline Root CA (air-gapped, HSM-backed)
  Vault Intermediate CA (online, Vault PKI engine)
    Leaf certificates (TLS, mTLS, SSH)
```

```bash
# 1. Enable intermediate CA in Vault
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int  # 5 years max

# 2. Generate CSR (Vault holds the private key)
vault write pki_int/intermediate/generate/internal \
    common_name="My Intermediate CA 2025" \
    key_type="rsa" \
    key_bits=4096 \
    -format=json | jq -r '.data.csr' > intermediate.csr

# 3. Sign with offline Root CA (offline step)
# openssl ca -config root-ca.conf -in intermediate.csr -out intermediate.crt

# 4. Import signed certificate
vault write pki_int/intermediate/set-signed certificate=@intermediate.crt

# 5. Configure CRL and OCSP URLs
vault write pki_int/config/urls \
    issuing_certificates="https://vault.example.com/v1/pki_int/ca" \
    crl_distribution_points="https://vault.example.com/v1/pki_int/crl" \
    ocsp_servers="https://vault.example.com/v1/pki_int/ocsp"
```

### PKI roles for different certificate types

```bash
# TLS server certificates (internal services)
vault write pki_int/roles/internal-tls \
    allowed_domains="internal.example.com,svc.cluster.local" \
    allow_subdomains=true \
    allow_bare_domains=false \
    max_ttl=720h \    # 30 days
    key_type=rsa \
    key_bits=2048 \
    server_flag=true \
    client_flag=false

# mTLS client certificates
vault write pki_int/roles/mtls-client \
    allowed_domains="clients.internal.example.com" \
    allow_subdomains=true \
    max_ttl=24h \     # Short-lived for mTLS
    server_flag=false \
    client_flag=true

# ACME provider (Vault 1.14+)
vault write pki_int/config/acme enabled=true
```

The Vault PKI engine can act as an ACME provider, which is how `cert-manager` and ACME clients can request certificates from Vault rather than from a public CA such as Let's Encrypt. See `cert-manager` and `lets-encrypt` for the consuming side.

## Audit device configuration

### Required for compliance

Enable at least two audit devices so Vault does not block if one fails (Vault requires all audit devices to succeed):

```bash
# Primary: file audit
vault audit enable file file_path=/vault/logs/audit.log log_raw=false

# Secondary: syslog to SIEM
vault audit enable -path=syslog syslog tag=vault

# If using only one device, use fallback mode
vault audit enable -options=fallback=true file file_path=/vault/logs/audit.log
```

### Log format

Audit logs are JSON. Key fields:

```json
{
  "time": "2025-01-01T00:00:00Z",
  "type": "request",
  "auth": {
    "client_token": "hmac-sha256:...",
    "accessor": "hmac-sha256:...",
    "policies": ["my-app-policy"],
    "entity_id": "entity-id",
    "display_name": "kubernetes-production-my-sa"
  },
  "request": {
    "id": "req-id",
    "operation": "read",
    "path": "secret/data/prod/myapp/config",
    "remote_address": "10.0.0.1"
  },
  "response": {
    "data": {
      "metadata": { "version": 1 }
    }
  }
}
```

Secret data values in the log are HMAC-hashed, not plaintext.

### Audit log monitoring alerts

Alert on:
- `auth.policies` containing `root` (root-token usage).
- A high rate of denied requests (403) from a single entity.
- Access to `sys/` paths (administrative operations).
- Token creation with TTL over 24h.
- Deletion operations on production secret paths.

## Vault Agent: production patterns

### Kubernetes sidecar pattern

```yaml
# pod spec with Vault Agent sidecar
initContainers:
- name: vault-agent-init
  image: hashicorp/vault:1.17
  args: ["agent", "-config=/vault/config/vault-agent.hcl", "-exit-after-auth"]
  volumeMounts:
  - name: vault-config
    mountPath: /vault/config
  - name: vault-secrets
    mountPath: /vault/secrets

containers:
- name: app
  image: myapp:latest
  volumeMounts:
  - name: vault-secrets
    mountPath: /vault/secrets
    readOnly: true

- name: vault-agent
  image: hashicorp/vault:1.17
  args: ["agent", "-config=/vault/config/vault-agent.hcl"]
  volumeMounts:
  - name: vault-config
    mountPath: /vault/config
  - name: vault-secrets
    mountPath: /vault/secrets
```

### Vault Secrets Operator vs Vault Agent

| Feature | VSO | Vault Agent |
|---|---|---|
| Paradigm | Kubernetes-native (CRDs) | Sidecar/daemon |
| Secret delivery | K8s Secrets | Files or env vars |
| Rotation | Automatic (watch + sync) | Automatic (template + command) |
| Application changes needed | No (mount K8s Secret) | No (read file) |
| Dynamic secrets | Yes (VaultDynamicSecret) | Yes (lease renewal) |
| Complexity | Lower (operator manages it) | Higher (config per pod) |
| Recommendation | Prefer for new K8s deployments | Use for non-K8s or complex templating |

VSO is GitOps-compatible: define VaultStaticSecret/VaultDynamicSecret resources in git, and VSO fetches the actual secret at runtime. No secret values land in git.

## High availability: network requirements

```
Vault nodes (Raft cluster):
  Port 8200: API + UI (HTTPS)
  Port 8201: Cluster replication (internal, TLS)
  Port 8300: Raft RPC (internal)
```

A load balancer should forward to the active node only (check `/v1/sys/health?standbyok=false`), or forward to any node (a standby redirects to the active node with a 307).

Health endpoint responses:
- `200`: active node.
- `429`: standby (read-only).
- `472`: DR secondary.
- `473`: performance standby.
- `501`: not initialised.
- `503`: sealed.

## Common misconfigurations

| Misconfiguration | Risk | Fix |
|---|---|---|
| No audit devices | Compliance failure, breach undetected | Enable file + syslog audit |
| Root token in use | Root-token compromise is full cluster access | Create admin tokens, revoke root |
| Shamir keys with one holder | No redundancy | Distribute key shares to multiple custodians |
| No auto-unseal | Manual unseal after restart | Configure cloud KMS auto-unseal |
| KV v1 instead of v2 | No versioning, metadata, or CAS | Migrate to KV v2 |
| `path "*" { capabilities = ["sudo"] }` | Unrestricted access | Write least-privilege policies |
| `vault server -dev` in production | Unsealed, in-memory, no persistence | Use a production config |
| No TTL on tokens | Tokens never expire | Always set ttl and max_ttl |
| Storing the Vault token in an env var | Token in the process list and logs | Use a Vault Agent file sink |
