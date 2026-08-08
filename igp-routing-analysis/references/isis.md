# IS-IS, protocol depth

Per-protocol reference loaded by `igp-routing-analysis/SKILL.md`. Owns IS-IS-specific procedure (adjacency FSM, NET address validation, LSPDB integrity, level 1 / 2 routing and leaking), threshold tables, decision trees, report template, and protocol-specific failure modes. Cross-cutting material (mutual IGP redistribution, IGP-then-BGP sequencing, migration patterns, family-level cross-refs) lives in the umbrella SKILL.md, not here.

IS-IS is the dominant IGP in service-provider cores, and Cisco IOS-XR is the dominant SP platform, so IOS-XR gets prominent treatment alongside the other supported platforms (Cisco IOS / IOS-XE / NX-OS, Juniper JunOS, Arista EOS). Commands are labelled `[IOS / IOS-XE / NX-OS]`, `[IOS-XR]`, `[JunOS]`, or `[EOS]` where syntax diverges. Where IOS-XR uses different syntax (the IS-IS surface diverges notably between IOS-XR and the classic IOS family), it is called out separately. Unlabelled statements apply across all vendors.

## Initial Assessment

Before walking adjacency state, understand:

1. **Design context**
   - Vendor(s) and OS version(s) on the affected device(s)? (IOS-XR is the SP-core default; IOS / IOS-XE / NX-OS are typical for enterprise IS-IS deployments; JunOS for mixed SP / DC; EOS for DC underlays.)
   - L1-only, L2-only, or L1 / L2 router roles per device?
   - Area addresses in use; is the design single-area-flat, hierarchical (L1 areas attached to L2 backbone), or multi-area-flat with all L2?
   - Route-leaking configured (L2 specifics into L1 for optimal egress)?
   - Metric style (narrow / wide / transition)?

2. **Symptom and timing**
   - Adjacency Down (no hellos received) vs Init (one-way) vs Up but no routes?
   - LSPDB mismatch (LSP counts differ across neighbours in the same level)?
   - LSP purge cycle (continuous purge / regenerate cycle) suggesting system ID conflict?
   - Suboptimal routing (L1-only routers taking wrong egress via default route)?
   - When did the symptom start; what change correlates (interface flap, NET edit, redistribution edit, auth rollout)?

3. **Evidence on hand**
   - Read-only access to `show isis neighbors` / `show isis adjacency` (vendor-dependent), LSPDB detail, interface state?
   - Recent config diffs affecting NET address, circuit type, metric style, authentication, redistribution, route-leaking policy?

## When to use (IS-IS-specific)

- IS-IS adjacency not forming, or stuck in Init / Down state.
- Adjacency Up but expected routes missing.
- Level 1 / 2 boundary issues: suboptimal routing through wrong egress, missing L1 default, route leaking not working as intended.
- LSPDB inconsistency: LSP count mismatch between neighbours, unexpected purges, sequence-number anomalies.
- NET address conflict or system ID duplication causing LSP wars.
- Post-change verification of IS-IS configuration (new interfaces, area changes, metric style migration, authentication rollout).
- DIS election not converging on broadcast segments.

## Prerequisites

- Read-only access to the device (SSH, console, or parsed telemetry).
- IS-IS process running on the device with at least one active interface.
- Knowledge of expected level topology: which routers are L1-only, L2-only, or L1 / L2; which areas (area addresses) are in use.
- System IDs and NETs known or documented. NET format is `AFI.areaID.systemID.NSEL` (for example `49.0001.1921.6800.1001.00`).
- Awareness of configured authentication per level and per interface (none, MD5, HMAC-SHA-256).
- For IOS-XR: knowledge of which address-families are configured (ipv4 unicast, ipv6 unicast, multi-topology vs single-topology).

## Procedure

Sequential. Each step builds on data from prior steps. Broad inventory first, then targeted diagnosis.

### Step 1: IS-IS instance and interface inventory

Verify IS-IS is running and confirm which interfaces participate at each level.

`[IOS / IOS-XE / NX-OS]`
```
show isis interface brief
show isis protocol
```

`[IOS-XR]`
```
show isis interface brief
show isis
```

`[JunOS]`
```
show isis interface
show isis overview
```

