---
name: virtualization-platform-selection
description: "Use when choosing between server virtualisation platforms, comparing hypervisors, planning a move from one to another, or when the platform is unclear. Triggers include \"which hypervisor\", \"vSphere vs Proxmox\", \"VMware alternative\", \"Proxmox vs KVM\", \"Hyper-V vs Proxmox\", \"Nutanix AHV\", \"XCP-ng\", \"XenServer\", \"Type-1 vs Type-2\", \"live migration requirements\", \"V2V migration\", \"convert VMDK to qcow2\", \"migrate off VMware\", \"HA needs shared storage?\", \"NUMA sizing\", \"can I mix Intel and AMD hosts\". Vendor-neutral comparison and migration reasoning; routes to the platform skill once the platform is known. NOT for day-to-day Proxmox operation (proxmox-ops), NOT for container runtimes (container-runtime-selection), NOT for cloud provider VM operations (aws-cloud-ops, azure-cloud-ops, gcp-cloud-ops), NOT for general cloud-versus-on-premises placement (cloud-platform-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Virtualisation platform selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: virtualization-platform-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Every mainstream hypervisor solves the same problems (CPU and memory isolation, shared or local storage, live migration, HA, backup) with different licensing, tooling and failure modes. The choice is rarely about raw performance. It is about licensing and support model, the skills in the team, the storage and network design already in place, and how painful the exit is later.

**Core principle:** decide on requirements first (workloads, HA and recovery targets, storage, support, budget, skills, exit cost), then compare platforms against them. Product facts, editions and prices change; verify them against the vendor's current documentation and say which source and date a claim came from.

## Router: once the platform is known

| Signal | Platform | Skill |
|---|---|---|
| Proxmox, PVE, qm, pct, pvesh, vzdump, PBS | Proxmox VE | `proxmox-ops` |
| KVM, QEMU, libvirt, virsh, virt-install | KVM with libvirt | no dedicated skill yet; use this skill for comparison and `linux-host-ops` for the host |
| vSphere, ESXi, vCenter, PowerCLI, vMotion, vSAN | VMware vSphere | no dedicated skill yet; use this skill for comparison and migration |
| Hyper-V, Windows failover clustering | Microsoft Hyper-V | comparison only here |
| Nutanix, AHV, Prism | Nutanix AHV | comparison only here |
| XenServer, XCP-ng, xe | XenServer, XCP-ng | comparison only here |
| EC2, Azure VM, Compute Engine | Cloud VMs | `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops` |
| Docker, Podman, containerd, Kubernetes | Containers, not VMs | `container-runtime-selection` |

## Step 1: collect requirements before comparing

Ask, in this order:

1. **Workloads:** Windows or Linux, licensed software with hypervisor support rules, GPU or PCIe passthrough, latency-sensitive databases, appliances that only ship for one hypervisor.
2. **Availability:** target recovery time and recovery point, planned-maintenance expectations, whether a host failure may mean an automatic restart (HA) or must mean no interruption (fault tolerance).
3. **Storage:** existing SAN or NAS, hyper-converged intent, replication needs, backup tool and its hypervisor support.
4. **Network:** VLAN design, overlay or microsegmentation needs, MTU, existing switch automation.
5. **Operations:** team skills (GUI-driven versus CLI and API-driven), automation stack (Terraform, Ansible), monitoring and backup integrations.
6. **Commercial:** support contract needed or optional, budget per host or per core, vendor-lock and exit-cost tolerance.
7. **Scale:** hosts, guests, sites. Small clusters and large ones have different best answers.

Write the answers down; a recommendation that does not reference them is an opinion.

## Cross-platform concepts

### Hypervisor types

**Type 1** runs on the hardware (ESXi, Hyper-V, XenServer, Nutanix AHV). **Type 2** runs as an application on a host OS (Workstation, VirtualBox); suitable for desktops and development. **KVM** is a kernel module, so Linux with KVM behaves as Type 1 while still being a full OS; Proxmox VE packages that with a management layer.

### Hardware support

x86 virtualisation needs Intel VT-x with EPT or AMD-V with NPT, plus an IOMMU (VT-d or AMD-Vi) for device passthrough. Check the firmware settings first, then `grep -E 'vmx|svm' /proc/cpuinfo` on Linux hosts.

### Live migration

