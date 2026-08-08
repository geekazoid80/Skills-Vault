---
name: rancher-ops
description: "Operating SUSE Rancher, the multi-cluster Kubernetes management layer, and its distributions: the Rancher management server (HA Helm deploy, downstream agents), RKE2 (CIS-hardened, FIPS) vs K3s (lightweight edge), Fleet GitOps at scale, Harvester HCI (KubeVirt + Longhorn), Provisioning v2 cluster lifecycle, and centralised multi-cluster RBAC, projects, and authentication (AD/LDAP/SAML/OIDC). WHEN: \"Rancher\", \"RKE2\", \"K3s\", \"Fleet GitOps\", \"Harvester\", \"multi-cluster management\", \"cluster provisioning\", \"Rancher projects\", \"centralized RBAC across clusters\", \"edge Kubernetes\", \"cattle.io\", \"cattle-cluster-agent\", \"Provisioning v2\", \"import a cluster\". Do NOT use for: generic Kubernetes operations and internals that are not Rancher-specific (kubernetes-ops); the orchestration platform choice such as Rancher-vs-OpenShift-vs-plain-Kubernetes (container-orchestration-selection); Helm chart authoring depth (helm-ops); OpenShift operations (openshift-ops); cluster security scanning and policy-as-security strategy (container-security); provider depth when Rancher manages a managed cluster (aws-cloud-ops, azure-cloud-ops, gcp-cloud-ops); service mesh selection (service-mesh-selection)."
license: MIT
metadata:
  version: 1.0.0
---

# Rancher operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: rancher-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns SUSE Rancher operations: standing up and running the Rancher management server, provisioning and importing downstream clusters, driving multi-cluster delivery with Fleet, running Harvester HCI, and administering centralised RBAC, projects, and authentication across a fleet of clusters. Rancher is a **management layer, not a Kubernetes distribution**. It sits above clusters and drives them; the clusters themselves run RKE2, K3s, or an imported distribution underneath. Generic Kubernetes operation that is not Rancher-specific (workloads, `kubectl`, controllers, the API objects any cluster has) belongs in `kubernetes-ops`; this skill covers the Rancher-specific layer on top. The orchestration-platform choice (Rancher vs OpenShift vs plain Kubernetes vs a managed service) is `container-orchestration-selection`; this skill operates Rancher once that choice is made.

## When to use

- Deploying or running the Rancher management server: HA Helm install, TLS source, downstream agent connectivity, server sizing for a given cluster count.
- Choosing and operating a distribution under Rancher: RKE2 for CIS-hardened, FIPS-validated production; K3s for lightweight edge and IoT; the RKE2-vs-K3s trade-off.
- Provisioning a new cluster (Provisioning v2 / `provisioning.cattle.io`) or importing an existing one (EKS/AKS/GKE or any conformant cluster) into Rancher.
- Multi-cluster continuous delivery with Fleet: `GitRepo`, `fleet.yaml`, `Bundle`/`BundleDeployment`, target customisation, drift detection, hundreds-to-thousands-of-clusters scale.
- Running Harvester HCI: VMs as Kubernetes resources (KubeVirt), Longhorn distributed storage, Multus networking, and provisioning nested clusters on Harvester VMs.
- Administering centralised RBAC and multi-tenancy: global/cluster/project roles, projects as namespace groupings, project resource quotas and NetworkPolicy.
- Wiring authentication: Active Directory, LDAP, SAML, OIDC, and group-to-role mappings.
- Troubleshooting the Rancher layer: agent connectivity, cluster import failures, Fleet sync failures, CIS scan results.

## When not to use

