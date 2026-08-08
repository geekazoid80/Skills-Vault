# Rancher architecture

Deep technical detail on the Rancher management layer, its distributions, Fleet, and Harvester.

## Management cluster architecture

### Rancher server components

Rancher runs as a Helm-deployed application on a dedicated Kubernetes cluster (RKE2 recommended):

```
Rancher Management Cluster (RKE2 recommended)
  |-- rancher Deployment (3 replicas for HA)
  |     |-- Authentication handler (OAuth, SAML, LDAP proxy)
  |     |-- API server (Rancher API, wraps the Kubernetes API)
  |     |-- Cluster controller (manages downstream cluster agents)
  |     |-- Project controller (namespace grouping, RBAC propagation)
  |     +-- App catalog controller (Helm chart deployment)
  |-- Fleet controller (fleet-controller namespace)
  |     |-- GitRepo controller (watches Git repositories)
  |     |-- Bundle controller (generates Bundles from GitRepos)
  |     +-- BundleDeployment controller (deploys to target clusters)
  |-- Ingress (NGINX or Traefik) -- TLS termination for the Rancher UI/API
  +-- cert-manager (certificate management for Rancher)
```

### Installation options

```bash
# Install Rancher via Helm
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=admin \
  --set replicas=3 \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@example.com
```

TLS options:

- Let's Encrypt (automatic certificate management)
- Rancher-generated self-signed (development only)
- Bring your own certificate (production)
- External load balancer TLS termination

Set `bootstrapPassword` out-of-band rather than committing it to a values file.

### Downstream cluster communication

```
Downstream Cluster
  +-- cattle-system namespace
        |-- cattle-cluster-agent (Deployment)
        |     |-- WebSocket connection TO the Rancher server (outbound only)
        |     |-- Proxies kubectl/API requests from Rancher to the downstream API server
        |     +-- Reports cluster status, metrics, events
        +-- cattle-node-agent (DaemonSet, optional)
              |-- Node-level operations (provisioning, cleaning)
              +-- Used during initial provisioning
```

**Key design**: agents connect outbound to Rancher. No inbound ports are needed on downstream clusters. This simplifies firewall rules and works across NAT boundaries.

**Connection resilience**: if the Rancher server is unavailable, downstream clusters continue to operate independently. Agents reconnect automatically when Rancher is available again.

## RKE2 architecture

### Component layout

```
RKE2 Server Node
  |-- rke2 binary (manages all components)
  |-- containerd (container runtime)
  |-- kubelet (node agent)
  |-- kube-apiserver (embedded)
  |-- kube-controller-manager (embedded)
  |-- kube-scheduler (embedded)
  |-- etcd (embedded etcd cluster member)
  |-- kube-proxy (or a Cilium eBPF replacement)
  +-- CNI plugin (Canal, Calico, or Cilium)

RKE2 Agent Node
  |-- rke2 binary
  |-- containerd
  |-- kubelet
  |-- kube-proxy (or Cilium)
  +-- CNI plugin
```

### CIS hardening

RKE2 with `profile: cis` automatically applies:

| CIS control | RKE2 implementation |
|---|---|
| API server audit logging | Enabled by default |
| etcd encryption at rest | Configurable (`secrets-encryption: true`) |
| RBAC enabled | Always |
| PodSecurity admission | Configured (restricted profile on system namespaces) |
| Network policies | Default deny in system namespaces |
| Service account tokens | Auto-mount disabled by default |
| Kubelet protections | Anonymous auth disabled, read-only port disabled |

### etcd management

```bash
# Snapshot (automatic via config, or manual)
rke2 etcd-snapshot save --name manual-backup

# List snapshots
rke2 etcd-snapshot list

# Restore
rke2 server --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/<snapshot>
```

**S3 backup**: RKE2 can automatically push etcd snapshots to S3. Keep the access and secret keys in a secret store, not committed to `config.yaml`:

```yaml
# /etc/rancher/rke2/config.yaml
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 10
etcd-s3: true
etcd-s3-bucket: my-rke2-backups
etcd-s3-region: us-east-1
etcd-s3-access-key: <from-secret-store>
etcd-s3-secret-key: <from-secret-store>
```

### Certificate rotation

RKE2 automatically rotates certificates:

- Kubelet client certificates rotate automatically.
- API server and controller manager certs: `rke2 certificate rotate`.
- Custom CA: provide your own CA during initial setup.

