# EIGRP, protocol depth

Per-protocol reference loaded by `igp-routing-analysis/SKILL.md`. Owns EIGRP-specific procedure (DUAL semantics, SIA triage, K-value validation), threshold tables, decision trees, report template, and protocol-specific failure modes. Cross-cutting material (mutual IGP redistribution, IGP-then-BGP sequencing, migration patterns, family-level cross-refs) lives in the umbrella SKILL.md, not here.

EIGRP is Cisco-proprietary (opened to limited third-party use but not implemented by Juniper or Arista), and IOS-XR does not implement EIGRP at all, so the vendor surface is `[IOS-XE]` (classic and named modes) and `[NX-OS]` (named-only; `feature eigrp` required). Commands are labelled `[IOS-XE]` or `[NX-OS]` where syntax diverges. Unlabelled statements apply to both platforms.

## Initial Assessment

Before walking neighbour state, understand:

1. **Design context**
   - Platform(s) and OS version(s) on the affected device(s)?
   - Classic mode (`router eigrp [AS-number]`) or named mode (`router eigrp [name]`)? NX-OS is always named.
   - Single AS or multiple AS with redistribution at the boundaries?
   - Stub routers configured (where, what type: `connected`, `summary`, `static`, `redistributed`)?
   - Summarisation points and route-tag policy at redistribution edges?

2. **Symptom and timing**
   - Neighbour adjacency not forming (K-value, passive-interface, AS mismatch), or formed but flapping (uptime resets, hold-time expiries)?
   - Route stuck in Active state (DUAL waiting for replies; SIA timer running)?
   - Route missing entirely, or installed but on a suboptimal path?
   - When did the change start; what config or event correlates (interface flap, neighbour reboot, redistribution edit, K-value change)?

3. **Evidence on hand**
   - Read-only access to `show ip eigrp neighbors`, topology table, interface state?
   - Recent config diffs affecting K-values, stub config, summary-address, distribute-list, offset-list, or redistribution?

## When to use (EIGRP-specific)

- EIGRP neighbour adjacency not forming, or flapping between up and down.
- Route stuck in Active state (SIA timer running, queries unanswered).
- EIGRP route missing from the routing table, or installed but on a suboptimal path.
- K-value mismatch suspected after a config change or new-device addition.
- Post-change verification after topology modifications, summarisation changes, or stub configuration.
- Redistribution loop suspected between EIGRP and another protocol (most commonly OSPF).
- Classic-to-named-mode migration: validating metric and path-selection parity.

## Prerequisites

- Read-only access to the IOS-XE or NX-OS device (SSH, console, or parsed telemetry).
- EIGRP process running (classic `router eigrp [AS]` or named `router eigrp [name]`).
- On NX-OS: `feature eigrp` enabled before any EIGRP configuration.
- Knowledge of the expected EIGRP AS number, stub topology, and summarisation design.
- Awareness of configured stub, summarisation, and distribute-list settings that affect query scope.
- Knowledge of redistribution edges to / from EIGRP and the route-tag policy applied at each edge.

## Procedure

Sequential. Each step builds on data from prior steps. Broad inventory first, then targeted DUAL-level analysis.

### Step 1: EIGRP instance and neighbour inventory

Verify EIGRP is running and collect the neighbour table.

`[IOS-XE]`
```
show ip eigrp neighbors
show ip eigrp neighbors detail
```

`[NX-OS]`
```
show ip eigrp neighbors vrf all
show ip eigrp neighbors detail vrf default
```

Record each neighbour: interface, address, hold time, uptime, SRTT, RTO, queue counts. Compare against expected topology; every directly connected EIGRP router should appear. Key observations:

- **Missing neighbour**: interface misconfiguration, passive-interface, K-value mismatch, AS number mismatch (proceed to Step 4).
- **Low uptime**: recent adjacency reset; correlate with change events.
- **High SRTT (greater than 100 ms)**: slow neighbour responses; potential SIA risk.
- **Non-zero Q Cnt**: neighbour is congestion-limited; queries and updates may be delayed.

