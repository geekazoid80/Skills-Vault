---
name: bgp-analysis
description: Use for any BGP-related diagnostic, change review, or peering design work across Cisco (IOS / IOS-XE / NX-OS / IOS-XR), Juniper (JunOS), or Arista (EOS). Triggers include "BGP neighbour not establishing", "BGP stuck in Idle / Connect / Active / OpenSent / OpenConfirm", "BGP route flap", "BGP convergence", "review this peering policy", "RPKI / route-server / IXP peering", "BGP route-reflector design", "iBGP full-mesh / RR migration", "AS-path / community / local-pref / MED policy", "graceful restart / non-stop routing", "BGP add-path / multipath", "BGP unexpected route selection", "JunOS sends no routes / missing export policy", "BGP route leak", "dampened / suppressed routes", "MD5 / TCP-AO mismatch". Six-step diagnostic procedure with peer-state and route-selection decision trees; threshold tables for neighbour state, prefix counts, holdtime / keepalive defaults per vendor. Multi-vendor syntax labels [Cisco] [JunOS] [EOS]. Diagnose-first; read-only `show` / `display` evidence before any state-changing command. Maps onto multi-vendor-network-ops 9-element response contract for production-impacting changes. Customised from vahagn-madatyan/netsec-skills-suite (Apache-2.0); references swapped to local vault skills.
metadata:
  version: 1.0.0
---

# BGP Analysis

Protocol-reasoning-driven diagnostic skill for BGP peering, path selection, and route propagation. Unlike device health checks (compare metrics against thresholds), BGP analysis interprets protocol state machines, walks the best-path algorithm, and validates policy application across the control plane.

This skill is the protocol-depth specialist. The `multi-vendor-network-ops` umbrella stays the entry point for general network work; this skill loads when the work is specifically BGP.

Commands are labeled `[Cisco]`, `[JunOS]`, or `[EOS]` where syntax diverges. Unlabeled statements apply to all three vendors.

