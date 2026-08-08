# Auth0 operations

## Environment strategy

Use separate Auth0 tenants per environment. Never test in production.

| Environment | Purpose | Connection configuration |
|---|---|---|
| Development | Feature development, Actions testing | Test social connections; mock enterprise IdP (Auth0 SAML IdP or a test Okta tenant) |
| Staging | Pre-production validation | Mirror production connections with test data; production-equivalent configuration |
| Production | Live customer traffic | Real social/enterprise connections; custom domain; full Attack Protection; log streaming |

**Configuration drift prevention**: manage all three tenants via the same IaC tooling (Deploy CLI or Terraform) to keep staging and production in sync.

---

## Tenant configuration as code

### Auth0 Deploy CLI

The Auth0 Deploy CLI (`a0deploy`) exports and imports tenant configuration as a directory of JSON/YAML files and Action scripts.

```bash
# Install
npm install -g auth0-deploy-cli

# Export tenant configuration to ./auth0/
a0deploy export \
  -c config.json \
  --format directory \
  --output_folder ./auth0

# Import (deploy) configuration from ./auth0/ to target tenant
a0deploy import \
  -c config.json \
  --input_folder ./auth0
```

**config.json** (store client secret via `secrets-hygiene`; inject at deploy time):

```json
{
  "AUTH0_DOMAIN": "company.auth0.com",
  "AUTH0_CLIENT_ID": "...",
  "AUTH0_CLIENT_SECRET": "${AUTH0_CLIENT_SECRET}",
  "AUTH0_EXPORT_IDENTIFIERS": false,
  "AUTH0_ALLOW_DELETE": false
}
```

**What Deploy CLI manages**: clients (applications), connections, Resource Servers (APIs), rules (legacy), hooks (legacy), actions, pages (login/error/password-reset), tenant settings, email templates, grants.

**What it does not manage**: users, log events, real-time webtask containers.

### Terraform provider

The official `auth0/auth0` Terraform provider manages Auth0 resources declaratively.

```hcl
terraform {
  required_providers {
    auth0 = { source = "auth0/auth0" }
  }
}

resource "auth0_client" "spa_app" {
  name     = "My SPA"
  app_type = "spa"
  callbacks           = ["https://app.company.com/callback"]
  allowed_logout_urls = ["https://app.company.com"]
  oidc_conformant     = true
}

resource "auth0_resource_server" "api" {
  name             = "Company API"
  identifier       = "https://api.company.com"
  signing_alg      = "RS256"
  enforce_policies = true
  token_dialect    = "access_token_authz"
}
```

Prefer Terraform when the organisation already uses Terraform for infrastructure; prefer Deploy CLI for Auth0-only pipelines or when exporting and diffing is a primary workflow.

---

## Logging and monitoring

### Tenant log events

Auth0 logs all authentication events, management API calls, and anomaly events in the tenant log. Retention is limited (typically 2 to 30 days depending on plan); stream to a SIEM for long-term retention.

**Critical log event codes to monitor:**

| Code | Meaning | Alert priority |
|---|---|---|
| `fcoa` | Failed cross-origin authentication | High |
| `fp` | Failed password login | Medium |
| `fu` | Failed login (generic) | Medium |
| `limit_mu` | IP blocked (multiple failed logins for one user) | High |
| `limit_wc` | Account blocked (too many failed logins) | High |
| `depnote` | Deprecation notice (feature being removed) | Medium |
| `sapi` | Management API operation | High (admin actions) |
| `s` | Successful login | Low (baseline) |
| `ss` | Successful signup | Low (baseline) |

### Log streaming

Configure log streaming in Auth0 Dashboard: Monitoring -> Streams.

Supported destinations:
- Datadog
- Splunk
- Sumo Logic
- AWS EventBridge
- Azure Event Grid
- Custom webhook (HTTP POST)

Use streaming for all production tenants; tenant log UI is for ad-hoc debugging only.

---

## Management API

The Management API (`https://<domain>/api/v2/`) provides programmatic access to all Auth0 resources.

**Rate limits**: 50 requests/second for most endpoints on the free plan; higher limits on paid plans. Plan bulk operations (user imports, role assignments) with rate limiting in mind. The `x-ratelimit-remaining` response header shows the remaining quota.

**Authentication**: obtain a Management API token via the client credentials flow. Use a dedicated M2M application scoped to the minimum required Management API scopes. Store the client secret via `secrets-hygiene`. Tokens expire; cache them until close to `exp`, then re-acquire. Use `utc-timestamps` to reason about `exp` values.

**Common operations:**

```javascript
// Get all users
GET /api/v2/users?page=0&per_page=50

// Update app_metadata (roles, custom attributes)
PATCH /api/v2/users/{id}
{
  "app_metadata": { "roles": ["admin"] }
}

// Assign roles
POST /api/v2/users/{id}/roles
{ "roles": ["rol_abc123"] }

// Create an Organization
POST /api/v2/organizations
{
  "name": "acme-corp",
  "display_name": "ACME Corporation"
}
```

---

## Actions deployment and testing

### Development workflow

1. Write and test the Action in the Auth0 Dashboard editor (supports console.log debugging).
2. Export via Deploy CLI or commit the Action script to source control.
3. Promote to staging tenant via Deploy CLI or Terraform; run integration tests.
4. Promote to production tenant via the same pipeline; do not edit Actions directly in production.

### Actions testing checklist

- Test with a real login flow (not just the editor "Run" button); confirm claims appear in the issued token.
- Test the deny-access path: confirm the user receives the expected error message.
- Test with `event.secrets` values; confirm secrets are read correctly and not logged.
- Load-test external API calls in the Action; confirm they respond within the timeout.
- Verify the Action does not double-set claims on re-login (idempotency).

### Migrating Rules to Actions

1. Identify all active Rules in the Dashboard: Auth Pipeline -> Rules.
2. For each Rule, create an equivalent Action under the Post Login trigger.
3. Test the Action against a development tenant.
4. Enable the Action and disable the Rule (do not delete until confirmed working).
5. After validation, delete the Rule.

---

## Custom domain setup

1. Dashboard: Branding -> Custom Domains -> Add Domain.
2. Add the provided CNAME record to your DNS provider.
3. Wait for DNS propagation and TLS certificate provisioning (Auth0 manages the certificate automatically).
4. Update all application callback URLs and logout URLs to use the custom domain.
5. Update the Auth0 SDK configuration in all applications to use the custom domain as the `domain` parameter.

Verify the custom domain is active before directing production traffic to it. Auth0 serves `auth0.com` as a fallback; using the fallback in production breaks same-site cookie behaviour.

---

## Common upgrade and migration tasks

### Migrating from Classic to New Universal Login

1. Review Classic Universal Login customisations: identify what must be replicated in New Universal Login.
2. Enable New Universal Login in a development tenant; test all authentication flows.
3. Apply Branding settings (logo, colours) and any Page Template customisations.
4. Test Attack Protection and MFA flows under New Universal Login.
5. Enable in staging; run integration tests with enterprise connections.
6. Enable in production; monitor log events for unexpected failures for 24 to 48 hours.

### User migration from a legacy system

Use a custom database connection for lazy migration:
1. Create a custom database connection with login/create/verify/change-password/delete scripts.
2. Set "Import Users to Auth0" to enabled (users are migrated on first login).
3. Keep the legacy system running in parallel until migration is complete (monitor via tenant logs: user creation events).
4. Once all active users have been migrated, switch the connection to an Auth0-managed database.
5. Decommission the legacy authentication endpoint.