- **Generic Kubernetes operations**: workload objects, `kubectl` mechanics, controllers, services, ingress objects, and cluster internals that any Kubernetes cluster has (not Rancher-specific) are `kubernetes-ops`. RKE2 and K3s are Kubernetes; their non-Rancher operation is there. This skill covers the Rancher-specific management on top and the RKE2/K3s install and config that Rancher cares about.
- **Orchestration-platform selection**: choosing between Rancher, OpenShift, plain upstream Kubernetes, or a managed service is `container-orchestration-selection`. That umbrella decides the platform; this skill operates Rancher once chosen.
- **Sibling orchestration skills**: OpenShift operation is `openshift-ops`; Helm chart authoring depth (templating, chart structure, releases) is `helm-ops`. Rancher deploys via Helm and Fleet wraps Helm, but the chart-authoring craft lives there.
- **Cluster security strategy**: image scanning as a gate, admission control (OPA Gatekeeper, Kyverno, Pod Security Standards), supply-chain integrity, and behavioural runtime protection are `container-security`. Rancher runs CIS Benchmark scans and RKE2 hardens by default; the security programme that decides how to use those lives there.
- **Managed-provider depth**: when Rancher imports or provisions a managed cluster (EKS, AKS, GKE) the provider-side depth (node groups, IAM, VPC, provider load balancers) is `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops`. Rancher's view of the cluster is here; the cloud account underneath is there.
- **Observability**: Rancher bundles a per-cluster Prometheus/Grafana monitoring app, but deep metric and dashboard configuration is `prometheus-configuration` and `grafana-dashboards`. Installing the monitoring app is here; authoring the alerts and dashboards is there.
- **CD pipelines**: Fleet is Rancher-native GitOps and is covered here, but generic CI/CD pipeline design and non-Fleet delivery are `cicd-platforms-ops` and `gh-actions-ci`.
- **Secrets and certificates**: operating a central secret store is `hashicorp-vault-ops`; the handling discipline for any token, kubeconfig, registry credential, or S3 backup key is `secrets-hygiene`.
- **Service mesh**: choosing and running a mesh (Istio, Linkerd, Cilium mesh) is `service-mesh-selection`. Rancher can install a mesh app, but the mesh decision routes out.

## Classify the request first

Every request resolves to one of these, which determines where the depth lives. Also identify the context: which distribution (RKE2, K3s, imported EKS/AKS/GKE), on-prem or cloud, and how many clusters. If unclear, ask.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | management-server components, downstream agent WebSocket model, RKE2/K3s component layout, Fleet reconciliation flow, Harvester (KubeVirt/Longhorn/Multus), authentication flows, CIS scanning, sizing | `references/architecture.md` |
| Distribution operation | RKE2 install and `config.yaml`, K3s install and disabled add-ons, HA with embedded etcd, etcd snapshot/restore, RKE2-vs-K3s choice | This body + `references/architecture.md` |
| Cluster provisioning / import | Provisioning v2 `Cluster` (`provisioning.cattle.io`), machine pools, infrastructure providers, importing an existing cluster | This body |
| GitOps (Fleet) | `GitRepo`, `fleet.yaml`, `Bundle`/`BundleDeployment`, target customisation, drift, scale | This body |
| Multi-cluster RBAC / projects | global/cluster/project roles, projects, quotas, project NetworkPolicy, auth integration | This body |
| Troubleshooting | agent connectivity, import failures, Fleet sync failures, CIS results | This body + `references/architecture.md` |

## Core model (condensed)

**A management server drives downstream clusters through outbound agents.** The Rancher server is a Helm-deployed application on a dedicated management cluster (RKE2 recommended). Each managed cluster runs a `cattle-cluster-agent` that connects **outbound** to the server over a WebSocket, so no inbound firewall ports are needed on downstream clusters and the model works across NAT.

```
Rancher Management Cluster (RKE2 or K3s)
  |-- Rancher Server (Helm chart, 3 replicas for HA)
  |     |-- Authentication (AD, LDAP, SAML, OIDC, GitHub, Google, Keycloak)
  |     |-- RBAC (global roles, cluster roles, project roles)
  |     |-- Cluster management (provision, import, monitor)
  |     +-- App catalog (Helm charts, Fleet GitOps)
  |-- Fleet controller (GitRepo -> Bundle -> BundleDeployment)
  +-- Downstream clusters, each running:
        |-- cattle-cluster-agent (Deployment, outbound WebSocket to server)
        +-- cattle-node-agent (DaemonSet, used during provisioning)
```

**Rancher is a layer, not a cluster.** It never replaces the Kubernetes underneath. RKE2 and K3s are the SUSE-supported distributions Rancher provisions; imported clusters keep their own distribution. If the Rancher server is unavailable, downstream clusters keep running independently and their agents reconnect automatically.

**Fleet is the built-in GitOps engine.** A `GitRepo` is polled; Fleet parses each path into a `Bundle`; each `Bundle` targets clusters by label or group and becomes a `BundleDeployment` per cluster. Designed for hundreds to thousands of clusters.

