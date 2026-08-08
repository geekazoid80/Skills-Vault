---
name: openshift-ops
description: "Operate Red Hat OpenShift Container Platform (OCP) and OKD clusters: Projects as multi-tenant namespaces, Routes with edge/passthrough/reencrypt TLS termination and route sharding, Security Context Constraints (SCC) and their relationship to Pod Security Standards, BuildConfigs (Source-to-Image, Docker, Custom) and ImageStreams with image-change triggers, Operator Lifecycle Manager (OLM) and OperatorHub, DeploymentConfig versus Deployment, the Machine Config Operator and RHCOS nodes, the integrated registry and monitoring stack, OpenShift GitOps and Pipelines, and oc CLI workflows. WHEN: \"OpenShift\", \"OCP\", \"OKD\", \"oc\", \"oc CLI\", \"Routes\", \"SCC\", \"SecurityContextConstraints\", \"BuildConfig\", \"S2I\", \"Source-to-Image\", \"ImageStream\", \"OLM\", \"OperatorHub\", \"operators\", \"DeploymentConfig\", \"Projects\", \"OpenShift GitOps\", \"OpenShift Pipelines\", \"Machine Config Operator\", \"ClusterOperator\", \"RHCOS\", \"CRI-O\". Do NOT use for: generic Kubernetes operations that OpenShift builds on, kubectl, Deployments, namespaces, generic Ingress and RBAC (kubernetes-ops); choosing an orchestrator or Kubernetes distribution (container-orchestration-selection); Helm chart operations (helm-ops); Rancher multi-cluster management (rancher-ops); container and Kubernetes security strategy such as image scanning, admission control, supply-chain integrity and runtime protection (container-security); operating a central secret store (hashicorp-vault-ops) or secret-handling discipline (secrets-hygiene); deep Prometheus configuration and dashboards even though OpenShift bundles a monitoring stack (prometheus-configuration, grafana-dashboards); CI/CD pipeline platforms (cicd-platforms-ops, gh-actions-ci)."
license: MIT
metadata:
  version: 1.0.0
---

# OpenShift operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: openshift-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns operating Red Hat OpenShift Container Platform (OCP) and its upstream community edition OKD: Projects, Routes, Security Context Constraints, BuildConfigs and Source-to-Image, ImageStreams, the Operator Lifecycle Manager, DeploymentConfig, the Machine Config Operator, and the `oc` CLI. It assumes OpenShift is the chosen platform; the orchestrator choice lives in `container-orchestration-selection`, and the generic Kubernetes that OpenShift is built on, kubectl, Deployments, namespaces, Ingress, and generic RBAC, lives in `kubernetes-ops`. The rule of thumb: if a primitive exists unchanged in vanilla Kubernetes, take it from `kubernetes-ops`; if OpenShift adds or replaces it (Routes, SCC, BuildConfig, ImageStream, OLM, DeploymentConfig, MCO), it is here.

OpenShift is Kubernetes plus a managed platform layer: an integrated registry, a bundled monitoring stack, an OAuth server, an in-cluster build system, and immutable nodes (RHCOS) managed as code. This skill covers the SCC security knobs at the operational level but routes the security strategy (image scanning as a gate, admission control, supply-chain integrity, runtime protection) to `container-security`.

Coverage targets OCP 4.x and the matching OKD releases. The architecture is stable across 4.x; the moving parts (OVN-Kubernetes as default CNI since 4.12, `restricted-v2` as the default SCC, DeploymentConfig deprecation, Grafana removal from built-in monitoring) are called out in `## Version notes`.

## When to use

- Managing Projects: creating them with `oc new-project`, project templates, self-provisioning quota, and the differences from a bare namespace.
- Publishing a service with a Route: edge, passthrough, or reencrypt TLS termination, `insecureEdgeTerminationPolicy`, wildcard routes, and route sharding across IngressControllers.
- Diagnosing or granting Security Context Constraints: the SCC selection algorithm, `oc adm policy add-scc-to-user`, custom SCCs, and the `restricted-v2` default that rejects root and arbitrary UIDs.
- Building images in-cluster: BuildConfigs (Source-to-Image, Docker, Custom strategies), build triggers (GitHub, ImageChange, ConfigChange), and ImageStreams with scheduled imports and image-change triggers.
- Installing and lifecycling operators through OLM: Subscriptions, CatalogSources, InstallPlans, ClusterServiceVersions, OperatorGroups, and air-gapped catalog mirroring.
- Working with DeploymentConfig on an older cluster, or migrating a DeploymentConfig to a Deployment on 4.14+.
- Configuring nodes as code: MachineConfig, MachineConfigPools, kernel args, systemd units, and the MCO rolling-update flow on RHCOS.
- Driving the cluster with `oc`: `oc get clusteroperators`, `oc debug node`, `oc rsh`, `oc rollout`, `oc registry login`, and the integrated monitoring stack.