For NX-OS, named EIGRP is the only mode; `show ip eigrp vrf default` confirms AS number and K-values in one pass.

### Step 2: Topology table analysis

Examine DUAL's successor and feasible-successor selection for the prefixes under investigation.

`[IOS-XE]`
```
show ip eigrp topology
show ip eigrp topology [prefix/len]
show ip eigrp topology all-links
```

`[NX-OS]`
```
show ip eigrp topology vrf default
show ip eigrp topology [prefix/len] vrf default
show ip eigrp topology all-links vrf default
```

For each route entry, interpret the DUAL state:

- **Feasible Distance (FD)**: best metric this router has ever known for this destination; the threshold for the feasibility condition.
- **Reported Distance (RD)**: the neighbour's own computed distance to this destination, as advertised in its update.
- **Successor**: neighbour whose path is currently installed in the routing table (lowest FD among feasible paths).
- **Feasible Successor (FS)**: backup neighbour whose RD is strictly less than the current FD. Guarantees loop-free alternate path; instant failover without a Query.

**Feasibility condition**: `RD(neighbour) < FD(current)`. If a neighbour's reported distance is lower than the current feasible distance, DUAL guarantees the neighbour is not routing through this router and can serve as a backup without triggering a Query.

If no feasible successor exists and the successor fails, DUAL must go Active and send Queries; proceed to Step 3.

DUAL substate semantics (Active state):

| Substate | Input Event Origin | Reply Status |
|---|---|---|
| Active (0) | Local event | Waiting for all replies |
| Active (1) | Local event | Query origin; will change distance |
| Active (2) | Query from successor | Waiting for all replies |
| Active (3) | Query from successor | Query origin; will change distance |

### Step 3: Stuck-in-Active diagnosis

Identify routes in Active state and diagnose query / reply failures.

`[IOS-XE]`
```
show ip eigrp topology active
show ip eigrp topology zero-successors
```

`[NX-OS]`
```
show ip eigrp topology active vrf default
show ip eigrp topology zero-successors vrf default
```

Routes in Active state are waiting for query replies from neighbours. The SIA timer (default 3 minutes) starts when a route goes Active. At half the SIA timer (90 seconds) a SIA-Query is sent to the unresponsive neighbour; if still no reply at the full timer, the neighbour is reset (adjacency torn down, which counts as a forced reply).

Determine which neighbour is not responding by checking the topology entry's `replies` counter. Then investigate the unresponsive neighbour:

- Reachable at the IP layer? Interface up; Layer 2 healthy?
- CPU overloaded on the neighbour?
- Waiting for its own downstream queries (cascading SIA)?

**Query scope is the primary lever for SIA prevention.** Broad query scope (queries propagating across the entire EIGRP domain) is the most common root cause. Mitigations:

- **Stub configuration** (`eigrp stub connected summary` and variants): stub routers neither send nor receive queries. Use on leaf / branch routers.
- **Summarisation** (`ip summary-address eigrp [AS] [summary]`): queries stop at the summarisation boundary.
- **Distribute-lists** filter routes but do NOT limit query propagation. Route-maps the same.

### Step 4: K-value and metric validation

Verify metric parameters match across all neighbours. Mismatched K-values prevent adjacency formation entirely.

`[IOS-XE]`
```
show ip protocols | section eigrp
show ip eigrp interfaces detail
```

`[NX-OS]`
```
show ip eigrp vrf default
show ip eigrp interfaces detail vrf default
```

Confirm K-values on each device: K1=1, K2=0, K3=1, K4=0, K5=0 (defaults). All neighbours in the same AS must use identical K-values or the adjacency is refused silently (no error in the neighbour table because the adjacency never forms).