`[EOS]`
```
show isis interface brief
show isis summary
```

Record each interface: level enablement (L1, L2, or L1 / L2), circuit type (point-to-point or broadcast), metric, hello interval, hold time. Compare against expected design; every interface that should participate must appear. An interface missing from output means IS-IS is not enabled on it (missing under the IS-IS router config or interface config).

Verify the NET address. On IOS / IOS-XE / NX-OS it appears in `show isis protocol`. On IOS-XR the configuration is under `router isis [tag]` and the operational view is `show isis`. On JunOS the equivalent is `show isis overview`; on EOS, `show isis summary`. The NET must be correctly formed and unique within the IS-IS domain. NET validation belongs to Step 3; here we just confirm one exists per IS-IS instance.

### Step 2: Adjacency assessment

List all IS-IS adjacencies and interpret their state.

`[IOS / IOS-XE / NX-OS]`
```
show isis neighbors
show isis neighbors detail
```

`[IOS-XR]`
```
show isis adjacency
show isis adjacency detail
```

`[JunOS]`
```
show isis adjacency
show isis adjacency detail
```

`[EOS]`
```
show isis neighbors
show isis neighbors detail
```

Compare the adjacency list against expected topology. For each adjacency, verify:

- **State**: Up is healthy. Init means one-way (hellos received but this router's SNPA / system ID not in the neighbour's hello). Down means no hellos received at all.
- **Level match**: L1 neighbours must share at least one area address. L2 neighbours may sit in different areas; only system ID uniqueness is required. An L1-only router will not form an L2 adjacency with an L2-only router.
- **Circuit type**: On broadcast segments, check DIS (Designated Intermediate System) election. Unlike OSPF DR / BDR, IS-IS DIS election is **preemptive**: a new router with higher priority takes over the DIS role immediately, no DR-stickiness to honour.
- **DIS status**: on broadcast segments, identify which router is DIS for each level. The DIS sends CSNPs every 10 seconds and originates the pseudonode LSP.

Adjacency FSM detail:

| State | Meaning | Common causes |
|---|---|---|
| Down | No hellos received from neighbour | Interface down; IS-IS not enabled remote side; ACL blocking; encapsulation mismatch |
| Init | Hellos received but this router's identity not echoed back | Level mismatch; area mismatch for L1; authentication mismatch; MTU drop preventing hello return; circuit-type mismatch (P2P vs broadcast) |
| Up | Bidirectional; LSPDB sync proceeding | Healthy. Routes follow LSPDB consistency. |

### Step 3: NET address validation

Verify NET format and system ID uniqueness across the domain.

`[IOS / IOS-XE / NX-OS]`
```
show isis protocol | include NET|System
```

`[IOS-XR]`
```
show isis | include NET|System
```

`[JunOS]`
```
show isis overview | match "NET|System"
```

`[EOS]`
```
show isis summary | include NET|System
```

Validate NET structure (`AFI.areaID.systemID.NSEL`):

- **AFI (Authority and Format Identifier)**: typically `49` for private IS-IS domains. Must be consistent within the domain.
- **Area ID**: variable length. All L1 neighbours must share at least one area address to form L1 adjacency. L1 / L2 and L2-only routers may have different area addresses and still form L2 adjacency.
- **System ID**: 6 bytes; must be globally unique within the IS-IS domain. Duplicate system IDs cause **LSP wars**: both routers originate LSPs with the same system ID but different content, triggering continuous purge / regenerate cycles.
- **NSEL (N-Selector)**: must be `00` for the router itself. A non-zero NSEL identifies an upper-layer protocol endpoint, not the router.

Example valid NET: `49.0001.1921.6800.1001.00`. Common errors: wrong AFI (using `47` or `39` by mistake), system ID derived inconsistently across the domain (some routers use loopback-IP-derived system IDs, others use serial-number-derived), NSEL set to non-zero.

### Step 4: LSPDB analysis

Examine the Link-State Protocol Data Unit database for integrity.

`[IOS / IOS-XE / NX-OS]`
```
show isis database
show isis database detail | include LSP|Lifetime|Sequence
```

`[IOS-XR]`
```
show isis database
show isis database detail
```

