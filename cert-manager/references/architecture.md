# cert-manager architecture: issuer types, Certificate resources, trust-manager, CSI driver

Deep reference covering all issuer types with full YAML, the Certificate resource spec and status model, Ingress auto-cert annotation, trust-manager CA bundle distribution, and the CSI driver for ephemeral certificate volumes.

## Issuer types

### ACME (Let's Encrypt, ZeroSSL, etc.)

ACME issuers obtain certificates by completing challenges that prove domain ownership. Use a staging ClusterIssuer during development to avoid Let's Encrypt production rate limits.

```yaml
# ClusterIssuer: Let's Encrypt production
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    # ACME account private key stored in this Secret
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    # HTTP-01: for non-wildcard domains with port 80 reachable
    - http01:
        ingress:
          class: nginx          # or: ingressClassName: nginx
    # DNS-01: for wildcard domains or when port 80 is blocked
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token-secret
            key: api-token
      selector:
        dnsZones:
          - "example.com"

---
# ClusterIssuer: Let's Encrypt staging (use this for testing)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

### DNS-01 solver providers

cert-manager has built-in DNS-01 solver support for the major cloud DNS providers. The solver credentials are stored in Kubernetes Secrets.

```yaml
# AWS Route 53
# Uses pod's IAM role (IRSA) if no credentials specified
solvers:
- dns01:
    route53:
      region: us-east-1
      hostedZoneID: Z123456789

---
# Azure DNS with managed identity
solvers:
- dns01:
    azureDNS:
      subscriptionID: <subscription-id>
      resourceGroupName: my-dns-rg
      hostedZoneName: example.com
      managedIdentity:
        clientID: <user-assigned-identity-client-id>

---
# Google Cloud DNS
solvers:
- dns01:
    cloudDNS:
      project: my-gcp-project
      serviceAccountSecretRef:
        name: clouddns-dns01-solver-svc-acct
        key: key.json

---
# Cloudflare
solvers:
- dns01:
    cloudflare:
      email: admin@example.com
      apiTokenSecretRef:
        name: cloudflare-api-token-secret
        key: api-token
```

Verify DNS propagation after a DNS-01 challenge completes or fails:

```bash
dig TXT _acme-challenge.example.com @8.8.8.8
```

If propagation is slow, the cert-manager ACME solver will keep retrying. Increase the propagation wait via the provider-specific field (e.g. `route53.region` has no wait knob; Cloudflare has no propagation-seconds field in the issuer spec itself, but external DNS resolvers can take up to 120 s on some zones).

### Vault PKI issuer

Uses HashiCorp Vault's PKI secret engine as the signing CA. cert-manager authenticates to Vault via a Kubernetes service account token.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: https://vault.example.com
    path: pki_int/sign/my-service    # Vault role path
    caBundle: <base64-encoded-vault-ca>
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes
        secretRef:
          name: cert-manager-vault-token
          key: token
```

Required Vault setup:

```bash
# Bind the cert-manager service account to a Vault role
vault write auth/kubernetes/role/cert-manager \
    bound_service_account_names=cert-manager \
    bound_service_account_namespaces=cert-manager \
    policies=pki-policy \
    ttl=20m

# Policy granting cert-manager the ability to sign certificates
vault policy write pki-policy - <<EOF
path "pki_int/sign/*" {
  capabilities = ["create", "update"]
}

path "pki_int/issue/*" {
  capabilities = ["create"]
}
EOF
```

For Vault PKI engine configuration, CA hierarchy, and operational procedures, see `hashicorp-vault-ops`.

### CA issuer (internal CA)

Uses a CA certificate and private key stored in a Kubernetes Secret as the signing authority.

```bash
# Create the Secret from local CA files
kubectl create secret tls internal-ca-secret \
    --cert=ca.crt \
    --key=ca.key \
    -n cert-manager
```

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca-issuer
spec:
  ca:
    secretName: internal-ca-secret
```

### Self-signed issuer

Useful for bootstrapping: sign a CA certificate with the self-signed issuer, then use that CA as a CA issuer.

```yaml
# Step 1: self-signed issuer (no config needed)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}

---
# Step 2: bootstrap a CA certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: internal-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: "Internal CA"
  secretName: internal-ca-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer

---
# Step 3: CA issuer backed by the bootstrapped CA
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: internal-ca-issuer
spec:
  ca:
    secretName: internal-ca-tls
```

### Venafi issuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: venafi-tpp-issuer
spec:
  venafi:
    zone: "\\VED\\Policy\\Kubernetes-TLS"
    tpp:
      url: https://tpp.example.com/vedsdk
      credentialsRef:
        name: venafi-tpp-credentials
      caBundle: <base64-ca>
```

## Certificate resource

The Certificate resource declares the desired state: what names, which issuer, what duration, what key type. cert-manager reconciles this into a Kubernetes Secret containing `tls.crt`, `tls.key`, and `ca.crt`.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-tls
  namespace: production
