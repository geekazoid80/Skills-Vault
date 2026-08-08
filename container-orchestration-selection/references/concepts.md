# Container orchestration concepts

The fundamentals an orchestration-selection decision rests on: desired state and declarative management, reconciliation loops, operators, custom resources, admission control, control-plane components, and the scheduling and multi-tenancy models that apply across every platform. These are platform-agnostic; Kubernetes, managed Kubernetes, OpenShift, Rancher, and the lightweight distributions all implement the same core patterns, which is why the selection reasoning outlasts any one product.

## Desired state and declarative management

Container orchestration is built on the declarative model: you describe the desired state of the system, and the orchestrator continuously works to make reality match that declaration.

```
User declares: "I want 3 replicas of my app, each with 256Mi memory"
Orchestrator: creates pods, monitors health, replaces failures, enforces resource limits
```

Imperative versus declarative:

- Imperative ("run this container on node-2") specifies the action.
- Declarative ("ensure 3 healthy replicas exist") specifies the outcome.

Declarative management is what enables self-healing, rollback, and auditability. The desired state is stored as data (YAML or JSON manifests) and can be version-controlled.

## Reconciliation loops

The core mechanism of orchestration. Every controller runs a continuous loop:

```
1. Observe: read current state from the cluster
2. Compare: diff current state against desired state
3. Act: take minimal actions to converge (create, update, delete resources)
4. Repeat
```

This pattern is called the control loop or reconciliation loop. It provides:

- Self-healing: if a pod crashes, the controller creates a replacement.
- Eventual consistency: transient failures are retried automatically.
- Idempotency: running reconciliation multiple times produces the same result.

Level-triggered versus edge-triggered: Kubernetes controllers are level-triggered, reacting to the current state rather than to change events. If a controller misses an event it still converges on the next reconciliation, because it compares the full desired state against the full current state.

### Watch mechanism

Controllers use the API server's watch endpoint to receive a stream of changes efficiently rather than polling. The watch delivers:

- The initial list of resources (at a specific `resourceVersion`).
- A stream of ADDED, MODIFIED, and DELETED events.

If the watch disconnects, the controller re-lists from the last known `resourceVersion` and resumes watching.

## Control-plane components

Orchestration platforms share a common control-plane shape. Understanding which components a platform runs (and who operates them) is the crux of the self-managed-versus-managed decision.

| Component | Role | Who runs it on managed platforms |
|---|---|---|
| API server | The front door: authenticates, validates, and persists every state change | The provider |
| etcd (or a compatible store) | The consistent key-value store holding cluster state | The provider (SQLite or dqlite on lightweight distributions) |
| Scheduler | Places pods onto nodes by matching requests against capacity and constraints | The provider |
| Controller manager | Runs the built-in reconciliation loops (deployments, replicasets, nodes) | The provider |
| kubelet | The node agent that starts and supervises containers via the CRI | You (on the worker nodes) |
| kube-proxy or a CNI dataplane | Programs service and pod networking on each node | You (via the chosen CNI) |

On self-managed clusters you own every row: upgrades, etcd backups, high availability, and certificate rotation. On managed Kubernetes the provider owns the control-plane rows and you own the node rows. Lightweight distributions collapse several components into a single binary and swap etcd for a lighter store.

## Operators and custom controllers

An operator is a controller that encodes domain-specific operational knowledge for a particular application or service. Operators extend the orchestrator's native reconciliation pattern to manage complex, stateful applications.

What operators do:

- Automate day-2 operations: upgrades, backups, scaling, failover.
- Encode runbooks as code ("if the primary database fails, promote a replica and reconfigure connection strings").
- Manage application lifecycle beyond simple deployment.

Operator pattern:

```
Custom Resource (CR): defines desired state for the application
     |
Operator Controller: watches CRs, reconciles application state
     |
Managed Resources: creates and updates Pods, Services, ConfigMaps, PVCs
```

### Operator maturity model

| Level | Capability | Example |
|---|---|---|
| 1, basic install | Automated deployment | Helm chart wrapper |
| 2, seamless upgrades | Automated version upgrades | Patch and minor version handling |
| 3, full lifecycle | Backup, restore, failure recovery | Database operator with point-in-time recovery |
| 4, deep insights | Metrics, alerts, log analysis | Operator exposes SLI dashboards |
| 5, autopilot | Auto-scaling, auto-tuning, anomaly detection | Self-optimising database operator |

Common frameworks: Kubebuilder (Go, controller-runtime), Operator SDK (Go, Ansible, and Helm-based operators), KUDO (declarative, simpler but less flexible), and Metacontroller (lightweight, webhook-based).

## Custom resource definitions (CRDs)

