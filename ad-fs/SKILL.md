---
name: ad-fs
description: "Use for Active Directory Federation Services configuration, troubleshooting, and migration planning. Covers AD FS architecture (AD FS farm, Web Application Proxy, WID vs SQL Server configuration database), claims pipeline (Claims Provider Trust, Relying Party Trust, Issuance Transform Rules, Issuance Authorization Rules, Acceptance Transform Rules), claims rule language, SAML 2.0 federation, WS-Federation, OAuth 2.0 and OIDC (device code flow, PKCE), token-signing and token-decryption certificate management (auto-rollover, manual rotation, Get-AdfsCertificate), extranet smart lockout (AdfsSmartLockoutEnforce, AdfsSmartLockoutLogOnly), AD FS 2016 (AD FS 4.0), AD FS 2019 (AD FS 5.0), relying party trust configuration (Add-AdfsRelyingPartyTrust, Add-AdfsClient), federation metadata, WAP troubleshooting (Test-WebApplicationProxyConnection), Entra ID migration (AD FS application activity report, claims rule migration, Conditional Access equivalents), and decommissioning. References: architecture.md. Triggers include \"AD FS\", \"ADFS\", \"federation services\", \"claims rules\", \"relying party trust\", \"claims provider trust\", \"WAP\", \"Web Application Proxy\", \"SAML federation AD\", \"AD FS migration\", \"token signing certificate\", \"token decryption certificate\", \"extranet lockout\", \"AdfsSmartLockout\", \"WS-Federation\", \"AD FS farm\", \"WID\", \"Get-AdfsProperties\", \"Get-AdfsCertificate\", \"Add-AdfsRelyingPartyTrust\", \"FederationMetadata\", \"AD FS claims pipeline\". For IAM architecture, federation protocols, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Active Directory Federation Services

> **Skill marker**: When applying this skill, begin your reply with `[skill: ad-fs]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers AD FS: claims-based federation, SAML 2.0, WS-Federation, OAuth 2.0/OIDC, relying party trusts, claims rules, WAP, certificate management, and migration to Entra ID. AD FS is in maintenance mode; Microsoft recommends Entra ID for all new federation deployments. This skill covers both operating existing AD FS farms and planning migration away from them. Architecture concepts (protocol choice, IdP selection) live in `identity-access-management`. AD DS directory services live in `ad-ds`. PKI lives in `ad-cs`.

**Important context:** AD FS is in maintenance mode with no new feature investment. Every day on AD FS is technical debt. New federation should use Entra ID. Existing deployments should plan migration proactively.

## When to use

- Configuring relying party trusts or claims provider trusts on an existing AD FS farm.
- Writing or debugging AD FS claims rules (issuance transform, authorization, acceptance transform).
- Troubleshooting AD FS token issuance failures: Event 364, token-signing certificate mismatches, WAP connectivity, loop redirects.
- Managing AD FS certificates: monitoring auto-rollover, manually rotating token-signing or token-decryption certificates, updating relying parties after rotation.
- Configuring or troubleshooting extranet smart lockout on AD FS 2016+ farms.
- Planning or executing migration from AD FS to Entra ID: inventory, categorise applications, configure in Entra, test, cut over, decommission.
- Upgrading AD FS farms from 2016 (4.0) to 2019 (5.0).

## When not to use

- **IAM architecture, federation protocol selection, or zero trust design**: use `identity-access-management`.
- **New federation deployments**: use `entra-id`. AD FS is in maintenance mode; Entra ID is the recommended replacement.
- **AD DS directory services, FSMO roles, replication, Kerberos**: use `ad-ds`.
- **AD CS PKI, certificate templates, ESC vulnerabilities**: use `ad-cs`.
- **AD FS token-signing certificate private key storage or rotation credentials**: use `secrets-hygiene`.

## Core model

### Architecture

```
Internet          |  DMZ                    |  Internal Network
                  |                         |
Client -> WAP --> |-- AD FS Farm -----------|-- AD DS (DCs)
         (443)    |   (443, internal)        |
                  |                         |-- SQL Server or WID (config DB)
                  |                         |
                  |                         |-- Certificate Store
```

**Components:**

- **AD FS farm**: one or more AD FS servers sharing a configuration database. Stateless; configuration is in the database, not per-server.
- **Web Application Proxy (WAP)**: reverse proxy in DMZ for extranet access. WAP is not a federation server and is not a WAF; it proxies requests to AD FS. WAP is not a security boundary.
- **Configuration database**: WID (Windows Internal Database) for small farms (up to 5 servers, 100 relying party trusts); SQL Server for large farms.
- **Certificate store**: token-signing, token-decryption, and SSL/TLS certificates.

### Claims pipeline

Every token issuance flows through the claims pipeline in this order:

```
1. Claims Provider Trust (incoming claims from AD DS or another IdP)
   -> Acceptance Transform Rules (filter/transform incoming claims)

2. AD FS Engine
   -> Authorization Rules (permit/deny access to the relying party)

3. Relying Party Trust (outgoing claims for the application)
   -> Issuance Transform Rules (create/transform claims for the application)

4. Token Generation
   -> Sign token with token-signing certificate
   -> Return to client
