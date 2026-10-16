# KVM, QEMU and libvirt architecture reference

How the stack fits together. Operating rules and the command safety table are in `SKILL.md`. Syntax here has not been run on live systems; check `man virsh` and the libvirt documentation for the installed release.

---

## KVM

KVM ships as kernel modules: `kvm` (core, `/dev/kvm`) plus `kvm_intel` (VT-x, VMCS, EPT) or `kvm_amd` (AMD-V, VMCB, NPT). Check with `lsmod | grep kvm`, `grep -E 'vmx|svm' /proc/cpuinfo`, and `cat /sys/module/kvm_intel/parameters/ept` (or `kvm_amd/parameters/npt`).

QEMU opens `/dev/kvm` and uses ioctls to create the VM, create vCPUs, map guest memory and run vCPUs. vCPUs execute directly on physical CPUs; only VM exits (privileged instructions, I/O, interrupts) return to KVM or QEMU.

**EPT and NPT** perform guest-physical to host-physical translation in hardware, which removed the need for software shadow page tables.

**Nested virtualisation** (a hypervisor inside a guest) is controlled by the `nested` parameter of `kvm_intel` or `kvm_amd`, set in a file under `/etc/modprobe.d/` and applied by reloading the module with no guests running. The L1 guest needs `host-passthrough` (or a CPU model exposing VMX or SVM). Treat nested guests as unsuitable for production.

---

## QEMU

QEMU is the per-guest userspace process: devices, firmware, display and the monitor.

| Machine type | Use |
|---|---|
| `q35` | Modern PCIe chipset; the sensible default for new x86 guests, and the usual choice for PCIe passthrough and a virtual IOMMU |
| `i440fx` | Legacy, for old guests |
| `virt` | ARM (aarch64) |

### VirtIO devices

| Device | Domain XML | Note |
|---|---|---|
| virtio-net | `<model type='virtio'/>` | Network; add `<driver name='vhost'/>` for kernel acceleration |
| virtio-blk | `<target bus='virtio'/>` | Simple block device |
| virtio-scsi | `<controller type='scsi' model='virtio-scsi'/>` | Many disks, hot-plug, discard |
| virtio-balloon | `<memballoon model='virtio'/>` | Memory reclaim |
| virtio-rng | `<rng model='virtio'>` | Entropy |
| guest agent channel | `<channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>` | Shutdown, freeze, IP reporting |
| virtio-gpu, virtiofs | `<video>`, `<filesystem>` | Display and host-guest sharing |

### Firmware

OVMF provides UEFI (needed for Secure Boot and Windows 11 together with a TPM). Packages: `ovmf` on Debian and Ubuntu, `edk2-ovmf` on RHEL and Fedora. Each guest has its own variable store (NVRAM) under `/var/lib/libvirt/qemu/nvram/`, which is why undefining a UEFI guest needs an explicit NVRAM choice.

### Monitor

`virsh qemu-monitor-command <dom> --hmp 'info status'` (human monitor) and `virsh qemu-monitor-command <dom> '{"execute":"query-status"}'` (QMP). Both bypass libvirt's bookkeeping; treat anything beyond `info` and `query-*` as dangerous, and never use them to change a guest libvirt manages.

---

## libvirt

### Daemons

| Daemon | Role |
|---|---|
| `libvirtd` | Monolithic: every driver in one daemon |
| `virtqemud` | Modular QEMU driver |
| `virtstoraged`, `virtnetworkd`, `virtnodedevd`, `virtsecretd`, `virtnwfilterd`, `virtinterfaced` | Modular storage, network, node device, secret, network filter and interface drivers |
| `virtproxyd` | Remote access and compatibility with clients of the monolithic socket |

The libvirt documentation says the monolithic daemon is still what clients prefer for now and that modular daemons are intended to become the default. Distributions differ; check what is active. Modular daemons use socket activation, so enable the `.socket` units for the drivers you need (the libvirt daemons page lists them) and do not run both models together.

### Connection URIs

| URI | Meaning |
|---|---|
| `qemu:///system` | Host-wide guests, managed as root |
| `qemu:///session` | Per-user, unprivileged guests |
| `qemu+ssh://user@host/system` | Remote over SSH |
| `qemu+tls://host/system` | Remote over TLS |
| `qemu+tcp://host:16509/system` | Remote, unencrypted unless wrapped; avoid |

### Domain XML

The persistent definition lives under `/etc/libvirt/qemu/`; the live definition can differ. Core elements: `<memory>`, `<vcpu>`, `<os>` (machine, firmware), `<cpu>` (mode and features), `<cputune>`, `<numatune>`, `<memoryBacking>`, `<devices>` (disks, interfaces, channels, video, TPM, hostdev). Always keep `virsh dumpxml` output from before an edit.

---

## Storage

| Format | Snapshots | Thin | Use |
|---|---|---|---|
| qcow2 | internal or external | yes | Default; backing files, linked clones |
| raw | external only | depends on the filesystem | Lowest overhead; LVM and block devices |
| vmdk | no | n/a | Import and export |

| Pool type | Backend |
|---|---|
| `dir` | A directory of image files |
| `logical` | LVM volume group |
| `netfs` | NFS mount, shared for migration |
| `iscsi` | iSCSI target |
| `rbd` | Ceph RADOS block devices |

Disk caching, I/O mode and discard are set on the `<driver>` element (`cache`, `io`, `discard`, `iothread`); see `best-practices.md`.

### virtiofs

Shares a host directory into a guest. Needs `virtiofsd`, shared memory backing (`<memoryBacking><source type='memfd'/><access mode='shared'/></memoryBacking>`) and a `<filesystem>` device with `<driver type='virtiofs'/>`. The guest mounts it with `mount -t virtiofs <tag> /mnt/share`. A guest using virtiofs generally cannot be live-migrated, so check support in your versions before relying on it in a cluster.

---

## Networking

NAT (`virbr0` with dnsmasq on the `default` network), bridged, macvtap, Open vSwitch, SR-IOV and isolated networks, compared in `SKILL.md`. A libvirt network is defined as XML (`virsh net-define`, `net-start`, `net-autostart`); bridged guests refer to a host bridge instead (`<interface type='bridge'><source bridge='br0'/>`). Open vSwitch ports add `<virtualport type='openvswitch'/>`.

SR-IOV: write the number of virtual functions to `/sys/class/net/<nic>/device/sriov_numvfs`, then pass a VF as a `hostdev`. It needs the IOMMU enabled.

---

## Live migration

Requirements: compatible CPU features on both hosts, network reachability, matching network and storage names, and either shared storage or a storage-copy option. Modes:

| Option | Storage | Note |
|---|---|---|
| `--live` | Shared | Standard live migration |
| `--live --copy-storage-all` | Local | Copies all read-write disks; destination images must be pre-created unless in a pool |
| `--live --copy-storage-inc` | Local | Topmost image of a backing chain only; images must be pre-created |
| `--postcopy` | Any that suits plain migration | Enables post-copy; the switch happens with `virsh migrate-postcopy` or `--postcopy-after-precopy`, after which the guest fetches memory on demand and depends on the source until it completes |
| `--p2p` | Any | Source daemon connects to the destination; continues if the client disconnects |
| `--tunnelled` | Shared | One firewall port; non-shared storage, parallel and post-copy may not be available |

By default migration changes no configuration on either host. `--persistent` defines the guest on the destination and `--undefinesource` removes it from the source.
