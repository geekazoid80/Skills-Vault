---
name: network-source-of-truth
description: "Use for network source-of-truth (SoT) operations: querying and reconciling NetBox, Nautobot, and OpsMill Infrahub against live network state. Owns SoT platform selection and the intent-vs-reality reconciliation methodology, and routes to per-platform references for tool depth. Triggers include \"source of truth\", \"network SoT\", \"NetBox\", \"Nautobot\", \"Infrahub\", \"OpsMill\", \"IPAM\", \"DCIM\", \"IP address management\", \"prefix lookup\", \"subnet allocation\", \"VRF\", \"tenant\", \"site IP summary\", \"device inventory\", \"config drift\", \"drift detection\", \"reconciliation\", \"reconcile NetBox\", \"reconcile source of truth\", \"intended state vs actual state\", \"undocumented link\", \"cable mismatch\", \"VLAN mismatch\", \"IP drift\", \"missing interface\", \"MTU mismatch\", \"GraphQL infrastructure query\", \"versioned infrastructure branches\", \"schema-driven infrastructure\", \"audit network documentation\", \"IPAM audit\", \"is my documentation accurate\", \"does NetBox match reality\". References: netbox.md, nautobot.md, infrahub.md, reconciliation.md. For multi-vendor live-state collection see pyats-network-automation; for cloud resource inventory see aws-cloud-ops, azure-cloud-ops, gcp-cloud-ops."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# Network source of truth

> **Skill marker**: When applying this skill, begin your reply with `[skill: network-source-of-truth]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

A network source of truth (SoT) is the authoritative record of intended infrastructure state: which devices exist, how they are addressed, which prefixes and VLANs are allocated, how things are cabled. This skill owns SoT platform selection across the three platforms with MCP support (NetBox, Nautobot, OpsMill Infrahub), and the reconciliation methodology that compares intended state against live device reality. Per-platform tool depth lives in the references.

The governing idea is the gap between two states. The SoT holds **intended** state; the live network holds **actual** state. When they differ, either the network is misconfigured or the SoT is stale. The SoT is authoritative, so the answer is never to silently rewrite one to match the other: discrepancies are reported, ticketed, and put in front of a human.

## When to use

- Querying a SoT for device inventory, IP addresses, prefixes, VRFs, tenants, sites, VLANs, or cabling.
- Choosing or comparing SoT platforms (NetBox vs Nautobot vs Infrahub) for a deployment.
- Reconciling a SoT against live device state to find config drift, undocumented links, cable mismatches, VLAN or IP divergence.
- Auditing whether network documentation still matches reality (scheduled validation, post-change verification, incident response, new-device onboarding, compliance evidence).
- Proposing an infrastructure change on a versioned branch (Infrahub) before it reaches production.

## When not to use

- **Collecting live device state itself** (CDP/LLDP neighbours, show-command output, interface counters): that is `pyats-network-automation`. This skill consumes live state for reconciliation but does not own the collection transport.
- **Pushing configuration to devices**: see `ansible-network-modules`, `nornir-automation`, or `napalm-netmiko`. A SoT records intent; it does not remediate the network.
- **Config-as-data correctness analysis** (ACL semantics, routing-policy reachability): see `acl-rule-analysis`, `bgp-analysis`, `igp-routing-analysis`. SoT reconciliation checks documentation accuracy, not whether the config is logically correct.
- **Cloud resource inventory** (VPC, subnets, cloud IPAM): see `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops` and the networking-audit skills. A SoT can model cloud objects, but cloud-native inventory lives with the vendor skills.

## Platform selection

```
Need to model your own infrastructure types, or want versioned (Git-like) changes to data?
  YES -> Infrahub (schema-driven, branches, GraphQL-native)   -> references/infrahub.md
  NO  -> Already running NetBox or Nautobot?
    NetBox   -> references/netbox.md   (read-write; reconciliation engine pairs with it)
    Nautobot -> references/nautobot.md (read-only IPAM via MCP; NTC ecosystem, Jobs framework)
    Neither, standard DCIM/IPAM, picking fresh -> NetBox or Nautobot per ecosystem fit