## K3s architecture

### Lightweight design

```
K3s Server
  |-- k3s binary (single binary, under 100 MB)
  |     |-- containerd (embedded)
  |     |-- kube-apiserver
  |     |-- kube-controller-manager
  |     |-- kube-scheduler
  |     |-- kubelet
  |     +-- kube-proxy
  |-- SQLite (default, single-server) or embedded etcd (HA)
  +-- Built-in add-ons:
        |-- Flannel (CNI)
        |-- CoreDNS
        |-- Traefik (ingress)
        |-- local-path-provisioner (storage)
        |-- metrics-server
        +-- ServiceLB (formerly Klipper LB)
```

### Disable built-in components

```bash
# Disable Traefik (use your own ingress)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

# Disable ServiceLB (use MetalLB instead)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable servicelb" sh -

# Disable Flannel (use Cilium or Calico)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none --disable-network-policy" sh -
```

### Edge deployment patterns

**Single-node edge**:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
```

**HA edge** (3 nodes with embedded etcd):

```bash
# Node 1
curl -sfL https://get.k3s.io | K3S_TOKEN=mysecret sh -s - server --cluster-init

# Nodes 2 and 3
curl -sfL https://get.k3s.io | K3S_TOKEN=mysecret sh -s - server --server https://node1:6443
```

**Air-gapped installation**:

```bash
# Pre-stage images
mkdir -p /var/lib/rancher/k3s/agent/images/
cp k3s-airgap-images-amd64.tar.gz /var/lib/rancher/k3s/agent/images/

# Install with a pre-staged binary
INSTALL_K3S_SKIP_DOWNLOAD=true ./install.sh
```

## Fleet architecture

### Reconciliation flow

```
GitRepo (user-defined)
  -> Git clone/pull (every pollingInterval)
Fleet controller
  -> Parse paths (Helm charts, Kustomize, raw YAML)
Bundle (auto-generated per path)
  -> Match targets (clusterSelector, clusterGroup)
BundleDeployment (one per Bundle x target cluster)
  -> Fleet agent on the target cluster
Helm install/upgrade (or kubectl apply for raw YAML)
```

### Bundle processing

Fleet processes Git repository contents in this order:

1. Look for `fleet.yaml` in each path.
2. If `Chart.yaml` exists, treat as a Helm chart.
3. If `kustomization.yaml` exists, treat as Kustomize.
4. Otherwise, treat as raw YAML manifests.

`fleet.yaml` is optional. Without it, Fleet uses defaults (auto-detected format, default namespace).

### Multi-cluster targeting

```yaml
# Target by cluster labels
targets:
  - name: production
    clusterSelector:
      matchLabels:
        env: production
      matchExpressions:
        - key: region
          operator: In
          values: ["us-east-1", "us-west-2"]

# Target by cluster group
targets:
  - name: us-clusters
    clusterGroup: us-regions

# Target all clusters
targets:
  - name: everywhere
    clusterSelector: {}
```

### Fleet drift detection

Fleet monitors deployed resources for drift:

- If a resource is modified outside Fleet (for example `kubectl edit`), Fleet detects the change.
- Fleet can auto-remediate by re-applying the expected state.
- Or it reports the drift without remediation (configurable).

```yaml
# fleet.yaml
correctDrift:
  enabled: true          # auto-remediate drift
  force: false           # force apply (overwrite conflicts)
  keepFailHistory: true
```

## Harvester architecture

### Components

```
Harvester Cluster
  |-- RKE2 (Kubernetes layer)
  |-- KubeVirt (VM workload API)
  |     |-- virt-controller (watches VirtualMachine CRs)
  |     |-- virt-handler (DaemonSet, manages VMs on each node)
  |     +-- virt-launcher (per-VM pod, runs QEMU/KVM)
  |-- Longhorn (distributed block storage)
  |     |-- Replicated volumes across nodes
  |     |-- Snapshots and backups (S3/NFS)
  |     +-- Volume encryption
  |-- Multus CNI (multi-network for VMs)
  |     +-- VLAN, bridge, SR-IOV network attachments
  +-- Harvester controller
        |-- VM lifecycle management
        |-- VM template management
        |-- Network management
        +-- Rancher integration (nested Kubernetes provisioning)