Check metric mode. Named EIGRP supports **wide metrics** (64-bit) and scales them through a `rib-scale` factor (default 128) before RIB installation. Classic mode uses 32-bit metrics. If migrating from classic to named mode, verify metric values: wide metrics distinguish high-speed interfaces (10G, 40G, 100G) that produce identical classic metrics.

Validate interface delay and bandwidth on key links. Default bandwidth on serial or tunnel interfaces is a common cause of incorrect metrics; explicit `bandwidth` and `delay` configuration is required where the default does not reflect link reality.

Classic composite metric (default K-values):

```
Metric = 256 × (10^7 / min_BW_kbps + cumulative_delay / 10)
```

Wide metric (named mode, simplified):

```
Wide Metric = K1 × (10^7 × 65536 / BW_kbps) + K3 × (delay_picoseconds / 10^6)
```

### Step 5: Redistribution and route filtering

Check for redistribution loops and verify route filtering.

`[IOS-XE]`
```
show ip route eigrp | include EX
show ip protocols | section distribute
show route-map [name]
```

`[NX-OS]`
```
show ip route eigrp vrf default | include EX
show run | section "router eigrp"
show route-map [name]
```

External EIGRP routes (`D EX` in `show ip route`) indicate redistribution. Common issues:

- **Mutual redistribution** between EIGRP and OSPF (or any other protocol) without route tagging creates loops: redistributed routes circle back and re-enter the original protocol with different metrics.
- **Missing distribute-list or route-map** on redistribution points allows unintended routes to cross protocol boundaries.
- **Administrative distance**: EIGRP external routes have AD 170, higher than OSPF (110). If the same prefix exists in both, OSPF wins by default. This may or may not be desired.

Use route tags at every redistribution point: tag EIGRP-originated routes outbound, deny those tags on re-entry to EIGRP. Verify distribute-lists and route-maps are applied at every redistribution point on both sides.

## Threshold tables

Operational parameter norms for EIGRP: protocol-level expectations, not device resource thresholds.

Hello and hold defaults by interface type:

| Parameter | LAN default | WAN default | Notes |
|---|---|---|---|
| Hello interval | 5s | 60s | WAN = multipoint links below 1.544 Mbps |
| Hold timer | 15s | 180s | 3 × hello by convention |
| Active (SIA) timer | 3 min | 3 min | Configurable; SIA-Query at half (90s) |
| Update / route delay | Immediate | Immediate | No MRAI; updates sent as computed |

K-value defaults (classic mode):

| K-value | Default | Weight | Component |
|---|---|---|---|
| K1 | 1 | Bandwidth | 10^7 / min-bandwidth-kbps |
| K2 | 0 | Load | Disabled by default |
| K3 | 1 | Delay | Sum of delays in tens of microseconds |
| K4 | 0 | Reliability | Disabled by default |
| K5 | 0 | Reliability | Disabled by default |

Operational norms:

| Metric | Healthy | Warning | Critical |
|---|---|---|---|
| Neighbour count | Matches design | ± 1 from baseline | greater than 2 missing |
| SIA events per week | 0 | 1 to 2 | greater than 3 |
| Active routes (point-in-time) | 0 | 1 to 5 | greater than 5 or persistent |
| Topology table size | Stable within 5 percent | Change greater than 10 percent | Change greater than 25 percent |
| SRTT (ms) | less than 100 | 100 to 500 | greater than 500 |

Metric comparison (classic vs wide):

| Link speed | Classic BW component | Wide BW component |
|---|---|---|
| 100 Mbps | 100,000 | 6,553,600,000 |
| 1 Gbps | 10,000 | 655,360,000 |
| 10 Gbps | 1,000 | 65,536,000 |
| 40 Gbps | 250 | 16,384,000 |
| 100 Gbps | 100 | 6,553,600 |

Classic mode produces the same value (100) for both 100G and 40G when BW is scaled (rounded). Wide metrics distinguish them clearly; this matters when ECMP across mixed-speed links is in play.

## Decision tree: stuck-in-active triage