## When not to use

- **Generic Kubernetes**: Deployments, namespaces, Services, generic Ingress and Gateway API, ConfigMaps, generic RBAC, HPA, and anything that behaves identically on vanilla Kubernetes is `kubernetes-ops`. OpenShift builds on it; take the unchanged primitives from there and the OpenShift-specific layer from here.
- **Orchestrator selection**: choosing Kubernetes versus a lighter orchestrator, or picking a distribution, is `container-orchestration-selection`. That umbrella decides; this skill operates OpenShift once chosen.
- **Sibling platforms**: Helm chart authoring and release operations are `helm-ops`; Rancher multi-cluster management is `rancher-ops`.
- **Security strategy**: image scanning methodology and CI gate policy, admission control (OPA Gatekeeper, Kyverno, Pod Security Standards as a programme), supply-chain integrity (SLSA, cosign, SBOM), and behavioural runtime protection are `container-security`. Summarising SCC as a security control is fine here; the programme that decides scanning gates and admission policy lives there.
- **Secrets and a central store**: the handling discipline for any token, pull secret, or webhook secret is `secrets-hygiene`; operating a central secret store is `hashicorp-vault-ops`. Never bake a secret into a BuildConfig env or an image layer.
- **Observability depth**: OpenShift bundles a Prometheus monitoring stack, but deep Prometheus rule and scrape configuration is `prometheus-configuration`, and dashboard authoring is `grafana-dashboards`.
- **CI/CD pipelines**: the external pipeline that calls `oc start-build` or applies manifests is `cicd-platforms-ops` and `gh-actions-ci`. OpenShift Pipelines (Tekton) and GitOps (Argo CD) run in-cluster and are operated here; the pipeline platform choice is there.

## Classify the request first

Every request resolves to one of these, which determines where the depth lives. Also identify the OCP 4.x version and whether it is OCP or OKD; feature availability and the operator catalog differ. If unclear, ask, then default guidance to a current 4.x release.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | Cluster Operators, RHCOS, MCO controller/daemon split, OLM component flow, HAProxy router internals, SCC evaluation algorithm, OVN-Kubernetes, integrated registry, OAuth | `references/architecture.md` |
| Projects and access | `oc new-project`, project templates, self-provisioning, OAuth identity providers, RBAC over SCC | This SKILL.md § Projects, § Version notes; deep OAuth in `references/architecture.md` |
| Routing | Routes, TLS termination modes, route sharding, IngressController tuning, Route vs Ingress | This SKILL.md § Routes vs Ingress |
| Security posture | SCC selection, custom SCCs, `add-scc-to-user`, the restricted-v2 default, SCC vs Pod Security Standards | This SKILL.md § Security Context Constraints vs Pod Security Standards |
| Builds and images | BuildConfig (S2I, Docker, Custom), build triggers, ImageStreams, image-change triggers, integrated registry | This SKILL.md § BuildConfigs and Source-to-Image, § ImageStreams |
| Operators | OLM Subscriptions, CatalogSources, InstallPlans, CSVs, OperatorGroups, air-gapped mirroring | This SKILL.md § Operator Lifecycle Manager and OperatorHub |
| Nodes | MachineConfig, MachineConfigPool, kernel args, systemd units, MCO rolling update | This SKILL.md § Nodes: RHCOS and the Machine Config Operator |
| Workloads | DeploymentConfig vs Deployment, image-change triggers, rollout, the 4.14 deprecation | This SKILL.md § DeploymentConfig vs Deployment |

## Core model (condensed)

**OpenShift is Kubernetes with a managed platform layer bolted on top.** The Kubernetes API server, etcd, scheduler, and controller manager are underneath; OpenShift adds an OAuth server, an integrated registry, an in-cluster build system, Routes, SCC admission, OLM, and immutable nodes managed by the Machine Config Operator. Every platform component is itself a Cluster Operator, reconciled continuously and reported through `oc get clusteroperators`.

