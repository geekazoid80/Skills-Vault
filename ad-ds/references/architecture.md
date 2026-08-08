# AD DS architecture and internals

## NTDS.dit database

### Database files

| File | Purpose | Default location |
|---|---|---|
| `NTDS.dit` | Main database (schema, objects, links, security descriptors) | `C:\Windows\NTDS\` |
| `edb.log` | Transaction log (current) | `C:\Windows\NTDS\` |
| `edb.chk` | Checkpoint file (tracks flushed transactions) | `C:\Windows\NTDS\` |
| `edbres00001.jrs` | Reserve log space (ensures clean shutdown when disk is full) | `C:\Windows\NTDS\` |
| `temp.edb` | Temporary table storage for ESE operations | `C:\Windows\NTDS\` |

### Database logical tables

- **Data table**: all AD objects; each row is an object; columns are schema-defined attributes; indexed by DNT (Distinguished Name Tag, internal row ID).
- **Link table**: forward and backward links between objects (member/memberOf); indexed by link ID and DNT.
- **Security Descriptor table**: unique security descriptors; objects reference SDs by index for deduplication (SD refcounting).
- **Hidden table**: internal metadata (database version, replication state, invocation ID).

### Database size and performance

Default page size is 8 KB (pre-2025). Server 2025 supports 32 KB pages as an optional feature at functional level 10. Typical database size is 1-10 GB for most organisations. ESE uses an auto-tuned buffer pool (database cache) in RAM. Transaction logs are 10 MB each; circular logging is NOT used. Logs are truncated after checkpoint advance and backup.

Online defragmentation runs automatically every 12 hours; it reclaims space within the file but does not shrink it. Offline defragmentation (`ntdsutil "activate instance NTDS" "files" "compact to C:\temp\ntds"`) requires a DSRM boot and is rarely needed.

---

## Replication internals

### Replication model

AD DS uses multi-master, pull-based replication. Each DC holds a writable copy (except RODCs). Destination DCs pull changes from source DCs.

### Update Sequence Numbers (USNs)

Each DC maintains a local USN counter. Every change increments the USN. Replication state is tracked via:

- **highestCommittedUSN**: current USN of the local DC.
- **Up-to-dateness vector (UTDV)**: table of (originating DC GUID, highest USN received from that DC). Prevents re-replicating already-seen changes.
- **High watermark table**: per-partner, the highest USN received. Used to request only new changes efficiently.

### Change metadata per attribute

- Originating DC that first wrote the change.
- Originating USN at the time of change.
- Version number (incremented with each change).
- Timestamp of the change.

### Conflict resolution

When the same attribute is modified on two DCs before replication:

1. Higher version number wins.
2. If version numbers tie: later timestamp wins.
3. If timestamps tie: higher originating DC GUID wins (deterministic tiebreaker).

### Replication topology (KCC)

The Knowledge Consistency Checker (KCC) runs on every DC every 15 minutes and generates the replication topology.

**Intra-site**: bidirectional ring ensuring at most 3 hops between any two DCs. Shortcut connections added when more than 7 DCs in a site. Replication triggered by change notification (15-second delay, configurable).

**Inter-site**: Inter-Site Topology Generator (ISTG) role on one DC per site creates connections. Uses site link cost to compute spanning tree (lowest cost path). Schedule-based (default 180 minutes). Uses site link bridges if enabled (transitive site links).

### Replication protocols

| Protocol | Transport | Use case | Compression |
|---|---|---|---|
| RPC over IP | TCP/135 + dynamic ports | All partitions, intra-site and inter-site | Inter-site always; intra-site only if greater than 50 KB |
| SMTP | SMTP port 25 | Schema and Configuration partitions only (inter-site) | Yes |

SMTP replication is rarely used and requires an Enterprise CA for message signing.

### Urgent replication

These changes bypass the 15-second notification delay and trigger immediate replication: account lockout, account lockout policy changes, domain password policy changes, LSASS secret changes, RID Manager state changes.

---

## Sites and subnets

Sites represent physical network topology. Subnets are associated with sites to enable clients to find the nearest DC.

### DC locator process

1. Client queries DNS for `_ldap._tcp.dc._msdcs.example.com` SRV records.
2. If site-aware: queries `_ldap._tcp.SiteName._sites.dc._msdcs.example.com`.
3. Client determines its site by presenting its IP to a DC (`DsGetSiteName`).
4. If the client and responding DC are in different sites, the DC refers the client to a DC in the client's site.

### Site link configuration

```powershell
# Create a site link
New-ADReplicationSiteLink -Name "NYC-LON" -SitesIncluded "NYC","LON" `
    -Cost 500 -ReplicationFrequencyInMinutes 60

# Restrict replication to off-hours
Set-ADReplicationSiteLink -Identity "NYC-LON" `
    -ReplicationSchedule @{DayOfWeek="Saturday";StartHour=0;EndHour=6}
