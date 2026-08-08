---
name: ad-ds
description: "Use for Active Directory Domain Services implementation, configuration, hardening, and troubleshooting across Windows Server 2016 through 2025. Covers AD DS architecture (NTDS.dit, ESE database, directory partitions), FSMO roles (PDC Emulator, RID Master, Infrastructure Master, Schema Master, Domain Naming Master), multi-master replication (KCC, intra-site change notification, inter-site site links, repadmin, replication conflicts), Group Policy (LSDOU processing order, Enforced, Block Inheritance, security filtering, WMI filtering, gpresult, gpupdate), Kerberos authentication (TGT, TGS, SPNs, clock skew, delegation, AS-REP roasting, Kerberoasting), NTLM reduction and deprecation (Server 2025), trust types (parent-child, shortcut, external, forest, realm, SID filtering), AD hardening and tiered administration model (Tier 0/1/2, PAWs, Authentication Policies and Silos), Protected Users group, LAPS (Windows LAPS, legacy LAPS), gMSA and sMSA, fine-grained password policies, AdminSDHolder, Credential Guard, sites and subnets, Global Catalog, schema extensions, RODC, DFS-R SYSVOL, AD Recycle Bin, dcdiag, repadmin, nltest, event IDs (4624, 4625, 4648, 4768, 4769, 4771, 4776, 4720, 4728, 4732, 4756, 4780, 2887, 2889, 1644, 8606, 8453, 8524), honeypot accounts, version differences across Server 2016 (PAM, temporal groups, functional level 2016), Server 2019 (Azure AD Password Protection, Defender for Endpoint, AD FS 5.0), Server 2022 (TLS 1.3 LDAPS, Kerberos AES-256, FAST armoring, Cloud Kerberos trust), and Server 2025 (functional level 10, 32K database pages, NTLM deprecated, certificate trust PKINIT). References: architecture.md, best-practices.md, diagnostics.md. Triggers include \"Active Directory\", \"AD DS\", \"ADDS\", \"domain controller\", \"FSMO\", \"PDC emulator\", \"Group Policy\", \"GPO\", \"replication\", \"dcdiag\", \"repadmin\", \"NTDS.dit\", \"Kerberos\", \"LDAP unsigned\", \"trust\", \"LAPS\", \"gMSA\", \"AD hardening\", \"tiered administration\", \"Protected Users\", \"AdminSDHolder\", \"Kerberoasting\", \"AS-REP roasting\", \"unconstrained delegation\", \"RODC\", \"SYSVOL\", \"DFS-R\", \"site link\", \"Global Catalog\", \"schema extension\", \"netdom\", \"nltest\", \"Get-ADUser\", \"Get-ADComputer\", \"Get-ADGroup\", \"setspn\", \"functional level\", \"32K pages\", \"NTLM deprecation\". For IAM architecture, federation protocols, MFA strategy, access-control models, and IdP selection see identity-access-management; for credential and secret storage see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Active Directory Domain Services

