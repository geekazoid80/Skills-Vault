# Cisco IOS-XE and NX-OS health check

Platform procedure for the shared frame in `../SKILL.md`. Commands are labelled **[IOS-XE]** or **[NX-OS]** where they diverge; unlabelled commands work on both. All are read-only. Full command tables are in `cisco-cli-reference.md` and the per-parameter thresholds in `cisco-threshold-tables.md`.

> **Verification status.** Commands were written from vendor documentation and the upstream material and were not run against devices while authoring this skill. Confirm syntax on the release and platform you operate.

Platform notes that change how to read the data:

- **IOS-XE** separates the route processor (RP, control plane) from the QuantumFlow Processor (QFP, data plane) on ASR, ISR and Catalyst 8000 routers. Triage the two independently. Catalyst 9K switches expose their data plane through `show platform hardware fed ...` rather than the QFP commands; use the platform's own forwarding-engine statistics there.
- **NX-OS** has a unified supervisor model: `show system resources` is the primary CPU and memory view, and the baseline runs hotter than IOS-XE because the supervisor does both planes. Health data is **VDC-scoped**: every command applies to the VDC you are in.

## Procedure

If the device is unresponsive, jump to Step 6 for crash recovery.

### Step 1: Context

**[IOS-XE]** `show version | include uptime|Version|bytes of memory`, `show inventory | include PID`, `show clock`
**[NX-OS]** `show version | include uptime|system version|Memory`, `show inventory | include PID`, `show clock`, `show vdc current-vdc`

Record hostname, OS version, uptime, model, time. A short uptime means a recent reload or crash; find out why before anything else. On NX-OS confirm the VDC: everything that follows describes that VDC only.

### Step 2: CPU

**[IOS-XE]** `show processes cpu sorted`, `show processes cpu history`, `show platform software status control-processor brief`, `show platform hardware qfp active statistics drop` (ASR, ISR, Catalyst 8000)
**[NX-OS]** `show system resources`, `show processes cpu sort`, `show processes cpu history`, `show module`

- **IOS-XE:** compare the 5-second, 1-minute and 5-minute RP averages. RP normal with QFP drops climbing means the data plane is overloaded while the control plane is healthy, which needs a different fix from an RP overload. Key RP processes: IP Input (traffic storms), BGP Router (route churn), Crypto IKMP (VPN storms), IOSD (control-plane congestion).
- **NX-OS:** `show system resources` reports kernel plus user CPU; a busy figure under about 50% is normal (see `cisco-threshold-tables.md`). Key processes: `netstack` (forwarding), `bgp` (route processing), `stp`, `vpc` (keepalive).

### Step 3: Memory

**[IOS-XE]** `show memory statistics`, `show processes memory sorted`
**[NX-OS]** `show system resources`, `show processes memory`

- **IOS-XE:** used percentage from the processor pool is `(Total - Free) / Total * 100`. If the largest free block is under 10% of total free, memory is fragmented.
- **NX-OS:** memory is total, used and free in KB at the Linux level. Used above 60% is typical; watch for `MemFree` below 15% of total.

### Step 4: Interfaces

`show interfaces summary`, `show interfaces counters errors`

**[IOS-XE]** `show interfaces | include line protocol|drops|error|CRC`, `show controllers [name]`
**[NX-OS]** `show interface [name] | include errors|drops|CRC`, `show hardware internal errors module [n]`

Error rate is `errors / (input + output packets) * 100`. CRC points to layer 1 (cable, optics, seating); input errors without CRC to buffer overruns; output drops to congestion (check QoS or capacity). On NX-OS, `show hardware internal errors` exposes ASIC-level drops that standard counters do not. Hand a specific link to `interface-health`.

### Step 5: Routing and redundancy

`show ip route summary`

**[IOS-XE]** `show ip bgp summary`, `show ip ospf neighbor`, `show ip eigrp neighbors`
**[NX-OS]** `show bgp ipv4 unicast summary`, `show ip ospf neighbors`, `show ip eigrp neighbors`, `show vpc brief`

