# Vault secret engines, auth methods, and integrations (usage)

Hands-on CLI and API usage for seal/unseal, secret engines, auth methods, policies, Vault Agent, the Vault Secrets Operator, audit devices, and the Enterprise feature map. For internals see `architecture.md`; for selection and design patterns see `best-practices.md`.

## Seal and unseal

Vault encrypts all data with a root key. On startup Vault is sealed: the root key is not in memory and no operation works except unseal.

Shamir secret sharing (default): the root key is split into N shares with K required to reconstruct it (default 5 shares, 3 required). Each key holder provides their share, and when the threshold is met Vault unseals.

```bash
# Check seal status
vault status

# Provide an unseal key (repeat K times with different keys)
vault operator unseal <key-share>

# Initialize a new Vault (generates root key + initial root token)
vault operator init -key-shares=5 -key-threshold=3
```

Auto-unseal (Enterprise and Community 1.4+) delegates root-key protection to an external KMS:
- AWS KMS (`awskms` seal)
- Azure Key Vault (`azurekeyvault` seal)
- GCP Cloud KMS (`gcpckms` seal)
- OCI KMS (`ocikms` seal)
- HSM via PKCS#11 (`pkcs11` seal, Enterprise only)

```hcl
# vault.hcl - AWS KMS auto-unseal
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}
```

Seal migration: migrate between Shamir and auto-unseal, or between two auto-unseal providers, using `vault operator unseal -migrate`.

### Storage configuration (Raft)

```hcl
# vault.hcl - Raft storage
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"
}

ha_storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"
}
```

## Secret engines

Each engine is mounted at a path.

```bash
vault secrets enable -path=secret kv-v2
vault secrets enable database
vault secrets enable pki
vault secrets list
```

### KV v2 (key-value)

The most common engine. A versioned key-value store.

```bash
# Write a secret
vault kv put secret/myapp/config db_password="s3cr3t" api_key="abc123"

# Read a secret (latest version)
vault kv get secret/myapp/config

# Read a specific version
vault kv get -version=2 secret/myapp/config

# Get metadata (all versions)
vault kv metadata get secret/myapp/config

# Delete (soft delete, version preserved)
vault kv delete secret/myapp/config

# Destroy (permanent, removes version data)
vault kv destroy -versions=1,2 secret/myapp/config

# Set max versions (metadata)
vault kv metadata put -max-versions=10 secret/myapp/config
```

### Database secret engine

Generates dynamic credentials for databases. Credentials are created on demand, carry a TTL, and are revoked automatically when the lease expires.

```bash
vault secrets enable database

# Configure connection (PostgreSQL example)
vault write database/config/my-postgres \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb" \
    allowed_roles="app-role" \
    username="vault-admin" \
    password="vault-admin-pass"

# Create a role
vault write database/roles/app-role \
    db_name=my-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"

# Generate credentials
vault read database/creds/app-role
# Returns: username=v-token-app-role-... password=...
```

Supported databases include PostgreSQL, MySQL/MariaDB, MSSQL, Oracle, MongoDB, Cassandra, Elasticsearch, Redis, and Snowflake.

### PKI secret engine

A full certificate authority built into Vault, used for internal PKI, mTLS, and as an ACME CA.

```bash
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki

# Generate root CA
vault write pki/root/generate/internal \
    common_name="My Root CA" \
    ttl=87600h

# Configure URLs
vault write pki/config/urls \
    issuing_certificates="https://vault.example.com/v1/pki/ca" \
    crl_distribution_points="https://vault.example.com/v1/pki/crl"

# Create intermediate CA
vault secrets enable -path=pki_int pki
vault write pki_int/intermediate/generate/internal common_name="My Intermediate CA"
# Sign with root, then set the signed cert
vault write pki/root/sign-intermediate csr=@pki_int.csr format=pem_bundle ttl=43800h
vault write pki_int/intermediate/set-signed certificate=@signed.pem

# Create a role for issuing certs
vault write pki_int/roles/my-service \
    allowed_domains="internal.example.com" \
    allow_subdomains=true \
    max_ttl=72h

# Issue a certificate
vault write pki_int/issue/my-service \
    common_name="api.internal.example.com" \
    ttl=24h
```

For production CA hierarchy guidance (Vault as an intermediate CA only, ACME provider config) see `best-practices.md`.

### Transit secret engine

Encryption-as-a-service. Applications encrypt and decrypt without ever handling the key.

```bash
vault secrets enable transit

# Create a key
vault write -f transit/keys/my-key

# Encrypt
vault write transit/encrypt/my-key \
    plaintext=$(echo "my secret data" | base64)
# Returns: ciphertext=vault:v1:...

# Decrypt
vault write transit/decrypt/my-key \
    ciphertext="vault:v1:..."
# Returns: plaintext (base64 encoded)

# Rotate the key (old versions still decrypt)
vault write -f transit/keys/my-key/rotate

# Rewrap ciphertext with the latest key version
vault write transit/rewrap/my-key ciphertext="vault:v1:..."

# Set minimum decryption version (retirement)
vault write transit/keys/my-key/config min_decryption_version=2
```

Key types: `aes256-gcm96` (default), `aes128-gcm96`, `chacha20-poly1305`, `rsa-2048`, `rsa-4096`, `ecdsa-p256`, `ed25519`.

### AWS, Azure, GCP secret engines

Generate cloud-provider credentials on demand:

```bash
# AWS - generates IAM user credentials or assumes roles
vault secrets enable aws
vault write aws/config/root access_key=... secret_key=... region=us-east-1
vault write aws/roles/my-role credential_type=assumed_role role_arns=arn:aws:iam::123:role/MyRole
vault read aws/creds/my-role  # Returns temporary STS credentials
```

