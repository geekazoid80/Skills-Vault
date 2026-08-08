# AD DS hardening and best practices

## Tiered administration model

The tiered model prevents credential theft from propagating across control planes. It is the single most impactful AD hardening measure.

### Tier definitions

| Tier | Controls | Assets | Admin accounts |
|---|---|---|---|
| Tier 0 | Forest and domain identity | DCs, AD DS, AD CS, AD FS, Entra Connect, PKI, PAM | T0 admin accounts, separate from daily-use accounts |
| Tier 1 | Servers and enterprise applications | Member servers, SQL, Exchange, SCCM, file servers | T1 admin accounts |
| Tier 2 | Workstations and end-user devices | Desktops, laptops, printers, mobile devices | Helpdesk, T2 admin accounts |

### Tier isolation rules

1. Tier 0 credentials NEVER touch Tier 1 or Tier 2 systems: no interactive logon, no RDP, no PSRemoting to member servers or workstations.
2. Tier 1 credentials NEVER touch Tier 2 systems: server admins do not log into workstations.
3. Lower tiers NEVER have admin access to higher tiers.
4. Enforce via Authentication Policies and Silos (Server 2012 R2+) or GPO logon restrictions.

### Authentication Policies and Silos implementation

```powershell
# Create Authentication Policy restricting where Tier 0 accounts can authenticate from
New-ADAuthenticationPolicy -Name "Tier0-Policy" `
    -UserAllowedToAuthenticateFrom "O:SYG:SYD:(XA;OICI;CR;;;WD;(@USER.ad://ext/AuthenticationSilo == ""Tier0-Silo""))" `
    -Enforce

# Create Authentication Silo binding Tier 0 accounts to Tier 0 devices
New-ADAuthenticationPolicySilo -Name "Tier0-Silo" `
    -UserAuthenticationPolicy "Tier0-Policy" `
    -ComputerAuthenticationPolicy "Tier0-Policy" `
    -ServiceAuthenticationPolicy "Tier0-Policy" `
    -Enforce

# Assign silo to Tier 0 accounts and DCs
Set-ADAccountAuthenticationPolicySilo -Identity "T0-Admin" -AuthenticationPolicySilo "Tier0-Silo"
Grant-ADAuthenticationPolicySiloAccess -Identity "Tier0-Silo" -Account "T0-Admin"
```

---

## Privileged Access Workstations (PAWs)

Dedicated workstations for Tier 0 administration.

### PAW configuration requirements

- Clean OS installation; separate from daily-use workstation.
- No internet access: block all outbound except to DCs and management tools.
- No email or web browsing.
- Application whitelisting via Windows Defender Application Control (WDAC) or AppLocker.
- Credential Guard enabled (requires Secure Boot, UEFI).
- BitLocker with TPM + PIN.
- USB restrictions: block removable storage via GPO.
- Full audit logging forwarded to SIEM.

### Jump server alternative

When dedicated PAWs are not feasible, use hardened jump servers:

- Hardened Windows Server in Tier 0 OU.
- RDP only from specific source IPs.
- Restricted Admin mode or Remote Credential Guard for RDP sessions.
- No internet, no email, application whitelisting.
- Session recording for audit.

---

## LAPS (Local Administrator Password Solution)

### Windows LAPS (built-in, Server 2019+ / Windows 10 21H2+)

```powershell
# Configure via GPO or Intune:
# Computer Configuration > Administrative Templates > System > LAPS
# Key settings: password complexity, length 14+ characters (max 64),
# password age 30 days, storage in AD or Entra ID,
# encryption (requires 2016+ domain functional level),
# post-authentication action: reset password + logoff.

# Retrieve password
Get-LapsADPassword -Identity "WORKSTATION01" -AsPlainText

# View password expiration
Get-LapsADPassword -Identity "WORKSTATION01" | Select-Object Account, PasswordUpdateTime, ExpirationTimestamp
```

### Legacy Microsoft LAPS (add-on)

- Schema extension required (`Update-AdmPwdADSchema`).
- Passwords stored in `ms-Mcs-AdmPwd` attribute (cleartext in AD, ACL-protected, no encryption unlike Windows LAPS).
- Migrate to Windows LAPS where possible.