```

Services that use AD sites for topology-aware behaviour: DFS namespace referrals, SCCM/MECM boundary groups, Exchange DAG and transport routing, and AD-integrated DNS (DCs register site-specific SRV records).

---

## Global Catalog

The Global Catalog (GC) is a partial read-only copy of all objects in every domain in the forest, stored on GC-designated DCs.

**Contents**: all objects from all domains, but only attributes marked `isMemberOfPartialAttributeSet = TRUE` in the schema (approximately 200 of the full attribute set).

**Ports**: LDAP 3268 (unencrypted), LDAPS 3269 (TLS).

**Use cases**: universal group membership resolution during Kerberos authentication; forest-wide LDAP searches (Exchange address book, UPN logon); object lookup across domain boundaries.

**Recommendation**: make all DCs Global Catalog servers unless you have a specific reason not to (single Infrastructure Master in a multi-domain forest where not all DCs are GCs).

---

## Schema

The schema partition defines all object classes and attributes in the forest. It is the blueprint for every object stored in AD. Only the Schema Master DC can write to the schema partition. Schema modifications are forest-wide and irreversible (attributes can be deactivated but not deleted). Test in a lab forest first. Use OID registration for custom attributes.

Common schema extensions: Exchange Server, SCCM/MECM, Lync/Skype for Business, LAPS, FIM/MIM.

---

## Trust authentication flow

### Cross-forest authentication (forest trust)

```
User@DomainA -> DC in DomainA
  -> User authenticates locally
  -> User requests access to resource in DomainB (different forest)
  -> DC in DomainA creates referral ticket (TGT for DomainB's KDC)
  -> Referral follows trust path: DomainA -> ForestRootA -> ForestRootB -> DomainB
  -> Each DC in the chain validates and re-issues referral
  -> DC in DomainB issues service ticket for the target resource
  -> SID filtering applies at the trust boundary
```

### Name suffix routing

Forest trusts use name suffix routing to determine which forest owns a UPN suffix or DNS name. Enabled by default for all DNS namespaces in the trusted forest. Can be disabled per suffix to prevent routing conflicts.

### Selective authentication

When enabled, users from the trusted domain/forest must be explicitly granted the "Allowed to Authenticate" permission on resources in the trusting domain/forest.

---

## RODC (Read-Only Domain Controller)

RODCs hold a read-only copy of the AD database. Designed for branch offices with limited physical security.

**Key characteristics:**
- No outbound replication (changes must be made on writable DCs).
- Credential caching controlled by Password Replication Policy (PRP).
- Filtered Attribute Set (FAS) excludes sensitive attributes from RODC replication.
- Each RODC has a unique `krbtgt_XXXXX` account for Kerberos ticket signing.
- Admin role separation: RODC-specific admin roles without domain-wide privileges.

**Password Replication Policy:**
- `Allowed RODC Password Replication Group`: accounts whose passwords CAN be cached.
- `Denied RODC Password Replication Group`: accounts whose passwords MUST NOT be cached (default includes Domain Admins, Enterprise Admins, Schema Admins).
- If a password is not cached and the writable DC is unreachable, authentication fails.

---

## DFS-R for SYSVOL

SYSVOL contains Group Policy templates, logon scripts, and other domain-wide files. DFS-R replaced FRS (File Replication Service) for SYSVOL replication starting with Windows Server 2008.

**Migration states (FRS to DFS-R):**

| State | Description |
|---|---|
| 0 Start | FRS active |
| 1 Prepared | DFS-R copies created alongside FRS |
| 2 Redirected | DFS-R is authoritative; FRS still running |
| 3 Eliminated | FRS removed |

```powershell
# Check SYSVOL replication state
dfsrmig /getmigrationstate

# Advance migration state
dfsrmig /setglobalstate 1  # Prepare
dfsrmig /setglobalstate 2  # Redirect
dfsrmig /setglobalstate 3  # Eliminate
```

FRS-to-DFS-R migration must be completed before raising the functional level to Server 2016 or higher.

---

## Version differences

### Server 2016 (domain and forest functional level 2016)

**New features at functional level 2016:**

- **Privileged Access Management (PAM)**: bastion forest architecture with shadow principals and temporal group memberships (time-limited, auto-expiring). Requires Microsoft Identity Manager (MIM) 2016 for full workflow.
- **PKInit Freshness Extension**: Kerberos pre-authentication freshness to detect replayed AS-REQs.
- **Automatic NTLM secret rolling**: for accounts configured to require smart card.

```powershell
# Enable PAM feature (forest functional level 2016 required)
Enable-ADOptionalFeature -Identity "Privileged Access Management Feature" `
    -Scope ForestOrConfigurationSet -Target "bastion.example.com"

# Create temporal group membership
Add-ADGroupMember -Identity "Domain Admins" -Members "TempAdmin" `
    -MemberTimeToLive (New-TimeSpan -Hours 2)

# Check TTL on group membership
Get-ADGroup "Domain Admins" -Properties member -ShowMemberTimeToLive
```

**AD FS 4.0 co-deployment**: native OIDC/OAuth 2.0, Azure MFA adapter, device authentication, HTTP.sys (no IIS dependency), and extranet lockout.

**Upgrade prerequisites**: all DCs must run Server 2016+; SYSVOL must use DFS-R (not FRS); run `adprep /forestprep` and `adprep /domainprep`.

Support status: mainstream ended January 2022; extended ends January 2027; ESU available through January 2030.

---

### Server 2019 (same functional level as 2016, no new FL)

**Hybrid identity improvements:**

- Azure AD Connect V2: improved sync engine, SQL Server 2019 LocalDB, TLS 1.2 enforcement.
- Password hash sync improvements: faster initial sync, better error reporting.
- Seamless SSO: Kerberos-based SSO to Entra ID without AD FS (with PTA or PHS).
- **Azure AD Password Protection**: extends Entra ID banned password list to on-premises DCs.

```powershell
# Check Azure AD Password Protection agent status
Get-AzureADPasswordProtectionDCAgent
Get-AzureADPasswordProtectionProxy
```

**Security enhancements:**

- Windows Defender for Endpoint (ATP) integration: DCs can be onboarded for advanced threat detection.
- Secured-core server: hardware root of trust, firmware protection (compatible hardware required).
- LEDBAT for inter-site replication: reduces replication impact on network bandwidth.

**AD FS 5.0 co-deployment**: external authentication providers, device code flow, SAML/WS-Fed single logout, and application activity reports for Entra ID migration analysis.

Key pitfall: there is no 2019 functional level. Do not attempt to raise FL to "2019".

Support status: mainstream ended January 2024; extended ends January 2029.

---

### Server 2022 (same functional level as 2016, no new FL)

**TLS 1.3 for LDAPS:**

- LDAPS on port 636 negotiates TLS 1.3 when both client and server support it.
- No configuration required; TLS 1.3 is enabled by default.
- Stronger cipher suites only (AES-GCM, ChaCha20-Poly1305).

TLS 1.0 and TLS 1.1 are disabled by default on Server 2022. Audit legacy TLS usage before upgrade.

**Kerberos improvements:**

- AES-256-CTS-HMAC-SHA1-96 preferred for Kerberos tickets.
- Kerberos armoring (FAST): Flexible Authentication via Secure Tunneling provides a protected channel for pre-authentication. Enabled by default when DCs and clients support it.
- Reduced RC4 usage; Event 4768/4769 encryption type field: 0x17 = RC4, 0x11 = AES128, 0x12 = AES256.

```powershell
# Enforce AES-only Kerberos for an account
Set-ADUser -Identity "jdoe" -KerberosEncryptionType "AES128,AES256"

# Check encryption types supported by an account
Get-ADUser -Identity "jdoe" -Properties msDS-SupportedEncryptionTypes
```

**Hybrid identity:**

- Azure AD Kerberos: passwordless security key sign-in to on-premises resources via Entra ID.
- Cloud Kerberos trust: Windows Hello for Business without PKI dependency.
- Entra Connect Cloud Sync: lightweight alternative to Azure AD Connect for simple sync.

**Credential Guard enabled by default** on qualifying hardware (UEFI, Secure Boot, TPM 2.0). Applications relying on NTLMv1 or credential injection into LSASS will break.

Support status: mainstream ends October 2026; extended ends October 2031.

---

### Server 2025 (functional level 10, new)

**Functional level 10** is the first new AD functional level since Server 2016. All DCs in the forest must run Server 2025 before raising to FL 10.

**32K database page size (optional feature at FL 10):**

- NTDS.dit page size increases from 8 KB to 32 KB.
- Performance benefit: fewer I/O operations for large objects (multi-valued attributes such as group membership and certificates).
- Capacity benefit: removes the 8 KB attribute value limit for certain operations.
- **Irreversible**: once enabled, 32K pages cannot be reverted. Existing DCs require an offline database upgrade. New DCs promoted after enabling will use 32K pages automatically.

```powershell
# Enable 32K database pages (irreversible; all DCs must be on Server 2025)
Enable-ADOptionalFeature -Identity "Database 32k Pages Feature" `
    -Scope ForestOrConfigurationSet -Target "example.com"
```

**NTLM deprecation:**

- NTLM is deprecated and disabled by default for new installations.
- NTLMv1 is completely removed; no configuration can re-enable it.
- NTLMv2 can be re-enabled as a compatibility measure but is deprecated.
- Start NTLM auditing months before migration; collect data for 60+ days; remediate all NTLM-dependent applications.

**Kerberos with certificate trust:**

- PKINIT via SHA-256/SHA-384 (stronger hash algorithms).
- Windows Hello for Business with certificate trust: Kerberos authentication from first logon without NTLM fallback.
- Eliminates NTLM dependency for initial device authentication in domain-join scenarios.

**Security posture:**

- Credential Guard enforced (not optional) on qualifying hardware.
- Legacy protocols disabled by default.
- Enhanced replication compression for inter-site traffic.

**Server 2025 upgrade sequence:**

1. Enable NTLM auditing; collect 60+ days of data; remediate all NTLM-dependent applications.
2. Verify replication health: `repadmin /replsummary`.
3. Run `adprep /forestprep` and `adprep /domainprep` from Server 2025 media.
4. Deploy Server 2025 DCs via swing migration; transfer FSMO roles; decommission old DCs.
5. Raise FL to 10: `Set-ADDomainMode` and `Set-ADForestMode`.
6. Enable optional 32K database pages after verifying all DCs are on Server 2025.

Key pitfall: NTLMv1 is completely removed; any system still using NTLMv1 (embedded devices, legacy printers) must be isolated or replaced before migration.

Support status: mainstream support active; GA release 2024.

---

## Version comparison table

| Feature | Server 2016 | Server 2019 | Server 2022 | Server 2025 |
|---|---|---|---|---|
| Functional level | 2016 (new) | 2016 (no change) | 2016 (no change) | 10 (new) |
| Database page size | 8 KB | 8 KB | 8 KB | 32 KB (optional) |
| TLS 1.3 for LDAPS | No | No | Yes | Yes |
| Kerberos FAST | Limited | Limited | Improved, default | Enhanced |
| NTLM status | Available | Available | Available, can restrict | Deprecated, disabled by default |
| NTLMv1 | Available | Available | Available | Completely removed |
| Credential Guard | Client supported | Server supported | Default on qualifying HW | Enforced |
| PAM temporal groups | Yes (new) | Yes | Yes | Yes |
| Azure AD Password Protection | No | Yes | Yes | Yes |
| Cloud Kerberos trust | No | No | Yes | Yes |
| 32K pages | No | No | No | Yes (optional) |
