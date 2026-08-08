# AD CS architecture and operations

## CA hierarchy

### Recommended hierarchy

```
Offline Root CA (standalone, air-gapped)
  -> Issuing CA 1 (enterprise, AD-integrated, online)
  -> Issuing CA 2 (enterprise, AD-integrated, online)
```

**Root CA**: offline, standalone (not domain-joined). Issues only subordinate CA certificates. Physically secured. CRL published manually. Bring online only to issue or renew subordinate CA certificates or to publish a CRL.

**Issuing CA (subordinate enterprise CA)**: domain-joined, AD-integrated. Issues end-entity certificates. Online for enrolment. Publishes to Active Directory and HTTP CRL distribution points.

**Single-tier PKI** (root CA also acting as issuing CA) is acceptable only in lab or test environments. Do not use single-tier PKI in production: compromise of the issuing CA also compromises the root of trust.

### CA types

| CA type | Domain-joined | AD-integrated | Typical role |
|---|---|---|---|
| Enterprise CA | Yes | Yes | Issuing CA; supports auto-enrolment and certificate templates |
| Standalone CA | No | No | Root CA (air-gapped) or cross-organisation issuance |

---

## Certificate templates

Templates define the properties and permissions for certificates issued by an enterprise CA. All published templates are stored in AD under `CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration`.

### Listing and inspecting templates

```powershell
# List all certificate templates
certutil -v -template

# List templates published on a specific CA
certutil -CATemplates

# Inspect template objects and security in AD
Get-ADObject -LDAPFilter "(objectClass=pKICertificateTemplate)" `
    -SearchBase "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=example,DC=com" `
    -Properties * | Select-Object Name, msPKI-Certificate-Name-Flag, msPKI-Enrollment-Flag, nTSecurityDescriptor
```

### Critical template flags

**msPKI-Certificate-Name-Flag:**

- `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT` (0x00000001): enrollee can supply Subject and SAN in the request. Required for ESC1.
- `CT_FLAG_NO_SECURITY_EXTENSION` (0x00080000 in msPKI-Enrollment-Flag): prevents embedding the security extension in the issued certificate. ESC9 condition.

**msPKI-Enrollment-Flag:**

- `CT_FLAG_PEND_ALL_REQUESTS` (0x00000002): requires manager approval for every request on this template.

### EKU (Extended Key Usage) and ESC2

| EKU | OID | Risk |
|---|---|---|
| Any Purpose | 2.5.29.37.0 | ESC2: certificate usable for any purpose including client authentication |
| No EKU | (none) | Treated as Any Purpose by many implementations |
| Client Authentication | 1.3.6.1.5.5.7.3.2 | Normal; restrict enrolment permissions |
| Server Authentication | 1.3.6.1.5.5.7.3.1 | Normal |
| Code Signing | 1.3.6.1.5.5.7.3.3 | High value; require authorised signatures and manager approval |
| Certificate Request Agent | 1.3.6.1.4.1.311.20.2.1 | ESC3 condition when broadly accessible |

---

## Enrolment methods

### Auto-enrolment

GPO-driven enrolment for domain-joined computers and users. Most common method.

Configuration path: `Computer Configuration > Windows Settings > Security Settings > Public Key Policies > Certificate Services Client - Auto-Enrollment`.

Troubleshooting auto-enrolment:

```powershell
# Force enrolment client to process templates
certutil -pulse

# Check Group Policy application
gpresult /h C:\temp\gpresult.html /scope:computer

# Review auto-enrolment events
Get-WinEvent -LogName "Microsoft-Windows-CertificateServicesClient-Lifecycle-System/Operational"
# Event 64: Enrolment for certificate failed
# Event 13: Auto-enrolment succeeded
```

### Web enrolment (certsrv)

Browser-based enrolment at `https://CA_SERVER/certsrv`. Must use HTTPS with Extended Protection for Authentication (EPA) to prevent ESC8 (NTLM relay). Disable HTTP. Disable web enrolment entirely if not needed; use auto-enrolment instead.

### CEP/CES (Certificate Enrolment Policy and Service)

Protocol for cross-forest, DMZ, and non-domain-joined clients. CEP provides policy information (available templates); CES processes enrolment requests.

### NDES (SCEP)