| Platform | Feature | Shared storage needed? | Storage migration |
|---|---|---|---|
| VMware | vMotion | No (shared-nothing vMotion exists) | Storage vMotion |
| Proxmox VE | `qm migrate --online` | No, with `--with-local-disks` (slower) | Part of migrate |
| KVM and libvirt | `virsh migrate --live` | No, with storage-copy options | Copy options on migrate |
| Hyper-V | Live Migration | No (shared-nothing supported) | Storage Live Migration |
| Nutanix AHV | Live migration | Built in (distributed storage) | Automatic |

Common requirements everywhere: compatible CPU feature sets (same vendor, similar generation, or a lowered baseline CPU type), a reachable migration network, matching virtual network and storage names on the destination, and spare capacity. Live migration between Intel and AMD hosts is unsupported or not guaranteed on the platforms that document it; keep migration domains single-vendor.

### HA and fault tolerance

| Capability | VMware | Proxmox VE | KVM and libvirt | Hyper-V |
|---|---|---|---|---|
| Restart after host failure | vSphere HA | HA Manager (watchdog fencing) | Pacemaker and Corosync | Failover Clustering |
| Zero-downtime protection | Fault Tolerance | not built in | not built in | not built in; Hyper-V Replica is asynchronous replication |
| Load balancing | DRS | Cluster resource scheduler; dynamic load balancing of HA guests added in 9.2 (check the release notes for your version) | manual or scripted | SCVMM dynamic optimisation |
| Typical minimum | 2 hosts plus shared datastore, 3 advised | 3 nodes plus shared storage | 3 nodes with quorum plus fencing | 2 plus a witness |

State the fencing method when comparing: Proxmox fences by watchdog self-reset and Pacemaker clusters typically fence by power control (STONITH). vSphere HA uses network and datastore heartbeats to tell a failed host from an isolated or partitioned one, which is isolation handling rather than a fence. A comparison that skips this is incomplete.

### Storage for guests

Local: LVM or LVM-thin (light, easy to over-provision), ZFS (checksums, snapshots, compression, uses RAM), directory with qcow2 or VMDK files (simple). Shared: NFS (simple), iSCSI and Fibre Channel (block SAN), Ceph RBD (scale-out, self-healing, needs three or more nodes and a good network), vSAN (VMware hyper-converged), Nutanix distributed storage. Thin provisioning on any of them needs monitoring, because a full pool fails every guest on it at once.

### Guest networking

Virtual switches (vSS and vDS, Linux bridge or Open vSwitch, Hyper-V vSwitch), VLAN tagging on the port or bridge, overlays (NSX with GENEVE, Proxmox SDN with VXLAN or EVPN, OVN), SR-IOV for near-native NIC performance, and a firewall at the hypervisor (NSX distributed firewall, Proxmox firewall, nftables). Overlay design is its own topic: `evpn-vxlan-fabric`.

## Comparison

| Criterion | VMware vSphere | Proxmox VE | KVM and libvirt |
|---|---|---|---|
| Licence | Commercial subscription (Broadcom); editions and bundles change, verify current terms | AGPL, free to use; optional per-socket support subscription | GPL; distribution vendor support if wanted |
| Management | vCenter and vSphere Client | Web UI on 8006, REST API, CLI | `virsh`, virt-manager, Cockpit; no built-in cluster UI |
| Clustering | vCenter with HA and DRS | Corosync with HA Manager | Pacemaker and Corosync |
| Storage | VMFS, vSAN, NFS | ZFS, LVM-thin, Ceph, NFS, iSCSI | LVM, qcow2 on files, NFS, Ceph |
| Containers | VMware Kubernetes offerings (separate products; verify current naming) | LXC system containers built in | Separate (Podman and others) |
| Automation | PowerCLI, REST, govc, Terraform | `pvesh`, REST, Terraform, Ansible | `virsh`, libvirt API, Terraform, Ansible |
| Best fit | Existing VMware estates, vendor-backed SLAs, mature backup ecosystem | Small to mid clusters, Linux-heavy, ZFS or Ceph, low licence cost | Linux-native shops that already automate everything, embedded use |
| Skills curve | Moderate, GUI-driven | Low to moderate | Higher, XML and CLI driven |

Other platforms, for comparison only:

- **Hyper-V** suits Windows-centred estates that already hold the licences and System Center or Windows Admin Center skills.
- **Nutanix AHV** is hyper-converged with distributed storage and Prism management; it is a commercial platform with its own hardware and software compatibility lists.
- **XenServer and XCP-ng** use the Xen hypervisor with XAPI and the `xe` CLI; XCP-ng is the open-source fork, with Xen Orchestra for management.
- **Cloud VMs** trade capital cost for operating cost and shift the hypervisor out of scope; use the cloud-ops skills.