CRDs extend the Kubernetes API with new resource types. Once a CRD is installed, users create, read, update, and delete instances of that custom resource through kubectl and the API server, just like built-in resources.

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.example.com
spec:
  group: example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
                enum: ["postgres", "mysql", "mongodb"]
              version:
                type: string
              replicas:
                type: integer
                minimum: 1
                maximum: 7
            required: ["engine", "version"]
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames: ["db"]
```

CRD good practice:

- Schema validation: always define `openAPIV3Schema` to validate custom resource fields at admission time.
- Versioning: use multiple versions with conversion webhooks for API evolution.
- Status subresource: enable the `.status` subresource so controllers update status without triggering spec watches.
- Printer columns: define `additionalPrinterColumns` so `kubectl get` shows useful information.

## Admission control

Admission controllers intercept requests to the API server after authentication and authorisation but before the object is persisted. They validate, mutate, or reject requests.

Admission pipeline:

```
Client Request
  -> Authentication (who are you?)
  -> Authorization (are you allowed?)
  -> Mutating Admission (modify the request)
  -> Schema Validation (does it match the API schema?)
  -> Validating Admission (custom validation)
  -> Persist to the state store
```

### Built-in admission controllers

| Controller | Purpose |
|---|---|
| NamespaceLifecycle | Prevents operations in terminating namespaces |
| LimitRanger | Applies default resource requests and limits |
| ResourceQuota | Enforces namespace resource quotas |
| PodSecurity | Enforces Pod Security Standards (restricted, baseline, privileged) |
| DefaultStorageClass | Assigns a default StorageClass to PVCs |
| MutatingAdmissionWebhook | Calls external webhooks to mutate objects |
| ValidatingAdmissionWebhook | Calls external webhooks to validate objects |

### Dynamic admission webhooks

External webhooks allow custom admission logic without modifying the API server:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: validate-pods
webhooks:
- name: validate.example.com
  clientConfig:
    service:
      name: validation-service
      namespace: system
      path: /validate
    caBundle: <base64-ca>
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["pods"]
  failurePolicy: Fail        # Fail closed (reject if the webhook is unavailable)
  sideEffects: None
  timeoutSeconds: 5
```

### ValidatingAdmissionPolicy (CEL)

Recent Kubernetes releases support in-process validation using CEL (Common Expression Language), removing the need for a webhook server for simple validation rules:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-labels
spec:
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: "has(object.metadata.labels) && 'app' in object.metadata.labels"
    message: "All deployments must have an 'app' label"
  - expression: "object.spec.replicas <= 50"
    message: "Replica count must not exceed 50"
```

CEL-based policies are faster (no network call), more reliable (no webhook availability concern), and simpler to deploy than webhook-based validation.

## Scheduling concepts

Orchestrators must decide where to place workloads.

- Resource-based scheduling: nodes advertise capacity (CPU, memory, GPUs); the scheduler matches pod requests against allocatable capacity.
- Affinity and anti-affinity: node affinity attracts pods to specific nodes (GPU or SSD nodes); pod affinity co-locates pods that communicate frequently; pod anti-affinity spreads pods apart for high availability.
- Topology-aware scheduling: distribute workloads across failure domains (zones, regions, racks); topology spread constraints define the maximum skew between domains.
- Preemption and priority: higher-priority pods can evict lower-priority ones when resources are scarce; PriorityClasses define the levels.
- Bin packing versus spreading: bin packing fills nodes densely for cost efficiency; spreading distributes across nodes for resilience. Most production environments balance both (spread across zones for HA, bin-pack within a zone for cost).

## Service discovery and load balancing

Orchestrators abstract away individual pod IPs and provide stable service endpoints:

- DNS-based discovery: services get DNS names (for example `myapp.production.svc.cluster.local`).
- Virtual IPs (ClusterIP): a stable IP that load-balances to backend pods.
- Headless services: DNS returns individual pod IPs for client-side load balancing.
- External exposure: LoadBalancer, NodePort, Ingress, and the Gateway API.

Health-based routing means traffic reaches only healthy pods: readiness probes gate endpoint membership, liveness probes trigger restarts, and startup probes give slow-starting containers time to initialise before liveness checks begin.

## Multi-tenancy models

How orchestration platforms isolate workloads for different teams or customers:

| Model | Isolation | Overhead | Use case |
|---|---|---|---|
| Namespace-per-tenant | Soft (RBAC, NetworkPolicy, ResourceQuota) | Low | Internal teams |
| Cluster-per-tenant | Strong (separate control planes) | High | Regulated or hostile tenants |
| Virtual clusters (vCluster) | Medium (virtual control plane, shared nodes) | Medium | Platform-as-a-service |

Key isolation mechanisms: RBAC restricts API access per namespace; NetworkPolicy restricts pod-to-pod traffic; ResourceQuota caps consumption per namespace; LimitRange enforces per-pod boundaries; Pod Security Standards enforce security baselines per namespace; and user namespaces map container root to an unprivileged host UID.
