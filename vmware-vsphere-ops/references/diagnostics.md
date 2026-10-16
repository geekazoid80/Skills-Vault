# VMware vSphere diagnostics reference

Read-only diagnostics first; actions that change state or add load are marked. Thresholds are rules of thumb, not VMware limits. Syntax has not been run on live systems; check Broadcom documentation for the installed release.

---

## esxtop

Run in the ESXi Shell or over SSH (enable them briefly). Panels: `c` CPU, `m` memory, `d` disk adapter, `n` network.

### CPU (`c`)

| Counter | Meaning | Indicator |
|---|---|---|
| %USED | CPU consumed | Context only |
| %RDY | Ready but waiting for a core | Sustained above about 5 per vCPU: contention |
| %CSTP | Co-stop, waiting on sibling vCPUs | Above about 3: too many vCPUs |
| %MLMTD | Held back by a limit | Above 0: check limits and shares |
| %SWPWT | Waiting on swapped pages | Above 0: severe memory pressure |

High %RDY: the host is overcommitted; reduce vCPUs or rebalance. High %CSTP: reduce the VM's vCPU count. %MLMTD: look at the resource pool or VM limit.

### Memory (`m`)

| Counter | Meaning | Indicator |
|---|---|---|
| MCTLSZ | Balloon target (MB) | Above 0: pressure, not necessarily a fault |
| SWCUR | Swapped to `.vswp` (MB) | Above 0: serious pressure |
| N%L | NUMA local memory | Below about 80: VM spans nodes |
| LLSWR/s | Swap reads to host cache | Above 0: latency impact |

### Storage (`d`)

| Counter | Meaning | Indicator |
|---|---|---|
| DAVG/cmd | Device (array) latency | Sustained above about 20 ms on flash or 50 ms on disk: array or fabric |
| KAVG/cmd | VMkernel queue latency | Above about 2 ms: queueing in the host |
| GAVG/cmd | DAVG plus KAVG, as the guest sees it | The latency applications feel |
| CMDS/s | IOPS | Context only |

High DAVG: look at the array, paths and queue depth. High KAVG with low DAVG: queue congestion or path selection.

### Network (`n`)

Watch %DRPTX and %DRPRX (drops above 0 mean saturation or misconfiguration) and %USED (sustained high use means consider more bandwidth).

### Batch capture

```bash
esxtop -b -n 60 -d 5 > /tmp/esxtop-capture.csv     # 60 samples, 5 s apart; adds load, keep it short
```

---

## vm-support bundles

```bash
vm-support -w /tmp/            # writes a bundle; adds load and disk use; check 'vm-support -h' for options
```

From the client: Host, Actions, Export System Logs. For vCenter use the appliance management interface (VAMI, port 5480), Support, Create Support Bundle. A bundle holds VMkernel and host logs, configuration, storage and network state, and core dumps after a PSOD.

---

## Purple screen of death (PSOD)

A kernel panic. Common causes: uncorrectable ECC memory errors, NIC or HBA driver bugs, firmware incompatibility, VMkernel resource exhaustion, storage faults.

1. Record the screen (photograph) or retrieve the core dump after reboot.
2. Check hardware logs (BMC, iDRAC, iLO) for concurrent faults.
3. Reboot the host; HA restarts its VMs elsewhere.
4. Collect a `vm-support` bundle immediately after the reboot.
5. Core dumps are in `/var/core/` or on the configured network dump target.
6. Read `/var/log/vmkernel.log` and `/var/log/vmkwarning.log` for events before the panic.
7. Align drivers, firmware and ESXi with the compatibility guide, and open a support case with the screen, core dump and bundle.

Prevention: compatibility-guide versions, hardware health monitoring, network core dump for headless hosts, HA.

---

## vMotion failures

| Message or symptom | Likely cause | Fix |
|---|---|---|
| CPU incompatible | Different CPU features | Enable EVC at the cluster |
| Network not found | Port group name mismatch | Create the matching port group |
| No shared datastore | Destination cannot see the datastore | Rescan, check LUN masking |
| Timeout | vMotion network too slow for the dirty rate | Faster vMotion NIC, add NICs |
| Cannot complete | VM has a device on a local resource | Disconnect local ISO or serial port |
| Insufficient resources | No headroom on the destination | Check DRS, admission control and limits |

