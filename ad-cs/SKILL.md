---
name: ad-cs
description: "Use for Active Directory Certificate Services implementation, PKI architecture, certificate template design, enrolment methods, revocation, hardening, and ESC vulnerability detection and remediation. Covers PKI hierarchy (offline root CA, enterprise issuing CA, subordinate CA), certificate templates (CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT, EKU, manager approval, authorised signatures, msPKI-Certificate-Name-Flag, msPKI-Enrollment-Flag), enrolment methods (auto-enrolment, web enrolment, CEP/CES, NDES/SCEP), revocation (CRL, delta CRL, OCSP, CDP extension, AIA extension), CA configuration (EDITF_ATTRIBUTESUBJECTALTNAME2, InterfaceFlags, IF_ENFORCEENCRYPTICERTREQUEST), NTAuthCertificates, certificate mapping (strong vs weak, KB5014754, altSecurityIdentities, StrongCertificateBindingEnforcement), and the full ESC attack path family: ESC1 (SAN abuse), ESC2 (Any Purpose EKU), ESC3 (enrolment agent misuse), ESC4 (template ACL write), ESC5 (PKI object ACL write), ESC6 (EDITF_ATTRIBUTESUBJECTALTNAME2), ESC7 (CA ACL ManageCA/ManageCertificates), ESC8 (NTLM relay to HTTP web enrolment, PetitPotam, PrinterBug), ESC9 (CT_FLAG_NO_SECURITY_EXTENSION), ESC10 (weak certificate mapping), ESC11 (NTLM relay to ICPR RPC), ESC12 (YubiHSM key in registry), ESC13 (OID group link msDS-OIDToGroupLink), ESC14 (altSecurityIdentities write), ESC15 (schema v1 Application Policy), ESC16. Detection tooling: Certify, Certipy, PSPKIAudit, Locksmith. Key event IDs: 4886, 4887, 4888, 4890, 4896, 4898, 4899. PowerShell: certutil, Get-OCSPRevocationConfiguration. References: architecture.md, vulnerabilities.md. Triggers include \"AD CS\", \"ADCS\", \"PKI\", \"certificate template\", \"auto-enrolment\", \"auto-enrollment\", \"CRL\", \"OCSP\", \"CDP\", \"AIA\", \"NTAuth\", \"ESC1\", \"ESC2\", \"ESC3\", \"ESC4\", \"ESC5\", \"ESC6\", \"ESC7\", \"ESC8\", \"ESC9\", \"ESC10\", \"ESC11\", \"ESC12\", \"ESC13\", \"ESC14\", \"ESC15\", \"ESC16\", \"Certify\", \"Certipy\", \"Locksmith\", \"PSPKIAudit\", \"certificate authority\", \"enterprise CA\", \"root CA\", \"subordinate CA\", \"PKINIT\", \"smart card\", \"certificate vulnerability\", \"SAN abuse\", \"enrolment agent\", \"web enrolment\", \"NDES\", \"SCEP\", \"altSecurityIdentities\", \"StrongCertificateBindingEnforcement\", \"PetitPotam\". For IAM architecture, federation protocols, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Active Directory Certificate Services

> **Skill marker**: When applying this skill, begin your reply with `[skill: ad-cs]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers enterprise PKI built on AD CS: CA hierarchy design, certificate template security, enrolment methods, revocation, and the ESC1-ESC16 attack path family. AD CS misconfigurations are among the most exploited vulnerabilities in enterprise environments; every deployment question here has a security lens. Architecture concepts (federation, IdP selection) live in `identity-access-management`. AD DS directory services live in `ad-ds`. AD FS federation lives in `ad-fs`.

## When to use

- Designing a PKI hierarchy: offline root CA, enterprise issuing CA, subordinate CA placement, two-tier vs three-tier.
- Designing or auditing certificate templates: subject name settings, EKU, enrolment permissions, manager approval, authorised signatures.
- Configuring enrolment: auto-enrolment via GPO, web enrolment (certsrv), CEP/CES, NDES/SCEP for network devices.
- Configuring certificate revocation: CRL publication schedules, delta CRL, OCSP responder deployment, CDP and AIA extension accessibility.
- Assessing or remediating ESC vulnerabilities: running Certify/Certipy/Locksmith/PSPKIAudit, interpreting results, implementing fixes.
- Hardening AD CS: template ACLs, CA ACLs, EDITF_ATTRIBUTESUBJECTALTNAME2, RPC signing enforcement, web enrolment HTTPS and EPA.
- Troubleshooting enrolment failures, chain building failures, CRL download failures, and OCSP responder issues.
- Certificate mapping enforcement (KB5014754, StrongCertificateBindingEnforcement, altSecurityIdentities).

## When not to use

- **IAM architecture, IdP selection, or MFA strategy**: use `identity-access-management`.
- **AD DS directory services, FSMO roles, replication, Group Policy, Kerberos**: use `ad-ds`. Note that AD DS and AD CS are co-Tier-0 assets; their operational boundary is distinct.
- **AD FS claims-based federation**: use `ad-fs`.
- **Entra ID certificate-based authentication (cloud PKI)**: use `entra-id`.
- **CA private key storage, keytab, and HSM credential custody**: use `secrets-hygiene`.

## Core model

### CA hierarchy

```
Offline Root CA (standalone, air-gapped)
  -> Issuing CA 1 (enterprise, AD-integrated, online)
  -> Issuing CA 2 (enterprise, AD-integrated, online)