Network Device Enrolment Service provides SCEP protocol for network devices (routers, switches, BYOD). Challenge passwords are single-use tokens for initial enrolment. Manage challenge passwords carefully; do not allow unlimited use.

---

## Certificate revocation

### CRL (Certificate Revocation List)

Base CRL published on a schedule (typically daily or weekly). Must be accessible via HTTP and LDAP (from the CDP extension in issued certificates). CRL expiry causes chain validation failures for all relying parties.

### Delta CRL

Supplements the base CRL with changes since the last base CRL publication. Published more frequently (typically hourly). Reduces the size clients must download between base CRL publications.

### OCSP (Online Certificate Status Protocol)

Real-time revocation checking via the Online Responder role. Preferred over CRL for time-sensitive scenarios. OCSP signing certificate must be renewed before it expires; expiry causes online responder failures.

```powershell
# Check CRL publication status and accessibility
certutil -verify -urlfetch <certificate.cer>

# Manually publish CRL
certutil -CRL

# Check Online Responder health and configuration
Get-OCSPRevocationConfiguration

# Test revocation via URL retrieval tool
certutil -URL <certificate.cer>
```

---

## CA configuration flags

### EDITF_ATTRIBUTESUBJECTALTNAME2 (ESC6)

When set on the CA, this flag allows any certificate request to include a SAN regardless of template settings. It overrides the template's subject name settings.

```powershell
# Check if flag is set
certutil -config "CA01\CORP-CA" -getreg policy\EditFlags
# Look for: EDITF_ATTRIBUTESUBJECTALTNAME2 (value 0x00040000)

# Remove the flag
certutil -config "CA01\CORP-CA" -setreg policy\EditFlags -EDITF_ATTRIBUTESUBJECTALTNAME2
Restart-Service certsvc
```

### RPC signing enforcement (ESC11)

```powershell
# Check if RPC signing is enforced on the CA
certutil -config "CA01\CORP-CA" -getreg CA\InterfaceFlags
# Check for IF_ENFORCEENCRYPTICERTREQUEST (0x00000200)

# Enable RPC signing enforcement
certutil -config "CA01\CORP-CA" -setreg CA\InterfaceFlags +IF_ENFORCEENCRYPTICERTREQUEST
Restart-Service certsvc
```

---

## Certificate mapping (KB5014754)

Certificate mapping determines how a certificate presented for authentication is linked to an AD account.

### Mapping methods (strong vs weak)

**Strong mapping** (preferred): uses the Subject Key Identifier (SKI) or the new `szOID_NTDS_CA_SECURITY_EXT` extension embedded by the CA. Introduced as enforcement in KB5014754.

**Weak mapping** (deprecated): uses UPN or DNS name from the certificate SAN. Susceptible to ESC9, ESC10, and ESC14 attack paths.

### Enforcement stages (KB5014754)

| Stage | StrongCertificateBindingEnforcement | Behaviour |
|---|---|---|
| Disabled | 0 | Weak mapping allowed (ESC10 condition) |
| Compatibility mode | 1 | Weak mapping allowed with audit logging |
| Full enforcement | 2 | Only strong mapping accepted; weak mapping rejected |

```powershell
# Check enforcement mode on each DC
Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" -Name StrongCertificateBindingEnforcement

# Set to full enforcement
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name StrongCertificateBindingEnforcement -Value 2
```

---

## Common troubleshooting

| Issue | Investigation | Resolution |
|---|---|---|
| Auto-enrolment not working | `certutil -pulse`; check GP application; Event 13/64 in CertificateServicesClient | Verify template permissions, CA accessibility, GP settings |
| Certificate chain build failure | `certutil -verify -urlfetch cert.cer` | Publish root/intermediate CA certs to NTAuth store; check AIA extension |
| CRL download failure | `certutil -URL cert.cer` (URL Retrieval Tool) | Fix CDP paths; verify HTTP/LDAP accessibility |
| Template not appearing in enrolment | Check published templates on CA; check enrolment permissions | Publish template; grant Enrol permission |
| OCSP responder failure | Online Responder console; Event Viewer | OCSP signing certificate expired; revocation config issue |
| Event 4888 (certificate denied) | Check CA pending requests; check CA manager approval settings | Grant approval or adjust template/policy |