```
Route stuck in Active state (SIA timer running)
├── Check query scope
│   ├── Queries flooding entire domain?
│   │   ├── No stub routers configured → Add stub config on leaf / branch routers
│   │   ├── No summarisation → Add summary-address at distribution boundaries
│   │   └── Large flat topology → Redesign with hierarchy (hub / stub or summarisation tiers)
│   └── Query scope bounded → Specific neighbour issue
│       ├── Unresponsive neighbour reachable at the IP layer?
│       │   ├── No → Interface or link failure
│       │   │   ├── Check interface status on both ends (show interfaces, show ip interface brief)
│       │   │   └── Check Layer 2 (ARP, CDP / LLDP neighbour discovery)
│       │   └── Yes → Neighbour processing delay
│       │       ├── CPU overloaded on neighbour? → Check process CPU
│       │       ├── Cascading SIA (neighbour waiting for its own downstream)?
│       │       │   └── Trace the query chain to the true bottleneck
│       │       └── Active timer too short for slow neighbour?
│       │           └── Consider `timers active-time` extension on the originator
│       └── Multiple neighbours unresponsive simultaneously?
│           └── Common upstream failure → Check shared infrastructure (uplink, CPE, transit)
```

## Decision tree: missing or suboptimal route

```
Expected EIGRP route missing, or wrong path selected
├── Route in topology table?
│   ├── Yes (route known to DUAL)
│   │   ├── In Active state? → Go to SIA triage above
│   │   ├── Successor installed but suboptimal?
│   │   │   ├── Compare FD / RD of competing paths → lowest FD wins
│   │   │   ├── Interface bandwidth / delay correct? → Misconfigured BW / delay skews metric
│   │   │   ├── Variance configured (`variance [multiplier]`)? → Unequal-cost balancing within variance × FD
│   │   │   └── Offset-list applied? → Offset-lists add to the delay component
│   │   └── Feasible successor exists but not used?
│   │       └── Normal: FS is backup only; activates on successor failure
│   │           (unless variance enables unequal-cost balancing)
│   └── No (route not in topology table)
│       ├── Network statement missing → Verify `network` command covers the prefix
│       ├── Passive-interface? → Check `show ip protocols | section Passive`
│       ├── Distribute-list filtering inbound? → Inspect inbound distribute-list / route-map
│       ├── Redistribution missing? → If external route expected, verify redistribution config
│       └── Wrong AS number? → AS must match across all routers in the same domain
```

## Report template

For production-impacting EIGRP work, map findings onto the `multi-vendor-network-ops` 9-element response contract. The EIGRP-specific report skeleton:

```
EIGRP ANALYSIS REPORT
=====================
Device: [hostname]
Platform: [IOS-XE | NX-OS]
EIGRP mode: [Classic AS [n] | Named instance [name]]
Check time (UTC): [timestamp]
Performed by: [operator / agent]

NEIGHBOUR STATUS:
- Expected neighbours: [n]
- Established: [n]; Missing: [n]
- Neighbours with high SRTT (greater than 100 ms): [list]
- Neighbours with non-zero Q Cnt: [list]

DUAL STATE:
- Routes in Passive state: [n] (normal)
- Routes in Active state: [n] (requires attention if greater than 0)
- Feasible successors available: [n] of [total] routes

FINDINGS:
1. [Severity] [Category]: [Description]
   Route or neighbour: [prefix/len or neighbour-id]
   Observed: [state, FD, RD, successor]
   Expected: [normal state or path]
   Root cause: [diagnosis from decision tree]
   Action: [recommended remediation]

METRIC VALIDATION:
- K-values consistent across neighbours: [yes / no; list mismatches]
- Metric mode: [Classic 32-bit | Wide 64-bit (named)]
- rib-scale factor (named mode only): [default 128 | other]

REDISTRIBUTION:
- External routes (D EX) count: [n]
- Route tags in use: [yes / no; list tags]
- Mutual redistribution active: [present / absent]
- Route-map / distribute-list at every redistribution point: [yes / no]

RECOMMENDATIONS:
- [Prioritised action list]

NEXT CHECK: [CRITICAL: 1 hr; WARNING: 8 hr; HEALTHY: 24 hr]
```

