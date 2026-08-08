# Keycloak operations

## Quarkus-based deployment

### Version history

| Version range | Runtime | Notes |
|---|---|---|
| Pre-17.0 | WildFly | End-of-life; no longer supported; migrate immediately |
| 17.0+ | Quarkus (current) | Production-ready; all new features |
| 22.0+ | Quarkus + React admin console | New admin console (React-based, replacing Angular) |
| 25.0+ | Quarkus | Organizations in preview |
| 26.0+ | Quarkus | Organizations GA; performance improvements |

### Production startup

```bash
# Build an optimised image (pre-compiles configuration for faster startup)
bin/kc.sh build \
  --db=postgres \
  --features=organizations

# Start Keycloak in production mode
bin/kc.sh start \
  --hostname=auth.company.com \
  --https-certificate-file=/etc/tls/cert.pem \
  --https-certificate-key-file=/etc/tls/key.pem \
  --db=postgres \
  --db-url=jdbc:postgresql://db:5432/keycloak \
  --db-username=keycloak \
  --db-password=secret
```

Store `--db-password` and TLS private keys via `secrets-hygiene`; inject at runtime via environment variables or a secrets manager, not hardcoded in the startup command.

### Kubernetes / container deployment

```bash
docker run \
  -e KC_HOSTNAME=auth.company.com \
  -e KC_DB=postgres \
  -e KC_DB_URL=jdbc:postgresql://db:5432/keycloak \
  -e KC_DB_USERNAME=keycloak \
  -e KC_DB_PASSWORD=secret \
  quay.io/keycloak/keycloak:latest start
```

Use a Kubernetes Secret for `KC_DB_PASSWORD`; mount as an environment variable from the Secret. Do not pass database passwords as plain environment variables in production manifests.

### Production checklist

- External database: PostgreSQL (recommended); MySQL or MariaDB (supported). H2 is for development only.
- TLS termination: at the Keycloak layer (`--https-certificate-file`) or at a reverse proxy (nginx, Envoy, AWS ALB).
- Hostname configuration: `--hostname=auth.company.com` must match the external URL used by clients.
- `kc.sh build` run: pre-compiles configuration; required before production starts or after any `--features` or `--db` change.
- Metrics endpoint: `--metrics-enabled=true` exposes Prometheus-format metrics at `/metrics`.
- Health endpoint: `--health-enabled=true` exposes health checks at `/health`, `/health/live`, `/health/ready`.

---

## High availability and clustering

### Session replication

Keycloak uses Infinispan (embedded) for distributed session caching. In a cluster, user sessions are replicated across all nodes, so any node can serve an authenticated request.