**Projects are namespaces with an ownership and lifecycle wrapper.** `oc new-project` creates a namespace plus default RoleBindings, a project template, and optional self-provisioning quota. Treat a Project as the multi-tenant unit; the underlying object is still a Kubernetes namespace.

**Routes predate and coexist with Ingress.** A Route is OpenShift's native L7 primitive with first-class TLS termination modes (edge, passthrough, reencrypt) and route sharding. Ingress objects are accepted and translated into Routes by the ingress operator, but the native features live on the Route.

**SCC is the admission gate every pod passes through.** The default `restricted-v2` SCC forbids running as root, forbids privilege escalation, drops all capabilities, and requires a seccomp profile. A workload that runs on vanilla Kubernetes as UID 0 will be rejected on OpenShift until it either runs non-root or is granted a broader SCC through its ServiceAccount.

**BuildConfig plus ImageStream give you in-cluster CI.** Source-to-Image compiles source into an image using a builder image, the result lands in an ImageStream, and image-change triggers can cascade a rebuild or a redeploy. This is optional; external CI that pushes to the integrated registry works too.

**Nodes are immutable and configured as code.** RHCOS has no `yum install` and no SSH-based edits; you change a node by applying a MachineConfig, which the Machine Config Operator rolls out one node at a time (cordon, drain, apply, reboot, uncordon). Reach a node with `oc debug node/<name>`, never SSH.

**Anti-patterns:** using `kubectl` for OpenShift-specific resources instead of `oc`, so Routes, SCC, and BuildConfigs are invisible; granting `privileged` or `anyuid` SCC when a narrower one satisfies the pod; assuming a manifest that runs on vanilla Kubernetes runs on OpenShift under `restricted-v2`; creating new workloads with the deprecated DeploymentConfig instead of a Deployment; exposing a service with a bare Ingress and losing the Route's TLS termination modes and sharding; SSHing to a node instead of `oc debug node`; hand-editing node files that the MCO reverts on the next reconcile; and baking a secret into a BuildConfig env or an image layer.

## Projects

A Project is a Kubernetes namespace with OpenShift lifecycle and access controls layered on:

```bash
oc new-project myapp --display-name="My App" --description="Team app"
oc project myapp          # switch the current context
oc projects               # list Projects you can see
oc adm policy add-role-to-user admin alice -n myapp   # project-scoped RBAC
```

Self-provisioning (whether authenticated users may create their own Projects) is controlled by the `self-provisioner` ClusterRoleBinding, and new-project defaults come from the project template in `openshift-config`. Quotas and limit ranges are applied per Project. Identity comes from the built-in OAuth server, which federates to LDAP, OIDC, GitHub, Google, GitLab, or HTPasswd; the identity-provider configuration and RBAC-over-SCC detail are in `references/architecture.md`.

## Routes vs Ingress

A Route is the native OpenShift way to publish a Service at L7, and it carries features a plain Ingress does not:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp
  namespace: production
spec:
  host: myapp.apps.cluster.example.com
  to:
    kind: Service
    name: myapp
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

| Termination | Behaviour | Use case |
|---|---|---|
| `edge` | TLS terminated at the router, HTTP to the pod | Most common and simplest |
| `passthrough` | TLS passed straight to the pod, no inspection | Pod handles its own TLS (gRPC, databases) |
| `reencrypt` | TLS terminated at the router, new TLS to the pod | End-to-end encryption with a route-level cert |

**Route sharding** splits traffic across multiple router deployments by label. Label the Route (`type: external`), then point an IngressController's `routeSelector` at that label with its own domain and node placement:

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: external
  namespace: openshift-ingress-operator
