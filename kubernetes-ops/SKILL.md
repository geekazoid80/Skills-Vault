---
name: kubernetes-ops
description: "Operating Kubernetes clusters day to day: control plane (kube-apiserver, etcd, scheduler, controller manager) and data plane (kubelet, kube-proxy, CRI) internals, workload resources (Pods, Deployments, StatefulSets, DaemonSets, Jobs, CronJobs), scheduling (affinity, taints, topology spread, priority), networking (Services, Ingress, Gateway API, NetworkPolicy, CoreDNS, CNI), storage (PV, PVC, StorageClass, CSI, VolumeAttributesClass), RBAC and ServiceAccounts as access mechanics, autoscaling (HPA, VPA, cluster autoscaler, Karpenter), kubeadm cluster upgrades and node management, and kubectl troubleshooting. WHEN: \"Kubernetes\", \"kubectl\", \"pod\", \"deployment\", \"service\", \"StatefulSet\", \"DaemonSet\", \"CronJob\", \"kube-apiserver\", \"etcd\", \"kubelet\", \"kube-proxy\", \"RBAC\", \"NetworkPolicy\", \"Gateway API\", \"StorageClass\", \"CSI\", \"CRD\", \"operator\", \"HPA\", \"kubeadm\", \"cluster upgrade\", \"node drain\", \"K8s 1.34\", \"K8s 1.35\". Do NOT use for: choosing an orchestrator or the Kubernetes-vs-alternatives decision (container-orchestration-selection); Helm packaging, OpenShift, or Rancher operations (helm-ops, openshift-ops, rancher-ops); container runtime choice and per-runtime operation (container-runtime-selection, docker-ops, podman-ops, containerd-ops); ALL Kubernetes security depth such as Pod Security Standards, admission control, RBAC as a security control, network policy strategy, image scanning, supply chain and runtime protection (container-security); managed-Kubernetes provider depth EKS/AKS/GKE (aws-cloud-ops, azure-cloud-ops, gcp-cloud-ops); ingress and load balancing (load-balancer-selection, aws-load-balancing, nginx-load-balancing, haproxy-load-balancing); in-cluster certificates (cert-manager, lets-encrypt); secret stores (hashicorp-vault-ops, secrets-hygiene); observability (prometheus-configuration, grafana-dashboards, distributed-tracing); GitOps and CD pipelines (cicd-platforms-ops, gh-actions-ci); cluster provisioning as IaC (terraform-iac-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Kubernetes operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: kubernetes-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating a Kubernetes cluster once Kubernetes is the chosen orchestrator: reasoning about the control plane and data plane, designing and running workloads, wiring Services and network policy, provisioning storage, granting access with RBAC, autoscaling, upgrading with kubeadm, and troubleshooting with kubectl. It assumes Kubernetes has been chosen; the Kubernetes-versus-alternatives decision lives in `container-orchestration-selection`. It treats RBAC, ServiceAccounts, and NetworkPolicy at the operational level (the mechanics of granting and shaping access), but routes the security programme (Pod Security Standards adoption, admission control, image scanning gates, supply-chain integrity, runtime protection) to `container-security`.

Coverage spans recent Kubernetes releases, currently 1.33 through 1.36. The core model is stable across them; the moving parts are sidecar containers, VolumeAttributesClass, user namespaces, in-place pod resize, and the nftables kube-proxy mode, all in `## Version notes` with version-specific references under `references/versions/`.

## When to use

- Designing a workload: choosing Deployment versus StatefulSet versus DaemonSet versus Job/CronJob, init and sidecar containers, probes, QoS class, graceful termination, security context.
- Wiring networking: Service types, Ingress and the Gateway API, NetworkPolicy shape, CoreDNS behaviour, choosing and reasoning about a CNI.
- Provisioning storage: PV/PVC, StorageClass and dynamic provisioning, access modes, CSI drivers, VolumeAttributesClass.
- Granting access: Roles and ClusterRoles, RoleBindings, ServiceAccounts, `kubectl auth can-i` audits, token projection.
- Scheduling placement: nodeSelector, node and pod affinity, taints and tolerations, topology spread, PriorityClass and preemption.
- Autoscaling: HPA on resource or custom metrics, VPA right-sizing, cluster autoscaler and Karpenter node provisioning, PodDisruptionBudgets.
- Cluster operations: kubeadm upgrades, etcd backup and restore, node cordon/drain/uncordon, certificate rotation, namespace hygiene.
- Troubleshooting: a Pending, ContainerCreating, CrashLoopBackOff, ImagePullBackOff, or stuck-Terminating pod; `kubectl describe`, `logs`, `events`, `top`, `debug`, exit codes, control-plane and etcd health.

