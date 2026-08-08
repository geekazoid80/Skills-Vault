# AD FS architecture and operations

## Farm architecture and components

```
Internet          |  DMZ                    |  Internal Network
                  |                         |
Client -> WAP --> |-- AD FS Farm -----------|-- AD DS (DCs)
         (443)    |   (443, internal)        |
                  |                         |-- SQL Server or WID
                  |                         |
                  |                         |-- Certificate Store
```

### AD FS farm

One or more AD FS servers sharing a configuration database. The farm is stateless per node; all configuration is in the database. A load balancer distributes client requests across farm members. All farm members share the same token-signing and token-decryption certificates.

### Web Application Proxy (WAP)

Reverse proxy in the DMZ for extranet access. WAP is NOT a federation server. It proxies and pre-authenticates requests before forwarding them to the AD FS farm. WAP does not provide application-layer security (no WAF capabilities).

WAP supports two modes:

- **Pass-through**: proxy without pre-authentication (not recommended).
- **AD FS pre-authentication**: authenticates users via AD FS before allowing access to the published application.

### Configuration database

| Option | Max servers | Max relying parties | Notes |
|---|---|---|---|
| WID (Windows Internal Database) | 5 | 100 | Primary node + read-only secondaries; automatic sync |
| SQL Server | Unlimited | Unlimited | Required for large farms; full SQL HA options |

For most deployments under the WID limits, WID is simpler to operate. Move to SQL Server before hitting limits.

---

## Claims pipeline in detail

Every token issuance flows through this pipeline:

```
1. Claims Provider Trust (incoming claims from AD DS or another IdP)
   -> Acceptance Transform Rules (filter/transform incoming claims before the engine processes them)

2. AD FS Engine
   -> Authorization Rules (permit/deny; evaluated per relying party)

3. Relying Party Trust (outgoing claims for the application)
   -> Issuance Transform Rules (transform and select claims to include in the issued token)

4. Token Generation
   -> Sign token with the current primary token-signing certificate
   -> Encrypt token if relying party requests encryption (uses relying party's encryption certificate)
   -> Return signed token to client
```

Rules within each stage are evaluated top-to-bottom; the first matching rule in an authorization context that issues a permit claim wins. If no permit claim is issued, access is denied.

---

## Relying party trust configuration

### SAML 2.0 relying party

```powershell
# Add a SAML 2.0 relying party trust from metadata URL
Add-AdfsRelyingPartyTrust -Name "MyApp" `
    -MetadataUrl "https://app.example.com/saml/metadata" `
    -IssuanceTransformRules $transformRules `
    -IssuanceAuthorizationRules $authRules