```

### VM management

```yaml
# VM template
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineTemplate
metadata:
  name: ubuntu-template
  namespace: default
spec:
  description: Ubuntu 22.04 template
  versions:
    - name: v1
      vm:
        spec:
          template:
            spec:
              domain:
                cpu:
                  cores: 2
                memory:
                  guest: 4Gi
                devices:
                  disks:
                    - name: rootdisk
                      disk:
                        bus: virtio
                  interfaces:
                    - name: default
                      masquerade: {}
              volumes:
                - name: rootdisk
                  containerDisk:
                    image: ubuntu:22.04
              networks:
                - name: default
                  pod: {}
```

### Storage architecture (Longhorn)

Longhorn provides distributed block storage for Harvester:

```
Volume (requested by a VM or PVC)
  |-- Engine (iSCSI target, runs on the node where the volume is attached)
  +-- Replicas (data copies, distributed across nodes)
       |-- Replica 1 (Node A)
       |-- Replica 2 (Node B)
       +-- Replica 3 (Node C)
```

Features: automatic replica rebuilding, scheduled snapshots, backup to S3/NFS, volume encryption, and clone.

### Nested Kubernetes on Harvester

Rancher can provision RKE2/K3s clusters using Harvester VMs as infrastructure:

```
Rancher -> Provisioning v2 -> Harvester node driver -> create VMs -> install RKE2/K3s
```

This enables a fully integrated stack: bare metal to Harvester to VMs to Kubernetes clusters, all managed from Rancher.

## Authentication integration

### SAML (ADFS, Okta, Azure AD)

```
User -> Rancher login page -> redirect to IdP -> SAML assertion -> Rancher validates -> session created
```

### LDAP / Active Directory

```
User -> Rancher login -> Rancher queries the LDAP server -> validates credentials -> maps groups to Rancher roles
```

Configuration:

- Service account DN for LDAP binding.
- User search base and filter.
- Group search base and filter.
- Group-to-role mappings (AD group `k8s-admins` to Rancher `Cluster Owner`).

### OIDC

```
User -> Rancher login -> redirect to the OIDC provider -> authorization code flow -> token exchange -> session
```

Compatible providers: Keycloak, Okta, Azure AD, Google Workspace, Auth0. Store OIDC client secrets and LDAP bind credentials in a secret store, not a committed values file.

## CIS Benchmark scanning

Rancher includes built-in CIS Kubernetes Benchmark scanning:

```
# Via Rancher UI: Cluster -> CIS Benchmark -> Run Scan
# Profiles: CIS 1.8 (K8s 1.27+), CIS 1.9 (K8s 1.29+), RKE2 permissive, RKE2 hardened
```

Scan results show:

- **Pass**: control is satisfied.
- **Fail**: control is not satisfied (with remediation guidance).
- **Skip**: control is not applicable.
- **Not Applicable**: the environment does not support the control.

Scheduled scans run CIS benchmarks on a cron schedule with automatic report generation. The scan surfaces findings; the security programme that decides how to gate and remediate them is `container-security`.

## Sizing and performance

### Rancher server

| Metric | Small (<=10 clusters) | Medium (10-50) | Large (50-100) | Enterprise (100+) |
|---|---|---|---|---|
| Rancher replicas | 3 | 3 | 3 | 3 |
| CPU per replica | 2 vCPU | 4 vCPU | 8 vCPU | 16 vCPU |
| Memory per replica | 4 GB | 8 GB | 16 GB | 32 GB |
| Management cluster nodes | 3 | 3 | 5 | 5 |
| etcd disk | SSD, 50 GB | SSD, 100 GB | SSD, 200 GB | NVMe, 500 GB |

### RKE2 cluster

| Nodes | Control plane sizing |
|---|---|
| <=50 | 3 CP nodes, 4 vCPU, 8 GB RAM |
| 50-200 | 3 CP nodes, 8 vCPU, 16 GB RAM |
| 200-500 | 5 CP nodes, 16 vCPU, 32 GB RAM |
| 500+ | 5 CP nodes, 32 vCPU, 64 GB RAM |

### K3s edge

| Deployment | Resources |
|---|---|
| Single-node | 1 vCPU, 1 GB RAM minimum (2 vCPU, 2 GB recommended) |
| HA (3 nodes) | 2 vCPU, 4 GB RAM per node |
| Agent node | 0.5 vCPU, 512 MB RAM minimum |