`[JunOS]`
```
show isis database
show isis database extensive
```

`[EOS]`
```
show isis database
show isis database detail
```

Assess LSPDB health:

- **LSP count per level**: compare across neighbours in the same level. Counts must match (LSPDB synchronisation invariant). Mismatch indicates flooding failure or area partition.
- **Remaining lifetime**: default maximum is 1200 seconds; originating routers refresh at 900 seconds (default). An LSP with lifetime near 0 that is not being refreshed indicates the originator is unreachable. Lifetime at 0 means the LSP is being purged.
- **Sequence numbers**: must increase monotonically per system ID. Backward jump in sequence number indicates a router restarted and is re-originating from a lower starting point, or there is a system ID conflict.
- **LSP purges**: an LSP with remaining lifetime of 0 and empty TLV content is a purge. Frequent purges for the same system ID indicate instability: the originator is flapping, or two routers share the system ID (LSP war).
- **Overload bit (OL)**: if set, SPF will not use this router for transit traffic. Check whether OL is intentional (maintenance, startup delay, memory-protection policy) or symptomatic (memory exhaustion, BGP-not-converged hold).
- **Pseudonode LSP**: on broadcast segments, the DIS originates a pseudonode LSP representing the segment. Missing pseudonode LSP indicates DIS election failed or DIS is not flooding correctly.
- **LSP fragmentation**: each system ID can originate up to 256 LSP fragments (fragment IDs 0 to 255). If fragment 255 fills, no further LSPs can be advertised by that system ID. Monitor fragment count on routers redistributing many external routes.

### Step 5: Level 1 / 2 routing and route leaking

Verify inter-level routing behaviour at L1 / L2 boundaries.

`[IOS / IOS-XE / NX-OS]`
```
show isis rib
show isis rib | include L1|L2|leak
```

`[IOS-XR]`
```
show route isis
show isis route-distribution
```

`[JunOS]`
```
show isis route
show route protocol isis table inet.0
```

`[EOS]`
```
show isis route
```

Validate inter-level behaviour:

- **L1 to L2 redistribution**: L1 / L2 routers automatically redistribute L1 routes into L2 by default. Verify L1 prefixes appear in the L2 LSPDB. If missing, check for redistribution filters or route policies on the L1 / L2 router.
- **L2 to L1 route leaking**: NOT automatic. Requires explicit configuration (a route-policy or distribute-list on the L1 / L2 router specifying which L2 prefixes to inject into L1). If configured, verify leaked L2 routes appear in the L1 RIB. Missing leaked routes indicate policy misconfiguration or the leak filter is too restrictive.
- **Attached bit (ATT)**: L1 / L2 routers set the Attached bit in their L1 LSP. L1-only routers use this signal to install a default route toward the nearest L1 / L2 router. If no L1 / L2 router has the Attached bit set, L1-only routers have no path out of the area. Verify by inspecting the LSP detail for L1 / L2 router LSPs and checking the ATT flag.
- **Suboptimal routing**: L1-only routers always route toward the nearest L1 / L2 router (default route). If there are multiple L1 / L2 exit points, traffic may take a suboptimal path. Fix by leaking specific L2 prefixes into L1, giving L1 routers prefix-level routing information rather than the blanket default.

## Threshold tables

Operational parameter norms for IS-IS: protocol-level expectations by network type and deployment scale.

Hello and hold defaults per vendor:

| Parameter | Cisco default | JunOS default | EOS default | Notes |
|---|---|---|---|---|
| Hello (broadcast) | 10s | 9s | 10s | Per-level configurable; DIS sends 3x faster |
| Hello (P2P) | 10s | 9s | 10s | Per-level configurable |
| Hold multiplier | 3 x hello | 3 x hello | 3 x hello | Hold = hello x multiplier |
| CSNP interval (DIS only) | 10s | 10s | 10s | DIS-only on broadcast |
| PSNP interval | 2s | 2s | 2s | Request missing LSPs |

LSPDB norms:

| Parameter | Normal | Warning | Critical |
|---|---|---|---|
| LSP max lifetime | 1200s | (constant) | (constant) |
| LSP refresh | every 900s | missed refresh | persistent purge cycle |
| LSP remaining lifetime | 300 to 1200s | 60 to 300s | less than 60s (near purge) |
| LSP purge rate | 0 per hour | 1 to 5 per hour | greater than 5 per hour |
| LSPDB count mismatch (neighbours, same level) | 0 LSP diff | 1 to 3 diff | greater than 3 diff |
| LSP fragment count per system ID | less than 50 | 50 to 200 | greater than 200 (approaching 256-fragment ceiling) |
| Overload bit (OL) | Clear | Set (intentional and brief) | Set (unintentional or persistent) |

SPF norms:

| Parameter | Normal | Warning | Critical |
|---|---|---|---|
| SPF runs (per hour) | 1 to 5 | 6 to 20 | greater than 20 |
| SPF initial delay | 50 to 200ms | less than 50ms (too aggressive) | greater than 5000ms (too slow) |
| SPF max hold | 5000 to 10000ms | less than 2000ms | greater than 50000ms |
| Convergence (single link) | less than 1s | 1 to 5s | greater than 10s |

Metric style:

| Metric style | Per-link range | Path-metric ceiling | Use when |
|---|---|---|---|
| Narrow (original; RFC 1195) | 1 to 63 | 1023 (10-bit) | Legacy domains only; avoid for new deployments |
| Wide (extended; RFC 5305) | 1 to 16,777,215 | 32-bit | Default for new deployments and any domain with high-bandwidth links |
| Transition (both TLVs) | both | both | Active migration from narrow to wide; remove transition mode after all routers carry wide |

## Decision tree: adjacency not forming

```
IS-IS adjacency not reaching Up state
├── State: Down (no hellos received)
│   ├── Interface up at L1 / L2? → Check show interfaces
│   ├── IS-IS enabled on interface? → Check IS-IS config on both sides
│   ├── Correct circuit type both sides? → P2P interface must match both sides
│   └── Hello reaching peer? → Check ACLs, VLAN, encapsulation, MAC filtering
│
├── State: Init (one-way hellos)
│   ├── Level mismatch?
│   │   ├── L1 requires shared area address → Compare area addresses in both NETs
│   │   ├── L2 allows different areas → Confirm both have L2 enabled
│   │   └── L1-only on one side, L2-only on the other → No common level, no adjacency
│   ├── Hello parameters?
│   │   ├── Authentication mismatch → Verify key and type per level
│   │   └── Hello interval incompatible → Hold time must exceed remote hello interval
│   ├── Circuit type mismatch?
│   │   ├── P2P vs broadcast both sides? → Must agree
│   │   └── Broadcast → DIS election proceeds after adjacency forms
│   ├── MTU issue?
│   │   ├── IS-IS does NOT negotiate MTU (unlike OSPF)
│   │   ├── Oversized hellos or LSPs silently dropped
│   │   └── Match interface MTU both sides; enable LSP padding inspection
│   └── System ID conflict?
│       └── Two routers with the same system ID prevent proper adjacency formation;
│           rapidly changing adjacency entries; LSP war (see LSPDB decision tree)
│
├── DIS election issue (broadcast only)
│   ├── DIS not elected? → Check priority (highest wins; tie broken by SNPA / MAC)
│   ├── DIS preemption observed? → Normal IS-IS behaviour
│   │   └── Higher-priority router takes DIS immediately on appearance
│   │       (unlike OSPF DR, which is sticky)
│   └── Pseudonode LSP missing? → DIS must originate pseudonode LSP for the segment
│
└── Adjacency flapping (Up to Down cycling)
    ├── Hello hold expiry → Packet loss or CPU overload starving hello generation
    ├── Authentication key rollover → Confirm key transition is overlapping
    │   (both old and new keys accepted during the change window)
    └── Interface errors → Check CRC, input errors, drops; suspect Layer 1 / 2
```

## Decision tree: LSPDB inconsistency

