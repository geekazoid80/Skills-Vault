---
name: igp-routing-analysis
description: "Use for any IGP-related diagnostic, change review, or design pass across the OSPF / EIGRP / IS-IS family on Cisco (IOS / IOS-XE / NX-OS / IOS-XR), Juniper (JunOS), or Arista (EOS). Family-aware skill that routes to per-protocol depth (references/ospf.md, references/eigrp.md, references/isis.md) and owns the cross-cutting material (mutual IGP redistribution, IGP-then-BGP sequencing, protocol-selection trade-offs, migration patterns). Triggers include \"OSPF adjacency not forming\", \"OSPF MTU mismatch\", \"OSPF stuck in EXSTART / EXCHANGE / Loading\", \"missing OSPF routes\", \"OSPF area design\", \"OSPF NSSA / stub / totally stubby\", \"OSPF / BGP redistribution\", \"LSDB integrity\", \"MaxAge LSAs\", \"Area 0 discontinuity\", \"virtual link\", \"EIGRP neighbour not forming\", \"EIGRP stuck in active\", \"stuck-in-active\", \"SIA timer expired\", \"SIA-Query\", \"K-value mismatch\", \"EIGRP DUAL\", \"feasible successor missing\", \"EIGRP route missing\", \"EIGRP suboptimal path\", \"EIGRP redistribution loop\", \"EIGRP variance\", \"EIGRP query scope\", \"EIGRP stub\", \"named EIGRP migration\", \"classic to named EIGRP\", \"IS-IS adjacency not forming\", \"IS-IS stuck in Init\", \"LSPDB inconsistency\", \"LSPDB mismatch between neighbours\", \"LSP purge\", \"LSP war\", \"system ID conflict\", \"NET address invalid\", \"AFI 49\", \"level 1 / level 2 routing\", \"L1 / L2 boundary\", \"route leaking IS-IS\", \"Attached bit\", \"ATT bit not set\", \"overload bit\", \"OL bit\", \"DIS election\", \"DIS preemption\", \"pseudonode LSP\", \"metric style narrow\", \"metric style wide\", \"IGP redistribution loop\", \"mutual IGP redistribution\", \"OSPF to IS-IS migration\", \"IS-IS to OSPF migration\", \"IGP-then-BGP sequencing\", \"stabilise the IGP first\", \"which IGP should we use\", \"OSPF vs IS-IS\", \"OSPF vs EIGRP\", \"IGP authentication\", \"IGP route-tag policy\". Multi-vendor syntax labels: [IOS / IOS-XE / NX-OS], [IOS-XR], [JunOS], [EOS] where commands diverge. Diagnose-first; read-only `show` / `display` evidence before any state-changing command. Maps onto `multi-vendor-network-ops` 9-element response contract for production-impacting changes. Cross-refs `bgp-analysis` for IGP-then-BGP sequencing during maintenance windows. Folded from three predecessor vault skills (ospf-analysis + eigrp-analysis + isis-analysis), all customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0)."
license: Apache-2.0
metadata:
  version: 2.0.0
---

# IGP Routing Analysis

Protocol-reasoning-driven diagnostic skill for the interior gateway protocol family: OSPF (link-state), IS-IS (link-state), and EIGRP (distance-vector / DUAL). Unlike device health checks that compare counters against thresholds, IGP analysis interprets neighbour / adjacency state machines, walks LSA / LSP / topology-table flooding scope, and validates area / level / AS topology across the control plane.

This skill is the family-level entry point. Per-protocol depth lives in `references/ospf.md`, `references/eigrp.md`, and `references/isis.md`. The umbrella body covers the protocol-selection decision tree and the cross-cutting concerns that span more than one IGP: mutual redistribution loops, IGP-then-BGP sequencing, migration patterns between IGPs, and the per-vendor protocol-availability matrix.

The `multi-vendor-network-ops` umbrella stays the entry point for general network work; this skill loads when the work is specifically IGP routing.