---

## Group Managed Service Accounts (gMSA)

gMSAs provide automatic password management for service accounts.

```powershell
# Create KDS root key (one-time, forest-wide; wait 10 hours in production)
Add-KdsRootKey -EffectiveImmediately   # Waits 10 hours for replication

# Lab only (skip replication wait)
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))

# Create gMSA
New-ADServiceAccount -Name "gMSA-SQLSvc" `
    -DNSHostName "gMSA-SQLSvc.example.com" `
    -PrincipalsAllowedToRetrieveManagedPassword "SQLServers-Group" `
    -KerberosEncryptionType AES128,AES256

# Install on target server
Install-ADServiceAccount -Identity "gMSA-SQLSvc"

# Test
Test-ADServiceAccount -Identity "gMSA-SQLSvc"

# Service account entry: use "DOMAIN\gMSA-SQLSvc$" with blank password
```

**gMSA benefits**: 240-character random password; auto-rotated every 30 days; no human knows the password (cannot be phished or guessed); Kerberoasting is impractical (password too complex); works with SQL Server, IIS, scheduled tasks, and Windows services.

---

## GPO security baselines

### Key GPO settings for domain controllers

| Setting | Recommended value | GPO path |
|---|---|---|
| Minimum password length | 14+ characters | Computer > Windows Settings > Security > Account Policies |
| Account lockout threshold | 10 invalid attempts | Computer > Windows Settings > Security > Account Policies |
| Account lockout duration | 15 minutes | Computer > Windows Settings > Security > Account Policies |
| Audit policy | Success + Failure for all categories | Computer > Windows Settings > Security > Advanced Audit Policy |
| NTLM restriction | Audit first, then deny | Computer > Security > Local Policies > Security Options |
| LDAP signing | Require signing | Computer > Security > Local Policies > Security Options |
| LDAP channel binding | Always | Registry: `LdapEnforceChannelBinding = 2` |
| SMB signing | Required | Computer > Security > Local Policies > Security Options |
| LAN Manager auth level | Send NTLMv2 only, refuse LM and NTLM | Computer > Security > Local Policies > Security Options |

### Protected Users group

Add ALL privileged accounts to the Protected Users group. Protections applied:

- NTLM authentication is blocked.
- DES and RC4 Kerberos encryption types are not used.
- Kerberos delegation (unconstrained and constrained) is blocked.
- Kerberos TGT lifetime reduced to 4 hours (non-renewable).
- Credential caching is disabled (no offline logon).

Requirements: domain functional level 2012 R2+, DCs running 2012 R2+.

### Fine-Grained Password Policies (FGPPs)

```powershell
# Create FGPP for admin accounts (stricter than domain default)
New-ADFineGrainedPasswordPolicy -Name "Admin-Password-Policy" `
    -Precedence 10 `
    -MinPasswordLength 16 `
    -PasswordHistoryCount 24 `
    -ComplexityEnabled $true `
    -MaxPasswordAge "90.00:00:00" `
    -MinPasswordAge "1.00:00:00" `
    -LockoutThreshold 5 `
    -LockoutDuration "00:30:00" `
    -LockoutObservationWindow "00:30:00" `
    -ReversibleEncryptionEnabled $false