Diagnostic steps:

1. `esxcli network ip interface list` on both hosts, to see the vMotion VMkernel port.
2. `esxcli network diag ping --host=<peer-vmk-ip> --interface=<vmkN>` between vMotion interfaces (add `--netstack=vmotion` if the vMotion netstack is in use).
3. `esxcli storage filesystem list` on both hosts, to compare datastores.
4. Compare the EVC baseline and CPU features.
5. Read `/var/log/hostd.log` on both hosts and `/var/log/vmware/vpxd/vpxd.log` on vCenter.
6. Test with a small VM to separate network from resource faults.

---

## Storage latency

1. Find the VM with vCenter performance charts.
2. In `esxtop` (`d`): high DAVG points to the array, high KAVG to the host queue.
3. Check snapshot chains: `ls -la /vmfs/volumes/<datastore>/<vm>/ | grep -iE 'delta|sesparse'` (VMFS 6 snapshots use SEsparse files).
4. Check datastore use (a read-only PowerCLI query):

```powershell
Get-Datastore | Where-Object { ($_.CapacityGB - $_.FreeSpaceGB) / $_.CapacityGB -gt 0.8 }
```

5. Check multipathing: `esxcli storage nmp device list`.
6. Look for SCSI errors: `grep -E 'H:0x[^0]|D:0x[^0]' /var/log/vmkernel.log | tail -20`.
7. Ask the storage team about array load, thin reclamation and rebuilds.

---

## HA failover

1. Confirm HA is enabled and healthy: `Get-Cluster | Select-Object Name, HAEnabled, HAAdmissionControlEnabled`.
2. Check host connection state; a not-responding host triggers HA.
3. Read the FDM log on the primary: `/var/log/fdm.log`.
4. Check admission control: HA cannot restart VMs without capacity.
5. Verify heartbeat datastores (absent in vSAN-only clusters).
6. Check restart priority: low or disabled VMs may not restart under pressure.
7. Check the isolation response for the isolated host.

| Issue | Cause | Resolution |
|---|---|---|
| VMs not restarted | Not enough capacity | Add capacity or reduce reservations |
| "Insufficient resources" | Large reservations | Reduce per-VM reservations |
| Host shows disconnected | Management network failure | Check vmk0, uplink and switch port |
| VMs reported on two hosts | Partition without working heartbeats | Fix the network; verify heartbeat datastores |
| HA configuration errors | FDM cannot reach vCenter | Check DNS and vpxa; restarting vpxa is disruptive, so confirm first |

---

## Logs

| Component | Path |
|---|---|
| VMkernel | `/var/log/vmkernel.log` |
| hostd | `/var/log/hostd.log` |
| vpxa | `/var/log/vpxa.log` |
| FDM (HA) | `/var/log/fdm.log` |
| Shell commands | `/var/log/shell.log` |
| Authentication | `/var/log/auth.log` |
| vCenter core | `/var/log/vmware/vpxd/vpxd.log` |
| vCenter database | `/var/log/vmware/vpostgres/` |

```bash
grep -iE 'scsi|nmp|device|path' /var/log/vmkernel.log | tail -50
grep -iE 'vmotion|migrate' /var/log/hostd.log | tail -30
grep -iE 'fault|failover|restart|isolation' /var/log/fdm.log | tail -30
grep -iE 'fail|denied|invalid' /var/log/auth.log | tail -20
```

---

## Counters and statistics levels

Useful vCenter counters: `cpu.ready.summation` (VM), `mem.swapped.average` (VM), `disk.maxTotalLatency.latest` (VM), `cpu.usage.average` and `mem.usage.average` (host), `disk.numberReadAveraged.average` and `disk.numberWriteAveraged.average` (datastore).

Statistics levels 1 to 4 collect progressively more; raise the level temporarily (a day or two) for troubleshooting, because level 4 grows the vCenter database quickly.