## When to choose what

- **VMware vSphere** when contractual or regulatory support is mandatory, the estate and its backup tooling are already VMware, vSAN suits the design, or software vendors only support their product on it. Weigh the commercial terms and renewal history before committing more capacity.
- **Proxmox VE** when licence cost matters, Linux guests and LXC dominate, ZFS or Ceph is wanted, and the team is comfortable with a Debian-based platform. Pay for a support subscription for production where an SLA matters.
- **KVM with libvirt** when the team already runs Linux and configuration management at scale and wants no hypervisor product layer.
- **Hyper-V** when the estate is Windows-centred and licensing already covers it.
- **Stay put** is a valid answer. A migration needs a measurable gain, because each guest conversion is a risk event.

## V2V migration

Plan it as a project: inventory guests, group by risk and dependency, pilot with non-critical guests, define rollback per guest, and agree a cutover window.

### VMware to Proxmox or KVM

1. Check what the target offers first. Proxmox VE includes an ESXi import wizard in current releases (check the release notes for the installed version), and `virt-v2v` (libguestfs) converts VMware guests for KVM and can inject drivers.
2. Manual path: export with `govc export.ovf -vm <name> <directory>` (or the vSphere export), power off the source guest for a consistent copy, create a shell VM on Proxmox, then import with `qm disk import <vmid> <image> <storage>` (it converts the format on the fly and leaves the disk as `unused`, so attach it afterwards) or, on KVM, convert with `qemu-img convert -f vmdk -O qcow2 in.vmdk out.qcow2` and use `virt-install --import`.
3. Remove VMware Tools after the move, install the QEMU guest agent, and move disks and NICs to VirtIO once the drivers are present.

### Proxmox or KVM to VMware

Convert with `qemu-img convert -f qcow2 -O vmdk -o subformat=streamOptimized` (the default sparse VMDK subformat is often rejected by ESXi; alternatively clone it on the host with `vmkfstools`), upload to a datastore, attach to a new VM, install VMware Tools, remove the QEMU guest agent, and move to PVSCSI and VMXNET3 after the tools are in.

### Windows guests, either direction

Install the target platform's drivers before the move (virtio-win for KVM and Proxmox, VMware Tools for vSphere) or inject them offline, change the disk controller in a controlled step, and keep a recovery plan if the guest fails to boot (boot into recovery, load the storage driver). Re-check licensing activation after hardware identity changes.

### After cutover

Verify application behaviour, not just boot. Keep the source guest powered off and intact for an agreed period. Update backup jobs, monitoring, and the asset inventory before deleting anything.

## Pitfalls

1. Skipping the firmware check for VT-x or AMD-V and IOMMU before deploying.
2. Mixing CPU vendors in a migration domain, or using a CPU type that the oldest host cannot satisfy.
3. Memory overcommit without ballooning, monitoring and a plan for OOM kills or swap storms.
4. Ignoring NUMA: guests that span nodes pay remote-memory latency. Size latency-sensitive guests to fit one node.
5. Treating snapshots as backups on any platform.
6. Enabling HA or live migration without shared storage (or replication) and a tested fencing method.
7. Thin-provisioned storage with no alert before it fills.
8. Choosing on licence cost alone and forgetting the cost of retraining, tooling and migration.
9. Believing a copied vendor statement: editions, limits and prices change, so cite the source and date.

## Red flags

- A recommendation with no stated requirements or sources.
- "HA" described without naming shared storage and the fencing mechanism.
- A migration plan with no per-guest rollback.
- A comparison table using figures from a listicle or vendor marketing page as primary evidence.
- A Windows migration plan that does not mention storage drivers.

## Boundaries

- Operating Proxmox VE day to day: `proxmox-ops`.
- Host-level Linux work (systemd, packages, LVM, backups): `linux-host-ops`, `linux-host-bringup`.
- Containers and Kubernetes: `container-runtime-selection`, `kubernetes-ops`.
- Cloud versus on-premises placement and cloud migration strategy: `cloud-platform-selection`; cloud VM operations: the cloud-ops skills.
- Overlay networking: `evpn-vxlan-fabric`.
- Infrastructure as code for guests: `terraform-iac-ops`, `ansible-automation-platform`.

## Bottom line

Collect requirements, then compare. State fencing, storage and licensing explicitly. Verify product facts against the vendor's current documentation and cite the date. Treat a migration as a per-guest risk event with a rollback, and remember that staying put is a legitimate outcome.