> **Skill marker**: When applying this skill, begin your reply with `[skill: igp-routing-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Protocol-selection decision tree

```
Which IGP is in play?
├── Network is single-vendor Cisco AND has EIGRP configured?
│   ├── IOS-XE classic mode (router eigrp [AS-number]) OR named mode (router eigrp [name])?
│   ├── NX-OS named-only mode (feature eigrp; router eigrp [tag])?
│   └── → references/eigrp.md (DUAL / SIA / K-values / wide metrics)
│       NOTE: IOS-XR does NOT implement EIGRP. Juniper and Arista do NOT either.
│
├── Network is multi-vendor (Cisco + Juniper + Arista mix) OR enterprise scale?
│   ├── OSPFv2 (IPv4) or OSPFv3 (IPv6)?
│   ├── Single-area-flat, multi-area-hierarchical, or stub / NSSA / totally-stubby?
│   └── → references/ospf.md (FSM / area design / LSDB / SPF / virtual links)
│
├── Service-provider core OR DC underlay using IS-IS?
│   ├── IOS-XR (dominant SP platform), JunOS (mixed SP / DC), or EOS (DC underlay)?
│   ├── L1-only, L2-only, or L1 / L2 router roles per device?
│   └── → references/isis.md (adjacency FSM / NET / LSPDB / level 1-2 leaking / DIS election)
│
└── Migration or coexistence?
    ├── OSPF ↔ IS-IS migration → both references/ospf.md AND references/isis.md
    ├── Classic EIGRP → named EIGRP → references/eigrp.md (named-mode migration section)
    ├── Narrow → wide IS-IS metrics → references/isis.md (metric style transition)
    └── Mutual redistribution between IGPs → § "Mutual IGP redistribution" below
