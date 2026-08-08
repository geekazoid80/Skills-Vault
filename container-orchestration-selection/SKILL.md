---
name: container-orchestration-selection
description: "Vendor-neutral container orchestration platform selection and comparison reasoning: self-managed Kubernetes vs managed Kubernetes (EKS, AKS, GKE) vs OpenShift vs Rancher vs lightweight and edge distributions (K3s, RKE2, MicroK8s, Kind, Minikube), and which orchestrator earns a given workload, team, compliance posture, and cloud footprint. Owns the self-managed-vs-managed decision and the which-managed-provider decision, not how to operate one. WHEN: \"orchestration\", \"Kubernetes vs\", \"which orchestrator\", \"managed Kubernetes\", \"EKS or AKS or GKE\", \"OpenShift\", \"Rancher\", \"K3s\", \"RKE2\", \"cluster management\", \"container platform selection\", \"self-managed vs managed Kubernetes\", \"orchestration comparison\", \"pick a container platform\". Do NOT use for: deep per-platform implementation (kubectl, pods, RBAC, scheduling, Helm charts, Routes, SCC, Fleet), which routes to kubernetes-ops, helm-ops, openshift-ops, or rancher-ops; managed-provider control-plane, IAM, and node-pool implementation depth (EKS, AKS, GKE lifecycle), which routes to aws-cloud-ops, azure-cloud-ops, or gcp-cloud-ops; container runtime and engine selection (Docker vs Podman vs containerd), which routes to container-runtime-selection; container and cluster SECURITY (image scanning, admission control policy, runtime protection, supply chain), which routes to container-security."
license: MIT
metadata:
  version: 1.0.0
---

# Container orchestration selection