Check the route count against baseline, that neighbours are established or full, and that nothing was withdrawn unexpectedly. A BGP prefix count more than 10% off baseline signals route churn. On NX-OS the vPC peer-link is critical: a failed peer-link orphans traffic.

### Step 6: Environment and platform

**[IOS-XE]** `show environment all`, `show platform software status control-processor brief`, `show logging | include %|Error|Warning|traceback`, `dir crashinfo:`
**[NX-OS]** `show environment`, `show module`, `show logging last 50`, `show cores`, `show system reset-reason`

Power supplies, fans and temperatures; any environmental alarm escalates at once. On IOS-XE review `crashinfo:` for recent crash dumps. On NX-OS `show cores` lists supervisor and module cores, and any presence means a process crashed.

## Decision trees

```
Is the device reachable?
├── No: console, power, environment; after recovery collect crashinfo (IOS-XE) or show cores and reset-reason (NX-OS)
└── Yes
    ├── [IOS-XE] CPU issue?
    │   ├── RP high, QFP normal: control-plane overload
    │   │   ├── BGP Router high: route churn, check peer stability
    │   │   ├── IP Input high: traffic storm, check ACLs and control-plane policing
    │   │   └── Other: collect show tech-support for the vendor
    │   ├── RP normal, QFP drops high: data-plane overload
    │   │   └── Check traffic rates, ACL complexity, NAT session count
    │   └── Both high: platform capacity exceeded, reduce load
    ├── [NX-OS] CPU issue?
    │   ├── Right VDC?
    │   ├── netstack high: forwarding overload, check ARP and routes
    │   ├── bgp high: route churn, check table size and peers
    │   ├── stp or vpc high: Layer 2 instability, check topology
    │   └── One module only: specific line card, see show module
    ├── Memory issue?
    │   ├── [IOS-XE] fragmentation high: schedule a reload in a window
    │   ├── [NX-OS] MemFree under 15%: find the top consumers
    │   └── Steady growth: leak, collect allocation data, plan a reload through change control
    ├── Interface errors?
    │   ├── CRC or input errors: layer 1
    │   ├── Output drops: QoS or congestion
    │   └── [NX-OS] ASIC errors: hardware, check module health
    └── Everything inside thresholds: document a clean result
```

Escalate to a senior engineer or the vendor when: CPU stays over 90% for 15 minutes or more; memory is under 15% free with no explanation; a traceback, CPUHOG or MALLOCFAIL appears (IOS-XE) or a core dump is present (NX-OS); any environmental alarm; more than 3 routing neighbour changes in an hour; an NX-OS module is not in the OK state or the vPC peer-link fails; QFP drops exceed 10,000 a second with no traffic explanation (IOS-XE).

## Troubleshooting

- **Unresponsive to SSH:** use the console. If that fails, check power and environment through out-of-band management. Afterwards collect `dir crashinfo:` (IOS-XE) or `show cores` and `show system reset-reason` (NX-OS).
- **NX-OS VDC confusion:** if metrics look wrong, check `show vdc current-vdc`. The default VDC holds system-level resources; the admin VDC shows aggregate hardware. Switching VDC is `switchto vdc [name]`.
- **CPU spike while checking:** show commands and SNMP polling can spike the CPU briefly. Wait 30 seconds after connecting, and set `terminal length 0` to avoid paging.
- **High QFP drops with a normal RP:** the data plane is stressed but the control plane is fine. Do not reload. Look at traffic patterns, ACL complexity and NAT sessions; `show platform hardware qfp active feature` shows which QFP feature is consuming resources.
- **NX-OS module not OK:** collect `show module internal exception-log module [n]` before acting. Power-cycling a line card can clear a transient fault but needs change control.
- **Memory readings disagree between platforms:** IOS-XE `show memory statistics` shows IOS memory pools; NX-OS `show system resources` shows Linux-level memory. The NX-OS baseline is higher (55 to 65% is normal).
