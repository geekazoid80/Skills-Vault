# OSPF, protocol depth

Per-protocol reference loaded by `igp-routing-analysis/SKILL.md`. Owns OSPF-specific procedure, threshold tables, decision trees, report template, and protocol-specific failure modes. Cross-cutting material (mutual IGP redistribution, IGP-then-BGP sequencing, migration patterns, family-level cross-refs) lives in the umbrella SKILL.md, not here.

Commands are labelled by platform where syntax diverges: `[IOS]`, `[IOS-XE]`, `[NX-OS]`, `[IOS-XR]` for the Cisco family (combined as `[IOS / IOS-XE / NX-OS]` where syntax is identical across the three CLI-similar platforms; `[IOS-XR]` is broken out separately because it drops the `ip` keyword from OSPF show commands and uses a different config hierarchy), `[JunOS]` for Juniper, `[EOS]` for Arista. Unlabelled statements apply to every vendor.

## Initial Assessment

Before walking neighbour state, understand:

1. **Design context**
   - Vendor(s) and OS version(s) on the affected device(s)?
   - OSPFv2 (IPv4) or OSPFv3 (IPv6); single area or multi-area?
   - Stub / NSSA / totally-stubby area boundaries?
   - ABR / ASBR roles; redistribution from / to BGP, EIGRP, static, connected?

2. **Symptom and timing**
   - Neighbour stuck in INIT / 2-WAY / EXSTART / EXCHANGE / LOADING (each implies a different root)?
   - Adjacency formed but LSDB inconsistent or routes missing?
   - When did the change start; what config or event correlates?

3. **Evidence on hand**
   - Read-only access to `show ip ospf neighbor`, LSDB, and interface state?
   - Recent config diffs affecting timers, MTU, authentication, network type?

## When to use (OSPF-specific)

- OSPF neighbour adjacency not forming or stuck in a non-Full state.
- Unexpected route changes or missing routes in the OSPF domain.
- Area design review: backbone connectivity, stub / NSSA configuration audit.
- SPF algorithm running too frequently (unstable link, flapping interface).
- Post-change verification of OSPF configuration (new interfaces, area changes, redistribution updates).
- LSDB growing unexpectedly or LSA age anomalies indicating flooding issues.
- Convergence too slow after planned maintenance or unplanned link failure.

## Prerequisites

- Read-only access to the device (SSH, console, or parsed telemetry).
- OSPF process running with at least one active interface.
- Knowledge of expected area topology: which routers are ABRs / ASBRs, which interfaces belong to which areas, expected neighbour relationships.
- Awareness of configured authentication type per area (none, simple, MD5).
- Router IDs known or deterministic (explicit configuration preferred over auto-selection from loopback / interface addresses).

## Procedure

Sequential. Each step builds on data from prior steps. Broad inventory first, then targeted diagnosis.

### Step 1: Instance and interface inventory

Verify OSPF is running and confirm which interfaces participate in each area.

`[IOS / IOS-XE / NX-OS]`
```
show ip ospf interface brief
```

`[IOS-XR]`
```
show ospf interface brief
```

`[JunOS]`
```
show ospf interface
```

`[EOS]`
```
show ip ospf interface brief
```

Record each interface: area assignment, network type (broadcast, point-to-point, NBMA), state (DR, BDR, DROther, Point-to-Point), cost, hello / dead timers. Compare against expected design: every interface that should participate must appear. An interface missing from output means OSPF is not enabled on it (missing `network` statement or `ip ospf` configuration). Verify area assignments match the design; a misassigned area creates a separate adjacency domain.

### Step 2: Neighbour state assessment

List all OSPF neighbours and interpret their FSM state.

`[IOS / IOS-XE / NX-OS]`
```
show ip ospf neighbor
```

`[IOS-XR]`
```
show ospf neighbor
```

`[JunOS]`
```
show ospf neighbor
```

`[EOS]`
```
show ip ospf neighbor
```

Compare the neighbour list against expected topology. Every directly connected OSPF router should appear. For each neighbour not in **Full** state, the FSM state reveals the failure domain:

- **Down**: no hellos received from this neighbour. Causes: interface down, OSPF not enabled on remote interface, ACL blocking multicast 224.0.0.5 / 6.
- **Attempt** (NBMA only): unicast hello sent, no reply. The neighbour is configured but not responding.
- **Init**: hellos received but this router's RID is not in the neighbour's hello. Causes: one-way communication (area ID mismatch, authentication mismatch, hello / dead timer mismatch, or MTU preventing return hellos).
- **2-Way**: bidirectional communication confirmed. On broadcast / NBMA networks, non-DR / BDR routers remain in 2-Way with each other. This is normal. Only DR / BDR pairs proceed to Full.
- **ExStart**: DR / BDR election complete, attempting to establish master / slave for database exchange. Stuck here equals **MTU mismatch** (most common cause), or DBD packet issues.
- **Exchange**: Database Description (DBD) packets being exchanged. Stuck here equals LSDB too large to synchronise, or DBD retransmission failures.
- **Loading**: LSR / LSU exchange in progress, retrieving missing LSAs. Stuck here equals unstable LSA flooding, or peer withdrawing LSAs during sync.