> **Skill marker**: When applying this skill, begin your reply with `[skill: bgp-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the AS topology, peer relationships, and policy posture before reading session state. Only ask the user for information not already covered or specific to this BGP investigation.

Before walking session state, understand:

1. **Session and topology context**
   - Vendor(s) and OS version(s) of the affected device(s)?
   - eBGP, iBGP, or both? AS numbers involved?
   - Route-reflector or full-mesh topology for iBGP?

2. **Symptom and timing**
   - Session never established, just flapped, or stable but wrong prefixes?
   - When did the change start (correlates with what config edit or upstream event)?
   - Expected prefix counts and best-path outcomes?

3. **Policy and evidence**
   - Configured route-maps, prefix-lists, AS-path filters, community policies?
   - Read-only access to `show bgp` output and the routing-table state?
   - Recent change history (policy edits, peer adds, soft-reconfig)?

---

## When to use

- BGP peer reported down or stuck in a non-Established state.
- Suspected route leak: prefixes appearing in tables where they should not.
- Path selection not matching expectations after policy changes.
- Convergence too slow after planned maintenance or unplanned failover.
- Post-change verification of BGP configuration (new peers, policy updates, community changes).
- Capacity planning for prefix table growth or session scaling.
- Investigating asymmetric routing caused by inconsistent BGP attributes.
- IGP-then-BGP sequencing decisions during maintenance windows (see `igp-routing-analysis` for the IGP side).

## Do NOT use this skill for

- Generic "what is BGP" tutoring.
- Layer 2 work (use `multi-vendor-network-ops` diagnose table).
- ACL / NAT / policy walks (use `acl-rule-analysis`).
- Pure pyATS / Genie automation around BGP (use `pyats-network-automation` for the framework; combine with this skill for the BGP semantics).

## Prerequisites

- Read-only access to the device (SSH, console, or parsed telemetry).
- BGP process running with at least one configured peer.
- Knowledge of expected peer topology: which neighbours should be up, expected prefix counts, intended path-selection outcomes.
- Awareness of configured routing policy: route-maps, prefix-lists, community filters, AS-path access lists, local-preference assignments.
- For iBGP: understanding of the route-reflector or full-mesh topology.

## Procedure

Sequential. Each step builds on the data from prior steps. Broad inventory first, then targeted diagnosis.

### Step 1: Session inventory

Collect all peer states and compare against expected topology.

`[Cisco]`
```
show bgp ipv4 unicast summary
```

`[JunOS]`
```
show bgp summary
```

`[EOS]`
```
show ip bgp summary
```

Record each neighbour: address, AS number, state, prefixes received, up / down time. Compare against expected topology: every configured peer should appear. A peer missing from output means it was never configured or was removed. Any peer not showing a numeric prefix count is not Established; proceed to Step 2 for that peer.

### Step 2: Peer state diagnosis

For any peer not in Established state, the BGP FSM state reveals the failure domain. This is the core diagnostic reasoning step.

`[Cisco]`
```
show bgp ipv4 unicast neighbors [addr] | include state|last reset|error
```

`[JunOS]`
```
show bgp neighbor [addr] | match "State|Last Error|Last State"
```

`[EOS]`
```
show ip bgp neighbors [addr] | include state|last reset|error
```

Interpret the FSM state to isolate the failure:

- **Idle**: BGP process not attempting connection. Causes: administratively shut down, no route to peer address, configured remote AS does not match, or maximum-prefix limit hit triggering teardown.
- **Connect**: TCP SYN sent, waiting for response. Peer is unreachable at Layer 3, or a firewall is blocking TCP port 179.
- **Active**: TCP connection attempt failed, retrying. Same causes as Connect but the router has cycled back. Check ACLs blocking port 179, peer not configured for this neighbour, peer address unreachable.
- **OpenSent**: TCP connected, OPEN message sent, no reply. Remote end accepted TCP but is not sending OPEN; typically remote BGP not configured for this neighbour, or remote peer in admin shutdown.
- **OpenConfirm**: OPEN received but parameters rejected. Check AS number mismatch, capability negotiation failure (AFI / SAFI mismatch), hold timer negotiation failure, authentication (MD5 / TCP-AO) mismatch.

Check "last reset reason" and "last error" fields; they often provide the definitive cause.

### Step 3: Route table analysis

For Established peers, verify prefix exchange matches expectations.

`[Cisco]`
```
show bgp ipv4 unicast neighbors [addr] routes | include Total
```

`[JunOS]`
```
show route receive-protocol bgp [addr] table summary
```

`[EOS]`
```
show ip bgp neighbors [addr] received-routes | include Total
```

Compare received prefix count against baseline. Significant deviation indicates:

- Drop greater than 10 percent: upstream is withdrawing routes (maintenance, filter change, or failure).
- Increase greater than 10 percent: route leak or new prefixes originated upstream.
- Zero received: peer is Established but sending no routes (missing export policy on JunOS, or outbound filter on remote blocking everything).

Check advertised prefix count similarly; confirm this router is sending the expected number of routes to each peer.

### Step 4: Path selection verification

When traffic takes an unexpected path, walk the BGP best-path algorithm to identify which attribute is making the selection.

`[Cisco]`
```
show bgp ipv4 unicast [prefix] bestpath
```

`[JunOS]`
```
show route [prefix] detail | match "AS path|Local|MED|Weight|preference"
```

`[EOS]`
```
show ip bgp [prefix] detail
```

The best-path algorithm evaluates in this order (first difference wins):

1. **Weight** (Cisco / EOS local; highest wins. JunOS does not use weight.)
2. **Local Preference** (highest wins; default 100).
3. **Locally originated** (network / aggregate preferred over learned).
4. **AS Path length** (shortest wins).
5. **Origin** (IGP < EGP < Incomplete).
6. **MED** (lowest wins; compared only within same neighbour AS by default).
7. **eBGP over iBGP** (external preferred).
8. **IGP metric to next-hop** (lowest wins).
9. **Router ID** (lowest wins; tiebreaker).

Identify which attribute selects the current best path. If unexpected, check the route-map or policy applying that attribute on ingress.

### Step 5: Route filtering validation

Verify that route-maps, prefix-lists, and community filters apply as intended.

`[Cisco]`
```
show bgp ipv4 unicast neighbors [addr] policy
```

`[JunOS]`
```
show policy [policy-name] | display detail
```

`[EOS]`
```
show route-map [name]
```

For suspected route leaks: examine the RIB for prefixes that should not be present. Check inbound filters on the peer that is the source. Common leak causes: missing or misordered prefix-list entry, regex error in AS-path filter, community match that is too broad.

For missing routes: verify the outbound policy on the advertising peer is not filtering the prefix. On JunOS, a peer with no export policy sends nothing by default; this is the most common JunOS-specific omission.

### Step 6: Convergence assessment

Evaluate convergence behaviour and route stability.

`[Cisco]`
```
show bgp ipv4 unicast dampening dampened-paths
```

`[JunOS]`
```
show route damping suppressed
```

`[EOS]`
```
show ip bgp dampening dampened-paths
```

Check for dampened (suppressed) routes; these indicate persistent flapping. Review BGP update activity: high update / withdrawal rates indicate churn. After a planned change, measure convergence time from the change event to the last BGP update. Compare against the target convergence window.

## Threshold tables

Operational parameter norms for BGP. These are protocol-level expectations, not device resource thresholds.

| Parameter | Cisco default | JunOS default | EOS default | Notes |
|---|---|---|---|---|
| Hold timer | 180s | 90s | 180s | Negotiated to lower value |
| Keepalive interval | 60s | 30s | 60s | Hold / 3 by convention |
| ConnectRetry timer | 120s | varies | 120s | Time between TCP attempts |
| MRAI (eBGP) | 30s | 0s (immediate) | 30s | Minimum Route Advertisement Interval |
| MRAI (iBGP) | 5s | 0s | 5s | Lower than eBGP for faster iBGP convergence |
| Default local-pref | 100 | 100 | 100 | Same across vendors |

Table size norms (IPv4 unicast):

| Deployment type | Expected prefixes | Warning | Critical |
|---|---|---|---|
| Internet edge (full table) | ~950K | greater than 1M | greater than 1.1M |
| Internet edge (partial) | 5K to 100K | varies | per design |
| Enterprise WAN | 100 to 10K | greater than 2x baseline | greater than 5x baseline |
| Data centre leaf | 50 to 5K | greater than 2x baseline | greater than 5x baseline |

Convergence targets:

| Scenario | Target | Acceptable | Degraded |
|---|---|---|---|
| eBGP failover | less than 90s | 90 to 180s | greater than 180s |
| iBGP reconvergence | less than 30s | 30 to 60s | greater than 60s |
| Full table reload | less than 5min | 5 to 10min | greater than 10min |

## Decision tree: peer not Established

```
Peer not in Established state
├── State: Idle
│   ├── Admin shut? Check config for "neighbor shutdown" / "deactivate"
│   ├── No route to peer? Check IGP / static route to peer address
│   ├── Prefix-limit exceeded? Check logs for max-prefix teardown
│   └── AS mismatch? Verify "remote-as" matches peer's local AS
│
├── State: Connect / Active
│   ├── Peer reachable? Ping / traceroute peer address
│   │   ├── No: fix Layer 3 reachability (IGP, static route)
│   │   └── Yes: TCP port 179 blocked?
│   │       ├── ACL on local device? Check interface / control-plane ACL
│   │       ├── ACL on remote device? Check remote inbound ACL
│   │       └── Firewall between peers? Verify TCP/179 permitted both directions
│   └── Peer configured? Verify remote has this router as neighbour
│
├── State: OpenSent
│   ├── Remote not sending OPEN: peer may not be configured for this neighbour
│   ├── TCP resets after connect: check for TTL issues (eBGP multihop)
│   └── Authentication? Verify MD5 / TCP-AO passwords match both sides
│
├── State: OpenConfirm
│   ├── Capability mismatch? Check AFI / SAFI (IPv4 / IPv6 / VPNv4) match
│   ├── AS mismatch in OPEN? Verify configured AS matches OPEN AS
│   ├── Hold timer = 0 on one side? Both peers must agree, or both use 0
│   └── Check NOTIFICATION message; decode error code / subcode
│
└── Established but dropping
    ├── Hold timer expiry? Keepalives not arriving (CPU, QoS, path issue)
    ├── NOTIFICATION received? Decode error code for root cause
    ├── Route refresh storm? Peer sending excessive route-refresh requests
    └── Max-prefix limit? Peer sending more prefixes than limit allows