## When not to use

- **Orchestrator selection**: choosing Kubernetes over Nomad, ECS, Swarm, or a plain runtime, or comparing them, is `container-orchestration-selection`. That umbrella decides whether Kubernetes fits; this skill operates it once chosen.
- **Distribution and packaging siblings**: Helm charts, releases, and templating are `helm-ops`; OpenShift-specific operation (Routes, SCCs, `oc`, BuildConfigs) is `openshift-ops`; Rancher multi-cluster management is `rancher-ops`. This skill operates upstream Kubernetes; those cover the layers built on top.
- **Runtime layer**: the container runtime choice is `container-runtime-selection`, and per-runtime operation is `docker-ops`, `podman-ops`, or `containerd-ops`. Kubernetes talks to the runtime through the CRI; node-level containerd config lives in `containerd-ops`.
- **Kubernetes security strategy**: Pod Security Standards adoption, admission control (OPA Gatekeeper, Kyverno, ValidatingAdmissionPolicy), RBAC as a security control, NetworkPolicy strategy, image scanning gates, supply-chain integrity, and runtime protection are `container-security`. This skill wires the RBAC, ServiceAccount, and NetworkPolicy mechanics; the programme that decides how to use them for security lives there.
- **Managed Kubernetes provider depth**: EKS, AKS, and GKE control-plane management, cloud IAM integration (IRSA, Workload Identity), provider load balancers and CSI drivers, and provider node pools are `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops`. Workload-level Kubernetes is the same everywhere and lives here; the provider's cluster lifecycle lives there.
- **Ingress and load balancing**: choosing an ingress or load-balancer approach is `load-balancer-selection`; the implementations are `aws-load-balancing`, `nginx-load-balancing`, and `haproxy-load-balancing`. Declaring a Service or Gateway is here; the L4/L7 balancer fronting it is there.
- **Certificates and secrets**: in-cluster and service certificates are `cert-manager`, with public issuance via `lets-encrypt`; operating a central secret store is `hashicorp-vault-ops`, and the handling discipline for any token or credential is `secrets-hygiene`. Kubernetes Secrets are base64, not encrypted, so real secret material belongs in those homes.
- **Observability**: metrics, dashboards, and tracing for the cluster and workloads are `prometheus-configuration`, `grafana-dashboards`, and `distributed-tracing`. The kubelet metrics endpoints are noted here; the pipeline that scrapes them lives there.
- **GitOps and CD**: continuous delivery of manifests (ArgoCD sync waves, Flux reconciliation, app-of-apps) and the pipelines that run `kubectl apply` are `cicd-platforms-ops` and `gh-actions-ci`. The manifest is here; the delivery mechanism is there.
- **Cluster provisioning as code**: standing up the cluster and its cloud infrastructure with Terraform is `terraform-iac-ops`. Operating the cluster is here; declaring the infrastructure that creates it is there.

## Classify the request first

Every request resolves to one of these, which determines the reference to load. Also identify the Kubernetes minor version; features are version-gated (sidecar containers GA in 1.33, VolumeAttributesClass GA in 1.34, user namespaces and in-place pod resize beta in 1.35, nftables kube-proxy GA in 1.33 and beta since 1.31). If the version is unclear, ask, then default guidance to the latest stable and note where behaviour differs.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | API server request flow, etcd operations and backup, scheduler framework, controller reconciliation, kubelet lifecycle, CRI, kube-proxy modes, CNI, certificate architecture | `references/architecture.md` |
| Best practices / design | resource requests and limits, QoS strategy, RBAC design, NetworkPolicy strategy, HPA/VPA tuning, PodDisruptionBudgets, deployment strategies, upgrade procedure, namespace hygiene, labels | `references/best-practices.md` |
| Troubleshooting / diagnostics | pod-not-starting flowchart, `describe`/`logs`/`events`/`top`/`debug`, exit codes, OOMKilled, CrashLoopBackOff, FailedScheduling, network and storage debugging, control-plane health | `references/diagnostics.md` |
| Version-specific | 1.34 VolumeAttributesClass GA; 1.35 user namespaces, in-place resize, KYAML, cgroup v1 deprecation | `references/versions/1.34.md`, `references/versions/1.35.md` |