spec:
  routeSelector:
    matchLabels:
      type: external
  domain: external.apps.cluster.example.com
  replicas: 3
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: ""
```

Ingress objects still work: the ingress operator converts an Ingress into one or more managed Routes. Use a Route when you want termination modes or sharding, and reach for `kubernetes-ops` for the generic Ingress and Gateway API semantics that are unchanged from vanilla Kubernetes. The HAProxy router internals and route-evaluation order are in `references/architecture.md`.

## Security Context Constraints vs Pod Security Standards

SCCs are OpenShift's per-pod admission mechanism, predating and more granular than Kubernetes Pod Security Standards. Both can run at once: Pod Security admission enforces a namespace-level baseline, and SCC decides what an individual pod is actually allowed to do.

Built-in SCCs, most to least restrictive:

| SCC | Key permissions |
|---|---|
| `restricted-v2` | Default. No root, no privilege escalation, drops all capabilities, seccomp required. Aligns with the Kubernetes Restricted PSS. |
| `restricted` | Legacy default, similar to restricted-v2 without the seccomp requirement. |
| `nonroot-v2` | Must run non-root; broader capabilities than restricted-v2. |
| `nonroot` | Legacy non-root. |
| `hostnetwork-v2` | Access to the host network namespace. |
| `anyuid` | Any UID, including root; no host access. |
| `hostaccess` | Host path volumes allowed. |
| `hostmount-anyuid` | Host path mounts plus any UID. |
| `node-exporter` | For Prometheus node exporters. |
| `privileged` | Unrestricted, full host access. |

```bash
oc get scc                                              # list SCCs
oc describe scc restricted-v2                            # inspect one
oc get pod myapp -o yaml | grep openshift.io/scc         # which SCC a pod got
oc adm policy add-scc-to-user anyuid -z my-sa -n myproject      # grant to a ServiceAccount
oc adm policy remove-scc-from-user anyuid -z my-sa -n myproject
oc adm policy who-can use scc anyuid                     # who may use an SCC
```

**Selection algorithm**: when a pod is created, OpenShift collects every SCC accessible to the pod's ServiceAccount, sorts them most-restrictive-first, and assigns the most restrictive SCC that satisfies the pod's security context, mutating the pod to fill defaults. If none match, the pod is rejected with `unable to validate against any security context constraint`. Diagnose by comparing the pod's `securityContext` against the SCCs the ServiceAccount can use, then grant the minimum SCC required; avoid `privileged` unless there is no alternative.

Summarising SCC as a security control is in scope here. The security programme that decides scanning gates, admission policy, supply-chain integrity, and runtime protection is `container-security`.

## BuildConfigs and Source-to-Image

A BuildConfig runs builds in-cluster. Source-to-Image (S2I) compiles source into an image using a builder image, with no Dockerfile required:

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp
spec:
  source:
    type: Git
    git:
      uri: https://github.com/myorg/myapp.git
      ref: main
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
        namespace: openshift
      env:
      - name: PIP_INDEX_URL
        value: "https://pypi.internal.example.com/simple"
  output:
    to:
      kind: ImageStreamTag
      name: myapp:latest
  triggers:
  - type: GitHub
    github:
      secret: webhook-secret
  - type: ImageChange     # rebuild when the base image updates
  - type: ConfigChange    # rebuild when the BuildConfig changes
```

Build strategies: `Source` (S2I), `Docker` (a Dockerfile in the repo), and `Custom` (a fully custom builder image). Drive builds with `oc start-build myapp` and follow logs with `oc logs -f bc/myapp`. Keep build-time secrets in a mounted build secret, never in a `env` value or a committed file; the handling discipline is `secrets-hygiene`.

## ImageStreams

An ImageStream is an OpenShift abstraction over image references that decouples a workload from a registry URL and drives trigger-based automation:

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: myapp
spec:
  lookupPolicy:
    local: true     # let pods reference the ImageStream tag without a full registry URL
  tags:
  - name: latest
    from:
      kind: DockerImage
      name: registry.example.com/myapp:latest
    importPolicy:
      scheduled: true    # periodically re-import to pick up a new digest
```

When a new image lands on a tracked tag, an image-change trigger can start a build, roll out a Deployment (via the `image.openshift.io/triggers` annotation) or a DeploymentConfig, and update running pods. Import an external image manually with `oc import-image myapp:latest --from=registry.example.com/myapp:latest --confirm`.

## Operator Lifecycle Manager and OperatorHub

OLM installs and lifecycles operators from a catalog. Declare intent with a Subscription:

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cert-manager
  namespace: openshift-operators      # cluster-scoped operators land here
spec:
  channel: stable
  name: cert-manager
  source: community-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic      # use Manual for production change control
EOF

oc get csv -n openshift-operators           # ClusterServiceVersion (installed version)
oc get installplans -n openshift-operators
oc get subscriptions -n openshift-operators
```