> **Skill marker**: When applying this skill, begin your reply with `[skill: container-orchestration-selection]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for choosing a container orchestration platform. It owns the reasoning that survives any one product: whether an orchestrator is warranted at all, whether to run a cluster self-managed or hand the control plane to a provider, which managed provider (EKS, AKS, GKE) fits a given cloud and team, and where OpenShift, Rancher, and the lightweight and edge distributions earn their place. Platform-specific configuration and operations (kubectl workflows, Helm charts, OpenShift Routes and SCC, Rancher Fleet, and the managed-provider node-pool and IAM lifecycle) live in the per-platform sibling skills; the depth here is the selection logic that outlasts a platform change.

## When to use

- Comparing orchestration platforms (self-managed Kubernetes versus managed versus OpenShift versus Rancher) for a new project or an existing estate.
- Deciding whether to run Kubernetes self-managed or on a managed control plane, and what each choice costs in operational burden.
- Choosing among the managed providers (EKS, AKS, GKE) given a cloud footprint, team skillset, and workload profile.
- Selecting a lightweight or edge distribution (K3s, RKE2, MicroK8s, Kind, Minikube) for constrained nodes, CI runners, or local development.
- Weighing an opinionated enterprise platform (OpenShift) or a multi-cluster management layer (Rancher) against upstream Kubernetes.
- Understanding the cross-platform architectural framing (declarative desired state, reconciliation, when to orchestrate at all) that applies before any product is named.

## When not to use

- **Deep per-platform implementation and operations**: the exact kubectl workflow, pod and deployment spec, RBAC binding, scheduling constraint, Helm chart, OpenShift Route or SecurityContextConstraint, or Rancher Fleet GitOps setup. Use the sibling platform skills `kubernetes-ops`, `helm-ops`, `openshift-ops`, or `rancher-ops`. This umbrella decides which platform fits; those build and run it.
- **Managed-provider control-plane, IAM, and node-pool implementation depth**: the EKS, AKS, or GKE cluster lifecycle, provider IAM integration (IRSA and Pod Identity, Azure Workload Identity, GKE Workload Identity Federation), CNI wiring, node-pool and autoscaler configuration, and provider billing. There are no standalone eks, aks, or gke skills; that depth lives in `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops`. This skill owns which managed provider to choose; those own how to stand one up and operate it.
- **Container runtime and engine selection**: Docker versus Podman versus containerd, daemonless and rootless requirements, and the low-level OCI runtime beneath a node. Use `container-runtime-selection` (sibling umbrella). This skill places runtimes under an orchestrator; that one compares the runtimes themselves.
- **Container and cluster security**: image scanning and CI gates, admission-control policy as a security control, runtime protection, Pod Security Standards enforcement, and supply-chain integrity. Use `container-security`. The concept reference here explains the admission pipeline as an orchestration mechanism; using it as a security boundary is that skill's ground.
- **Service mesh selection**: whether to adopt a mesh and which one, routes to `service-mesh-selection`.

## Classify the request first

Every request resolves to one of these, which determines whether the concept reference is needed:

| Class | Examples | Where the depth lives |
|---|---|---|
| Self-managed versus managed | Own the control plane or offload it, air-gapped or regulated constraints, cloud lock-in avoidance, dedicated platform team availability | this SKILL.md, "Platform comparison framework" below |
| Which managed provider | EKS versus AKS versus GKE for a given cloud, IAM model, autoscaler, serverless-pod and Autopilot options | this SKILL.md, "Managed Kubernetes" below (provider IMPLEMENTATION depth routes to the cloud-ops skills) |
| Enterprise or multi-cluster platform | OpenShift for regulated enterprise, Rancher for many-cluster management across clouds and on-prem | this SKILL.md, "OpenShift" and "Rancher" below |
| Lightweight or edge | K3s, RKE2, MicroK8s, Kind, Minikube for edge, IoT, CI, or local dev | this SKILL.md, "Lightweight and edge" below |
| Fundamentals: how orchestration works | Desired state, reconciliation loops, operators, CRDs, admission control, control-plane components, scheduling, multi-tenancy | `references/concepts.md` |

## Core model (condensed)

**Orchestration is declarative reconciliation, not a fancier way to run containers.** You declare a desired state (so many replicas, this much memory, these health checks) and a set of controllers work continuously to make reality match. That control loop is what buys self-healing, rollout and rollback, and horizontal scaling. Every platform below implements the same pattern; they differ in who operates the control plane, how opinionated the platform is, and how many clusters it is built to manage.

**Decide whether you need an orchestrator at all before choosing one.** A single-host deployment or a small project is often better served by Compose or a systemd-managed runtime than by a cluster whose operational cost it cannot amortise. Reach for orchestration when you need horizontal scaling, self-healing, rolling deployments across many nodes, or declarative multi-service topology. When the answer is "not yet", the runtime question routes to `container-runtime-selection`.

**Gather the deciding context before recommending.** The right platform turns on: the cloud footprint (a single cloud favours its managed offering; multi-cloud or on-prem changes the calculus); team expertise and whether a dedicated platform team exists; compliance and regulatory constraints (air-gapped, data residency, hardened-by-default); scale and cluster count (one cluster versus a fleet); workload profile (stateless services, ML and AI, edge and IoT); and the appetite for operational burden versus vendor lock-in.

## Platform comparison framework

Use this when the question is "which platform should I use" or "X versus Y".

### Self-managed Kubernetes

**When to choose**: full control over the control plane; air-gapped or highly regulated environments; avoidance of cloud vendor lock-in; custom control-plane configuration (non-standard admission controllers, custom schedulers).

**Trade-offs**: you own upgrades, etcd backups, high availability, and certificate rotation. Significant operational burden that realistically needs a dedicated platform team.

**Distributions**: kubeadm (upstream), RKE2 (CIS-hardened), K3s (lightweight and edge).

### Managed Kubernetes (EKS, AKS, GKE)

**When to choose**: cloud-native workloads; a desire to offload control-plane operations; integration with the provider's IAM, networking, storage, and observability; a team that would rather focus on applications than infrastructure. **This umbrella owns which provider to pick; the lifecycle, IAM, and node-pool implementation depth routes to `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops`.**

| Dimension | EKS | AKS | GKE |
|---|---|---|---|
| Control plane SLA | 99.95% | 99.95% (Standard tier; Free tier is a 99.9% SLO) | 99.95% (regional) |
| Node autoscaling | Karpenter (recommended) or Cluster Autoscaler | Karpenter (NAP) or Cluster Autoscaler | Node Auto-Provisioning or Cluster Autoscaler |
| Serverless pods | Fargate | Virtual Nodes (ACI) | Autopilot mode |
| IAM integration | IRSA / Pod Identity | Workload Identity | Workload Identity Federation |
| Default CNI | VPC CNI (pod IPs from the VPC) | Azure CNI or kubenet | GKE CNI (VPC-native) |
| GitOps built-in | Flux (add-on) | Flux (add-on) | Config Sync (Enterprise) |
| Policy engine | OPA / Gatekeeper (add-on) | Azure Policy (built-in) | Policy Controller (Enterprise) |
| Cost model | Per-cluster hourly fee plus nodes | Free control plane plus nodes | Per-cluster hourly fee plus nodes; Autopilot bills per pod |
| Best for | AWS-heavy orgs, Karpenter-first | Azure and hybrid orgs, .NET workloads | GCP orgs, ML and AI, Autopilot simplicity |

The provider decision usually follows the existing cloud: run the managed Kubernetes of the cloud you already operate in, unless a specific capability (Autopilot's hands-off model, Karpenter's provisioning, a particular IAM federation) tips it. Multi-cloud by choice is a Rancher or fleet-management conversation, not three managed clusters run by hand.

### OpenShift

**When to choose**: enterprise requiring integrated CI/CD (Source-to-Image builds), an operator marketplace (OLM), hardened-by-default security (SecurityContextConstraints), an integrated monitoring and logging stack, and Red Hat enterprise support. Common in financial services, government, and regulated industries.

**Trade-offs**: higher licensing cost; an opinionated platform where some upstream patterns work differently (Routes rather than Ingress, SCC rather than Pod Security Standards); and slower version adoption, typically a version or two behind upstream Kubernetes.

### Rancher

**When to choose**: multi-cluster management across clouds and on-prem; centralised RBAC and policy for dozens to hundreds of clusters; edge deployments (K3s); and the need to manage heterogeneous cluster types (EKS plus AKS plus on-prem RKE2) from a single pane.

**Trade-offs**: Rancher is a management layer, not a distribution itself (it runs RKE2 or K3s underneath). Fleet GitOps is powerful but adds complexity, and the Rancher server is a single point of management failure, so deploy it in HA.

### Lightweight and edge

**When to choose**: edge locations, IoT gateways, CI/CD runners, and development environments; resource-constrained nodes (ARM, low memory).

| Distribution | Binary size | Default store | Target |
|---|---|---|---|
| K3s | Under 100MB | SQLite | Edge, IoT, dev |
| RKE2 | Single bundle | etcd (CIS-hardened) | Regulated edge and on-prem production |
| MicroK8s | Around 200MB | dqlite | Dev, single-node |
| Kind | Runs in a container | Per the container | CI/CD testing |
| Minikube | Around 90MB | etcd | Local dev |

### Decision matrix

| Requirement | Self-managed | Managed (EKS/AKS/GKE) | OpenShift | Rancher | Lightweight |
|---|---|---|---|---|---|
| Control-plane ops burden | You own all of it | Offloaded to provider | Red Hat-supported, still yours to run | Managed clusters, Rancher server is yours | Minimal, single binary |
| Cloud lock-in | Lowest | Highest (per provider) | Portable across clouds | Portable, multi-cloud by design | Lowest |
| Regulated / air-gapped | Best fit | Provider-dependent | Strong (hardened default) | Supported | RKE2 for hardened edge |
| Multi-cluster fleet | Manual | Per-provider tooling | Advanced Cluster Management add-on | Best fit | Not the target |
| Edge / constrained nodes | K3s / RKE2 | Not the target | Heavy footprint | K3s under Rancher | Best fit |
| Time to first cluster | Slowest | Fast | Moderate | Moderate | Fastest |

**Anti-patterns:** reaching for Kubernetes when a single host and Compose would do; running three managed clouds by hand instead of a fleet-management layer; picking a managed provider that fights your existing cloud's IAM and networking; assuming OpenShift is drop-in upstream Kubernetes (Routes and SCC differ); treating the Rancher server as disposable rather than an HA-critical control point; and choosing self-managed without the platform team to carry upgrades, etcd backups, and certificate rotation.

## Reference router

- `references/concepts.md`: orchestration fundamentals that apply across every platform, desired state and declarative management, reconciliation loops, operators, custom resource definitions, admission control, control-plane components, scheduling, service discovery, and multi-tenancy models. Load it when the request needs conceptual grounding rather than a platform pick.

## Cross-references

- `container-runtime-selection` (sibling umbrella): the runtime layer beneath the orchestrator, Docker versus Podman versus containerd, daemonless and rootless, and the OCI runtime. This skill places a runtime under a cluster; that one compares the runtimes.
- `kubernetes-ops`: core Kubernetes operations, pods, deployments, services, RBAC, scheduling, and networking. This umbrella decides whether Kubernetes fits; that skill runs it.
- `helm-ops`: Helm package management, charts, templates, values, Helmfile, and helm-secrets, the deployment layer on top of a chosen cluster.
- `openshift-ops`: OpenShift operations, OLM, Routes, SecurityContextConstraints, BuildConfigs, and ImageStreams. This umbrella decides whether OpenShift fits; that skill runs it.
- `rancher-ops`: Rancher operations, multi-cluster management, RKE2 and K3s provisioning, Fleet GitOps, and Harvester. This umbrella decides whether Rancher fits; that skill runs it.
- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`: the managed-Kubernetes implementation depth (EKS, AKS, GKE cluster lifecycle, provider IAM, CNI, node pools, and autoscalers). This skill chooses the provider; those operate it. There are no standalone eks, aks, or gke skills.
- `container-security`: image scanning and CI gates, admission-control policy as a control, runtime protection, Pod Security Standards, and supply-chain integrity. This skill selects a platform; that one secures it.
- `service-mesh-selection`: whether to adopt a service mesh and which one; the cross-cluster and cross-service traffic, identity, and observability layer above orchestration.
- `load-balancer-selection`: choosing how to expose cluster services externally (LoadBalancer, ingress controllers, and the layer-4 versus layer-7 decision) beyond the in-cluster ClusterIP.
- `cert-manager`: automated TLS certificate issuance and rotation for ingress and in-cluster workloads on a chosen platform.
- `hashicorp-vault-ops`: secret management and dynamic credentials for workloads running on the orchestrated cluster.
- `prometheus-configuration`, `grafana-dashboards`: metrics collection and dashboards for the cluster and the workloads it schedules.
- `cicd-platforms-ops`: the delivery pipelines that build images and deploy them onto the chosen platform.
- `terraform-iac-ops`: provisioning the clusters and managed platforms this skill selects, declaratively and reproducibly.
- `utc-timestamps`: cluster event and audit-log correlation depends on UTC, NTP-synchronised clocks; skew corrupts the timeline across a fleet.