## Core model (condensed)

**Everything goes through the API server, and etcd is the single source of truth.** kubectl, controllers, and operators all talk REST to `kube-apiserver`, which authenticates, authorises (RBAC/Node/Webhook), runs admission (mutating then validating webhooks, then CEL-based ValidatingAdmissionPolicy), validates against the OpenAPI schema, and persists to etcd. Only the API server talks to etcd.

```
kubectl / controller / operator
  -> kube-apiserver (authn -> authz -> admission -> schema -> etcd)
  -> etcd (Raft-replicated key-value store, /registry/...)

kube-scheduler   watches unscheduled pods, filters+scores nodes, binds spec.nodeName
kube-controller-manager   reconciles desired vs actual for every built-in controller
kubelet (per node)   watches its pods, drives the CRI runtime, runs probes
kube-proxy (per node)   programs Service routing (iptables / ipvs / nftables)
```

**The scheduler filters, scores, then binds.** It eliminates nodes that fail hard constraints (resources, taints, affinity, topology), ranks the survivors, and sets `spec.nodeName` on the winner. The Scheduling Framework exposes extension points (Filter, Score, Reserve, Permit, Bind) for custom behaviour.

**Controllers reconcile.** Each built-in controller (ReplicaSet, Deployment, StatefulSet, Job, Node, PV/PVC, EndpointSlice) runs an independent loop: watch through an informer cache, diff desired against actual, act. This reconciliation model is also how CRDs plus operators extend the cluster.

**Every pod gets its own IP and reaches every other pod without NAT.** The CNI plugin implements this flat network (overlay or native routing). A Service gives a stable virtual IP in front of a changing set of pod IPs; kube-proxy (or an eBPF CNI) programs the DNAT. CoreDNS resolves `<service>.<namespace>.svc.cluster.local`.

**Isolation and least privilege are configuration you apply.** Pods run with whatever security context you set, RBAC grants whatever verbs you bind, and all traffic is allowed until a NetworkPolicy selects a pod. These are the operational knobs; the security programme that decides the policy is `container-security`.

**Anti-patterns:** no resource requests, so the scheduler cannot place pods sensibly and BestEffort pods are evicted first; CPU limits that cause CFS throttling on an idle node; binding `cluster-admin` to an application ServiceAccount; running as root with no security context; no readiness probe, so a rolling update sends traffic to a pod that is not ready; no PodDisruptionBudget, so a node drain takes the last replica; skipping more than one minor version on upgrade; treating a base64 Secret as if it were encrypted.

## Workloads

Choose the controller by the workload's shape.

| Resource | Use for | Key behaviour |
|---|---|---|
| Deployment | stateless services | ReplicaSet-managed rolling updates (`maxUnavailable`, `maxSurge`), `kubectl rollout undo`, revision history |
| StatefulSet | stateful, identity-bound | stable network IDs (pod-0, pod-1), ordered rollout, per-pod PVC via `volumeClaimTemplates`, headless Service for DNS |
| DaemonSet | one pod per node | log collectors, monitoring agents, CNI plugins |
| Job / CronJob | batch to completion | parallelism, completions, backoff, `ttlSecondsAfterFinished`; CronJobs add a schedule plus concurrency policy (Allow/Forbid/Replace) |

Inside a pod:

- **Init containers** run sequentially before app containers, each must exit 0. **Sidecar containers** are init containers with `restartPolicy: Always` (stable since 1.33); they start before app containers and run for the pod's lifetime, the correct pattern for proxies and log shippers.
- **Probes**: liveness restarts on failure, readiness removes the pod from Service endpoints, startup delays liveness until the app is up. A missing readiness probe is the most common cause of a rolling update dropping traffic.
- **QoS class** follows from requests and limits: Guaranteed (requests == limits) is evicted last, Burstable next, BestEffort (nothing set) first. Use Guaranteed for critical stateful workloads.
- **Graceful termination**: SIGTERM, then `terminationGracePeriodSeconds` (default 30s), then SIGKILL. Handle SIGTERM to drain connections.
- **Security context**: `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, drop `ALL` capabilities, `seccompProfile: RuntimeDefault`. Deep patterns are in `references/best-practices.md`; the policy that mandates them is `container-security`.

## Networking

| Service type | Behaviour |
|---|---|
| ClusterIP | internal-only virtual IP (the default) |
| NodePort | ClusterIP plus a port on every node (30000-32767) |
| LoadBalancer | NodePort plus an external load balancer (provider or MetalLB) |
| ExternalName | CNAME alias to an external DNS name |
| Headless (`clusterIP: None`) | DNS returns pod IPs directly, used by StatefulSets |

- **Ingress and the Gateway API**: the Gateway API (v1.x, GA) is the role-oriented successor to Ingress: a GatewayClass names the controller, a Gateway configures listeners and TLS, and HTTPRoute/GRPCRoute define routing. Declaring these is here; the balancer that implements them is `load-balancer-selection` and its vendor siblings.
- **NetworkPolicy** is a namespace-scoped, pod-selecting firewall. All traffic is allowed until a policy selects a pod, which then becomes default-deny for the listed policy types. It needs a CNI that enforces it (Calico, Cilium, Weave). The mechanics are here; a default-deny strategy is `container-security`.
- **CoreDNS** provides cluster DNS from a ConfigMap in `kube-system`; Service records are `<service>.<namespace>.svc.cluster.local`.
- **CNI** implements the flat pod network. The choice (Calico, Cilium, Flannel, provider CNI) affects NetworkPolicy support, dataplane (iptables versus eBPF), and encryption; the comparison table is in `references/architecture.md`.

## Storage

- **PV, PVC, StorageClass**: a PVC requests storage, a PV represents it, a StorageClass enables dynamic provisioning through a CSI `provisioner`. Access modes are `ReadWriteOnce` (one node), `ReadOnlyMany`, `ReadWriteMany`, and `ReadWriteOncePod` (one pod). Reclaim policy is `Delete` (default for dynamic) or `Retain` (manual cleanup, safer for data you must not lose).
- **CSI** is the plugin interface every serious storage backend implements. `WaitForFirstConsumer` binding mode delays provisioning until a pod is scheduled, so the volume lands in the right zone.
- **VolumeAttributesClass** (GA in 1.34) modifies attributes such as IOPS and throughput without recreating the PVC, when the CSI driver supports `MODIFY_VOLUME`.

Prefer a StatefulSet with `volumeClaimTemplates` for per-pod persistent storage rather than sharing one PVC across replicas.

## Scheduling

- **nodeSelector**: simple label match. **nodeAffinity**: expressive matching (In, NotIn, Exists, Gt, Lt), required or preferred.
- **podAffinity / podAntiAffinity**: co-locate or spread pods relative to other pods (spread replicas across zones, keep a cache near its app).
- **Taints and tolerations**: a node repels pods unless the pod tolerates the taint; used for dedicated node pools and to keep workloads off control-plane nodes.
- **Topology spread constraints**: distribute pods across failure domains with a configurable `maxSkew`.
- **PriorityClass and preemption**: a higher-priority pod can evict lower-priority pods when the cluster is full.

## RBAC and access

RBAC has four objects: Role and RoleBinding (namespace-scoped), ClusterRole and ClusterRoleBinding (cluster-scoped). Rules list `apiGroups`, `resources`, and `verbs`. Operate it by least privilege:

- Prefer namespace-scoped Roles over ClusterRoles; bind to Groups from the identity provider rather than individual Users.
- Give each workload its own ServiceAccount, never the namespace `default`, and never bind `cluster-admin` to an application ServiceAccount.
- Set `automountServiceAccountToken: false` where a pod needs no API access; use projected, audience-scoped, time-limited tokens where it does (the default binding since 1.24).
- Audit with `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>`.

These are the access mechanics. Treating RBAC as a security control (the review cadence, the privilege-escalation paths, admission enforcement) is `container-security`. Real secret material belongs in `hashicorp-vault-ops` or a CSI secret store, not a base64 Kubernetes Secret; follow `secrets-hygiene`.

## Cluster operations and upgrades

- **Upgrade order** (kubeadm): read the release notes for deprecations, back up etcd, upgrade control-plane nodes one at a time, then drain/upgrade/uncordon worker nodes one at a time. Skip only one minor version at a time (1.34 to 1.35, not 1.34 to 1.36). Test in staging first.
- **etcd backup**: `etcdctl snapshot save`, verify with `snapshot status`, and know the restore path (stop the API server, `snapshot restore` to a new data dir). Full commands are in `references/architecture.md`.
- **Node maintenance**: `kubectl cordon` to stop new scheduling, `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` to evict respecting PodDisruptionBudgets, then `kubectl uncordon` after.
- **Certificates**: kubeadm manages the PKI; check with `kubeadm certs check-expiration` and renew with `kubeadm certs renew all`. The kubelet rotates its own client cert by default.
- **Namespace hygiene**: apply ResourceQuota, LimitRange, Pod Security Standards labels, and a default-deny NetworkPolicy to every user namespace; clean up finished Jobs with `ttlSecondsAfterFinished`.

## Troubleshooting

Start by classifying the pod's status, then read the events:

- **Pending**: the scheduler cannot place it. Check `kubectl describe pod` events for insufficient resources, blocking taints, impossible affinity, an unbound PVC, or an exceeded ResourceQuota.
- **ContainerCreating (Waiting)**: image pull failure (name, tag, `imagePullSecrets`), a volume that will not attach or mount (multi-attach, missing CSI driver), or a CNI that is not ready.
- **CrashLoopBackOff**: `kubectl logs <pod> --previous` for the crashed container. Exit 137 is OOMKilled (raise the memory limit or fix the leak), 139 a segfault, 126/127 a bad command.
- **ImagePullBackOff**: image name/tag typo, missing `imagePullSecrets`, registry rate limit, or an architecture mismatch.
- **Running but not Ready**: the readiness probe is failing or the app is not listening on the expected port.
- **Terminating (stuck)**: a finalizer is blocking deletion (`kubectl get pod -o json | jq '.metadata.finalizers'`); force only as a last resort with `--grace-period=0 --force`.

Core commands: `kubectl describe`, `kubectl logs [--previous] [-c container]`, `kubectl get events --sort-by=.lastTimestamp`, `kubectl top pod/nodes`, and `kubectl debug` for an ephemeral container that does not mutate the pod spec. The full flowchart, error-message catalogue, and control-plane health checks are in `references/diagnostics.md`.

## Reference router

Load the reference that matches the class:

- `references/architecture.md`: control plane internals, etcd operations and backup/restore, scheduler framework, controller reconciliation, kubelet lifecycle, CRI, kube-proxy modes, CNI comparison, cluster networking, certificate architecture. Read for "how does X work".
- `references/best-practices.md`: resource requests and limits, QoS strategy, LimitRange and ResourceQuota, RBAC design, NetworkPolicy strategy, HPA and VPA tuning, PodDisruptionBudgets, deployment strategies, upgrade procedure, observability, and label conventions. Read for design and operations.
- `references/diagnostics.md`: the pod-not-starting flowchart, essential kubectl diagnostic commands, the common-error catalogue, cluster health checks, performance diagnostics, and JSONPath debugging. Read when troubleshooting.
- `references/versions/1.34.md` and `references/versions/1.35.md`: version-gated behaviour and upgrade notes.

## Version notes

Guidance defaults to the latest stable when the version is unknown. Boundaries that change behaviour:

- **1.33**: native sidecar containers go GA (init containers with `restartPolicy: Always`); nftables kube-proxy mode goes GA (beta since 1.31); topology-spread `nodeTaintsPolicy` goes GA.
- **1.34** (August 2025): **VolumeAttributesClass goes GA** (modify IOPS/throughput without recreating a PVC); OIDC discovery and Windows improvements. See `references/versions/1.34.md`.
- **1.35** (December 2025): **user namespaces** beta on by default (`hostUsers: false` maps container root to an unprivileged host UID); **in-place pod resize** beta (change CPU/memory without restart via the `resize` subresource); **pod certificates** beta; **KYAML** the stricter kubectl YAML parser; **cgroup v1 deprecation** begins. See `references/versions/1.35.md`.

Sidecar containers and VolumeAttributesClass are the two changes most likely to affect existing manifests on the way in; user namespaces and KYAML are the two most likely to surprise on a 1.35 upgrade. Validate manifests against the target server with `kubectl apply --dry-run=server` before an upgrade.

## Cross-references

- `container-orchestration-selection`: the vendor-neutral umbrella that decides Kubernetes versus the alternatives; this skill operates Kubernetes once that choice is made. Reciprocal reference.
- `helm-ops`, `openshift-ops`, `rancher-ops`: sibling skills for packaging (Helm) and the distributions built on Kubernetes (OpenShift, Rancher).
- `container-runtime-selection`, `docker-ops`, `podman-ops`, `containerd-ops`: the runtime choice and per-runtime operation beneath the CRI; node-level containerd is `containerd-ops`.
- `container-security`: the security programme this skill's RBAC, ServiceAccount, and NetworkPolicy mechanics serve, Pod Security Standards, admission control, image scanning, supply chain, runtime protection. Wire the knobs here; take the policy from there.
- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`: managed-Kubernetes provider depth (EKS, AKS, GKE), cloud IAM integration, provider load balancers and CSI, and node pools. Workload Kubernetes is here; the provider cluster lifecycle is there.
- `load-balancer-selection`, `aws-load-balancing`, `nginx-load-balancing`, `haproxy-load-balancing`: choosing and implementing the ingress or L4/L7 balancer that fronts a Service or Gateway.
- `cert-manager`, `lets-encrypt`: in-cluster and service certificates and public issuance; a base64 Kubernetes Secret is not encrypted.
- `hashicorp-vault-ops`, `secrets-hygiene`: the central secret store and the handling discipline for any token or credential mounted into a pod.
- `prometheus-configuration`, `grafana-dashboards`, `distributed-tracing`: the metrics, dashboards, and tracing pipeline that consumes the kubelet and workload endpoints.
- `cicd-platforms-ops`, `gh-actions-ci`: GitOps and the CD pipeline that applies manifests to the cluster.
- `terraform-iac-ops`: provisioning the cluster and its cloud infrastructure as code; operating it is here.
- `service-mesh-selection`: sidecar versus ambient mesh, mTLS, and traffic management above the Service layer.
- `utc-timestamps`: pod events, logs, and etcd revisions correlate on UTC; a skewed node clock corrupts the timeline and can break certificate validity windows.