```

- **Root CA**: offline, standalone (not domain-joined). Issues only subordinate CA certificates. Physically secured. CRL published manually. Never bring online for day-to-day operations.
- **Issuing CA (subordinate)**: enterprise CA, domain-joined, AD-integrated. Issues end-entity certificates. Online for enrolment.
- **Single-tier PKI** (root CA as issuing CA) is acceptable only for lab/test environments. Never use in production.

### Certificate templates

Templates define properties and permissions for certificates issued by an enterprise CA.

```powershell
# List all published certificate templates
certutil -v -template

# List templates published on a CA
certutil -CATemplates

# Inspect template security
Get-ADObject -LDAPFilter "(objectClass=pKICertificateTemplate)" `
    -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com" `
    -Properties * | Select-Object Name, msPKI-Certificate-Name-Flag, msPKI-Enrollment-Flag, nTSecurityDescriptor
```

**Critical template settings:**

| Setting | Secure configuration | Risk if misconfigured |
|---|---|---|
| Subject Name | Build from AD (not supplied by requestor) | ESC1: attacker specifies any SAN/UPN |
| Enrolment permissions | Restricted to specific groups | Broad enrolment enables exploitation |
| EKU (Extended Key Usage) | Specific EKU (Client Auth, Server Auth) | Any Purpose or no EKU: impersonation risk (ESC2) |
| Manager Approval | Required for sensitive templates | Unapproved enrolment if disabled |
| Authorised Signatures | Required for sensitive templates | Enrolment without CSR co-signing |

### Enrolment methods

| Method | Use case | Security considerations |
|---|---|---|
| Auto-enrolment | Domain-joined computers and users | GPO-driven, most common; ensure template permissions are tight |
| Manual enrolment (MMC) | Administrator-initiated | Direct CA access required |
| Web enrolment (certsrv) | Browser-based enrolment | NTLM relay risk (ESC8) if HTTP; must use HTTPS with EPA |
| CEP/CES | Cross-forest, DMZ, non-domain-joined | Certificate Enrolment Policy/Service endpoints |
| NDES (SCEP) | Network devices (routers, switches, BYOD) | Challenge password management is critical |

### Certificate revocation

| Mechanism | Freshness | Deployment | Considerations |
|---|---|---|---|
| CRL (Certificate Revocation List) | Periodic (hours/days) | CDP extension in certificates | Must be accessible to all relying parties; publish to HTTP and LDAP |
| Delta CRL | More frequent | Supplements base CRL | Reduces CRL download size between base publications |
| OCSP | Real-time | Online Responder role | Preferred for real-time checking; requires Online Responder |

```powershell
# Verify certificate chain and revocation
certutil -verify -urlfetch <certificate.cer>

# Publish CRL manually
certutil -CRL