### Step 3: Area design validation

Verify OSPF area topology matches the intended design.

`[IOS / IOS-XE / NX-OS]`
```
show ip ospf | include Area|router
```

`[IOS-XR]`
```
show ospf | include Area|router
```

`[JunOS]`
```
show ospf overview
```

`[EOS]`
```
show ip ospf | include Area|router
```

Validate these design invariants:

- **Backbone connectivity**: Area 0 must be contiguous. If an ABR has area 0 interfaces that cannot reach other area 0 routers, a virtual link is required. Verify virtual links are up if configured.
- **ABR identification**: any router with interfaces in multiple areas is an ABR. Confirm ABR count matches design; unexpected ABRs indicate area misconfiguration.
- **ASBR identification**: routers performing redistribution into OSPF. Verify only intended routers are ASBRs; unplanned redistribution causes routing instability.
- **Stub / NSSA consistency**: all routers in a stub or NSSA area must agree on the area type. A mismatch prevents adjacency formation. NSSA areas generate Type 7 LSAs that ABRs translate to Type 5; verify translation is occurring.

### Step 4: LSDB analysis

Examine the Link-State Database for integrity and anomalies.

`[IOS / IOS-XE / NX-OS]`
```
show ip ospf database database-summary
```

`[IOS-XR]`
```
show ospf database database-summary
```

`[JunOS]`
```
show ospf database summary
```

`[EOS]`
```
show ip ospf database database-summary
```

Check LSA types and counts per area:

- **Type 1 (Router)**: one per router per area. Count should match router count.
- **Type 2 (Network)**: one per broadcast / NBMA segment with a DR. Count should match multi-access segment count.
- **Type 3 (Summary)**: generated by ABRs. High count in stub areas indicates summarisation not configured.
- **Type 4 (ASBR Summary)**: generated by ABRs to advertise ASBR reachability.
- **Type 5 (External)**: generated by ASBRs. Should not appear in stub areas. Unexpected Type 5 LSAs indicate redistribution issues.
- **Type 7 (NSSA External)**: NSSA equivalent of Type 5. Translated to Type 5 by the ABR at the NSSA boundary.

Check LSA age: maximum age is 3600 seconds; LSAs are refreshed at 1800 seconds. LSAs with age near 3600 that are not being refreshed indicate an originating router has lost reachability. LSAs with age stuck at 3600 (MaxAge) are being flushed from the LSDB; excessive MaxAge LSAs indicate instability.

### Step 5: SPF convergence assessment

Evaluate SPF calculation frequency and convergence behaviour.

`[IOS / IOS-XE / NX-OS]`
```
show ip ospf | include SPF
```

`[IOS-XR]`
```
show ospf | include SPF
```

`[JunOS]`
```
show ospf statistics
```

`[EOS]`
```
show ip ospf | include SPF
```

Check SPF run count and last execution time. Frequent SPF runs (more than once per minute sustained) indicate network instability: a flapping link or interface causing repeated LSA updates. Identify the trigger by checking the LSDB for recently updated LSAs (low age values).

Review SPF throttle timers: initial delay, secondary delay, maximum hold time. Aggressive timers (low initial delay) provide faster convergence but increase CPU load during instability. Conservative timers protect the CPU but delay convergence.

After a planned change, measure time from the change event to the last SPF run. Compare against the convergence target for the deployment type.

## Threshold tables

Operational parameter norms for OSPF: protocol-level expectations by network type and deployment scale.

Hello and Dead interval defaults:

| Network type | Hello interval | Dead interval | Notes |
|---|---|---|---|
| Broadcast | 10s | 40s | Default for Ethernet |
| Point-to-Point | 10s | 40s | Default for serial / P2P |
| NBMA | 30s | 120s | Requires neighbour statements |
| Point-to-Multipoint | 30s | 120s | No DR election |

All routers on a segment must agree on hello and dead intervals; mismatch prevents adjacency.

LSA norms:

| Parameter | Normal | Warning | Critical |
|---|---|---|---|
| LSA age | 0 to 1800s | 1800 to 3500s | 3600s (MaxAge) |
| LSA refresh | every 1800s | missed refresh | persistent MaxAge |
| Type 1 count per area | equals router count | greater than 2x routers | indicates duplicate RID |
| Type 5 count (enterprise) | 10 to 500 | greater than 1000 | greater than 5000 |
| Type 5 in stub area | 0 | any (design violation) | not applicable |

SPF norms:

| Parameter | Normal | Warning | Critical |
|---|---|---|---|
| SPF runs (per hour) | 1 to 5 | 6 to 20 | greater than 20 |
| SPF initial delay | 50 to 200ms | less than 50ms (too aggressive) | greater than 5000ms (too slow) |
| SPF max hold | 5000 to 10000ms | less than 2000ms | greater than 50000ms |
| Convergence (single link) | less than 1s | 1 to 5s | greater than 10s |

## Decision tree: adjacency not forming

```
Neighbour not reaching Full state
├── State: Down
│   ├── Interface up? Check Layer 1 / 2 status
│   ├── OSPF enabled on interface? Check network statement or ip ospf config
│   ├── Correct area? Compare area ID both sides
│   └── Multicast reachable? Check ACLs for 224.0.0.5 / 224.0.0.6
│
├── State: Init (one-way)
│   ├── Hello timer mismatch? Compare hello / dead intervals both sides
│   ├── Area ID mismatch? Must match exactly on shared segment
│   ├── Authentication mismatch? Verify type and key both sides
│   ├── Subnet mismatch? Interfaces must be on same subnet
│   └── MTU blocking return hellos? Check interface MTU both sides
│
├── State: 2-Way (expected on broadcast for DROther <-> DROther)
│   ├── Both routers DROther? Normal: Full only with DR / BDR
│   ├── DR / BDR election stuck? Check priority values, verify DR is up
│   └── Unexpected? Force DR election by clearing OSPF process (disruptive)
│
├── State: ExStart (most actionable stuck state)
│   ├── MTU mismatch? Compare MTU both sides (most common cause)
│   │   ├── IOS / IOS-XE / NX-OS: `ip mtu` (or `mtu`) at the interface; `ip ospf mtu-ignore` at the OSPF interface stanza
│   │   ├── IOS-XR: `mtu` at the interface; `mtu-ignore` under `router ospf <pid> area <id> interface <if>`
│   │   ├── JunOS: interface MTU settings
│   │   └── Fix: match MTU end-to-end, or enable mtu-ignore (workaround; papers over the real Layer 2 / 3 problem)
│   └── DBD packet issues? Check for packet drops, interface errors
│
├── State: Exchange
│   ├── LSDB too large? Reduce area scope, add summarisation
│   ├── DBD retransmissions? Check interface reliability, CRC errors
│   └── CPU overloaded? Check process CPU during exchange
│
└── State: Loading
    ├── LSAs being withdrawn during sync? Check for flapping neighbour
    ├── Incomplete LSR responses? Verify peer stability
    └── Timeout? Increase retransmit interval if link is slow
```

## Decision tree: missing or unexpected routes

```
Route not in routing table (or unexpected route present)
├── Missing route?
│   ├── LSA in LSDB? show ip ospf database [type] [id]
│   │   ├── LSA present: SPF did not install
│   │   │   ├── Better route via another protocol? Check admin distance
│   │   │   ├── Filtered by distribute-list? Check outbound filters
│   │   │   └── Next-hop unreachable? Verify forwarding address
│   │   └── LSA absent: not being advertised
│   │       ├── In stub area? Type 5 filtered by design (use NSSA or default route)
│   │       ├── ABR not summarising? Check area range / summary config
│   │       ├── Redistribution missing? Verify ASBR redistribute config
│   │       └── Originator down? Check originating router's OSPF status
│   └── Check area boundaries: ABR filtering or summarisation may exclude
│
└── Unexpected route?
    ├── Unexpected Type 5 LSA? Identify ASBR; check redistribution scope
    ├── Unexpected Type 7 to Type 5 translation? Check NSSA ABR behaviour
    ├── Route from wrong area? Verify area assignments on originator
    └── Duplicate router ID? Two routers with same RID cause LSA conflicts
```

## Report template

For production-impacting OSPF work, map findings onto the `multi-vendor-network-ops` 9-element response contract. The OSPF-specific report skeleton:

```
OSPF ANALYSIS REPORT
=====================
Device: [hostname]
Vendor / platform: [IOS | IOS-XE | NX-OS | IOS-XR | JunOS | EOS]
OSPF process ID: [process-id]
Router ID: [router-id]
Check time (UTC): [timestamp]
Performed by: [operator / agent]

ADJACENCY STATUS:
- Total neighbours expected: [n]
- Full: [n]; Non-Full: [n]
- Neighbours requiring attention: [list with FSM states]

AREA TOPOLOGY:
- Areas configured: [list with types: backbone, stub, NSSA, standard]
- ABR count: [n]; ASBR count: [n]
- Backbone contiguous: [yes / no]

FINDINGS:
1. [Severity] [Category]: [Description]
   Neighbour / Area: [identifier]
   Observed: [state or metric]
   Expected: [normal state or value]
   Root cause: [diagnosis from decision tree]
   Action: [recommended remediation]

LSDB SUMMARY:
- LSA counts by type: [Type 1: n, Type 2: n, ...]
- MaxAge LSAs: [count; 0 is healthy]
- LSA age anomalies: [any near-expiry LSAs]

SPF STATUS:
- Last SPF run (UTC): [timestamp]
- SPF runs in last hour: [count]
- Convergence assessment: [healthy / warning / critical]

RECOMMENDATIONS:
- [Prioritised action list]

NEXT CHECK: [CRITICAL: 1hr; WARNING: 8hr; HEALTHY: 24hr]
```

## Common failure modes (OSPF-specific)

### MTU mismatch (ExStart stuck)

The most common OSPF adjacency failure. Neighbours reach ExStart but cannot proceed because DBD packets exceed the smaller MTU and are dropped. Fix by matching MTU on both sides. Workaround: `ip ospf mtu-ignore` (IOS / IOS-XE / NX-OS / EOS) or `mtu-ignore` under the OSPF interface stanza (IOS-XR) skips the check but may cause fragmentation issues downstream. On JunOS, set matching MTU values at the interface level.

### Duplicate router IDs

Two routers with the same Router ID cause LSA conflicts; each router's Type 1 LSA overwrites the other's in the LSDB. Symptoms: routes flapping, intermittent reachability. Fix: assign unique router IDs explicitly. Detect by checking for Type 1 LSAs with the same Link State ID but different advertising routers.

### Area 0 discontinuity

If area 0 is split, inter-area routing breaks; ABRs cannot flood Type 3 LSAs across the gap. Fix: restore physical backbone connectivity, or configure virtual links through a transit area. Virtual links are temporary solutions; long-term design should maintain a contiguous backbone.

### Excessive redistribution

Redistributing too many external routes into OSPF floods the LSDB with Type 5 LSAs, increasing SPF computation time and memory usage. Use route-maps with prefix-lists to limit redistribution scope. Consider stub or NSSA areas to shield non-edge routers from external LSAs.

### Type 7 to Type 5 translation

In NSSA areas, the ABR with the highest Router ID translates Type 7 LSAs to Type 5 for flooding into area 0. If translation fails, external routes from the NSSA are invisible to the rest of the OSPF domain. Verify the translator ABR is healthy and the forwarding address in the Type 7 LSA is reachable.

### Authentication drift

A single router with the wrong key (or wrong type: simple / MD5 / SHA-HMAC) on a shared segment will appear stuck in Init while every other neighbour pair forms Full. Audit `ip ospf authentication-key` / `ip ospf message-digest-key` (IOS / IOS-XE / NX-OS), the OSPF interface stanza `authentication` block (IOS-XR; key-chain-based), or `authentication` (JunOS) on every interface in the area; key IDs must also match for MD5. IOS-XR key-chains add a rotation surface absent on the classic platforms; verify the active key lifetime overlaps every neighbour's.

## Red flags (OSPF-specific)

Cross-cutting IGP red flags live in the umbrella SKILL.md. OSPF-specific red flags:

- About to bounce an OSPF process (`clear ip ospf process`, `restart ospf`, `clear ospf`) without explaining the blast radius.
- About to change area type (standard to stub, stub to NSSA, etc.) without a full neighbour audit; **all** routers in the area must agree on the area type or the area will fragment.
- About to enable `ip ospf mtu-ignore` as a fix instead of correcting the MTU mismatch (papers over a real Layer 2 / 3 problem).
- About to deploy aggressive SPF throttle timers (initial delay below 50ms) without confirming CPU headroom for instability events.
- About to change a router ID on a live router during business hours; takes the OSPF process down.
- About to skip area design validation when adding a new ABR (unexpected ABR can break Type 3 / 4 / 5 propagation).
- About to ignore MaxAge LSAs lingering in the LSDB (originating router unreachable; symptom of upstream failure not yet diagnosed).

## Bottom line (OSPF-specific)

FSM state is the failure-domain signal; ExStart-stuck is almost always MTU; area type must agree across every router in the area; LSDB integrity (right LSA types, right counts, age within bounds) is the health proxy.