| Resource | Purpose |
|---|---|
| CatalogSource | Points to an operator catalog (a registry image) |
| Subscription | Declares intent to install an operator and track a channel |
| InstallPlan | Created by OLM to install or upgrade operator resources; `Automatic` or `Manual` approval |
| ClusterServiceVersion (CSV) | Describes an operator version: its deployments, CRDs, and permissions |
| OperatorGroup | Defines which namespaces an operator may watch |

Catalog sources: `redhat-operators` (Red Hat certified and supported), `certified-operators` (partner ISV certified), `community-operators` (community contributed), and `redhat-marketplace` (paid). For air-gapped clusters, mirror a catalog to an internal registry with `oc adm catalog mirror` and `opm`, then point a CatalogSource at the mirror; the full mirroring flow and OLM component architecture are in `references/architecture.md`.

## DeploymentConfig vs Deployment

DeploymentConfig is the original OpenShift workload controller. It predates the Kubernetes Deployment and adds native image-change and config-change triggers plus lifecycle hooks:

```bash
oc rollout latest dc/myapp     # trigger a new rollout
oc rollout status dc/myapp
```

**DeploymentConfig is deprecated as of OCP 4.14.** For new workloads use a standard Kubernetes Deployment and wire image updates with the `image.openshift.io/triggers` annotation instead of a DeploymentConfig trigger. This is a divergence from the upstream community skill, which still presents DeploymentConfig as a current primitive; treat it as legacy-only and prefer Deployment. Generic Deployment, ReplicaSet, and rollout semantics are unchanged from vanilla Kubernetes and live in `kubernetes-ops`; the OpenShift-specific triggers and the migration are here.

## Nodes: RHCOS and the Machine Config Operator

RHCOS (and Fedora CoreOS on OKD) is immutable: change a node by applying a MachineConfig, not by editing files:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-custom-sysctl
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/sysctl.d/99-custom.conf
        mode: 0644
        contents:
          inline: |
            net.core.somaxconn = 65535
            vm.max_map_count = 262144