# Apply to admin group
Add-ADFineGrainedPasswordPolicySubject -Identity "Admin-Password-Policy" -Subjects "Domain Admins"
```

---

## Monitoring and alerting

### Critical events to alert on

| Event | Alert priority | Description |
|---|---|---|
| 4728/4732/4756 targeting privileged groups | Critical | Member added to Domain Admins or other privileged group |
| 4780 | High | AdminSDHolder ACL propagated; unexpected triggers indicate attack |
| 4720 in admin OU | Critical | Account created in admin OU |
| 4768 with RC4 (type 0x17) | Medium | Potential AS-REP roasting |
| 4769 with RC4 (type 0x17) | Medium | Potential Kerberoasting |
| 8222 (DS Access) | High | Shadow credentials (Key Trust) modification |
| 1644 (Directory Service) | Medium | Expensive LDAP query (performance issue or reconnaissance) |
| Replication failure exceeding 1 hour | High | Replication broken |
| FSMO role seizure | Critical | Unplanned role seizure |
| GPO modification (Event 5136) | Medium | Track all GPO changes |

### Honeypot accounts

Create decoy accounts to detect reconnaissance:

- Use names that appear valuable (for example, `svc-backup-admin`, `sql-sa`).
- Ensure no legitimate process ever accesses these accounts.
- Alert immediately on Event 4625 (failed logon) or 4624 (successful logon) for these accounts.

---

## DC placement and sizing

### DC placement guidelines

| Scenario | Recommendation |
|---|---|
| Main office (more than 500 users) | 2+ writable DCs, both GC-enabled |
| Branch office (50-500 users, secure location) | 1-2 writable DCs |
| Branch office (50-500 users, insecure location) | 1-2 RODCs |
| Branch office (fewer than 50 users) | RODC or rely on WAN to hub DC |
| Cloud (Azure/AWS) | DC VMs in cloud for cloud workloads, or use Microsoft Entra Domain Services |
| DMZ | Never place a writable DC; RODC only if required; prefer LDAPS proxy |

### DC sizing

| Component | Recommendation |
|---|---|
| CPU | 4+ cores (8+ for large environments or when AD CS is co-located) |
| RAM | 8 GB minimum; 16+ GB recommended. ESE cache auto-tunes to RAM minus 1 GB |
| Disk (NTDS.dit) | SSD strongly recommended; separate volume from OS |
| Disk (transaction logs) | Separate volume from NTDS.dit for write performance |
| Disk (SYSVOL) | Can share OS volume for small environments |
| Network | 1 Gbps minimum; dual NIC for redundancy (not teaming on DCs) |

---

## Backup and recovery

### Backup requirements

- Backup System State on at least two DCs per domain.
- Frequency: daily minimum.
- Retention: at least two backup cycles within the tombstone lifetime.
- Test restore quarterly in an isolated lab.
- Document and test the forest recovery procedure.

### AD Recycle Bin

```powershell
# Enable AD Recycle Bin (irreversible; requires Forest Functional Level 2008 R2+)
Enable-ADOptionalFeature -Identity "Recycle Bin Feature" `
    -Scope ForestOrConfigurationSet `
    -Target "example.com"

# Recover deleted object
Get-ADObject -Filter {displayName -eq "John Doe" -and isDeleted -eq $true} `
    -IncludeDeletedObjects | Restore-ADObject

# Recover deleted OU and all children
Get-ADObject -Filter {isDeleted -eq $true -and lastKnownParent -eq "OU=Sales,DC=example,DC=com"} `
    -IncludeDeletedObjects | Restore-ADObject
```

Deleted object lifetime: 180 days (same as tombstone lifetime by default). After this, objects are permanently removed and cannot be recovered from the Recycle Bin.

---

## NTLM reduction

NTLM is a legacy authentication protocol that must be minimised; deprecated in Server 2025.

### Audit phase

```powershell
# Enable NTLM auditing via GPO
# Computer Configuration > Windows Settings > Security > Local Policies > Security Options
# "Network security: Restrict NTLM: Audit incoming NTLM traffic" = Enable auditing for all accounts
# "Network security: Restrict NTLM: Audit NTLM authentication in this domain" = Enable all

# Monitor events:
# Event 8001 (Operational log) -- NTLM authentication in domain
# Event 8002 (Operational log) -- NTLM pass-through from server
# Event 8003 (Operational log) -- NTLM block would have occurred
```

### Reduction steps

1. **Audit**: enable NTLM auditing; collect data for 30+ days (60+ days before Server 2025 migration).
2. **Identify**: list applications and services using NTLM from audit events.
3. **Remediate**: fix applications (add SPNs, update configurations to use Kerberos).
4. **Exception**: add remaining NTLM-dependent systems to exception list.
5. **Block**: enable NTLM blocking with the exception list.
6. **Monitor**: continue monitoring for new NTLM usage.
