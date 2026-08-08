# Control frameworks deep reference

Deep reference for the control frameworks a GRC programme attests to. A framework is an organisational control set, not a technical baseline; it says "enforce logical access control", and a benchmark scan or a system report is the evidence that you do. Load this when scoping a programme, mapping controls across frameworks, or deciding which evidence a control needs.

The frameworks below are described at the level needed to scope and map a programme. For the authoritative control text, obtain the source document: AICPA TSC for SOC 2, the ISO/IEC 27001:2022 standard, the PCI SSC document library, the HHS HIPAA Security Rule, and csrc.nist.gov for NIST CSF and SP 800-53.

---

## SOC 2 Trust Service Criteria

SOC 2 is the dominant attestation for B2B SaaS. It is organised around five Trust Service Criteria (TSC): Security (the mandatory Common Criteria), Availability, Processing Integrity, Confidentiality, and Privacy. Most reports cover Security only; the others are added when a customer commitment requires them.

The Common Criteria (CC series) is where most testing happens. CC6, Logical and Physical Access Controls, is the most commonly tested:

```
CC6.1  Logical access security software and architecture are implemented
  Evidence: MFA enrolment report (100% on production), access control policy,
            network segmentation diagram, firewall configuration review

CC6.2  Users are registered and authorised before being granted access
  Evidence: access provisioning tickets, HR new-hire to IT provisioning process,
            manager approval records

CC6.3  Access is removed when no longer required
  Evidence: HR offboarding to IT deprovisioning process, offboarding checklist,
            SCIM deprovisioning logs, periodic access reviews showing removal

CC6.6  Access measures prevent unauthorised access from outside the system
  Evidence: annual penetration test report, vulnerability scan results,
            WAF / DDoS protection, VPN / ZTNA for remote access
```

**Type I vs Type II** is the distinction that matters most:

```
Type I:  point-in-time. Controls are suitably designed as of a single date.
         Used for a new programme; less trusted by sophisticated buyers;
         completable in 2 to 3 months.

Type II: period assessment, typically 6 to 12 months. Controls are suitably
         designed AND operating effectively across the period. The B2B SaaS
         standard. The first Type II is the hardest because it needs 6 to 12
         months of documented evidence; renewal is annual.
```

The Type II requirement for evidence across a whole period is the single strongest argument for continuous, automated evidence collection over an annual scramble.

---

## ISO 27001:2022 control structure

ISO/IEC 27001 certifies an Information Security Management System (ISMS), not just a control list. The 2022 revision reorganised Annex A into 4 themes and 93 controls (down from 114 in 14 domains):

```
Organisational (37 controls): policies, roles, threat intelligence, security in
  project management, supplier security, incident management, business
  continuity, legal and regulatory compliance.

People (8 controls): screening, terms of employment, awareness and training,
  disciplinary process, remote working, reporting security events.

Physical (14 controls): security perimeters, physical entry, securing offices,
  clear desk and screen, media disposal, monitoring physical activity.

Technological (34 controls): endpoint devices, privileged access, access
  control, authentication, encryption, secure development, configuration
  management, backup, logging, monitoring, network and web filtering.
```

**New controls in the 2022 revision** (worth flagging when migrating from 2013):

```
5.7   Threat intelligence
5.23  Information security for use of cloud services
5.30  ICT readiness for business continuity
7.4   Physical security monitoring
8.9   Configuration management
8.10  Information deletion
8.11  Data masking
8.12  Data leakage prevention
8.16  Monitoring activities
8.23  Web filtering
8.28  Secure coding
```

Certification runs on a three-year cycle: a Stage 1 (documentation) and Stage 2 (implementation) audit for initial certification, then annual surveillance audits and a full recertification at year three.

---

## PCI DSS v4.0 key requirements

PCI DSS applies to anyone who stores, processes, or transmits cardholder data. Version 4.0 is organised into 12 requirements:

```
Req 1-2:   Network security controls. Firewalls, segmentation, secure system
           configuration, no default vendor passwords.
Req 3-4:   Protect account data. Minimise stored cardholder data, encrypt
           stored PAN, encrypt data in transit.
Req 5-6:   Vulnerability management. Anti-malware on all systems, secure
           development and patching.
Req 7-8:   Access control. Restrict by business need-to-know; identify and
           authenticate access (MFA required everywhere in v4.0, a key change).
Req 9:     Physical security. Restrict physical access to cardholder data.
Req 10-11: Logging and monitoring. Log all access to system components (10.7
           sets log retention); test security systems (quarterly scans, annual
           penetration test).
Req 12:    Information security policies. Security policy, risk assessment,
           awareness training, vendor management, incident response (12.10).
```

The v4.0 headline changes are MFA everywhere (not just for remote and admin access) and the "customised approach", which lets an entity meet a requirement's objective with a different control if it can prove equivalence, alongside the traditional "defined approach".

---

## HIPAA Security Rule

The HIPAA Security Rule governs electronic protected health information (ePHI) for covered entities and business associates. It is structured as three safeguard families, each a mix of "required" and "addressable" implementation specifications ("addressable" means implement it or document why an equivalent is reasonable, not optional):

```
Administrative safeguards: security management process (risk analysis is the
  anchor requirement), assigned security responsibility, workforce security,
  information access management, security awareness training, contingency plan,
  evaluation.

Physical safeguards: facility access controls, workstation use and security,
  device and media controls.

Technical safeguards: access control (unique user ID, emergency access,
  automatic logoff, encryption), audit controls, integrity, person/entity
  authentication, transmission security.
```

The Security Rule is deliberately technology-neutral and scales with the entity's size and risk; the risk analysis drives which addressable specifications apply. Breach notification obligations sit in the separate Breach Notification Rule.

---

## NIST CSF 2.0 and SP 800-53

The **NIST Cybersecurity Framework (CSF) 2.0** is a voluntary, outcome-based framework organised into six functions. The 2.0 revision (2024) added **Govern** to the original five:

```
Govern (GV):   organisational context, risk strategy, roles, policy, oversight.
Identify (ID): asset management, risk assessment, supply chain.
Protect (PR):  identity and access, awareness, data security, platform security.
Detect (DE):   continuous monitoring, adverse event analysis.
Respond (RS):  incident management, analysis, mitigation, reporting.
Recover (RC):  incident recovery, communications.
```

CSF describes outcomes, not specific controls; it is the common language layer that maps to detailed catalogues underneath.

**NIST SP 800-53 Rev 5** is the detailed control catalogue (20 control families) that CSF outcomes map down to, and the basis for FISMA, FedRAMP, and (via 800-171) CMMC. Six families have direct technical-system relevance and are where a device or system assessment concentrates:

```
AC  Access Control
AU  Audit and Accountability
CM  Configuration Management
IA  Identification and Authentication
SC  System and Communications Protection
SI  System and Information Integrity
```

The other 14 families (AT, CA, CP, IR, MA, MP, PE, PL, PM, PS, PT, RA, SA, SR) address organisational process, physical, personnel, and supply-chain concerns assessed at the programme level rather than in a single system's configuration. A system's FIPS 199 categorisation (Low / Moderate / High) selects the control baseline; higher impact means more controls and stricter implementation. The per-family assessment method lives in `benchmark-auditing.md`.

---

## Cross-framework mapping

The payoff of a mapped control set is that one control answers the same question in many frameworks. A small illustrative crosswalk:

| Control | SOC 2 | ISO 27001:2022 | PCI DSS v4.0 | NIST 800-53 | HIPAA |
|---|---|---|---|---|---|
| MFA on access | CC6.1 | A.8.5 | Req 8 | IA-2 | Technical: authentication |
| Access removed on offboarding | CC6.3 | A.5.18 | Req 8 | AC-2 | Admin: workforce security |
| Centralised logging | CC7.2 | A.8.15 | Req 10 | AU-2, AU-6 | Technical: audit controls |
| Encryption in transit | CC6.7 | A.8.24 | Req 4 | SC-8 | Technical: transmission security |
| Vulnerability management | CC7.1 | A.8.8 | Req 6, 11 | RA-5, SI-2 | Admin: risk management |
| Incident response | CC7.4 | A.5.24 | Req 12.10 | IR family | Admin: contingency plan |

Build the control once, name the evidence once, and tag it with every framework reference it satisfies. The mapping table itself becomes an artefact auditors value, because it shows the programme is designed rather than assembled per audit.
