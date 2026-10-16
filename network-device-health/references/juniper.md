# Juniper JunOS health check

Platform procedure for the shared frame in `../SKILL.md`, covering MX, SRX, EX, QFX and PTX. All commands are read-only. Full command tables are in `juniper-cli-reference.md` and the per-parameter thresholds in `juniper-threshold-tables.md`.

> **Verification status.** Commands were written from vendor documentation and the upstream material and were not run against devices while authoring this skill. Confirm syntax on the release and platform you operate.

JunOS separates the Routing Engine (RE, control plane) from the Packet Forwarding Engine (PFE, data plane). They are independent health domains: a healthy RE does not guarantee a healthy PFE, and the reverse. This procedure assesses both, and starts with RE mastership because every figure that follows is scoped to the RE you are logged in to.

## Procedure

### Step 1: Verify RE mastership (mandatory)

On a dual-RE system the data comes from the RE you are on. On the backup RE every metric describes the standby engine, not the forwarding path.

`show chassis routing-engine | match "Slot|Current state|Mastership"`, `show route summary | match "Router ID"`, `show system uptime`

Confirm the session is on the master RE. If `Current state` shows `Backup`, move to the master with `request routing-engine login other-routing-engine`. On a single-RE platform confirm the RE is `Master` and not degraded. Record hostname, RE slot, mastership, uptime and last reboot reason; a short uptime after an unexpected reboot comes first.

### Step 2: Alarms

JunOS surfaces alarms as first-class indicators, so check them before digging.

`show chassis alarms`, `show system alarms`

- **Major:** service-affecting; address immediately and ahead of everything else.
- **Minor:** degraded but running; investigate promptly.

Record each alarm's class, description and time. Common sources: FPC offline, power supply failure, rescue configuration not set, licence expiry, FRU removal. No alarms means continue the systematic check.

### Step 3: Routing Engine

`show chassis routing-engine`, `show system processes extensive`, `show task replication`

From `show chassis routing-engine`: CPU idle (30 to 60% is Warning, 10 to 30% Critical, under 10% Emergency), memory used (71 to 80% Warning, 81 to 90% Critical, over 90% Emergency), temperature, start time (a recent RE restart means a crash or failover) and load averages (sustained over 1.0 per core is elevated).

Top processes: `rpd` (route churn, table size, peer instability), `chassisd` (sensor polling, FPC communication), `snmpd` (polling storms), `mgd` (large configuration, slow commit, many CLI sessions), `kmd` (IKE and IPsec storms on SRX). RE CPU can reach 80 to 90% briefly during a `commit`; correlate with `show system commit`.

### Step 4: PFE

A healthy RE with a degraded PFE still drops traffic.

`show chassis fpc`, `show chassis fpc detail`, `show pfe statistics traffic`, `show pfe statistics error`

- **State** must be `Online`; `Present`, `Offline` or `Empty` indicates a hardware fault or intentional deactivation.
- **CPU** 61 to 80% is Warning, 81 to 95% Critical, over 95% Emergency. **Heap** over 80% means memory pressure (`juniper-threshold-tables.md`).
- In `show pfe statistics traffic`, a large input-versus-output difference indicates drops; check `fabric drops` and `local drops`.
- In `show pfe statistics error`, any non-zero counter deserves a look, and counters that keep rising across two reads 30 seconds apart indicate an active problem.

On a chassis with several FPCs check each one; a single degraded FPC affects only its own interfaces.

### Step 5: System resources

`show system storage`, `show system memory`, `show system core-dumps`, `show system commit`

- **Storage:** a partition at 76 to 85% used is a Warning, 86 to 95% Critical, and over 95% Emergency; a full `/var` blocks commits and logging.
- **Memory:** compare the kernel view with Step 3; sustained growth with no configuration change suggests a leak.
- **Core dumps:** any core within seven days means a process crashed. Record the process name and time; that is what the vendor will ask for.
- **Commit history:** if the device was healthy before a commit and unhealthy after, the investigation path is obvious.

### Step 6: Interfaces and routing

`show interfaces terse | match "down|err"`, `show interfaces extensive [name] | match "error|drop|CRC|carrier"`, `show route summary`, `show bgp summary`, `show ospf neighbor`, `show isis adjacency`

For each interface with errors: CRC points to layer 1 (cable, optics, SFP); input errors without CRC to buffer overruns or an MTU mismatch; output drops to congestion or a policer; carrier transitions to a flap (check optics with `show interfaces diagnostics optics [name]`). Verify the expected neighbour count and that adjacencies are established or full. A BGP prefix count more than 10% off baseline means route churn. Hand a specific link to `interface-health`.