## Red flags

- About to recommend Kubernetes for a single-host or small project whose operational cost a cluster cannot amortise, where Compose or a systemd-managed runtime is the honest answer.
- About to choose a managed provider that fights the organisation's existing cloud, IAM, and networking, instead of running the managed Kubernetes of the cloud already in use.
- About to stand up several managed clusters across clouds by hand when a fleet-management layer (Rancher, or a provider's multi-cluster tooling) is what the requirement actually describes.
- About to treat OpenShift as drop-in upstream Kubernetes, missing that Routes replace Ingress and SecurityContextConstraints replace Pod Security Standards.
- About to pick self-managed Kubernetes without the dedicated platform team to carry upgrades, etcd backups, high availability, and certificate rotation.
- About to reach into EKS, AKS, or GKE lifecycle and IAM depth in this umbrella instead of routing that to `aws-cloud-ops`, `azure-cloud-ops`, or `gcp-cloud-ops`.
- About to deploy the Rancher server as a single non-HA control point for a fleet that then depends on it.
- About to select a platform from familiarity before the cloud footprint, team expertise, compliance constraints, scale, and workload profile are known.

## Bottom line

Choose the orchestration platform from the operational model the deployment needs, not from habit or hype. First decide whether you need an orchestrator at all; a single host is often better served by a runtime and Compose. If you do, the axis is who runs the control plane: self-managed earns air-gapped, regulated, and lock-in-averse estates that can staff a platform team; managed Kubernetes earns cloud-native workloads that would rather offload the control plane, and it usually follows the cloud you already run; OpenShift earns regulated enterprises that want a hardened, supported, batteries-included platform; Rancher earns fleets spanning clouds and on-prem; and the lightweight distributions earn the edge, CI, and local development. This umbrella owns the self-managed-versus-managed decision and the which-managed-provider decision; it routes provider implementation depth to the cloud-ops skills, and it hands off to the per-platform sibling when the question turns to operating, securing, meshing, or watching a cluster run.