## Red flags

- About to run pods with no resource requests, leaving the scheduler blind and BestEffort pods first to be evicted.
- About to set CPU limits that throttle a workload on an otherwise idle node.
- About to bind `cluster-admin`, or a broad ClusterRole, to an application ServiceAccount.
- About to ship a workload with no readiness probe and expect a zero-downtime rolling update.
- About to run a production Deployment with no PodDisruptionBudget, so a node drain can remove the last replica.
- About to skip more than one minor version in a single upgrade (1.34 straight to 1.36).
- About to upgrade without backing up etcd first.
- About to store real secret material in a Kubernetes Secret as if base64 were encryption.
- About to add a NetworkPolicy without an explicit DNS-egress allow, silently breaking name resolution under default-deny.
- About to upgrade to 1.35 without checking cgroup v2 on every node or dry-running manifests through KYAML.

## Bottom line

Kubernetes is an API server backed by etcd, with a scheduler and reconciling controllers on the control plane and a kubelet plus kube-proxy on every node; CRDs and operators extend the same reconciliation model. Match the controller to the workload shape, set requests (and usually memory limits), give every pod a readiness probe and a security context, and protect production with PodDisruptionBudgets. Give each workload its own least-privilege ServiceAccount, default-deny network traffic and allow back only what is needed, and keep real secrets in a proper store. Upgrade one minor at a time behind an etcd backup, drain nodes respecting PDBs, and dry-run manifests before a version bump. Bring the orchestrator choice from `container-orchestration-selection` and the security programme from `container-security`; keep certificates, secrets, ingress, observability, and CD in their proper homes.
