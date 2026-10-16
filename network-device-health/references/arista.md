# Arista EOS health check

Platform procedure for the shared frame in `../SKILL.md`, covering the 7000, 7500 and 720X families. All commands are read-only. Full command tables are in `arista-cli-reference.md` and the per-parameter thresholds in `arista-threshold-tables.md`.

> **Verification status.** Commands were written from vendor documentation and the upstream material and were not run against devices while authoring this skill. Confirm syntax on the release and platform you operate. EOS agent and environment commands in particular vary between releases.

EOS runs on a Linux kernel with one process (an agent) per protocol or subsystem. Two consequences: Linux-native tools (`bash top`, `bash free`, `bash dmesg`) are valid supplements to EOS `show` commands, and agent health is a first-class concern, because a crashed or stuck agent can silently disable one subsystem while the device-level numbers look normal.

Steps 1 to 5 are core health and apply everywhere. Steps 6 and 7 are data-centre extensions; skip them where MLAG or VXLAN/EVPN is not configured.

## Procedure

### Step 1: Context

`show version`, `show uptime`, `show clock`, `show inventory`

Record hostname, EOS version, uptime, model, total memory and time. A short uptime means a recent reload or crash; `show reload cause` gives the trigger. The 7050X, 7280R, 7500R and 720X families have different memory and CPU profiles, so note the platform.

### Step 2: CPU and memory

`show processes top once`, `show version | include Free memory`

Linux-native, for more granularity: `bash timeout 5 top -bn1 | head -n 20`, `bash free -m`.

`show processes top once` shows per-process CPU and memory like Linux `top`, and CPU is usually consumed by agents. Watch: `Stp` (topology instability), `Rib` and `IpRib` (route churn, large table operations), `Ebra` (L2 forwarding, MAC learning storms), `Bgp` (peer negotiation, route processing), and the ASIC agents such as `Sand` and `Fap-sobek` (forwarding-plane programming).

Free memory of 20 to 40% is a Warning and under 20% Critical (`arista-threshold-tables.md`). EOS uses the Linux page cache heavily, so "used" includes reclaimable cache: read the `available` column of `bash free -m`, not `free`.

### Step 3: Agent and daemon health

A crashed agent affects its subsystem silently.

`show agent` (output varies by release; `show processes` is the fallback), `show agent [name] logs`, `show logging last 50 | include AGENT|agent|crash|restart`

Healthy means every agent is running with an uptime that matches the device. Red flags: an agent with a shorter uptime than the device (it crashed and restarted), an agent in a crashed or not-running state (its subsystem is down), and repeated restarts in the log (recurring instability). After a restart read the agent's log first; common causes are memory exhaustion, an uncaught exception and a watchdog timeout.

### Step 4: Interfaces

`show interfaces status`, `show interfaces counters errors`, `show interfaces counters discards`

For interfaces with errors: `show interfaces [name]`, `show interfaces [name] transceiver`.

CRC or FCS errors point to layer 1; input errors without CRC to buffer overruns or an MTU mismatch; alignment errors to a duplex mismatch or layer 1; output discards to egress congestion; late collisions to a duplex mismatch (not expected on modern links). Low Rx power (below about -10 dBm for most 10G SFP+) points to fibre or optic degradation. Hand a specific link to `interface-health`.

### Step 5: Environment and platform

`show environment all`, `show environment cooling`, `show environment power`, `show environment temperature`, `show reload cause`, `show logging last 30 | include ERR|WARN|traceback|panic`

Temperatures inside limits, power supplies OK, fans running. If the device reloaded recently, `show reload cause` separates expected causes (user-initiated, software upgrade) from unexpected ones (kernel panic, watchdog timeout, power loss). Logs are also readable with `bash cat /var/log/messages | tail -n 50`.

### Step 6: MLAG (data-centre extension)

MLAG state is often the most important health indicator in an Arista data centre: a degraded pair causes black-holes and asymmetric forwarding.

`show mlag`, `show mlag detail`, `show mlag interfaces`, `show mlag config-sanity`

| Field | Healthy | Problem |
|---|---|---|
| state | active | disabled, inactive |
| negotiation status | connected | connecting, disconnected |
| peer-link status | up | down, errdisabled |
| local-interface status | up | down |
| config-sanity | consistent | inconsistent |

`show mlag detail` gives the peer address, peer-link status, heartbeat and the reload-delay timers (critical for avoiding traffic loss during boot). Resolve any `inconsistent` config-sanity result before trusting the rest. In `show mlag interfaces`, every interface should be `active-full` on both sides; `active-partial` means one side is down and redundancy is reduced, and `disabled` means the interface is down.

### Step 7: VXLAN/EVPN (data-centre extension)