```

## Decision tree: unexpected route selection

```
Wrong path selected for prefix
├── Check Weight (Cisco / EOS only)
│   └── Weight set via route-map? Highest weight wins
├── Check Local Preference
│   └── Local pref differs? Set via inbound route-map; highest wins
├── Check AS Path length
│   ├── AS prepending applied? Verify prepend count
│   └── AS path differs? Shortest wins
├── Check Origin
│   └── IGP vs Incomplete? IGP (network statement) preferred
├── Check MED
│   ├── MED comparison enabled across AS? "always-compare-med"
│   └── MED set correctly? Lowest wins within same neighbour AS
├── Check eBGP vs iBGP
│   └── External path preferred over internal if equal above
├── Check IGP metric to next-hop
│   └── Closest exit wins (hot-potato routing)
└── All equal: lowest Router ID wins (or oldest route if stable)
```

## Report template

For production-impacting BGP work, map findings onto the `multi-vendor-network-ops` 9-element response contract (assumptions, risk category, evidence, recommendation, pre-checks, execution guidance, post-checks, rollback, escalation). The BGP-specific report shape below is a useful skeleton:

```
BGP ANALYSIS REPORT
====================
Device: [hostname]
Vendor: [Cisco | JunOS | EOS]
Check time (UTC): [timestamp]
Performed by: [operator / agent]