```

A MachineConfigPool groups nodes (`master`, `worker`, or a custom pool) for config application. The MCO rolls a change out one node at a time by default (cordon, drain respecting PodDisruptionBudgets, apply, reboot if required, uncordon); raise `maxUnavailable` on the pool to update more nodes at once. Reach a node with `oc debug node/<name>`, which mounts the host filesystem at `/host`; never SSH. The MachineConfigController and MachineConfigDaemon split, and worked kernel-arg and systemd-unit examples, are in `references/architecture.md`.

## Integrated platform services and the oc CLI

OpenShift ships services that vanilla Kubernetes leaves for you to install:

- **Integrated registry** at `image-registry.openshift-image-registry.svc:5000`. Log in with `oc registry login`, or expose it externally by patching the image-registry config's `defaultRoute`.
- **Monitoring stack**: a pre-configured Prometheus, Alertmanager, and Thanos Querier in `openshift-monitoring`. Enable user-workload monitoring to let application teams create `ServiceMonitor` and `PrometheusRule` objects in their namespaces. The standalone Grafana was removed from the built-in stack in 4.11; dashboards are in the web console, and if you run your own Grafana, dashboard authoring is `grafana-dashboards`. Deep Prometheus rule and scrape configuration is `prometheus-configuration`.
- **OAuth server** for cluster authentication, federating to external identity providers.

Common `oc` workflows:

```bash
oc new-project myapp                 # Projects
oc start-build myapp                 # builds
oc logs -f bc/myapp
oc get clusteroperators              # cluster health
oc get clusterversion
oc adm top nodes
oc debug node/worker-0               # node access (no SSH)
oc rsh pod/myapp-abc123              # shell into a pod
oc import-image myapp:latest --from=registry.example.com/myapp:latest --confirm
```

Prefer `oc` over `kubectl` for OpenShift-specific resources; `kubectl` cannot see Routes, SCCs, BuildConfigs, or ImageStreams as first-class objects.

## Version notes

Guidance targets a current OCP 4.x release when the version is unknown. Boundaries that change behaviour:

- **OVN-Kubernetes is the default CNI since 4.12**, replacing OpenShift SDN; OpenShift SDN was removed in 4.17, so a cluster upgrading through that boundary must migrate to OVN-Kubernetes first.
- **`restricted-v2` is the default SCC since 4.11**, tightening the older `restricted` default (seccomp now required); workloads that passed on `restricted` may need a security-context adjustment.
- **Built-in Grafana was removed from cluster monitoring in 4.11**; the monitoring stack is Prometheus, Alertmanager, and Thanos, with dashboards moved into the web console.
- **DeploymentConfig is deprecated as of 4.14**; use Deployment for new workloads.
- **OKD tracks OCP** but ships Fedora CoreOS nodes and community operators, without the enterprise SLA and the Red Hat certified catalog.

## Reference files

- `references/architecture.md`: OCP internals, the platform-layer diagram, RHCOS, the Cluster Operators table, the Machine Config Operator controller and daemon split with its update flow, OLM component architecture and air-gapped catalog mirroring, the HAProxy router and route evaluation, the integrated registry, OVN-Kubernetes networking (EgressFirewall, EgressIP), and the security architecture (SCC evaluation algorithm, OAuth identity providers, certificate management). Read it for architecture and design questions.

## Cross-references

- `kubernetes-ops`: the generic Kubernetes that OpenShift builds on, kubectl, Deployments, namespaces, Services, generic Ingress and Gateway API, ConfigMaps, generic RBAC, HPA. Take the unchanged primitives from there; this skill owns the OpenShift-specific layer. Reciprocal reference.
- `container-orchestration-selection`: the vendor-neutral umbrella that decides Kubernetes versus a lighter orchestrator and picks a distribution; this skill operates OpenShift once that choice is made.
- `helm-ops`, `rancher-ops`: sibling platform skills for Helm chart operations and Rancher multi-cluster management.
- `container-security`: the security strategy the SCC knobs serve, image scanning as a gate, admission control, supply-chain integrity, runtime protection. Summarise SCC-as-a-control here; take the programme from there.
- `hashicorp-vault-ops`, `secrets-hygiene`: operating a central secret store, and the handling discipline for pull secrets, webhook secrets, and build secrets. Never bake a real literal into a BuildConfig or an image layer.
- `prometheus-configuration`, `grafana-dashboards`: deep Prometheus rule and scrape configuration, and dashboard authoring, even though OpenShift bundles a monitoring stack.
- `cicd-platforms-ops`, `gh-actions-ci`: the external pipeline that calls `oc start-build` or applies manifests. In-cluster OpenShift Pipelines (Tekton) and GitOps (Argo CD) are operated here; the pipeline platform choice is there.
- `service-mesh-selection`: OpenShift Service Mesh is Istio-based; route mesh selection and comparison there.

## Red flags

- About to use `kubectl` for a Route, SCC, BuildConfig, or ImageStream, which it cannot see as a first-class object; use `oc`.
- About to grant `privileged` or `anyuid` SCC when a narrower SCC satisfies the pod's security context.
- About to deploy a manifest that runs as root or an arbitrary UID, assuming it will pass, when `restricted-v2` will reject it.
- About to create a new workload with DeploymentConfig, deprecated since 4.14, instead of a Deployment.
- About to expose a service with a bare Ingress and lose the Route's TLS termination modes and sharding.
- About to SSH to a node instead of using `oc debug node/<name>`; RHCOS is immutable.
- About to hand-edit a node file that the Machine Config Operator will revert on the next reconcile; use a MachineConfig.
- About to bake a secret into a BuildConfig `env` or an image layer instead of a mounted build secret.
- About to expect a built-in Grafana that was removed from cluster monitoring in 4.11.
- About to run an MCO rolling update without PodDisruptionBudgets, risking eviction of every replica of a workload at once.

## Bottom line

OpenShift is Kubernetes with a managed platform layer: Projects wrap namespaces, Routes are the native L7 primitive with edge/passthrough/reencrypt TLS and sharding, SCC is the admission gate that `restricted-v2` locks down by default, BuildConfig plus ImageStream give in-cluster CI, OLM lifecycles operators, and RHCOS nodes are configured as code through the Machine Config Operator. Drive it with `oc`, not `kubectl`, and reach a node with `oc debug node`. Prefer Deployment over the deprecated DeploymentConfig on 4.14+, grant the minimum SCC rather than `privileged`, and keep secrets out of BuildConfigs and layers. Bring the generic Kubernetes primitives from `kubernetes-ops`, the orchestrator choice from `container-orchestration-selection`, and the security programme from `container-security`.