`show vxlan vtep`, `show vxlan address-table`, `show interfaces vxlan 1`, `show bgp evpn summary`

- The VTEP count should match what you expect; missing VTEPs point to underlay reachability or EVPN peering.
- The VTEP source interface must be up. The flood list should match the remote VTEPs for flood-and-learn, or be empty for BGP EVPN with ingress replication.
- Every EVPN peer should be Established; Active or Connect means a transport or configuration issue. Compare the EVPN route count with baseline. `show vxlan address-table` shows MAC learning across the overlay; stale or missing entries indicate a control-plane problem.
- For symmetric IRB: `show ip route vrf [name] summary`, `show bgp evpn route-type ip-prefix`; check VRF route counts and that type-5 routes are present for inter-VRF routing.

## Decision trees

```
Is the device reachable?
├── No: console, power, environment; after recovery check the reload cause
└── Yes
    ├── Agent problem?
    │   ├── Crashed or not running: the subsystem is down
    │   │   ├── Bgp: sessions down.  Stp: loops possible.  Ebra: L2 forwarding affected
    │   │   └── Check agent logs; restarting is a configuration change, so recommend it and escalate
    │   ├── Restarted recently: read its logs for the crash reason
    │   └── All running, uptimes match: agent layer healthy
    ├── CPU high? -> find the top agent (no single agent dominant: general overload, check traffic rates)
    │   ├── Stp: topology change, check link flaps
    │   ├── Rib or IpRib: route churn, check BGP and OSPF peers
    │   ├── Ebra: MAC learning storm, check for loops
    │   ├── Bgp: large table, negotiation or policy
    │   └── Sand or Fap: ASIC programming backlog
    ├── Memory low? -> top consumers; cache is reclaimable; steady growth is an agent leak, collect data, plan a reload through change control
    ├── Interface errors? -> classify, hand off to interface-health
    ├── MLAG configured? -> MLAG tree below
    ├── VXLAN/EVPN configured? -> missing VTEPs: underlay and EVPN peers; EVPN peer down: transport, route-map, ASN
    └── Everything inside thresholds: document a clean result
```

```
MLAG configured?
├── No: skip
└── Yes
    ├── State active?  No: read show mlag for the reason and check peer reachability
    ├── Peer-link up?  No: CRITICAL, traffic orphaned; check the physical link, SFP, port-channel members; verify reload-delay timers
    ├── Negotiation connected?  No: control-plane problem; check heartbeat, peer IP, peer-link VLANs
    ├── Config-sanity consistent?  No: VLAN, STP priority or trunk mismatch; fix before trusting the state
    ├── Interfaces all active-full?  active-partial: one side down; disabled: interface down
    └── All pass: MLAG healthy
```

Escalate to a senior engineer or the vendor when: CPU stays over 90% for 15 minutes with no cause; memory is under 15% free with no explanation; an agent stays crashed or several crash close together; a traceback or kernel panic appears (`show logging`, `bash dmesg`); any environmental alarm; more than 3 routing neighbour changes in an hour; an MLAG peer-link fails with no physical cause or config-sanity cannot be resolved; the VXLAN overlay loses more than 10% of expected VTEPs.

## Troubleshooting

- **Unresponsive to SSH:** use the console or out-of-band management. After recovery: `show reload cause`, `bash dmesg | tail -n 50`, `show logging last 50`. Core and crash file locations vary by release; look under `/var/core` and `/var/log` (`bash ls -la /var/core /var/log`).
- **Agent crash and recovery:** read `show agent [name] logs`, then `show logging last 50 | include [agent-name]`, then Linux-side `bash journalctl -u [agent-name] --no-pager | tail -n 30`. Restarting an agent is a configuration change; collect the logs before restarting, because the crash data is needed for the vendor.
- **CPU spikes during a check:** wait 30 seconds after connecting, and use `show processes top once` rather than an interactive `top` that holds a session.
- **MLAG split-brain:** both peers `active` with negotiation `disconnected` means each believes it is primary. Causes: peer-link failure, a peer-link VLAN problem, or a heartbeat-network partition. Verify the physical peer-link first, then the peer-link VLAN trunking and the heartbeat network (usually the management VRF).
- **Linux-native diagnostics:** `bash top -bn1`, `bash free -m`, `bash df -h` (watch `/mnt/flash` and `/var/log`), `bash dmesg | tail`, `bash cat /proc/meminfo`. They supplement the EOS commands; running them is a read-only act, but a shell on a production switch is subject to your access policy.
- **Confusing memory readings:** `show version` may show low free memory while real pressure is low, because the page cache uses spare memory. Use the `available` column of `bash free -m`.