```

### Claims rule language

AD FS uses a custom claims rule language for all transform and authorization rules:

```
# Pass through an AD attribute as a claim
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname"]
 => issue(store = "Active Directory",
    types = ("http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
             "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
             "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"),
    query = ";mail,givenName,sn;{0}", param = c.Value);

# Map AD group SID to application role
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid",
   Value == "S-1-5-21-xxx-yyy-zzz-1234"]
 => issue(Type = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
    Value = "AppAdmin");

# Authorization rule (permit only specific group)
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/groupsid",
   Value == "S-1-5-21-xxx-yyy-zzz-5678"]
 => issue(Type = "http://schemas.microsoft.com/authorization/claims/permit",
    Value = "true");
```

### Certificate management

AD FS uses three certificate types:

| Certificate | Purpose | Rotation | Impact on rotation |
|---|---|---|---|
| Token-signing | Signs issued tokens (SAML assertions, JWTs) | Auto-rollover 20 days before expiry | All relying parties must trust the new certificate |
| Token-decryption | Decrypts encrypted tokens from claims providers | Auto-rollover | Claims providers must update their encryption cert |
| SSL/TLS (service communication) | HTTPS endpoint for AD FS service | Manual renewal | Affects all client connections |

```powershell
# Check certificate status
Get-AdfsCertificate

# Check auto-rollover status
Get-AdfsProperties | Select-Object AutoCertificateRollover, CertificateGenerationThreshold

# Manually trigger token-signing certificate rotation
Update-AdfsCertificate -CertificateType Token-Signing -Urgent

# Federation metadata URL (relying parties consume new certs from here if configured)
# https://adfs.example.com/FederationMetadata/2007-06/FederationMetadata.xml
```

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture and operations | AD FS farm and WAP topology, WID vs SQL Server, claims pipeline detail, relying party trust PowerShell configuration, OAuth/OIDC configuration, certificate management procedures, extranet smart lockout configuration (2016 vs 2019), AD FS 4.0 vs 5.0 feature comparison, troubleshooting playbook (common errors, event logs, health checks), migration to Entra ID (assessment, steps, claims rule mapping table), decommissioning | `references/architecture.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts (SAML 2.0, OIDC, WS-Federation), IdP selection rationale, zero trust design; route all new federation design here rather than to AD FS.
- `ad-ds`: AD FS authenticates against AD DS; AD FS is a Tier 0 asset alongside DCs; the claims pipeline sources user attributes from AD DS.
- `ad-cs`: AD FS token-signing and token-decryption certificates are issued by AD CS; WAP SSL certificates require PKI-issued certificates; certificate chain trust is critical for AD FS operation.
- `entra-id`: Entra ID is the recommended replacement for AD FS. Entra Connect (Cloud Sync) bridges on-premises AD DS to Entra ID for hybrid SSO. Migration from AD FS to Entra ID is the recommended path for all existing deployments.
- `secrets-hygiene`: AD FS service account credentials, token-signing certificate private keys, and SQL Server connection string credentials are sensitive material; their custody belongs here.
- `utc-timestamps`: token `NotBefore`/`NotOnOrAfter` (clock skew causes "Token timestamps out of range" errors), token-signing certificate expiry, and session lifetime must be reasoned about in UTC.
- `oncall-runbooks`: AD FS farm outage, WAP connectivity failure, token-signing certificate rollover breaking relying parties, and extranet lockout storm runbooks.

## Red flags

- **Certificate auto-rollover breaks relying parties**: auto-rollover changes the token-signing certificate. Relying parties that consume federation metadata automatically handle this. Relying parties with manually configured certificates break silently on rollover. Audit all relying parties for manual certificate pinning.
- **WAP treated as a security boundary**: WAP provides pre-authentication and HTTPS reverse proxy but no application-layer protection. Do not rely on WAP for XSS or SQLi protection.
- **WID with more than 5 servers or 100 relying parties**: WID has hard limits. Above these limits, move to SQL Server. Monitor relying party count in growing deployments.
- **Delaying migration to Entra ID**: AD FS is in maintenance mode. Complex claims rules, WAP management, and certificate rotation are ongoing operational burden. Plan migration proactively; do not wait for a crisis.
- **Complex claims rules with no test coverage**: claims rules are hard to debug. Use the claims rule debugger (`Set-AdfsRelyingPartyTrust -IssuanceTransformRulesFile`) and test with IdP-initiated sign-on before production rollout.
- **Clock skew causing token failures**: AD FS tokens include `NotBefore` and `NotOnOrAfter` timestamps. If the AD FS farm or a relying party has significant time drift, authentication fails with timestamp errors. Synchronise NTP across the entire federation chain.
- **Not planning for AD FS 2016 end of extended support**: extended support ends January 2026; ESU available through January 2029. Begin migration planning now.

## Bottom line

Operate AD FS defensively while planning migration to Entra ID. For the existing farm: monitor certificate auto-rollover with an alerting rule on `Get-AdfsCertificate` expiry; enable extranet smart lockout in LogOnly mode first, then Enforce; keep token-signing certificates current; export AD FS Admin event logs to SIEM. For migration: start with the AD FS application activity report (AD FS 2019 farms) or manual inventory; categorise by migration complexity; configure and test in Entra ID; cut over one application at a time. Do not build new federation on AD FS.