## Common failure modes (EIGRP-specific)

### K-value mismatch (silent adjacency failure)

Neighbours with different K-values refuse to form adjacency. No error appears in the neighbour table because the adjacency never establishes. Symptoms: expected neighbour simply absent from `show ip eigrp neighbors`. Diagnose with `show ip protocols | section eigrp` (IOS-XE) or `show ip eigrp vrf default` (NX-OS) on both sides and compare K1 through K5. This is the most common silent EIGRP failure.

### Stuck-in-Active cascading

One unresponsive neighbour can cascade SIA across the domain: Router A queries B, B queries C, C is down. If C never replies, B cannot reply to A, and A eventually resets B. The fix is query-scope containment: `eigrp stub` on leaf routers, summarisation at distribution boundaries. Without containment, every SIA event has potential to cascade.

### Redistribution loops with OSPF (or any peer protocol)

Mutual redistribution (EIGRP into OSPF, OSPF into EIGRP) without route tags creates loops where routes re-enter their original protocol with altered metrics. Use route tags at every redistribution point: tag EIGRP-originated routes outbound, deny those tags on re-entry to EIGRP. Verify both sides of every redistribution edge; a tag policy on one side does not protect the other side.

### Named vs classic mode confusion

Named mode uses 64-bit wide metrics internally and scales them through a `rib-scale` factor before RIB installation. Mixing classic and named mode in the same AS is supported, but metrics appear different in `show` output. Validate with `show eigrp address-family ipv4` (named) versus `show ip eigrp` (classic). Both should compute the same successor; if they do not, an interface bandwidth or delay value diverges between modes.

### Passive-interface misconfiguration

`passive-interface default` suppresses EIGRP on all interfaces. New interfaces added without an explicit `no passive-interface [interface]` are silent: hellos are not sent, neighbours never form. Check `show ip protocols | section Passive` (IOS-XE) when neighbours are missing on freshly cabled interfaces.

### NX-OS named-only and `feature eigrp` gate

NX-OS never supports classic EIGRP. Every NX-OS EIGRP config must use named mode (`router eigrp [tag]`) and `feature eigrp` must be enabled first. Migrating from IOS / IOS-XE classic to NX-OS is therefore always a mode change as well as a vendor change; validate behavioural parity with named mode on the IOS-XE side first, then move to NX-OS.

## Red flags (EIGRP-specific)

Cross-cutting IGP red flags live in the umbrella SKILL.md. EIGRP-specific red flags:

- About to bounce an EIGRP process (`clear ip eigrp neighbors [*|address]`, `clear ip eigrp process`) without explaining the blast radius (every neighbour resets; topology table rebuilds; brief reachability gap).
- About to change a K-value without first auditing all neighbours' K-values; mismatched K-values silently break every adjacency in the AS.
- About to lift a stub configuration to "make queries reach further" without confirming the SIA fix actually requires it (lifting stub widens query scope; usually wrong direction).
- About to disable summarisation at a distribution boundary without verifying the downstream effect on query scope (and therefore SIA risk).
- About to enable variance for unequal-cost load balancing without confirming the alternate path's RD is genuinely less than the successor's FD (variance only activates feasible-successor paths, not arbitrary ones).
- About to deploy aggressive `timers active-time` (below default 3 minutes) without confirming CPU headroom on every router in the query scope.

## Bottom line (EIGRP-specific)

DUAL state is the failure-domain signal; Active-state-with-no-FS is the moment Queries propagate, and query scope determines whether SIA cascades. The feasibility condition (RD < FD) is the loop-prevention invariant; understand it before any redistribution or variance change. K-value mismatch is the silent adjacency killer; check K-values on both sides before debugging anything else when a neighbour is simply absent.