**Anti-patterns:** running the Rancher server on the same cluster it manages (couple the management plane to a workload cluster and an outage takes both); a single-replica Rancher server in production (no HA); importing a cluster and then also provisioning it (double management); leaning on the local (management) cluster for real workloads; opening inbound ports to downstream clusters when the agent model is outbound-only; hard-coding kubeconfigs and S3 backup keys in `config.yaml` committed to Git instead of a secret store; using K3s SQLite for anything that needs HA; skipping `profile: cis` on a cluster that has a compliance requirement.

## Rancher management server and HA

Rancher installs as a Helm chart into `cattle-system` on a dedicated management cluster. Run **three replicas** and a **dedicated RKE2 cluster with three control-plane nodes** for HA; do not run production workloads on the management cluster.

```bash
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm install rancher rancher-stable/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=rancher.example.com \
  --set replicas=3 \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=admin@example.com
```

TLS source options: Let's Encrypt (automatic), a bring-your-own certificate (production), Rancher-generated self-signed (development only), or termination at an external load balancer. Set the bootstrap password out-of-band, never in a committed values file (`secrets-hygiene`). Size the server to the managed-cluster count:

| Managed clusters | Rancher server (per replica) | Management cluster nodes |
|---|---|---|
| <=10 | 2 vCPU, 4 GB RAM | 3 |
| 10-50 | 4 vCPU, 8 GB RAM | 3 |
| 50-100 | 8 vCPU, 16 GB RAM | 5 |
| 100+ | 16 vCPU, 32 GB RAM | 5 |

## RKE2 vs K3s distributions

Both are CNCF-conformant Kubernetes distributions from SUSE. RKE2 targets hardened enterprise production; K3s targets lightweight edge and development. Rancher provisions and manages either.

| Aspect | K3s | RKE2 |
|---|---|---|
| Target | Edge, IoT, development | Enterprise production |
| Binary size | Under 100 MB | ~220 MB |
| Default CNI | Flannel | Canal (Calico policy + Flannel networking); Calico and Cilium supported |
| CIS hardening | Manual | Built-in via `profile: cis` |
| FIPS 140-2 | No | Yes (validated crypto modules) |
| Default datastore | SQLite (single server), embedded etcd for HA | Embedded etcd |
| Default ingress | Traefik | NGINX |
| Runtime | containerd | containerd |

**RKE2** (control plane, then agent):

```bash
curl -sfL https://get.rke2.io | sh -
systemctl enable --now rke2-server
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
systemctl enable --now rke2-agent
```

```yaml
# /etc/rancher/rke2/config.yaml
token: my-shared-secret          # keep out of Git; use a secret store
tls-san:
  - my-cluster.example.com
  - 10.0.0.10
cni: cilium                      # canal (default), calico, cilium
profile: cis                     # CIS hardening
etcd-snapshot-schedule-cron: "0 */6 * * *"
etcd-snapshot-retention: 10
```

**K3s**, including an HA cluster on embedded etcd:

```bash
# Single server (SQLite datastore)
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# HA: first server initialises the embedded-etcd cluster
curl -sfL https://get.k3s.io | K3S_TOKEN=mysecret sh -s - server --cluster-init
# Additional servers join
curl -sfL https://get.k3s.io | K3S_TOKEN=mysecret sh -s - server --server https://<first-server>:6443
# Agent joins
curl -sfL https://get.k3s.io | K3S_URL=https://<server>:6443 K3S_TOKEN=<token> sh -
```

K3s ships batteries-included (containerd, Flannel, CoreDNS, Traefik, local-path-provisioner, metrics-server, ServiceLB); disable what you replace, for example `--disable traefik` when you bring your own ingress or `--disable servicelb` for MetalLB. Air-gapped installs pre-stage images under `/var/lib/rancher/k3s/agent/images/`. Deeper component layout, etcd snapshot/restore and S3 backup, and certificate rotation are in `references/architecture.md`.

## Fleet GitOps

Fleet is Rancher's built-in multi-cluster continuous delivery. A `GitRepo` on the management cluster points Fleet at a repository; Fleet generates a `Bundle` per path and a `BundleDeployment` per target cluster, then a Fleet agent on each cluster applies it (Helm, Kustomize, or raw YAML, auto-detected).

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: myapp-config
  namespace: fleet-default