### Step 7: Environment

`show chassis environment`, `show chassis temperature-thresholds`, `show chassis power`, `show chassis fan`

Temperatures inside thresholds, power supplies OK, fans running. An environmental alarm maps directly to Major severity. On dual-RE systems check both RE temperatures: a hot standby can mean a cooling fault even when the master looks fine.

## Decision trees

```
Is the device reachable?
├── No: console, power, environment; after recovery collect core dumps
└── Yes
    ├── On the master RE? -> if not, switch to it and restart the triage
    ├── Alarms?
    │   ├── Major: address first
    │   │   ├── FPC offline: show chassis fpc detail, check the PFE
    │   │   ├── Power supply failure: show chassis power and environment
    │   │   ├── RE failover: show chassis routing-engine, check the standby
    │   │   └── Other: collect alarm detail, escalate
    │   ├── Minor: note it, continue
    │   └── None: continue
    ├── RE CPU high?
    │   ├── rpd: route churn, check BGP, OSPF and IS-IS neighbours
    │   ├── chassisd: FPC or sensor communication
    │   ├── snmpd: polling storm
    │   ├── mgd: commit or CLI overload, see show system commit
    │   ├── kmd (SRX): IKE storm, check IPsec SA count
    │   └── A recent commit correlates: rollback candidate, through change control
    ├── PFE issue (RE healthy, traffic dropping)?
    │   ├── FPC not Online: hardware
    │   ├── PFE CPU over 80%: forwarding overload, check traffic, filter complexity, next-hop resolution
    │   ├── Drops rising: fabric drops (line card to fabric), local drops (punt or exception path), discards (filter or policer, may be expected)
    │   └── PFE memory pressure: route or session table exhaustion
    ├── Memory or storage?
    │   ├── RE memory over 85%: find the top consumers
    │   ├── Storage over 90%: logs, cores, old images; /var full blocks commits
    │   └── Core dumps present: a process crashed, collect for the vendor
    ├── Interface errors? -> classify (CRC, input, output, carrier), hand off to interface-health
    └── Everything inside thresholds: document a clean result
```

Alarm triage: a Major FPC-offline alarm affects only that line card's interfaces (check `show chassis fpc detail [slot]`; power-cycle only through change control, RMA if it persists); a power supply failure with redundancy lost needs prompt replacement, and both failed is an emergency; an RE failover needs the new master's health verified (Steps 1 to 3) and the old master investigated; a Minor "licence expiry" needs the feature impact checked and a renewal planned, and a Minor "FRU removal" should be confirmed intentional and recorded; a Minor "rescue config not set" is resolved with `request system configuration rescue save` (a configuration action, so recommend it).

Escalate to a senior engineer or the vendor when: RE CPU stays over 90% for 15 minutes with no cause; RE memory is over 90% with no change to explain it; a PFE stays offline after a power-cycle attempt; core dumps appear from critical processes (`rpd`, `chassisd`, `pfed`); a Major alarm has no clear remedy; several FPCs fail or fabric errors appear; the RE fails over repeatedly; any environmental alarm; more than 3 routing neighbour changes in an hour.

## Troubleshooting

- **Unresponsive to SSH:** use the console. If that also fails, use the craft interface or console server for power and environment. Afterwards collect `show system core-dumps`, the reboot reason from `show chassis routing-engine`, and `show log messages | match "kernel|panic|watchdog"`.
- **Logged in to the backup RE:** you are reading standby metrics. Switch to the master. If the master is unreachable from the backup, treat it as a master RE failure and read the master's last known state from the backup.
- **RE CPU spikes during a commit:** expected. Confirm with `show system commit`, wait until about five minutes after the commit and re-check; sustained high CPU after that is real.
- **PFE drops with a healthy RE:** the planes are independent. Read `show pfe statistics traffic` for drop categories and `show chassis fpc detail` for PFE CPU and memory. Common causes: filter or policer drops (possibly expected), next-hop resolution failures, PFE memory exhaustion from large tables.
- **Storage full blocks commits:** `request system storage cleanup` removes old logs, cores and temporary files. It deletes files, so recommend it rather than run it during triage; if it is not enough, use `show system storage` to find the largest consumers.
- **After an RE failover:** verify the new master (Steps 1 to 3), then investigate the old one. `show log messages | match "mastership|failover|switchover"` finds the trigger. Common causes: RE crash (a core is present), watchdog timeout, manual switchover, GRES or NSR failure.