**Sticky sessions are recommended** (route a user's requests to the same node during a session) but not required when session replication is enabled. Sticky sessions reduce inter-node cache traffic.

### JGroups cluster discovery

JGroups handles cluster-member discovery and group communication. Choose the discovery protocol for the environment:

| Protocol | Use case | Configuration |
|---|---|---|
| DNS_PING | Kubernetes/OpenShift (pods with predictable DNS names) | Set `jgroups.dns.query` to the headless service DNS name |
| JDBC_PING | Any environment with a shared database | Uses the database to coordinate member registration |
| UDP multicast | Local development or bare-metal | Requires multicast network; not suitable for cloud VMs |

**DNS_PING example (Kubernetes):**

```bash
bin/kc.sh start \
  --hostname=auth.company.com \
  --cache=ispn \
  --cache-stack=kubernetes
```

Keycloak's Kubernetes cache stack pre-configures DNS_PING using the `KUBERNETES_NAMESPACE` environment variable and the headless service DNS.

### Cross-DC deployment

For active-passive or active-active multi-data-centre deployments, use external Infinispan (not embedded):

1. Deploy an external Infinispan cluster accessible from both DCs.
2. Configure Keycloak to use the external Infinispan for sessions and caches (`--cache=ispn --cache-remote-host=infinispan.dc1`).
3. Infinispan handles cross-DC replication; Keycloak nodes in each DC connect to their local Infinispan cluster, which replicates to the remote DC.

Active-active: both DCs serve traffic; sessions are shared. Active-passive: only one DC serves traffic; the other is on standby with a replicated session cache.

---

## Metrics and monitoring

### Metrics endpoint

When `--metrics-enabled=true`, Keycloak exposes Prometheus-format metrics at `/metrics`.

Key metrics to monitor:

| Metric | Meaning |
|---|---|
| `keycloak_login_total` | Total login attempts (successful and failed) |
| `keycloak_login_errors_total` | Login failures by error type |
| `keycloak_failed_login_attempts_total` | Brute-force-tracked failed attempts |
| `keycloak_request_duration_*` | Request latency (histogram) |
| `jvm_memory_used_bytes` | JVM heap usage (monitor for memory pressure) |
| `vendor_jgroups_sent_messages_total` | Cluster communication volume |

Create Prometheus alert rules for: login error rate spike, JVM heap > 80%, health endpoint returning non-200.

### Health checks

```bash
# Liveness: Keycloak process is alive
GET /health/live

# Readiness: Keycloak is ready to serve requests (DB connected, caches initialised)
GET /health/ready
```

Use `/health/ready` for Kubernetes readinessProbe; use `/health/live` for livenessProbe.

---

## Upgrade path

### WildFly to Quarkus migration

1. Export the WildFly realm configuration via the Admin Console (Realm settings -> Export).
2. Set up a fresh Keycloak Quarkus instance with an external database.
3. Import the exported realm configuration.
4. Validate: all clients, flows, identity providers, and user federation configurations present.
5. Migrate users: use the Admin API to export users from WildFly (`GET /auth/admin/realms/{realm}/users`) and import to Quarkus (`POST /admin/realms/{realm}/users`).
6. Test all authentication flows end-to-end in the new instance.
7. Update DNS / load-balancer to point to the new instance.
8. Decommission WildFly.

### Version upgrade (Quarkus to Quarkus)

1. Review the Keycloak migration guide for the target version. Theme breakage and SPI API changes are the most common issues.
2. Upgrade in a staging environment first; test all custom themes and custom SPI providers.
3. Run `kc.sh build` on the new version.
4. Back up the database before upgrading production.
5. The new Keycloak version runs automatic database migration on first startup; monitor startup logs for migration errors.
6. After upgrade, test all authentication flows and custom themes.

**Version-specific notes:**
- 17.0: switch from WildFly to Quarkus; `standalone.xml` is replaced by `kc.sh` configuration.
- 22.0: new React-based admin console; custom admin console themes may need updates.
- 25.0: Organizations in preview; not suitable for production until 26.0.
- 26.0: Organizations GA; cross-DC improvements; cache configuration changes.

---

## Common operational tasks

### Reset an admin password (emergency)

If admin credentials are lost:

```bash
# Directly via kc.sh (while Keycloak is stopped)
bin/kc.sh start --override-run-config=... # Not available
# Use the Keycloak admin bootstrap: set KC_BOOTSTRAP_ADMIN_USERNAME and KC_BOOTSTRAP_ADMIN_PASSWORD
# on first start, or use the Keycloak Operator for Kubernetes deployments.
```

For Kubernetes, delete the admin secret and redeploy with new credentials via the Keycloak Helm chart or Operator.

### Rotate a client secret

1. Admin Console: Clients -> [client name] -> Credentials -> Regenerate Secret.
2. Or via API: `POST /admin/realms/{realm}/clients/{client-id}/client-secret`.
3. Update the application's configuration with the new secret (store via `secrets-hygiene`).
4. Verify the application can authenticate with the new secret before removing the old one.

Client secret rotation may cause a brief authentication failure window; coordinate with application teams and consider maintenance-window scheduling.

### Diagnose token claim issues

1. Obtain a token via the authentication flow (Authorization Code or client credentials).
2. Decode the JWT (base64-decode the payload) and inspect the claims.
3. If an expected claim is missing: check the protocol mapper is configured on the correct client scope, the client scope is assigned to the client as a default scope, and the mapper's token type (ID token, access token) matches where you expect the claim.
4. Use `GET /realms/{realm}/.well-known/openid-configuration` to confirm the JWKS URI and issuer.
5. Use `POST /realms/{realm}/protocol/openid-connect/token/introspect` to inspect an opaque token or validate a JWT against Keycloak.