spec:
  repo: https://github.com/myorg/fleet-config
  branch: main
  paths:
    - apps/myapp
  targets:
    - name: production
      clusterSelector:
        matchLabels:
          env: production
  pollingInterval: 30s
```

Per-directory behaviour lives in a `fleet.yaml`, which sets the namespace, the Helm chart and values, and `targetCustomizations` that override values per cluster group (for example five replicas in production, one in staging). Fleet detects drift and can auto-remediate (`correctDrift.enabled: true`) or just report it. Fleet is built for hundreds to thousands of clusters with batched, parallel rollouts, so the targeting model (labels, `clusterGroup`, `clusterSelector: {}` for all) is the primary control surface.

| Resource | Purpose |
|---|---|
| GitRepo | A Git repository Fleet monitors |
| Bundle | Generated by Fleet from a `GitRepo` path |
| BundleDeployment | A Bundle applied to one target cluster |
| Cluster | A managed cluster (auto-created by Rancher) |
| ClusterGroup | A logical grouping of clusters for targeting |

Fleet is Rancher-native GitOps; generic CD outside Rancher routes to `cicd-platforms-ops` and `gh-actions-ci`, and Helm chart authoring depth to `helm-ops`.

## Cluster provisioning and import

**Provision** a fresh RKE2 or K3s cluster with Provisioning v2 (`provisioning.cattle.io/v1`), which manages machine pools through node drivers on the supported infrastructure providers (vSphere, AWS, Azure, GCP, DigitalOcean, Linode, Harvester):

```yaml
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  name: prod-rke2
  namespace: fleet-default
spec:
  kubernetesVersion: v1.31.5+rke2r1     # pin to a supported RKE2 release
  rkeConfig:
    machineGlobalConfig:
      cni: cilium
      profile: cis
    machinePools:
      - name: control-plane
        controlPlaneRole: true
        etcdRole: true
        quantity: 3
        machineConfigRef:
          kind: VmwarevsphereConfig
          name: cp-config
      - name: workers
        workerRole: true
        quantity: 5
        machineConfigRef:
          kind: VmwarevsphereConfig
          name: worker-config
```

**Import** an existing cluster (including a managed EKS/AKS/GKE cluster) by registering it: Rancher issues a registration manifest, you apply it on the target with `kubectl`, and its `cattle-cluster-agent` dials back out to the server. A cluster is either imported or Rancher-provisioned, never both. Validate either path with `kubectl get clusters.management.cattle.io` and the cluster status in the Rancher UI. For a managed cluster, the provider-side node and network depth routes to `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops`.

## Multi-cluster RBAC and projects

Rancher centralises access control across the whole fleet in three tiers, and propagates the bindings down to the target clusters.

```
Global roles (fleet-wide)
  |-- Admin (full access)
  |-- Restricted Admin (manage all clusters, not Rancher global settings)
  +-- Standard User (create clusters, manage own resources)
Cluster roles (per cluster): Cluster Owner, Cluster Member, custom
Project roles (per project): Project Owner, Project Member, Read Only, custom
```

**Projects** are a Rancher concept with no upstream-Kubernetes equivalent: a grouping of namespaces within one cluster. A project gives you shared RBAC (one binding applies to every namespace in the project), project-level resource quotas, and project-level NetworkPolicy isolation. Use projects for team or tenant boundaries inside a shared cluster.

Authentication integrates with Active Directory and LDAP (bind DN, user/group search bases, group-to-role mappings such as AD `k8s-admins` to Rancher Cluster Owner), SAML (ADFS, Okta, Azure AD), and OIDC (Keycloak, Okta, Azure AD, Google Workspace, Auth0). OIDC client secrets and LDAP bind credentials belong in a secret store (`secrets-hygiene`, `hashicorp-vault-ops`), never a committed values file.

## Harvester HCI

Harvester is SUSE's open-source hyperconverged infrastructure, built on RKE2, that runs virtual machines as Kubernetes resources so one control plane manages both VMs and containers. It is the common replacement target for VMware vSphere.

```
Harvester Cluster (RKE2-based)
  |-- KubeVirt (VMs as VirtualMachine CRs: virt-controller, virt-handler, virt-launcher)
  |-- Longhorn (distributed replicated block storage; snapshots and S3/NFS backup)
  |-- Multus CNI (multi-network for VMs: VLAN, bridge, SR-IOV)
  +-- Rancher integration (provision nested RKE2/K3s clusters on Harvester VMs)