# Add a SAML 2.0 relying party trust manually
Add-AdfsRelyingPartyTrust -Name "MyApp" `
    -Identifier "https://app.example.com" `
    -SamlEndpoint (New-AdfsSamlEndpoint -Protocol SAMLAssertionConsumer `
        -Uri "https://app.example.com/saml/acs" -Binding POST) `
    -IssuanceTransformRules $transformRules `
    -IssuanceAuthorizationRules $authRules
```

### OAuth 2.0 / OIDC configuration

```powershell
# Add OIDC/OAuth relying party trust
Add-AdfsRelyingPartyTrust -Name "MyAPI" `
    -Identifier "api://my-api" `
    -IssuanceTransformRules $transformRules

# Add OAuth client (for OIDC/OAuth applications)
Add-AdfsClient -ClientId "my-client-id" `
    -Name "My Web App" `
    -RedirectUri "https://app.example.com/callback" `
    -Description "OIDC web application"
```

### AD FS 4.0 vs AD FS 5.0 feature comparison

| Feature | AD FS 4.0 (Server 2016) | AD FS 5.0 (Server 2019) |
|---|---|---|
| OIDC/OAuth 2.0 | Supported | Enhanced (device flow, PKCE) |
| Azure MFA adapter | Built-in | Improved |
| Extranet lockout | Basic (threshold only) | Smart lockout with familiar/unfamiliar locations |
| Password-less | Microsoft Passport for Work | Enhanced password-less options |
| Activity reports | Not available | Application usage reports for Entra migration |
| External auth providers | Limited | Plugin architecture |
| WS-Federation SLO | Not available | Single logout support |
| Auditing | Basic | Enhanced |

---

## Certificate management

AD FS uses three certificate types with distinct rotation requirements.

### Token-signing certificate

Signs all tokens issued by AD FS (SAML assertions, JWTs, WS-Federation tokens). Relying parties must trust this certificate to validate tokens.

**Auto-rollover** (default: enabled): AD FS generates a new secondary certificate 20 days before the primary expires, then promotes it. Relying parties that consume federation metadata update automatically. Relying parties with manually configured certificates break on rollover.

```powershell
# Check certificate status and expiry
Get-AdfsCertificate

# Check auto-rollover configuration
Get-AdfsProperties | Select-Object AutoCertificateRollover, CertificateGenerationThreshold

# Manually trigger rotation (useful when relying parties need advance notice)
Update-AdfsCertificate -CertificateType Token-Signing -Urgent

# Federation metadata URL (relying parties can consume this URL to get updated certs)
# https://adfs.example.com/FederationMetadata/2007-06/FederationMetadata.xml
```

### Token-decryption certificate

Decrypts encrypted tokens sent by claims providers (when a claims provider encrypts assertions for AD FS). Follows the same auto-rollover behaviour as token-signing.

### SSL/TLS (service communication) certificate

HTTPS endpoint certificate for the AD FS service. Must be renewed manually. Affects all client connections including WAP -> AD FS traffic. Common name must match the AD FS service name (for example, `adfs.example.com`).

---

## Extranet smart lockout

Protects against brute-force password attacks on extranet-facing AD FS. Available in AD FS 2016 and later.

```powershell
# AD FS 2016: basic extranet lockout
Set-AdfsProperties -EnableExtranetLockout $true `
    -ExtranetLockoutThreshold 15 `
    -ExtranetObservationWindow (New-TimeSpan -Minutes 30) `
    -ExtranetLockoutRequirePDC $false

# AD FS 2019: enhanced smart lockout with familiar/unfamiliar location tracking
# Step 1: Enable in LogOnly mode first (audit without blocking)
Set-AdfsProperties -ExtranetLockoutMode AdfsSmartLockoutLogOnly

# Step 2: Monitor events; once comfortable, switch to Enforce
Set-AdfsProperties -ExtranetLockoutMode AdfsSmartLockoutEnforce
```

Familiar locations are IP addresses from which a user has previously authenticated successfully. Authentication from unfamiliar locations triggers lockout sooner.

---

## Troubleshooting

### Common issues

| Symptom | Investigation | Resolution |
|---|---|---|
| "An error occurred" on login | AD FS Admin event log, Event ID 364 | Check claims rules, certificate trust, relying party config |
| Token-signing cert mismatch | Compare AD FS cert thumbprint with RP metadata | Update federation metadata on the relying party side |
| WAP not connecting to AD FS | WAP event log; `Test-WebApplicationProxySslCertificate` | Certificate mismatch, firewall, DNS, expired trust |
| Loop redirect | Relying party redirect URI mismatch | Fix redirect URI in RP trust configuration |
| Clock skew errors | Token timestamps out of range | Sync NTP across AD FS farm and relying parties; check NotBefore/NotOnOrAfter |
| Slow authentication | Enable AD FS performance counters | Database contention (migrate WID to SQL); DC latency |

### Health check commands

```powershell
# Check AD FS service health and configuration
Get-AdfsProperties | Select-Object HostName, FederationPassiveAddress, CurrentFarmBehavior

# Test token issuance via IdP-initiated sign-on
# Navigate to: https://adfs.example.com/adfs/ls/IdpInitiatedSignon.aspx

# Check AD FS event logs
Get-WinEvent -LogName "AD FS/Admin" -MaxEvents 50

# Verify WAP connectivity
Test-WebApplicationProxyConnection -FederationServiceName "adfs.example.com"
```

---

## Migration to Entra ID

Microsoft's recommended path: migrate all relying party trusts from AD FS to Entra ID, then decommission the AD FS farm.

### Assessment

```powershell
# AD FS 2019: use application activity report in Azure portal
# Entra ID > Usage & insights > AD FS application activity

# For AD FS 2016 or earlier: manual inventory
Get-AdfsRelyingPartyTrust | Select-Object Name, Identifier, Enabled, LastUpdateTime
```

### Migration steps

1. **Inventory**: list all relying party trusts (`Get-AdfsRelyingPartyTrust`).
2. **Categorise** applications:
   - Apps in Entra ID gallery (pre-integrated): easy migration.
   - Custom SAML/OIDC apps: configure manually in Entra ID.
   - Apps requiring claims transformations: map AD FS claims rules to Entra claims mapping policies.
   - Apps using WS-Federation: many can switch to SAML or OIDC.
3. **Configure applications in Entra ID**: create enterprise applications or app registrations.
4. **Test authentication**: validate SSO, claims, MFA, Conditional Access.
5. **Cut over**: update DNS or application configuration to point to Entra ID.
6. **Monitor**: verify sign-in logs in Entra ID; check for authentication failures.
7. **Decommission AD FS**: after all applications are migrated, demote WAP and AD FS servers.

### Claims rule migration mapping

| AD FS claims rule | Entra ID equivalent |
|---|---|
| Pass-through email, name, UPN | Default claims in SAML token configuration |
| Group-to-role mapping | Group claims with app roles |
| Custom claim from AD attribute | Claims mapping policy or optional claims |
| Authorization rules (permit/deny) | Conditional Access policies + app assignment |
| Transform claim values | Claims transformation rules or custom claims provider |

---

## Decommissioning

After all relying party trusts are migrated:

1. Verify zero active traffic to AD FS (monitor sign-in logs for 30+ days).
2. Disable AD FS service on all farm members.
3. Revoke or archive token-signing certificates.
4. Remove WAP servers from DMZ.
5. Demote AD FS server roles (`Uninstall-WindowsFeature ADFS-Federation`).
6. Remove AD FS service account and group Managed Service Account if applicable.
7. Archive configuration database backup for compliance retention.
8. Remove AD FS DNS records.