```
LSPDB mismatch or instability detected
├── LSP purge observed (lifetime = 0)
│   ├── System ID conflict (LSP war)?
│   │   ├── Two routers with the same system ID
│   │   ├── Both originate LSPs → Continuous purge and regenerate cycle
│   │   ├── Sequence numbers jump erratically → Confirms conflict
│   │   └── Fix: assign unique system IDs; audit NET addresses domain-wide
│   ├── Router departed gracefully? → Normal purge after shutdown / process restart
│   └── Router crashed and ageing out? → LSP ages to 0 over 1200s then purges
│
├── LSPDB count mismatch between neighbours (same level)
│   ├── MTU preventing LSP flooding?
│   │   ├── Large LSPs dropped silently (IS-IS does not negotiate MTU)
│   │   ├── Check interface MTU across the flooding path
│   │   └── Increase MTU or enable LSP fragmentation
│   ├── Partition? → L2 backbone split into two independent LSPDBs
│   │   ├── Verify L2 connectivity between all L2 routers
│   │   └── Check for failed L2 link isolating a segment
│   ├── Flooding blocked by authentication?
│   │   ├── Adjacency Up (hello auth passes) but LSPs rejected (LSP auth fails)
│   │   └── Verify auth config at both hello and LSP scope independently
│   └── L1 to L2 redistribution filtered unexpectedly?
│       └── Check route policy on L1 / L2 routers for over-restrictive filters
│
├── Overload bit (OL) set
│   ├── Intentional? → Maintenance mode, on-startup timer, BGP-not-converged hold
│   ├── Memory exhaustion? → Router cannot hold full LSPDB
│   └── Startup delay? → OL set for N seconds after process restart
│
└── Sequence number anomaly
    ├── Backward jump? → Router restarted, re-originating from lower seq
    ├── Rapid increment? → Frequent topology changes triggering re-origination
    └── Stuck at max (0xFFFFFFFF)? → Sequence wrap; extremely rare; requires
        process restart to recover (router originates a self-purge then resumes)
```

## Report template

For production-impacting IS-IS work, map findings onto the `multi-vendor-network-ops` 9-element response contract. The IS-IS-specific report skeleton:

```
IS-IS ANALYSIS REPORT
=====================
Device: [hostname]
Vendor: [IOS | IOS-XE | NX-OS | IOS-XR | JunOS | EOS]
IS-IS instance / tag: [tag]
System ID: [system-id]
NET: [full NET address]
Check time (UTC): [timestamp]
Performed by: [operator / agent]

ADJACENCY STATUS:
- Total adjacencies expected: [n]
- Up: [n]; Init: [n]; Down: [n]
- DIS role: [DIS for L1 and / or L2 on segment X, or none]
- Adjacencies requiring attention: [list with state, level, interface]

LEVEL TOPOLOGY:
- Levels configured: [L1 / L2 / L1 / L2]
- Area addresses: [list]
- Attached bit present on L1 LSP: [yes / no, per L1 / L2 router]

FINDINGS:
1. [Severity] [Category]: [Description]
   Neighbour or interface: [identifier]
   Observed: [state, level, metric]
   Expected: [normal state or value]
   Root cause: [diagnosis from decision tree]
   Action: [recommended remediation]

LSPDB SUMMARY:
- L1 LSP count: [n]; L2 LSP count: [n]
- LSP purges in last hour: [count; 0 is healthy]
- Overload bit set on any router: [yes / no, who]
- Lifetime anomalies: [near-expiry or stuck-at-0 LSPs]
- Fragment count outliers: [system IDs approaching the 256-fragment ceiling]

ROUTE ANALYSIS:
- L1 routes: [count]; L2 routes: [count]
- Route leaking configured (L2 into L1): [yes / no; policy summary]
- Suboptimal-routing risk: [yes / no; affected L1-only routers]

RECOMMENDATIONS:
- [Prioritised action list]

NEXT CHECK: [CRITICAL: 1 hr; WARNING: 8 hr; HEALTHY: 24 hr]
```

## Common failure modes (IS-IS-specific)

### System ID conflict (LSP war)

Two routers with the same system ID cause an LSP war. Each router originates an LSP with the same system ID but different content. Each then purges the other's LSP and regenerates its own, creating continuous churn. Symptoms: rapidly incrementing sequence numbers for one system ID, frequent purge events, unstable routing. Detect by checking for the same system ID with two different SNPAs or source addresses in adjacency tables. Fix: assign unique system IDs and audit NET addresses domain-wide.