## Auth methods

Applications prove their identity to Vault to receive a token.

### Token auth (always enabled)

The root auth method. All other methods ultimately issue tokens.

```bash
vault token create -policy="my-policy" -ttl=24h
vault token create -policy="my-policy" -period=24h   # periodic, for long-running services
vault token lookup
vault token renew
```

### AppRole auth

Machine-to-machine auth without platform identity. Use when no cloud IAM or Kubernetes is available.

```bash
vault auth enable approle

vault write auth/approle/role/my-app \
    secret_id_ttl=10m \
    token_ttl=20m \
    token_max_ttl=30m \
    token_policies="my-app-policy"

# Get RoleID (not secret, can be baked into config)
vault read auth/approle/role/my-app/role-id

# Generate SecretID (treat like a password; deliver via a trusted mechanism)
vault write -f auth/approle/role/my-app/secret-id

# Login
vault write auth/approle/login role_id=<role-id> secret_id=<secret-id>
```

See `best-practices.md` for SecretID response-wrapping (Cubbyhole).

### Kubernetes auth

Native auth for pods, using projected service-account tokens.

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault write auth/kubernetes/role/my-app \
    bound_service_account_names=my-sa \
    bound_service_account_namespaces=my-namespace \
    policies=my-app-policy \
    ttl=1h
```

### OIDC / JWT auth

For human users via SSO (Okta, Azure AD, Google):

```bash
vault auth enable oidc

vault write auth/oidc/config \
    oidc_discovery_url="https://accounts.google.com" \
    oidc_client_id="..." \
    oidc_client_secret="..." \
    default_role="default"

vault write auth/oidc/role/default \
    bound_audiences="vault" \
    allowed_redirect_uris="https://vault.example.com/ui/vault/auth/oidc/oidc/callback" \
    user_claim="email" \
    policies="default"
```

### AWS IAM auth

For EC2 instances and Lambda functions:

```bash
vault auth enable aws

vault write auth/aws/config/client access_key=... secret_key=...

vault write auth/aws/role/my-ec2-role \
    auth_type=iam \
    bound_iam_principal_arn=arn:aws:iam::123:role/MyRole \
    policies=my-policy \
    ttl=1h
```

## Policies

Policies control what a token can do. They are written in HCL and are path-based.

```hcl
# my-app-policy.hcl
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "database/creds/app-role" {
  capabilities = ["read"]
}

path "pki_int/issue/my-service" {
  capabilities = ["create", "update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
# Access to all other paths is denied by default
```

Capabilities: `create`, `read`, `update`, `delete`, `list`, `patch`, `deny`, `sudo`.

```bash
vault policy write my-app-policy my-app-policy.hcl
vault policy list
vault policy read my-app-policy
```

Templated policies use identity metadata to avoid per-entity policies:

```hcl
path "secret/data/{{identity.entity.aliases.auth_kubernetes_abc123.metadata.service_account_name}}/*" {
  capabilities = ["read"]
}
```

## Vault Agent

A sidecar or daemon that handles auth, token renewal, and secret templating, removing Vault auth logic from applications.

```hcl
# vault-agent-config.hcl
vault {
  address = "https://vault.example.com"
}

auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "my-app"
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
    }
  }
}

template {
  source      = "/vault/templates/config.tpl"
  destination = "/vault/secrets/config.txt"
  command     = "sh -c 'kill -HUP $(cat /app/app.pid)'"  # reload app on change
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}
```

Template syntax (Go templates with Vault functions):

```
{{ with secret "secret/data/myapp/config" }}
DB_PASSWORD={{ .Data.data.db_password }}
API_KEY={{ .Data.data.api_key }}
{{ end }}
```

## Vault Secrets Operator (VSO)

A Kubernetes operator that syncs Vault secrets into Kubernetes Secrets and auto-rotates them.

```yaml
# VaultAuth - authenticate to Vault
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: default
  namespace: my-namespace
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: my-app
    serviceAccount: my-sa

---
# VaultStaticSecret - sync a KV secret
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: my-app-secret
  namespace: my-namespace
spec:
  type: kv-v2
  mount: secret
  path: myapp/config
  destination:
    name: my-app-secret  # K8s Secret name
    create: true
  refreshAfter: 30s

---
# VaultDynamicSecret - sync dynamic credentials
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: db-creds
  namespace: my-namespace
spec:
  mount: database
  path: creds/app-role
  destination:
    name: db-credentials
    create: true
```

## Audit devices

Enable audit logging (required for compliance):

```bash
vault audit enable file file_path=/vault/logs/audit.log
vault audit enable syslog tag=vault facility=AUTH
vault audit enable socket address=logstash:5000 socket_type=tcp
vault audit list
```

Audit logs are HMAC-hashed (salted): sensitive values are hashed, not plaintext. Verify a value against the HMAC using `vault audit hash`.

## Enterprise feature map

| Feature | Description |
|---|---|
| Namespaces | Multi-tenancy: isolated Vault environments within one cluster |
| Performance replication | Read-only replica clusters for geo-distributed reads |
| DR replication | Disaster-recovery replica (active-passive) |
| Sentinel policies | Fine-grained policy framework (EGP/RGP), request/response inspection |
| MFA | Step-up MFA for sensitive paths (TOTP, Okta, Duo, PingID) |
| Control groups | Approval workflows: require N operators to approve sensitive actions |
| HSM auto-unseal | PKCS#11 HSM for root-key protection |
| FIPS 140-3 | FIPS-compliant build |