# Check Online Responder health
Get-OCSPRevocationConfiguration
```

### Key event IDs

| Event ID | Source | Description |
|---|---|---|
| 4886 | Security | Certificate request received |
| 4887 | Security | Certificate request approved and issued |
| 4888 | Security | Certificate request denied |
| 4890 | Security | Certificate manager settings changed |
| 4896 | Security | Certificate template deleted |
| 4898 | Security | Certificate Services loaded a template |
| 4899 | Security | Certificate template updated |

### Hardening checklist

1. Audit all certificate templates: run Certify, Certipy, or PSPKIAudit. Fix all ESC1-ESC16 findings.
2. Restrict enrolment permissions: remove "Authenticated Users" and "Domain Computers" from sensitive templates.
3. Disable "Supply in the request": unless explicitly required and protected by manager approval.
4. Enable manager approval: for templates that allow SANs or have broad enrolment.
5. Require authorised signatures: for sensitive templates (code signing, smart card).
6. Secure web enrolment: HTTPS only; disable HTTP endpoints; enable Extended Protection for Authentication (EPA).
7. Harden CA servers: treat as Tier 0; no internet access; minimal roles installed; Credential Guard enabled.
8. Enable auditing: object access auditing on CA; certificate request auditing.
9. Disable unnecessary templates: unpublish templates not actively used.
10. Enforce EDITF check: verify `EDITF_ATTRIBUTESUBJECTALTNAME2` is not set.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| PKI architecture | CA hierarchy (root, issuing, subordinate), certificate template settings and flags, enrolment methods, revocation (CRL/delta CRL/OCSP), key event IDs, common troubleshooting (auto-enrolment failures, chain build failures, CRL download failures, OCSP failures) | `references/architecture.md` |
| ESC vulnerabilities | ESC1 through ESC16: full attack conditions, exploitation examples (Certify, Certipy), detection via event IDs and audit tooling, step-by-step remediation; proactive scanning commands; event-based and continuous monitoring strategy | `references/vulnerabilities.md` |

## Cross-references

- `identity-access-management`: PKI as an enabling technology for certificate-based authentication (PKINIT, smart cards, passkeys backed by certificates); IAM conceptual layer.
- `ad-ds`: AD CS is co-deployed with AD DS and is a Tier 0 asset alongside DCs. PKINIT, Kerberos certificate trust (Server 2025), and auto-enrolment depend on AD DS integration.
- `ad-fs`: AD FS token-signing and token-decryption certificates are managed by AD CS; WAP SSL certificates require PKI-issued certificates.
- `entra-id`: Cloud Kerberos trust (Server 2022+) and Entra ID certificate-based authentication use cloud PKI; Entra Connect relates to hybrid identity.
- `secrets-hygiene`: CA private keys, HSM authentication credentials (ESC12 covers YubiHSM key exposure), and NDES challenge passwords are credentials; their custody belongs here.
- `utc-timestamps`: certificate validity windows, CRL publication schedules, OCSP responder signing certificate expiry, and auto-enrolment renewal thresholds must be reasoned about in UTC.
- `oncall-runbooks`: CA outage, certificate chain failure, CRL expiry, and ESC8 active exploitation runbooks.

## Red flags

- **EDITF_ATTRIBUTESUBJECTALTNAME2 set on the CA**: this flag allows any certificate request to specify a SAN regardless of template settings. It is the ESC6 condition and is critical severity. Check with `certutil -config "CA\NAME" -getreg policy\EditFlags`.
- **"Authenticated Users" or "Domain Computers" with Enrol permission on sensitive templates**: most ESC1-ESC4 attacks require only a low-privileged domain user to have Enrol rights. Audit enrolment ACLs on every published template.
- **Web enrolment (certsrv) accessible via HTTP**: ESC8 requires only that an attacker coerce machine account NTLM authentication to the HTTP endpoint. Disable HTTP; enforce HTTPS with EPA.
- **Template with CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT and no manager approval**: the ESC1 condition. An attacker can request a certificate with any UPN in the SAN and use it for PKINIT authentication as that user.
- **Weak certificate mapping not yet enforced**: KB5014754 moved DCs through compatibility mode toward full enforcement. Check `StrongCertificateBindingEnforcement` on all DCs; compatibility mode ends with future Windows updates.
- **CA servers not treated as Tier 0**: a compromised CA can issue certificates for any identity in the forest. CA servers must have the same physical and logical security as DCs.
- **ESC audit tooling not run regularly**: template and ACL configurations drift. Run Certify, Certipy, or Locksmith monthly at minimum.

## Bottom line

Deploy a two-tier PKI (offline root CA plus online enterprise issuing CA). Audit all certificate templates immediately with Certify or Certipy and remediate ESC1-ESC16 findings. Disable `EDITF_ATTRIBUTESUBJECTALTNAME2`, enforce HTTPS-only web enrolment with EPA, and require RPC signing (`IF_ENFORCEENCRYPTICERTREQUEST`). Restrict enrolment permissions on every template; enable manager approval for any template that supplies a SAN. Treat CA servers as Tier 0 alongside DCs. Export certificate issuance events (4886/4887/4899) to SIEM and alert on SAN mismatches and template modifications.