### Area mismatch preventing L1 adjacency

L1 adjacency requires at least one matching area address in the NET. Two L1-only routers with different area addresses form no adjacency. L1 / L2 routers with different areas can still form L2 adjacency but not L1. Verify area addresses on both sides. Fix: correct the area address on one side, or change one router to L2-only if inter-area routing is the intent.

### MTU mismatch (silent LSP loss)

Unlike OSPF (which exchanges Database Description packets and detects MTU mismatch at adjacency formation), IS-IS does not negotiate MTU. An MTU mismatch is silent: the adjacency forms, but oversized LSPs are dropped on the smaller-MTU link. Symptom: LSPDB mismatch between two adjacent routers even though the adjacency is Up. Fix: match MTU on both sides; LSP padding (`hello-padding` on Cisco; `padding` on JunOS) can help surface MTU issues during adjacency formation.

### Metric style mismatch (narrow vs wide)

A router using narrow metrics (1 to 63 per link) and a neighbour using wide metrics (1 to 16,777,215 per link) may form adjacency but the routes may not compute correctly if one side cannot interpret the other's TLVs. During migration, configure transition mode (both narrow and wide TLVs advertised) on every router for the duration of the migration. Verify with LSPDB detail: check for both old-style and extended IP reachability TLVs. Remove transition mode after all routers carry wide.

### Authentication mismatch (hello vs LSP scope)

IS-IS supports per-level and per-interface authentication, and the scope splits into hello authentication and LSP authentication independently. A mismatch at hello scope prevents adjacency formation. A mismatch at LSP scope allows adjacency to form but blocks LSP flooding. Check auth config at both hello and LSP levels independently. Symptom of LSP-only mismatch: adjacency Up but LSPDB diverges.

### LSPDB overload from excessive redistribution

Redistributing large external route tables into IS-IS generates many LSPs, increasing LSPDB size, SPF computation time, and flooding overhead. Each system ID can originate up to 256 LSP fragments (0 to 255); approaching the ceiling means new prefixes cannot be advertised. Use route policies to limit redistribution scope. Consider setting the overload bit on non-transit routers that cannot handle the full LSPDB. Monitor LSP fragment count per system ID.

### IOS-XR address-family multi-topology gotcha

IOS-XR IS-IS supports both single-topology and multi-topology (MT) mode for IPv4 and IPv6. Mixing single-topology and multi-topology routers in the same level breaks SPF: routers advertise reachability in incompatible TLVs. Decide one mode for the domain and apply uniformly. The default in modern IOS-XR is single-topology IPv4; IPv6 requires explicit address-family configuration and either single-topology (one SPF for both AFs, requires identical metrics) or multi-topology (separate SPF per AF).

## Red flags (IS-IS-specific)

Cross-cutting IGP red flags live in the umbrella SKILL.md. IS-IS-specific red flags:

- About to bounce an IS-IS process (`clear isis *`, `restart isis`, `clear isis process`) without explaining the blast radius (every adjacency in the level resets; LSPDB rebuilds; transient routing gap).
- About to change a system ID on a live router during business hours; LSPs originated under the old ID purge while new-ID LSPs propagate, and any peer with stale state cannot reach the device until convergence completes.
- About to set the Overload bit (OL) on a transit router without confirming it is the intended behaviour; OL silently removes the router from SPF transit and causes traffic re-routing.
- About to add a new L1 / L2 router without checking the Attached bit propagation on the existing L1 / L2 routers; an inconsistent ATT bit can leave L1-only routers without a default route.
- About to change authentication keys at LSP scope without confirming hello scope is unaffected; you can leave adjacencies Up but LSPDB diverging.

## Bottom line (IS-IS-specific)

Adjacency state (Down / Init / Up) plus level match plus circuit type is the failure-domain signal. NET address validation is non-negotiable; system ID duplication causes silent LSP wars that destabilise the whole level. LSPDB count must match across neighbours in the same level; mismatch is always a real problem. IS-IS does not negotiate MTU, unlike OSPF, so MTU mismatches are silent and surface as LSPDB divergence rather than adjacency failure. L2 to L1 route leaking is not automatic and must be configured explicitly to fix suboptimal routing in multi-egress L1 areas.
