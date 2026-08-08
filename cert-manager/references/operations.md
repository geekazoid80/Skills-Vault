# cert-manager operations: installation, troubleshooting, renewal

Operational reference covering Helm installation, installation verification, troubleshooting the full cert-manager resource chain, and forced certificate renewal.

## Installation

### Helm install (recommended)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --version v1.17.0
```

The `crds.enabled=true` flag installs the CRDs as part of the Helm release. This is the recommended approach so CRDs are managed with the same Helm upgrade lifecycle.

### Verify installation

```bash
# All three controller pods should be Running
kubectl get pods -n cert-manager

# All cert-manager CRDs should appear
kubectl get crds | grep cert-manager
```

Quick smoke test with a self-signed issuer:

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: selfsigned-test
    kind: ClusterIssuer
  dnsNames:
    - example.com
EOF

kubectl describe certificate test-cert -n default
# Expect: Conditions Ready=True within a few seconds

# Cleanup
kubectl delete certificate test-cert -n default
kubectl delete clusterissuer selfsigned-test
kubectl delete secret test-cert-tls -n default
```

## Troubleshooting

### General approach: follow the resource chain

cert-manager decomposes a Certificate into a chain of resources. Start at the top and work down until you find the first resource showing an error or stuck state.

```bash
# Step 1: Certificate
kubectl describe certificate <name> -n <namespace>
# Look for: Ready condition status, Reason, Message, and Events

# Step 2: CertificateRequest
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>

# Step 3 (ACME only): Order
kubectl get order -n <namespace>
kubectl describe order <name> -n <namespace>

# Step 4 (ACME only): Challenge
kubectl get challenge -n <namespace>
kubectl describe challenge <name> -n <namespace>

# cert-manager controller logs (most detailed view of what went wrong)
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

### Certificate not ready: common causes

**HTTP-01 challenge failing**

The Let's Encrypt (or other ACME CA) validation server must be able to reach `http://<domain>/.well-known/acme-challenge/<token>` from the public internet.

Checks:
- Port 80 must be reachable from outside the cluster. Check firewall rules and security groups.
- The Ingress controller must route `/.well-known/acme-challenge/` to cert-manager's solver pod. Verify the Ingress annotation `kubernetes.io/ingress.class` (or `spec.ingressClassName`) matches the `ingress.class` in the ClusterIssuer solver.
- The solver creates a temporary Ingress and Service during challenge. If an existing redirect (HTTP to HTTPS) intercepts the challenge path, the validation will fail. Make sure HTTPS redirects exclude the `/.well-known/acme-challenge/` path.

```bash
# Check challenge details for the URL being validated
kubectl describe challenge <name> -n <namespace>
# Look for: Presented (should be true), Reason, Message
```

**DNS-01 challenge failing**

```bash
# Check if the TXT record is visible externally
dig TXT _acme-challenge.example.com @8.8.8.8

# Check challenge events for the specific error
kubectl describe challenge <name> -n <namespace>
```

Common causes:
- DNS API credentials in the Secret are wrong or have insufficient permissions. Verify the token has DNS zone edit access.
- DNS propagation is slower than cert-manager's default wait time. Some DNS providers take 60-120 s.
- The Secret referenced by `apiTokenSecretRef` does not exist or has the wrong key name.

**Vault issuer failing**

```bash
# Confirm cert-manager can reach Vault
kubectl exec -n cert-manager deploy/cert-manager -- \
    curl -sk https://vault.example.com/v1/sys/health | head -c 200

# Check cert-manager controller logs for Vault auth errors
kubectl logs -n cert-manager -l app=cert-manager --tail=200 | grep -i vault
```

Common causes:
- The Kubernetes auth role in Vault does not include the cert-manager service account name and namespace.
- The `path` in the Vault issuer spec does not match the actual PKI mount path and role.
- Vault's CA certificate is not correctly base64-encoded in the `caBundle` field of the issuer.

**Certificate stuck in Pending, no CertificateRequest created**

If `kubectl get certificaterequest -n <namespace>` returns nothing after a minute, the cert-manager controller pod may not be reconciling. Check:

```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

If the controller is running, check that the Certificate's `issuerRef` references an existing Issuer or ClusterIssuer with the correct `kind`.

**CertificateRequest exists but no Order created (ACME)**

Indicates the ACME server is unreachable or the account key registration failed.

```bash
kubectl describe certificaterequest <name> -n <namespace>
# Look for: Ready=False with a message about ACME server connectivity

kubectl logs -n cert-manager -l app=cert-manager --tail=200 | grep -i acme
```

Check that the `server:` URL in the ClusterIssuer is reachable from the cert-manager pod.

### Troubleshooting table

| Symptom | Likely cause | First check |
|---|---|---|
| Certificate `Ready=False`, no CertificateRequest | Controller not running or issuerRef wrong | `kubectl get pods -n cert-manager`, issuerRef kind/name |
| CertificateRequest `Ready=False` | Issuer auth failure or ACME unreachable | Controller logs, issuer spec |
| Order `pending`, Challenge not completing | HTTP-01 or DNS-01 validation failing | Port 80 / DNS TXT record / credentials |
| Challenge `presented=false` | Solver could not create the challenge resource | Controller logs, RBAC on cert-manager service account |
| Vault issuer `Failed` | Vault auth error or wrong PKI path | `vault write` test, controller logs for Vault errors |
| Certificate renews but pods still get old cert | Secret updated but app not watching for file changes | Application cert reload logic or pod restart |

## Forcing manual renewal

cert-manager renews automatically at `renewBefore`. For exceptional cases:

```bash
# Option 1: use cmctl (cert-manager's CLI tool)
cmctl renew api-tls -n production

# Option 2: delete the managed Secret (cert-manager re-issues immediately)
kubectl delete secret api-tls-secret -n production

# Option 3: annotate the Certificate with any change to trigger reconciliation
kubectl annotate certificate api-tls -n production \
    cert-manager.io/issue-temporary-certificate="true" --overwrite
```

Install cmctl:

```bash
# macOS
brew install cmctl

# Linux
curl -Lo cmctl "https://github.com/cert-manager/cmctl/releases/latest/download/cmctl_linux_amd64"
chmod +x cmctl
sudo mv cmctl /usr/local/bin/
```

`cmctl status certificate <name> -n <namespace>` gives a concise one-shot view of all related resources (Certificate, CertificateRequest, Order, Challenge) without having to `describe` each one individually.