> **Skill marker**: When applying this skill, begin your reply with `[skill: ad-ds]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill covers Active Directory Domain Services across Windows Server 2016 through 2025: directory internals, FSMO roles, replication, Group Policy, Kerberos, trust types, AD hardening, and version-specific differences. The conceptual layer (federation protocol choice, IdP selection, access-control models, zero trust) lives in `identity-access-management`. Certificate services live in `ad-cs`. Federation services live in `ad-fs`.

## When to use

- Designing or troubleshooting AD DS architecture: domain and forest structure, FSMO role placement, site topology, Global Catalog placement.
- Diagnosing replication failures: `repadmin /replsummary`, `repadmin /showrepl`, lingering objects, tombstone violations, replication error codes.
- Group Policy design or troubleshooting: LSDOU processing, Enforced vs Block Inheritance, security filtering, WMI filtering, `gpresult`, SYSVOL replication issues.
- Kerberos authentication problems: duplicate SPNs, clock skew, delegation misconfiguration, AS-REP roasting (Event 4768), Kerberoasting (Event 4769 with RC4), NTLM fallback.
- AD hardening and tiered administration: Tier 0/1/2 isolation, PAWs, Authentication Policies and Silos, Protected Users group, Credential Guard, LAPS, gMSA.
- Trust configuration and cross-forest authentication: trust types, SID filtering, selective authentication, name suffix routing.
- Version assessment and upgrade planning: functional level differences, NTLM deprecation readiness for Server 2025, 32K page migration.
- Running `dcdiag`, `repadmin`, `nltest`, PowerShell AD cmdlets for diagnostics or operations.

## When not to use

- **IAM architecture, federation protocol design, or IdP selection**: use `identity-access-management`.
- **AD FS claims-based federation, SAML/OIDC, WAP, and migration to Entra ID**: use `ad-fs`.
- **AD CS enterprise PKI, certificate templates, ESC vulnerabilities**: use `ad-cs`.
- **Entra ID (Azure AD), Conditional Access, PIM, Entra Connect**: use `entra-id`.
- **Credential, KRBTGT secret, keytab, gMSA password, and service-account secret storage**: use `secrets-hygiene`.
- **Kerberos ticket lifetime maths or certificate validity windows**: use `utc-timestamps` alongside this skill.

## Core model

### Directory structure

AD DS is a multi-master replicated directory built on the Extensible Storage Engine (ESE). The database file is `NTDS.dit`, stored at `C:\Windows\NTDS\` by default.

**Directory partitions:**

| Partition | Replication scope | Contents |
|---|---|---|
| Schema | Forest-wide | Object class and attribute definitions |
| Configuration | Forest-wide | Sites, subnets, services, replication topology |
| Domain | Domain-wide | Users, groups, computers, OUs, GPOs |
| Application | Configurable | DNS zones (ForestDnsZones, DomainDnsZones), custom |

Every object has a globally unique `objectGUID`, a security-aware `objectSid`, and a `distinguishedName` reflecting its position in the hierarchy.

### FSMO roles

Five Flexible Single Master Operations roles that break the multi-master model for specific operations:

| Role | Scope | Purpose | Critical impact if unavailable |
|---|---|---|---|
| Schema Master | Forest | Schema modifications | Cannot extend schema |
| Domain Naming Master | Forest | Add/remove domains | Cannot add/remove domains |
| PDC Emulator | Domain | Password changes, time sync, GPO edit, account lockout | Authentication failures, time drift |
| RID Master | Domain | Allocates RID pools for SID creation | Cannot create new objects when pool exhausted |
| Infrastructure Master | Domain | Cross-domain reference updates | Stale group membership display (multi-domain only) |

The PDC Emulator is the most operationally critical role; place it on your strongest DC. The Infrastructure Master should not sit on a Global Catalog server unless all DCs are GCs.

### Replication model

AD DS uses multi-master pull-based replication. The Knowledge Consistency Checker (KCC) automatically generates a replication topology.

- Intra-site: change notification within 15 seconds; RPC over IP; compressed only if greater than 50 KB.
- Inter-site: schedule-based (default 180 minutes); always compressed; uses site link cost for topology.

Conflict resolution: highest version number wins; if tied, later timestamp wins; if timestamps tie, higher originating DC GUID wins.

### Group Policy processing

LSDOU order: Local, Site, Domain, OU (parent before child). Last applied wins. Modifiers: Enforced prevents child override; Block Inheritance blocks all GPOs from above except Enforced.

### Kerberos authentication

AD DS runs the Kerberos KDC on every DC. Default TGT lifetime is 10 hours (renewable 7 days), service ticket 10 hours, clock skew tolerance 5 minutes. SPNs must be registered correctly: duplicate SPNs produce `KRB_AP_ERR_MODIFIED`; missing SPNs cause NTLM fallback.

### Tiered administration

| Tier | Controls | Rule |
|---|---|---|
| Tier 0 | DCs, AD DS, AD CS, AD FS, Entra Connect | T0 credentials never touch Tier 1 or Tier 2 |
| Tier 1 | Member servers, SQL, Exchange | T1 credentials never touch Tier 2 |
| Tier 2 | Workstations, end-user devices | Standard and helpdesk tier |

Enforce isolation via Authentication Policies and Silos (Server 2012 R2 and later). Use Privileged Access Workstations (PAWs) for Tier 0 administration.

## Reference router

| Topic | Covers | Reference |
|---|---|---|
| Architecture internals | NTDS.dit and ESE database files, database tables (Data/Link/SD/Hidden), replication USNs and conflict resolution, KCC topology, intra-site and inter-site replication protocols, sites and subnets, DC locator, Global Catalog, schema, trust authentication flow (cross-forest referral chain), RODC and Password Replication Policy, DFS-R SYSVOL migration states, version differences (2016 PAM and temporal groups / 2019 hybrid identity / 2022 TLS 1.3 and Kerberos FAST / 2025 functional level 10 and NTLM deprecation) | `references/architecture.md` |
| Hardening and best practices | Tiered administration implementation (Authentication Policies, Silos, PowerShell), PAW configuration, Windows LAPS and legacy LAPS deployment, gMSA creation and deployment, GPO security baselines (password policy, audit policy, NTLM restriction, LDAP signing, SMB signing), Protected Users group, fine-grained password policies, DC placement and sizing, backup and recovery (AD Recycle Bin, authoritative restore), NTLM reduction steps, monitoring and alerting (critical event IDs, honeypot accounts) | `references/best-practices.md` |
| Diagnostics and troubleshooting | dcdiag test reference, repadmin command playbook, nltest commands, replication error code table, replication failure workflow, authentication event IDs (4624/4625/4648/4768/4769/4771/4776), account management event IDs (4720/4728/4732/4756/4780), directory service event IDs (1388/1988/2042/2887/2889), Group Policy event IDs (1058/1030/7016), DNS troubleshooting for AD (required SRV records, common DNS issues), account lockout investigation, Kerberos troubleshooting, trust relationship failures, NTDS performance counters, expensive LDAP query detection, backup and recovery scenarios | `references/diagnostics.md` |

## Cross-references

- `identity-access-management`: federation protocol concepts, IdP selection, JML lifecycle design, Kerberos and LDAP concepts at the architectural level.
- `ad-cs`: enterprise PKI co-deployed with AD DS; certificate-based authentication (PKINIT, smart cards) depends on AD CS. CA servers are Tier 0 assets alongside DCs.
- `ad-fs`: on-premises SAML/OIDC/WS-Federation federation; AD FS authenticates against AD DS and is deprecated in favour of Entra ID.
- `entra-id`: Entra Connect and Cloud Sync bridge on-premises AD DS to Entra ID; hybrid identity joins these two identity planes.
- `windows-dns-ops`: AD DS is critically dependent on DNS; AD-integrated DNS zones, `_msdcs` delegation, SRV record registration, and DC locator all live in `windows-dns-ops`.
- `secrets-hygiene`: KRBTGT account secret, keytabs, service-account passwords, gMSA key distribution service root key, and CA private keys are credentials; their custody and rotation belong here.
- `utc-timestamps`: Kerberos TGT lifetimes (TGT 10 hours, renew 7 days), service ticket windows, clock skew tolerance (5 minutes), and replication tombstone lifetime must be reasoned about in UTC.
- `oncall-runbooks`: AD DS outage, replication failure, FSMO role seizure, golden ticket response, and mass account lockout runbooks.

## Red flags

- **KRBTGT not rotated after a suspected compromise**: a stolen KRBTGT enables forged golden tickets valid for the ticket lifetime. Rotate KRBTGT twice (allow replication between rotations) immediately after any suspected DC compromise.
- **Unconstrained delegation on a non-DC**: any service with unconstrained delegation can impersonate any user to any service. Audit with `Get-ADComputer -Filter {TrustedForDelegation -eq $true}` and restrict to constrained or resource-based constrained delegation.
- **Domain Admins used for routine administration**: Domain Admin is massively over-privileged. Delegate specific OU permissions; never use DA for day-to-day server management.
- **Infrastructure Master on a Global Catalog server**: in a multi-domain forest, this causes stale cross-domain group membership display. Place the Infrastructure Master on a non-GC DC.
- **DCs pointing to external DNS**: a DC must resolve its own domain via an AD-integrated DNS server, not an external resolver. External DNS for the AD domain causes replication and authentication failures.
- **SYSVOL still on FRS**: FRS is not supported at Windows Server 2016 functional level. Complete the DFS-R migration (`dfsrmig /setglobalstate 3`) before raising functional level.
- **Tombstone lifetime exceeded on an offline DC**: a DC offline longer than 180 days (default tombstone lifetime) reintroduces deleted objects as lingering objects on reconnect. Decommission rather than reconnect.
- **AdminSDHolder not monitored**: attackers modify AdminSDHolder to persist admin access. Alert on Event 4780 (unexpected propagation) and audit `CN=AdminSDHolder` ACL regularly.

## Bottom line

Deploy at least two writable GC-enabled DCs per site. Place FSMO roles deliberately (PDC Emulator on the strongest DC; Infrastructure Master off a GC server in multi-domain forests). Enforce tiered administration via Authentication Policies and Silos with PAWs for Tier 0. Use gMSA for all service accounts, Windows LAPS for workstation local admin, and Protected Users for all privileged accounts. Monitor replication with `repadmin /replsummary` daily and alert on Event 4769 (Kerberoasting), Event 4780 (AdminSDHolder), and replication failures exceeding one hour. For Server 2025 migrations, complete NTLM auditing and remediation before deployment.
