# PKI and certificate concepts

Deep reference for public-key infrastructure and certificate lifecycle management: certificate strategy, CA hierarchy design, X.509 structure, chain validation, revocation, Certificate Transparency, the ACME protocol, key algorithms, and compliance. For the implementation skills see `cert-manager` (the Kubernetes certificate controller), `lets-encrypt` (the public ACME CA and certbot), and `hashicorp-vault-ops` (Vault's own PKI secret engine). For secrets-management fundamentals (rotation, envelope encryption, HSMs) see `secrets-management-concepts.md`.

## Certificate strategy

### When to use a public CA

Use a publicly-trusted CA (Let's Encrypt, DigiCert, and so on) for any certificate that must be trusted by browsers, mobile devices, or external clients: customer-facing APIs and web applications, and external integrations where you cannot control the trust store.

### When to use a private or internal CA

Use a private CA (Vault PKI, EJBCA, smallstep, internal AD CS) for internal service-to-service TLS, mTLS client certificates, developer and staging environments, short-lived certificates for CI/CD, and SSH host and user certificates.

### Short-lived vs long-lived certificates

| Dimension | Long-lived (1 year) | Short-lived (24h or less) |
|---|---|---|
| Revocation needed? | Yes (CRL/OCSP required) | No (expiry is revocation) |
| Automation required? | Recommended | Mandatory |
| Risk on key compromise | High (valid until expiry) | Low (expires soon anyway) |
| Operational complexity | Lower (less frequent renewal) | Higher (constant renewal) |
| Industry direction | Declining | Growing |

The industry is moving toward short-lived certificates. Let's Encrypt launched 6-day certificates in March 2025 as an opt-in, with 45-day certificates as an opt-in from May 2026. Short-lived certificates eliminate the need for revocation: by the time a compromise is detected, the certificate has likely already expired.

## CA hierarchy design

### Public-facing services

```
External Root CA (DigiCert, Let's Encrypt, etc.)
  Their Intermediate CA (managed by the CA)
    Your TLS certificates (90 days, automated)
```

Use ACME for automation. No intermediate-CA management is needed.

### Internal services

```
Offline Root CA (self-generated, air-gapped)
  Online Intermediate CA (Vault PKI, EJBCA, step-ca)
    TLS server certificates (24-72h for mTLS, 30-90d for internal TLS)
    mTLS client certificates (short-lived)
    SSH host/user certificates (short-lived)
```

Keep the root CA offline. If the online intermediate is compromised, revoke the intermediate cert from the root (offline) and re-issue a new intermediate.

### Enterprise / regulated

```
Internal Root CA (HSM-backed, air-gapped)
  Issuing CA for Infrastructure (Vault PKI / EJBCA / AD CS)
    Server TLS, mTLS client certs
  Issuing CA for Code Signing (air-gapped)
    Code signing certificates
  Issuing CA for Email (S/MIME)
    User email certificates
```

## X.509 certificate structure

An X.509 v3 certificate (RFC 5280) is a DER-encoded ASN.1 structure:

```
Certificate ::= SEQUENCE {
  tbsCertificate      TBSCertificate,    -- "to be signed"
  signatureAlgorithm  AlgorithmIdentifier,
  signatureValue      BIT STRING
}

TBSCertificate ::= SEQUENCE {
  version          [0] INTEGER { v3(2) },
  serialNumber     CertificateSerialNumber,
  signature        AlgorithmIdentifier,   -- must match outer signatureAlgorithm
  issuer           Name,
  validity         Validity { notBefore, notAfter },
  subject          Name,
  subjectPublicKeyInfo SubjectPublicKeyInfo,
  extensions       [3] SEQUENCE OF Extension
}
```

### Critical extensions

- **Subject Alternative Name (SAN), OID 2.5.29.17:** the authoritative field for hostnames and IPs. The `commonName` (CN) is deprecated for hostname matching (RFC 2818, enforced by browsers since around 2017). Values: `DNS:example.com`, `DNS:*.example.com` (wildcard, one level only), `IP:192.168.1.1`, `email:user@example.com`.
- **Basic Constraints, OID 2.5.29.19 (critical for CAs):** `CA:TRUE` with optional `pathLenConstraint` for CA certs (`pathLen:0` signs leaf certs only, `pathLen:1` signs one level of sub-CA); `CA:FALSE` for end-entity certs.
- **Key Usage, OID 2.5.29.15 (critical):** `digitalSignature` (TLS handshake, ECDH agreement in TLS 1.3), `keyEncipherment` (RSA key exchange in TLS 1.2), `keyCertSign` (sign certificates, CA only), `cRLSign` (sign CRLs, CA only), plus `nonRepudiation`, `dataEncipherment`, `keyAgreement`. For a TLS server: `digitalSignature` plus `keyEncipherment` (RSA) or `digitalSignature` (ECDSA).
- **Extended Key Usage (EKU), OID 2.5.29.37:** `serverAuth` (1.3.6.1.5.5.7.3.1), `clientAuth` (1.3.6.1.5.5.7.3.2, mTLS), `codeSigning` (1.3.6.1.5.5.7.3.3), `emailProtection` (1.3.6.1.5.5.7.3.4, S/MIME), `timeStamping` (1.3.6.1.5.5.7.3.8).
- **Authority Key Identifier (AKI), OID 2.5.29.35:** identifies the CA key that signed this certificate, used for chain building.
- **Subject Key Identifier (SKI), OID 2.5.29.14:** a hash of the subject's public key, referenced in the AKI of certificates this cert signs.
- **CRL Distribution Points, OID 2.5.29.31:** HTTP URLs for the CRL.
- **Authority Information Access (AIA), OID 1.3.6.1.5.5.7.1.1:** `OCSP` (responder URL) and `caIssuers` (issuing-CA cert URL).
- **Certificate Policies, OID 2.5.29.32:** policy OIDs for validation level (`2.23.140.1.2.1` DV, `2.23.140.1.2.2` OV, `2.23.140.1.2.3` EV).
- **Must-Staple, OID 1.3.6.1.5.5.7.1.24:** signals the server must provide a stapled OCSP response; clients reject the cert if no staple is present.

### Certificate encoding formats

| Format | Extension | Description |
|---|---|---|
| PEM | `.pem`, `.crt`, `.cer`, `.key` | Base64 DER with `-----BEGIN...-----` header |
| DER | `.der`, `.cer` | Binary encoding, used in Java and Windows APIs |
| PKCS#12 | `.p12`, `.pfx` | Container for cert plus private key, password-protected |
| PKCS#7 | `.p7b`, `.p7c` | Certificate chain without the private key |
| JKS | `.jks` | Java KeyStore, Java-specific |

## Certificate chain validation

A client validating a TLS certificate:
1. Builds a chain from the leaf certificate to a trusted root.
2. Verifies each signature in the chain.
3. Checks the validity period (notBefore, notAfter) for each cert.
4. Checks revocation for each cert (CRL or OCSP, unless OCSP stapling).
5. Verifies the hostname matches a Subject Alternative Name.
6. Checks the EKU includes `serverAuth`.
7. Checks Basic Constraints: intermediate certs must have `CA:TRUE`.
8. Verifies path-length constraints are not exceeded.

Chain building uses the AKI extension to find the issuing CA certificate; the issuer's SKI should match the subject's AKI. Common issues: a missing intermediate (the server must serve the full chain of leaf plus intermediates, not the root), wrong order (leaf then intermediate then optional root), cross-signed intermediates (some CAs cross-sign for backward compatibility), and an expired intermediate (which affects every leaf it issued).

Trust stores: operating systems and browsers ship a set of trusted root CA certificates. Linux uses `/etc/ssl/certs/` and `/etc/pki/tls/certs/`; macOS uses the System Keychain; Windows uses the Cert Store; Java uses `$JAVA_HOME/lib/security/cacerts`; Firefox bundles its own NSS store; Chrome and Safari use the OS trust store.

## Certificate revocation

### CRL (Certificate Revocation List, RFC 5280)

A signed, time-stamped list of revoked serial numbers published by the CA. Problems: CRLs can be large (megabytes for large CAs), are published periodically (typically 24h or 7 days) rather than in real time, and clients often fail open if the CRL URL is unreachable. Delta CRLs reduce download size but add complexity.

### OCSP (Online Certificate Status Protocol, RFC 6960)

An HTTP protocol for real-time status: the client sends the issuer name hash, issuer key hash, and serial number, and the responder returns `good`, `revoked`, or `unknown` plus a signature. Problems: privacy (the CA learns which certificates you validate), availability (dependence on responder uptime), performance (an extra round-trip per handshake), and soft-fail behaviour (most clients fail open if OCSP is unreachable).

### OCSP stapling (RFC 6066 / RFC 6961)

The TLS server pre-fetches its own OCSP response and includes it in the handshake as a Certificate Status extension. This removes the client privacy concern and the extra round-trip, and makes responder availability less critical. The staple has a validity period (typically 24h to 7d) so the server must refresh it; the `must-staple` extension prevents staple stripping.

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/ssl/chain.pem;
resolver 8.8.8.8 8.8.4.4 valid=300s;
```

### Revocation reason codes (X.509)

| Code | Reason |
|---|---|
| 0 | unspecified |
| 1 | keyCompromise |
| 2 | cACompromise |
| 3 | affiliationChanged |
| 4 | superseded |
| 5 | cessationOfOperation |
| 6 | certificateHold |
| 9 | privilegeWithdrawn |
| 10 | aACompromise |

### CAA (Certification Authority Authorization) DNS record

A DNS record specifying which CAs may issue certificates for a domain:
```
example.com. CAA 0 issue "letsencrypt.org"
example.com. CAA 0 issuewild ";"        ; prohibit wildcard
example.com. CAA 0 iodef "mailto:security@example.com"
```
CAs must check CAA before issuance (required by the CA/Browser Forum). It does not prevent issuance by rogue CAs but creates accountability.

## Certificate Transparency (CT, RFC 6962)

A system of append-only, publicly auditable logs recording every certificate issued by publicly-trusted CAs. Browsers require CT proof before trusting certificates.

How it works: the CA submits the certificate (a pre-certificate or final) to CT logs; the log returns a Signed Certificate Timestamp (SCT); the CA embeds the SCT in the certificate, serves it via a TLS extension, or delivers it via OCSP; the browser verifies the SCT signature from a trusted log. Anyone can monitor CT logs for unauthorised issuance for their domain.

Monitor your domain at `https://crt.sh/?q=example.com` or `https://censys.io/`, and alert on new certificates not in your inventory, certificates with unexpected SANs, and certificates from unexpected CAs (correlate with your CAA records).

## ACME protocol (RFC 8555)

ACME (Automatic Certificate Management Environment) automates the entire certificate lifecycle: domain validation, issuance, renewal, and revocation. It is used by Let's Encrypt and most modern CAs, and is the basis for `lets-encrypt` and the ACME issuers in `cert-manager`.

### Protocol objects

- **Account:** a registered ACME client identified by a key pair (RSA or ECDSA); the account key signs all requests.
- **Order:** a request for a certificate for a set of identifiers (DNS names or IP addresses).
- **Authorization:** proof that the client controls a specific identifier (one per DNS name per order).
- **Challenge:** a method of proving domain control (one per authorization).
- **CSR:** the certificate signing request submitted after authorizations complete, carrying the new certificate's public key.

All ACME requests are JSON Web Signature (JWS) objects whose header carries `alg`, an anti-replay `nonce`, the `url` being requested, and `jwk` (first request) or `kid` (subsequent requests).

### Flow

```
1. Account registration: POST /acme/new-account -> account URL + key
2. Order creation:       POST /acme/new-order { identifiers } -> order, authorization URLs, finalize URL
3. Authorization:        complete a challenge (HTTP-01, DNS-01, or TLS-ALPN-01)
4. Finalization:         generate key + CSR, POST the finalize URL
5. Download:             GET the certificate URL -> PEM chain
6. Renewal:              repeat from step 2 before expiry (typically at 2/3 of lifetime)
```

### Challenge types

- **HTTP-01:** provision a file at `http://example.com/.well-known/acme-challenge/{token}` with content `token.BASE64URL(SHA256(accountKey_JWK))`. Needs port 80 accessible and no redirect to HTTPS before verification. Cannot be used for wildcards.
- **DNS-01:** create a `_acme-challenge.example.com` TXT record with value `BASE64URL(SHA256(KEY_AUTHORIZATION))`. Required for wildcard certificates; works when HTTP is not reachable; needs DNS API access for automation and tolerance of propagation delay.
- **TLS-ALPN-01:** serve a special TLS certificate on port 443 negotiated via the `acme-tls/1` ALPN protocol, carrying the `acmeValidation-v1` extension (OID 1.3.6.1.5.5.7.1.31). An alternative to HTTP-01 when only port 443 is reachable.

### Rate limits (Let's Encrypt production)

| Limit | Value |
|---|---|
| Certificates per registered domain | 50 / week (sliding 7-day window) |
| Duplicate certificates (same SAN set) | 5 / week |
| Failed validations | 5 / hour / account / hostname |
| New orders | 300 / 3 hours / account |
| Pending authorizations | 300 / account |
| New accounts per IP | 10 / 3 hours |
| Accounts per IP range (/48) | 500 / 3 hours |

The staging environment (`acme-staging-v02.api.letsencrypt.org`) has roughly 10x higher limits and uses an untrusted root for testing. ACME clients include certbot (the reference implementation), acme.sh, cert-manager, Caddy, Traefik, and the step CLI.

## Key algorithms

- **RSA:** sizes 2048 (minimum), 3072 (recommended for new certs), 4096 (high security or long-lived 5+ year certs). Signature schemes PKCS#1 v1.5 and PSS. Universal compatibility but large keys and slower than ECC. All signatures must use SHA-2 (SHA-256 minimum); SHA-1 is forbidden.
- **ECDSA:** curves P-256 (widest compatibility), P-384 (higher security), P-521. Smaller keys, faster operations; P-256 is roughly RSA-3072 security and is the default for most TLS certificates.
- **Ed25519:** for SSH certificates, code signing, and JWT signing; faster than ECDSA P-256 and immune to timing attacks, but not yet broadly supported for X.509 TLS server certificates.
- **DSA:** deprecated; do not use (removed from TLS 1.3).

## Certificate automation and discovery

For Kubernetes, `cert-manager` is the standard controller; it supports ACME (Let's Encrypt, ZeroSSL), Vault PKI, Venafi, AWS Private CA, self-signed, and custom CA issuers. For large enterprises, certificate-lifecycle-management tools (Venafi, DigiCert TLM) add discovery, policy enforcement, workflow approvals, multi-CA support, and compliance reporting.

Before automating, discover the existing estate: CT-log scanning (`crt.sh`, Censys), network scanning (Nmap/Masscan TLS negotiation, Qualys SSL Labs), AD CS enrollment records, and continuous-discovery agents. Organisations typically have 2-5x more certificates than they track, and undiscovered expiring certs cause outages.

## PKI design patterns

- **Internal PKI for zero trust:** use the Vault PKI engine or smallstep, issue short-lived certificates (hours to days), and skip revocation infrastructure when the TTL is short. SPIFFE/SPIRE provides workload identity using X.509 SVIDs.
- **Certificate pinning (avoid):** pinning hard-codes the expected certificate or public key and breaks on legitimate rotation. It is an anti-pattern for general applications; acceptable only for mobile apps where you control both ends, or high-security internal tooling with controlled deployment.
- **Wildcard vs SAN:** a wildcard (`*.example.com`) covers one level of subdomains, cannot cover the root or deeper subdomains, and shares one private key across all subdomains (compromise of one service exposes all). Multi-SAN certificates list each hostname explicitly for better isolation and are preferred for production; cert-manager makes them trivial in Kubernetes.

## Compliance requirements

- **PCI-DSS:** minimum TLS 1.2 for cardholder data, 2048-bit RSA or 256-bit EC minimum, certificate-expiry monitoring required, no expired or self-signed certs for external services.
- **FIPS 140-3:** RSA 2048/3072/4096 with SHA-2, ECDSA P-256/P-384/P-521; no MD5, SHA-1, or RSA-1024.
- **CA/Browser Forum (public CAs):** a maximum of 398 days for publicly-trusted TLS certificates (enforced since 2020), SAN required, CAA checked at issuance, CT log submission required, OCSP stapling recommended, with the industry moving toward a 90-day maximum.
- **US Federal / FedRAMP:** FIPS 140-3 Level 1+ for software and Level 3 for HSM, CAC/PIV compliance for user certs, a Certificate Policy and Certification Practice Statement, and Federal PKI bridge cross-certification for some use cases.