SESSION STATUS:
- Total configured peers: [n]
- Established: [n]; Not Established: [n]
- Peers requiring attention: [list with FSM states]

FINDINGS:
1. [Severity] [Category]: [Description]
   Peer: [neighbour address / AS]
   Observed: [state or metric]
   Expected: [normal state or value]
   Root cause: [diagnosis from decision tree]
   Action: [recommended remediation]

PATH ANALYSIS:
- Prefix: [prefix under review]
- Selected path via: [next-hop / AS path]
- Selecting attribute: [which best-path attribute decided]
- Expected path: [if different, what was expected and why]

ROUTE TABLE SUMMARY:
- IPv4 prefixes received: [total across all peers]
- Baseline deviation: [percent change from expected]

RECOMMENDATIONS:
- [Prioritised action list]

NEXT CHECK: [based on severity. CRITICAL: 4hr; WARNING: 24hr; HEALTHY: 7d]
```

## Common failure modes

### Session flapping

Peer cycles between Established and Idle / Active repeatedly. Common causes: unstable underlying transport (IGP flap, link errors), aggressive hold timers on congested control planes, MTU issues on the path causing fragmented keepalives to be dropped. Check `last reset reason` and correlate with interface or IGP events at the same timestamps.

### Route oscillation

The same prefix alternates between two or more paths. Caused by inconsistent MED comparison across route reflectors, or deterministic-MED not enabled when multiple exit points exist to the same neighbour AS. Enable `always-compare-med` and `deterministic-med` to stabilise.

### Memory pressure from full table

Full Internet table (~950K IPv4 prefixes) requires 1 to 2 GB of RIB memory depending on path diversity. Symptoms: slow convergence, peer resets during table reload. Mitigate with soft-reconfiguration inbound (trades memory for stability) or ORF (Outbound Route Filtering) to reduce inbound load.

### Community stripping

Routes arrive without expected communities. Check each transit AS in the path: many providers strip non-standard communities by default. Use large communities (RFC 8092) for end-to-end propagation across providers that strip standard communities.

### JunOS default export policy

JunOS sends no routes to a peer without an explicit export policy. If a peer shows Established with zero prefixes sent, add an export policy. This is the most common JunOS-specific BGP issue and does not occur on Cisco or EOS.

### eBGP multihop and TTL

Direct-eBGP defaults to TTL=1; multihop peerings need explicit `neighbor X ebgp-multihop N` (Cisco / EOS) or `multihop ttl N` (JunOS). Symptom: stuck in Connect / Active despite Layer 3 reachability.

## Cross-references

- `multi-vendor-network-ops`: umbrella entry-point for general network work; the 9-element response contract is the iron rule for any production-impacting BGP advice. The "Routing convergence risk" diagnose-table row routes here.
- `igp-routing-analysis`: IGP family (OSPF / EIGRP / IS-IS) protocol-depth specialist with per-protocol references. Sequence: stabilise the IGP first, then BGP. If you are touching both in the same change, do an IGP-clean window before any BGP work. Mutual IGP / BGP redistribution requires route-tag policy on both sides regardless of which IGP is in play. IS-IS is the dominant IGP in service-provider cores where BGP is the most operationally complex.
- `acl-rule-analysis`: when "BGP peer not establishing" turns out to be a TCP/179 ACL block, the rule walk lives there.
- `pyats-network-automation`: pyATS / Genie can parse BGP `show` output into structured form for automated baseline diff and convergence measurement.
- `systematic-debugging`: Phase 1 boundary evidence at the peer level (control-plane vs data-plane vs IGP) is the diagnose-before-generate pattern; use it especially when symptoms are ambiguous.
- `oncall-runbooks`: when a BGP issue becomes an incident, runbook structure applies (severity classification, mitigation-vs-resolution, blameless postmortem with UTC timeline).
- `secrets-hygiene`: peer authentication (MD5, TCP-AO) keys are secrets. Never repeat them in responses; redact when pasted.
- `completion-gate` Layer 3: no claim of "BGP convergence done", "peer up", "policy applied" without fresh post-checks in this turn.
- `plan-time-tooling`: any state-changing BGP work fires the `engineering:deploy-checklist` mandatory trigger. Plan it as a chunk; do not freelance.

## Red flags

- About to clear a BGP session (`clear ip bgp *`, `restart routing`, `clear bgp neighbour`) without explaining the blast radius.
- About to redistribute IGP-into-BGP or BGP-into-IGP without a route-map filter and a maximum-prefix safeguard.
- About to change MED, local-preference, or AS-prepend on a peering without a full policy audit and a rollback plan.
- About to add a new peer without confirming `remote-as`, address-family negotiation, and authentication parity with the remote side.
- About to lift a max-prefix safeguard (`maximum-prefix N restart M`) because it tripped, instead of investigating the prefix-count surge.
- About to recommend `next-hop-self` blanket-on or blanket-off without checking iBGP topology (RR vs full-mesh) and the data-plane next-hop reachability.
- About to advise enabling `always-compare-med` without confirming all PEs use the same comparison rule (creates oscillation otherwise).
- About to recommend `bgp graceful-restart` enable / disable without confirming both sides support the same flavour (helper, restarter, both).
- About to repeat an MD5 / TCP-AO key from a pasted config in your response.
- About to declare BGP done without post-checks (per `completion-gate` Layer 3).

## Bottom line

Diagnose-first. FSM state is the failure-domain signal; walk the best-path algorithm before guessing why a path was chosen; respect the JunOS default-export-policy trap; verify with read-only `show` / `display` evidence before any state-changing command. Production-impacting changes always emit the 9-element response contract per `multi-vendor-network-ops`. Sequence IGP work before BGP work in the same window per the `igp-routing-analysis` cross-reference.