spec:
  # Secret where cert/key will be stored
  secretName: api-tls-secret

  # Subject
  commonName: api.example.com
  dnsNames:
    - api.example.com
    - api-v2.example.com
  ipAddresses:
    - 10.0.0.1

  # Validity period
  duration: 2160h      # 90 days
  renewBefore: 360h    # Renew 15 days before expiry

  # Private key configuration
  privateKey:
    algorithm: ECDSA    # or RSA
    size: 256           # P-256 for ECDSA; 2048 or 4096 for RSA
    rotationPolicy: Always  # Rotate key on every renewal (recommended over Never)

  # X.509 key usage
  usages:
    - server auth
    - client auth   # Include for mTLS client certificates too

  # Which issuer to use
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer   # or Issuer (namespace-scoped)
    group: cert-manager.io

  # Labels and annotations to add to the generated Secret
  secretTemplate:
    annotations:
      my-annotation: "value"
    labels:
      app: api
```

### Certificate status and conditions

```bash
# Check Certificate status
kubectl describe certificate api-tls -n production
# Look for: Conditions (Ready=True), Events

# Inspect the chain of CRDs cert-manager created
kubectl get certificaterequest -n production
kubectl get order -n production        # ACME only
kubectl get challenge -n production    # ACME only, present during issuance

# Read the issued certificate
kubectl get secret api-tls-secret -n production \
    -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

Condition types on the Certificate resource:

| Condition | Meaning |
|---|---|
| `Ready=True` | Certificate is issued and not yet due for renewal |
| `Ready=False` reason `Pending` | Issuance in progress |
| `Ready=False` reason `Failed` | Issuance failed; see Events and CertificateRequest for details |
| `Issuing=True` | Active renewal or first issuance in progress |

## Ingress auto-cert annotation

Annotate an Ingress resource so cert-manager manages its TLS certificate automatically. cert-manager reads the `tls` stanza and creates a Certificate resource for each `secretName` entry.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
  namespace: production
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # For a namespace-scoped Issuer instead:
    # cert-manager.io/issuer: "my-issuer"
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls-secret   # cert-manager creates and manages this Secret
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

## trust-manager

trust-manager is a separate cert-manager sub-project. It distributes CA trust bundles (CA certificates only, no private keys) across namespaces as ConfigMaps or Secrets. Applications mount the trust bundle to verify internal certificate chains without having to ship CA certs into each image.

```bash
# Install trust-manager into the cert-manager namespace
helm install trust-manager jetstack/trust-manager \
    --namespace cert-manager \
    --set app.trust.namespace=cert-manager
```

The Bundle resource defines what sources contribute to the bundle and which namespaces receive it:

```yaml
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: internal-ca-bundle
spec:
  sources:
  # From a ConfigMap in the trust namespace
  - configMap:
      name: internal-ca-cert
      key: ca.crt
  # From a Secret (public cert portion only, not the private key)
  - secret:
      name: internal-ca-tls
      key: tls.crt
  # Include the Mozilla public CA bundle from cert-manager's default bundle
  - useDefaultCAs: true

  target:
    # Write to a ConfigMap key in every matching namespace
    configMap:
      key: ca-bundle.crt
    namespaceSelector:
      matchLabels:
        bundle.cert-manager.io/inject: "true"
```

Mount the trust bundle in application pods:

```yaml
volumes:
- name: ca-bundle
  configMap:
    name: internal-ca-bundle
    items:
    - key: ca-bundle.crt
      path: ca-bundle.crt

containers:
- name: app
  volumeMounts:
  - name: ca-bundle
    mountPath: /etc/ssl/custom-certs
    readOnly: true
  env:
  - name: SSL_CERT_FILE
    value: /etc/ssl/custom-certs/ca-bundle.crt
```

Label each namespace that should receive the bundle:

```bash
kubectl label namespace my-app bundle.cert-manager.io/inject=true
```

## cert-manager CSI driver

The CSI driver mounts certificates directly as volumes in pods, bypassing Kubernetes Secrets entirely. Certificates are not stored in etcd. This makes it suitable for high-churn, short-lived certificates and for workloads where etcd exposure of private keys is unacceptable.

```bash
helm install cert-manager-csi-driver jetstack/cert-manager-csi-driver \
    --namespace cert-manager
```

Pod spec with CSI volume:

```yaml
spec:
  volumes:
  - name: tls
    csi:
      driver: csi.cert-manager.io
      readOnly: true
      volumeAttributes:
        csi.cert-manager.io/issuer-name: internal-ca-issuer
        csi.cert-manager.io/issuer-kind: ClusterIssuer
        csi.cert-manager.io/dns-names: "${POD_NAME}.${POD_NAMESPACE}.svc.cluster.local"
        csi.cert-manager.io/duration: 1h
        csi.cert-manager.io/is-ca: "false"

  containers:
  - name: app
    volumeMounts:
    - name: tls
      mountPath: /tls
      readOnly: true
    # Files available at mount path: tls.crt, tls.key, ca.crt
```

CSI driver characteristics:
- Certificate lifecycle is tied to the pod. When the pod is deleted, the certificate is also deleted.
- cert-manager renews the certificate before expiry while the pod is running.
- The application must be able to reload the certificate from the filesystem without a full restart (or tolerate pod recycling on renewal if it cannot).
- No `Certificate` resource is created; the CSI volume attributes replace it.