```

| Platform | Origin | Data model | Versioning | API | MCP surface |
|---|---|---|---|---|---|
| NetBox | DigitalOcean / NetBox Labs | Fixed DCIM/IPAM + custom fields | No branching | REST + GraphQL | Read-write |
| Nautobot | Network to Code (NetBox fork) | Fixed DCIM/IPAM + Jobs + custom fields | No branching | REST + GraphQL + Jobs | Read-only IPAM (5 tools) |
| Infrahub | OpsMill | Fully schema-driven (define any model) | Git-like branches for data | GraphQL-native | Read + GraphQL mutations + branches (10 tools) |

If an organisation runs more than one, use whichever holds the authoritative record for the object in question, and reconcile across them when migrating.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| NetBox | Golden rule, MCP tools, object-type model, changelog audit, when to use | `references/netbox.md` |
| Nautobot | Read-only IPAM tools, prefix/IP/VRF/tenant filtering, IPAM workflows | `references/nautobot.md` |
| Infrahub | Schema-driven model, GraphQL queries, versioned branches, 10 MCP tools, workflows | `references/infrahub.md` |
| Reconciliation | Intent-vs-reality methodology, discrepancy taxonomy, diff engine, ticketing, fleet reporting | `references/reconciliation.md` |

## Reconciliation in one screen

Reconciliation is platform-agnostic: any SoT supplies intended state, `pyats-network-automation` supplies actual state, and the diff engine classifies every divergence by severity.

```
Collect SoT intent (devices, interfaces, IPs, cables, VLANs)
  + Collect live state via pyATS (show output, CDP/LLDP)
  -> Diff per type -> severity-sorted report -> ticket criticals -> visual drift summary
```

Discrepancy taxonomy (severity order CRITICAL > HIGH > MEDIUM > LOW): IP_DRIFT (critical), MISSING_INTERFACE / UNDOCUMENTED_LINK / CABLE_MISMATCH (high), VLAN_MISMATCH / STATUS_MISMATCH (medium), MTU_MISMATCH (low). Full diff logic, report layout, ServiceNow ticketing, and fleet-wide rollup are in `references/reconciliation.md`.

**Golden rule:** discrepancies are reported and ticketed, NEVER auto-corrected without explicit human approval. The SoT is the intended state; deciding whether the device or the SoT is wrong is a human call.

## Cross-references

- `pyats-network-automation`: supplies live device state (interfaces, IPs, CDP/LLDP neighbours, switchport data) that the reconciliation engine diffs against SoT intent.
- `multi-vendor-network-ops`: diagnose-first entry point for multi-vendor estates; SoT inventory feeds its review workflows.
- `ansible-network-modules`, `nornir-automation`, `napalm-netmiko`: push the remediation once a human approves a reconciliation finding. A SoT records intent; these change the network.
- `acl-rule-analysis`, `bgp-analysis`, `igp-routing-analysis`: config-as-data analysis; complementary to documentation-accuracy checks.
- `incident-response-network`, `oncall-runbooks`: an accurate SoT baseline accelerates forensics and on-call triage; a reconciliation finding can open an incident.
- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`, `aws-networking-audit`: cloud-side inventory to reconcile a hybrid SoT against.
- `secrets-hygiene`: SoT MCP servers authenticate with API tokens (NETBOX, NAUTOBOT_TOKEN, INFRAHUB_API_TOKEN); handle them per the hygiene discipline, never inline in code.
- `systematic-debugging`: when a reconciliation finding is itself the symptom of a deeper fault, diagnose root cause before remediating.
- ServiceNow change/incident workflow and network-topology-discovery: critical reconciliation findings route to change tickets, and CDP/LLDP topology overlaps with discovery work; both are forthcoming vault skills, cross-referenced once they land.

## Red flags

- Auto-correcting a device or the SoT to resolve a discrepancy without explicit human approval. The golden rule is non-negotiable.
- Treating live device output as authoritative over the SoT (or vice versa) without deciding which is actually correct for each finding.
- Querying a SoT platform without first discovering its schema (Infrahub) or valid filters: guessing kind names or filter syntax wastes round-trips.
- Mutating Infrahub `main` directly instead of creating a branch for the change.
- Ignoring VRF scope on overlapping address space: the same IP can exist in multiple VRFs, so an unfiltered query conflates them.
- Reconciling without a UTC-timestamped report and stable finding IDs, so the audit trail cannot be followed later.

## Bottom line

Pick the SoT platform that fits the estate, load its reference for tool depth, and frame every reconciliation around the gap between intended and actual state. Report and ticket discrepancies by severity; never auto-correct without a human in the loop.