```

Rancher can use Harvester as an infrastructure provider (a node driver), giving a fully integrated stack from bare metal to Harvester to VMs to Kubernetes clusters, all managed from Rancher. VM and storage internals (KubeVirt object model, Longhorn engine/replica layout) are in `references/architecture.md`.

## Reference router

- **Architecture and internals**: `references/architecture.md` for the management-server component breakdown, downstream-agent communication, RKE2/K3s component layout and etcd/snapshot mechanics, the Fleet reconciliation flow and drift model, Harvester (KubeVirt/Longhorn/Multus) deep dive, authentication flows, CIS Benchmark scanning, and sizing tables.

## Cross-references

- `container-orchestration-selection`: the vendor-neutral umbrella that decides Rancher vs OpenShift vs plain Kubernetes vs a managed service; this skill operates Rancher once that choice is made.
- `kubernetes-ops`: generic Kubernetes operation underneath Rancher (workloads, `kubectl`, controllers, cluster internals not specific to Rancher). RKE2 and K3s are Kubernetes; their non-Rancher operation lives there.
- `helm-ops`: Helm chart authoring depth. Rancher deploys via Helm and Fleet wraps Helm; the chart-authoring craft is there.
- `openshift-ops`: the sibling orchestration platform; use it for OpenShift-specific operation.
- `container-security`: cluster security scanning and policy-as-security strategy (admission control, supply-chain integrity, runtime protection) that Rancher's CIS scans and RKE2 hardening serve.
- `hashicorp-vault-ops`, `secrets-hygiene`: the central secret store and the handling discipline for kubeconfigs, cluster tokens, OIDC/LDAP credentials, and S3 backup keys. Never commit a real literal to `config.yaml` or a Fleet values file.
- `prometheus-configuration`, `grafana-dashboards`: Rancher bundles a per-cluster monitoring app; deep alert and dashboard configuration routes here.
- `cicd-platforms-ops`, `gh-actions-ci`: Fleet is Rancher-native GitOps and is covered in this skill, but generic CI/CD pipeline design and non-Fleet delivery route here.
- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`: when Rancher imports or provisions a managed cluster, the provider-side node, IAM, and network depth routes here.
- `service-mesh-selection`: choosing and running a service mesh; Rancher can install a mesh app, but the mesh decision routes out.
- `utc-timestamps`: cluster events, Fleet sync history, and CIS scan reports correlate across the fleet on UTC; a skewed node clock corrupts the timeline.

## Red flags

- About to run the Rancher server on the same cluster it manages, coupling the management plane to a workload cluster.
- About to deploy a single-replica Rancher server in production with no HA.
- About to run production workloads on the management (local) cluster.
- About to open inbound firewall ports to downstream clusters when the agent model is outbound-only.
- About to both import and provision the same cluster (double management).
- About to commit a cluster token, kubeconfig, OIDC secret, or S3 backup key into `config.yaml` or a Fleet values file instead of a secret store.
- About to use K3s SQLite for a cluster that needs HA (use embedded etcd or RKE2).
- About to skip `profile: cis` on a cluster with a compliance requirement, then bolt hardening on later.
- About to treat Rancher as the Kubernetes itself, or push generic `kubectl`/workload depth through this skill instead of `kubernetes-ops`.
- About to hand deep image-scanning or admission-control policy to Rancher's CIS scan instead of the `container-security` programme.

## Bottom line

Rancher is a management layer over Kubernetes, not a distribution: a Helm-deployed server on a dedicated HA cluster drives downstream clusters through outbound agents, so no inbound ports are needed. Under it, RKE2 is the hardened FIPS/CIS production distribution and K3s the lightweight edge one; provision either with Provisioning v2 or import an existing cluster (never both). Deliver to the fleet with Fleet GitOps (`GitRepo` to `Bundle` to `BundleDeployment`, targeted by label), centralise access with global/cluster/project roles and projects, and run Harvester when you need VMs and containers from one control plane. Keep the management cluster free of workloads, keep secrets out of `config.yaml` and Fleet values, and bring the platform choice from `container-orchestration-selection`, the generic-Kubernetes depth from `kubernetes-ops`, and the security programme from `container-security`.