```

## Vendor-platform matrix

Which IGPs run on which platforms:

| Platform | OSPFv2 / v3 | EIGRP | IS-IS | Notes |
|---|---|---|---|---|
| Cisco IOS / IOS-XE | yes | yes (classic + named) | yes | full IGP-trio support |
| Cisco NX-OS | yes | yes (named-only; `feature eigrp` required) | yes | EIGRP classic mode unavailable |
| Cisco IOS-XR | yes | **NO** | yes | EIGRP not implemented; IS-IS is dominant |
| Juniper JunOS | yes | **NO** | yes | EIGRP is Cisco-proprietary |
| Arista EOS | yes | **NO** | yes | EIGRP is Cisco-proprietary |

Implication: if the network mixes Cisco with Juniper or Arista, EIGRP is not a viable choice for the multi-vendor segment. OSPF or IS-IS is required. IOS-XR cores almost always run IS-IS by convention; enterprise mixed estates almost always run OSPF.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the IGP design (per-protocol: areas / levels / AS topology; redistribution boundaries; route-leaking policy; authentication scope) before reading neighbour / adjacency state. Only ask the user for information not already covered or specific to this investigation.

Before walking neighbour / adjacency state, understand:

1. **Design context** (per IGP, see references/<protocol>.md for protocol-specific design questions)
   - Vendor(s) and OS version(s) on the affected device(s)?
   - Which IGP(s) are running on the device; if multiple, what is the role split?
   - Are there redistribution edges between IGPs, or between an IGP and BGP / static?
2. **Symptom and timing**
   - Adjacency / neighbour failing to form, or formed but flapping?
   - Routes missing, or installed but on a suboptimal path?
   - When did the change start; what config or event correlates?
3. **Evidence on hand**
   - Read-only access to per-protocol `show` / `display` output, the device's IGP databases, interface state?
   - Recent config diffs affecting timers, MTU, authentication, network type, area / level / AS configuration, redistribution?

## When to use

- Any single-protocol IGP diagnostic (route to references/<protocol>.md for the per-protocol procedure).
- Mutual IGP redistribution review (this umbrella; § "Mutual IGP redistribution" below).
- IGP-vs-IGP protocol-selection conversations (this umbrella; § "Protocol-selection decision tree" above).
- IGP migration windows (OSPF ↔ IS-IS, classic → named EIGRP, narrow → wide IS-IS metrics): use this umbrella as the entry point, then the per-protocol reference(s) for depth.
- IGP-then-BGP sequencing decisions (this umbrella; § "IGP-then-BGP sequencing" below; depth in `bgp-analysis`).
- Post-change verification spanning more than one IGP (e.g. verifying an OSPF area change did not destabilise the EIGRP stub topology on the same routers).

## Do NOT use this skill for

- Generic "what is OSPF / EIGRP / IS-IS" tutoring.
- BGP work (use `bgp-analysis`).
- Layer 2 work (use `multi-vendor-network-ops` diagnose table).
- ACL / NAT / policy walks (use `acl-rule-analysis`).
- Pure pyATS / Genie automation around IGPs (use `pyats-network-automation` for the framework; combine with this skill for IGP semantics).

## Mutual IGP redistribution (cross-cutting)

Mutual redistribution between two IGPs (OSPF ↔ EIGRP, OSPF ↔ IS-IS, EIGRP ↔ IS-IS) is the most common source of silent routing loops in mixed-IGP networks. Each redistribution edge is bidirectional in policy intent but unidirectional in mechanism: every direction needs its own metric, its own filter, and its own loop-prevention strategy.

**Iron rule: route-tag policy on BOTH sides of every redistribution edge.** Tag IGP-A-originated routes on the way into IGP-B; deny those tags on re-entry into IGP-A from IGP-B. A tag policy on one side does not protect the other; the missing direction is where the loop lands.

Companion controls (use alongside route tags, not as substitutes):

- **Administrative distance separation.** OSPF AD 110, IS-IS AD 115, EIGRP internal AD 90 / external AD 170, BGP eBGP AD 20. Where the same prefix exists from multiple sources, the lower AD wins. Plan AD interactions explicitly at every redistribution edge.
- **Prefix-list filters.** Tag-based loop prevention can fail if tags are stripped by a transit device; prefix-list filtering at the redistribution edge is the belt to the tag's braces.
- **Metric translation.** OSPF Type 1 / 2, IS-IS internal / external, EIGRP internal / external (D EX) all carry distinct metric semantics. Translate metrics explicitly per direction so downstream path selection remains deterministic.
- **Route-map filters.** Apply at every redistribution point on both sides; verify with `show route-map` and confirm the policy is applied to the redistribute statement.

Per-protocol redistribution mechanics live in references/<protocol>.md. The discipline above is invariant across IGP pairs.

## IGP-then-BGP sequencing (cross-cutting)

Iron rule: **stabilise the IGP first, then BGP.** Any maintenance window that touches both IGP and BGP on the same device must complete the IGP work and verify IGP convergence (per references/<protocol>.md) before any BGP edit. BGP next-hop resolution depends on the IGP; an unstable IGP makes every BGP path selection unreliable, and BGP churn re-triggers SPF computations that the IGP needs to settle.

Sequencing recipe:

1. Plan IGP changes as one chunk (per `plan-time-tooling`'s `engineering:deploy-checklist` mandatory trigger for production-impacting changes).
2. Apply IGP changes; verify per references/<protocol>.md Step 5 (SPF / DUAL / LSPDB convergence assessment).
3. Confirm zero SIA / no LSDB mismatch / SPF run rate within norm (per per-protocol threshold tables).
4. Only then proceed to BGP edits per `bgp-analysis`.

If the IGP destabilises mid-window, **back out IGP changes before touching BGP**. Do not stack BGP work on a still-converging IGP.

## Migration patterns (cross-cutting)

| Migration | Approach | Critical control |
|---|---|---|
| OSPF → IS-IS (or reverse) | Run both in parallel during migration; selective redistribution at boundaries with tag-based loop prevention | Per-prefix audit at cutover; explicit cutover order (per area / per region, not big-bang) |
| Classic EIGRP → named EIGRP | Coexists in same AS; named-mode adds wide metrics + HMAC-SHA-256 auth | Validate metric parity before retiring classic (wide-metric scaling differs above 10G) |
| Narrow → wide IS-IS metrics | Transition mode (both narrow and wide TLVs) on every router for the duration; remove transition after all routers carry wide | Domain-wide consistency required; partial conversion diverges SPF results |
| Single-topology → multi-topology IS-IS (IOS-XR) | Decide one mode for the domain; mixing single + multi breaks SPF silently | All routers in the level must agree; verify TLV consistency |

Use the per-protocol references for the migration-specific commands and verification gates.

## Cross-references

- `multi-vendor-network-ops`: umbrella entry-point for general network work; the 9-element response contract is the iron rule for any production-impacting IGP advice. The "Routing convergence risk" diagnose-table row routes here.
- `bgp-analysis`: BGP protocol-depth specialist. Sequence: IGP first (this skill), then BGP. Mutual IGP / BGP redistribution requires explicit metric and route-map control on both sides.
- `acl-rule-analysis`: when "adjacency not forming" turns out to be an ACL block on IGP multicast (OSPF 224.0.0.5 / 6; EIGRP 224.0.0.10; IS-IS L2 multicast 01:80:C2:00:00:14 / 15), the rule walk lives there. IS-IS runs directly over Layer 2, not over IP, so IPv4 ACLs do not block it but L2 ACLs and MAC filters do.
- `pyats-network-automation`: pyATS / Genie can parse IGP `show` output into structured form for automated baseline diff, convergence measurement, LSPDB consistency checks, and SIA-event detection.
- `systematic-debugging`: Phase 1 boundary evidence (interface vs IGP process vs LSDB / topology table vs SPF / DUAL vs RIB) is the diagnose-before-generate pattern; use it especially when symptoms are ambiguous.
- `oncall-runbooks`: when an IGP issue becomes an incident, runbook structure applies (severity classification, mitigation-vs-resolution, blameless postmortem with UTC timeline).
- `secrets-hygiene`: IGP authentication keys (OSPF simple / MD5 / key-chain; EIGRP MD5 / HMAC-SHA-256; IS-IS MD5 / HMAC-SHA-256 / key-chain) are secrets. Never repeat them in responses; redact when pasted.
- `completion-gate` Layer 3: no claim of "IGP convergence done", "adjacency / neighbour up", "redistribution clean", "area / level / AS design changed" without fresh post-checks in this turn.
- `plan-time-tooling`: any state-changing IGP work fires the `engineering:deploy-checklist` mandatory trigger. Plan it as a chunk; do not freelance.

## Red flags (cross-cutting)

Per-protocol red flags live in references/<protocol>.md. Cross-cutting red flags:

- About to add mutual redistribution between two IGPs without route-tag policy on **both sides** and an explicit loop-prevention strategy (administrative distance separation, prefix-list, or tag-based).
- About to touch BGP on the same router without first stabilising the IGP (per `bgp-analysis` sequencing).
- About to start an IGP-to-IGP migration (OSPF ↔ IS-IS) without per-prefix audit at cutover; big-bang migrations fail silently.
- About to migrate IS-IS metric style (narrow ↔ wide) without configuring transition mode first; partial conversion diverges SPF results across the domain.
- About to enable IOS-XR multi-topology on one router but not the rest of the IS-IS domain; mixed-topology breaks SPF silently.
- About to redistribute large external route tables into an IGP without route-policy bounds; LSDB / topology-table inflation pushes SPF / DUAL load past safe operating range (and IS-IS approaches the 256-fragment ceiling per system ID).
- About to repeat any IGP authentication key from a pasted config in your response.
- About to declare IGP done without post-checks (per `completion-gate` Layer 3).

## Bottom line

Diagnose-first; the per-protocol state machine (OSPF FSM, IS-IS adjacency FSM, EIGRP DUAL) is the failure-domain signal, route to references/<protocol>.md for depth. The umbrella owns three cross-cutting invariants: route-tag policy on both sides of every IGP-to-IGP redistribution edge; IGP-then-BGP sequencing during any combined maintenance window; explicit migration transition modes (never partial cutover). Verify with read-only `show` / `display` evidence before any state-changing command. Production-impacting changes always emit the 9-element response contract per `multi-vendor-network-ops`.
