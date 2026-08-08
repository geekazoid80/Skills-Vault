# Container and Kubernetes security concepts

The security model that separates container security from VM security, the Kubernetes architecture the controls attach to, and the cluster-hardening detail behind Pod Security Standards, RBAC, and network policy. Load this when the question is about how the model works rather than how to write a specific policy.

## Container security model

### Containers vs VMs

Containers share the host operating-system kernel; VMs have hardware-level isolation. The consequences are fundamental:

- A container running as root can, given a kernel vulnerability, escape to the host.
- Syscalls from every container are processed by the same kernel.
- Container isolation rests on kernel namespaces and cgroups, not on a hypervisor boundary.

**Namespaces** provide the isolation:

| Namespace | Isolates |
|---|---|
| `pid` | Process IDs; a container sees only its own processes |
| `net` | Network interfaces, routing tables, firewall rules |
| `mnt` | Filesystem mounts |
| `uts` | Hostname and domain name |
| `ipc` | System V IPC and POSIX message queues |
| `user` | User and group IDs; the basis for rootless containers |
| `cgroup` | cgroup hierarchies |

**cgroups** provide resource control: limiting CPU, memory, block I/O, and network I/O per container, which blunts a denial-of-service attack where one container starves the others.

### Defence-in-depth layers

Container security requires controls at every layer, because any single layer can be bypassed. From source integrity down to the control plane:

1. **Supply chain**: source-code and build integrity (SLSA, Sigstore, SBOM).
2. **Build**: Dockerfile hardening and multi-stage builds that shrink the final image.
3. **Image scanning**: a pre-registry gate for CVEs, secrets, and misconfigurations.
4. **Registry**: authentication, content trust, and signature enforcement at distribution.
5. **Admission control**: the deployment-time gate (Gatekeeper, Kyverno, Pod Security Admission).
6. **Runtime**: seccomp, AppArmor, and behavioural monitoring during execution.
7. **Network**: network policies and service-mesh mTLS across east-west traffic.
8. **Infrastructure**: RBAC, etcd encryption, and API-server hardening on the control plane.

## Admission control architecture

An admission controller intercepts a request to the Kubernetes API server after authentication and authorisation, and can validate, mutate, or reject the object before it is persisted. The request lifecycle runs in order:

1. `kubectl apply` submits the object.
2. The API server authenticates the request.
3. The API server authorises the request via RBAC.
4. **Mutating** admission webhooks modify the object (Gatekeeper mutation, Kyverno mutation, service-mesh sidecar injection).
5. The object schema is validated.
6. **Validating** admission webhooks approve or reject (Gatekeeper validation, Kyverno validation, Pod Security Admission).
7. The object is persisted to etcd.

**Webhook failure policy** decides what happens when a webhook is unavailable:

- `failurePolicy: Fail` rejects the API request. Safe, but a downed webhook can block deployments.
- `failurePolicy: Ignore` allows the request. Less safe, since policy is silently skipped.
- The rule of thumb: `Ignore` for non-critical webhooks, `Fail` plus high availability for security-enforcing webhooks so a downed webhook cannot become an open door.

**Built-in admission controllers** need no extra deployment: `LimitRanger` (per-pod resource limits), `ResourceQuota` (namespace quotas), `PodSecurity` (enforces Pod Security Standards, replacing the removed PodSecurityPolicy), and `NodeRestriction` (limits what a kubelet can modify).

## Pod Security Standards

Pod Security Admission enforces three profiles, applied per namespace by label:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # enforce: reject pods that violate the profile
    pod-security.kubernetes.io/enforce: restricted
    # audit: log violations without rejecting
    pod-security.kubernetes.io/audit: restricted
    # warn: warn the user without rejecting
    pod-security.kubernetes.io/warn: restricted
```

| Profile | Posture | What it does |
|---|---|---|
| Privileged | Unrestricted | No restrictions; appropriate only for tightly controlled system namespaces |
| Baseline | Minimally restrictive | Blocks known privilege escalations; allows many defaults |
| Restricted | Heavily hardened | Requires non-root, no privilege escalation, dropped capabilities, and a seccomp profile |

**Baseline** forbids `privileged: true`, host namespaces (`hostPID`, `hostIPC`, `hostNetwork`), `hostProcess` (Windows), most hostPath volumes, dangerous capabilities such as `NET_ADMIN`, `SYS_ADMIN`, and `SYS_PTRACE`, an `unconfined` AppArmor override, and an `Unconfined` seccomp profile.

**Restricted** adds: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, a seccomp profile of `RuntimeDefault` or `Localhost`, and dropping all capabilities (adding back only `NET_BIND_SERVICE` where needed). A read-only root filesystem is not required by the profile but is recommended hardening.

```yaml
# A Restricted-compliant pod security context
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: myapp:v1.0.0
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    volumeMounts:
    - name: tmp
      mountPath: /tmp        # writable volume, since the root filesystem is read-only
  volumes:
  - name: tmp
    emptyDir: {}
```

## Kubernetes RBAC

Role-Based Access Control is Kubernetes' authorisation mechanism. Four objects compose it:

- `Role` grants permissions within a single namespace.
- `ClusterRole` grants permissions cluster-wide or over non-namespaced resources.
- `RoleBinding` binds a Role or ClusterRole to subjects within a namespace.
- `ClusterRoleBinding` binds a ClusterRole cluster-wide.

Least privilege means specific verbs, specific resources, and where possible specific resource names, with one service account per workload:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: my-app
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
  resourceNames: ["my-specific-pod"]   # scope tighter than the whole resource type where you can
```

### Dangerous permissions

Some permissions are admin-equivalent even without an explicit `cluster-admin` binding:

| Permission | Why it is dangerous |
|---|---|
| `verbs: ["*"]` on any resource | Full control of that resource type |
| `secrets: get/list` in kube-system | Reads service-account tokens and TLS certificates |
| `pods/exec` | Runs arbitrary commands in any pod |
| `pods/attach` | Attaches to a running pod's processes |
| `clusterroles: escalate, bind` | Grants any permission to self or others |
| `nodes: proxy` | Proxies to the kubelet API and can exec into any pod |
| `validatingwebhookconfigurations: *` | Disables admission webhooks |
| `mutatingwebhookconfigurations: *` | Hijacks all deployments |
| `networkpolicies: *` | Removes network isolation |

Common mistakes: `cluster-admin` bound to service accounts or developers; wildcards in verbs or resources; secrets access granted to workloads that never need it; a service account shared across workloads; and ClusterRoleBindings used where a namespaced RoleBinding would do.

A quick audit:

```bash
# Every cluster-admin binding
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name == "cluster-admin") | {name: .metadata.name, subjects: .subjects}'

# Can a given service account list secrets?
kubectl auth can-i list secrets --as system:serviceaccount:my-namespace:my-sa
```

### Service-account tokens and workload identity

Modern Kubernetes (1.20 and later) uses projected service-account tokens: short-lived (default one hour), audience-bound, and rotated automatically by the kubelet. Older clusters (before 1.24) auto-created long-lived, non-expiring service-account secrets; find and retire any that remain:

```bash
kubectl get secrets --all-namespaces -o json | \
  jq '.items[] | select(.type == "kubernetes.io/service-account-token") |
    {namespace: .metadata.namespace, name: .metadata.name, sa: .metadata.annotations["kubernetes.io/service-account.name"]}'
```

For cloud API access, federated workload identity beats a long-lived token: AWS IRSA (IAM Roles for Service Accounts, via OIDC), Azure AD Workload Identity (OIDC), and GCP Workload Identity (a Kubernetes-to-Google service-account binding). Annotate the service account rather than mounting a static key:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: my-namespace
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
```

### API-server hardening

Authentication methods include X.509 client certificates, bearer tokens (service-account or OIDC), OIDC federation to a corporate IdP, and webhook token auth. Authorisation should run RBAC and Node mode enabled; ABAC is legacy and best avoided. Core hardening flags:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --anonymous-auth=false
    - --audit-log-path=/var/log/audit.log
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    - --enable-admission-plugins=NodeRestriction,PodSecurity
    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml   # etcd encryption at rest
    - --tls-min-version=VersionTLS12
```

## Network policy

Kubernetes Network Policies control pod-to-pod and pod-to-external traffic. They require a CNI that supports them (Calico, Cilium, Weave, Canal). Start from default-deny and open only the flows you need:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-app
spec:
  podSelector: {}          # every pod in the namespace
  policyTypes:
  - Ingress
  - Egress

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### CNI comparison

| CNI | Network policy support | Notable features |
|---|---|---|
| Calico | Full Kubernetes NetworkPolicy plus extended Calico policy | Host-endpoint policy, BGP, WireGuard encryption |
| Cilium | Full Kubernetes NetworkPolicy plus Cilium policy (L7) | eBPF-based, L7 HTTP/gRPC policy, Hubble observability, WireGuard |
| Weave Net | Full Kubernetes NetworkPolicy | Simple to deploy, fewer features |
| Flannel | None | Simple overlay; pair with Calico for policy |
| AWS VPC CNI | Requires Calico for policy | Native VPC networking with a Calico policy engine |

### Limitations and where eBPF fills the gap

Standard Kubernetes Network Policies cannot express DNS-based egress (allow to `api.github.com`), L7 HTTP rules (allow `GET /health` but not `POST /admin`), policy-decision logging, or a cluster-wide default; granularity stops at the namespace. An eBPF CNI such as Cilium adds these:

```yaml
# Cilium L7 HTTP policy: allow only GET /health from monitoring
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: allow-health-check-only
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: monitoring
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/health"

---
# Cilium DNS-based egress
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
  - toFQDNs:
    - matchName: "api.github.com"
  - toPorts:
    - ports:
      - port: "443"
```

## Container escape vectors and mitigations

Understanding how a container escapes drives the defensive configuration:

1. **Privileged container** (`--privileged`): grants all capabilities plus host device access; an attacker can mount the host filesystem. Never use it; grant specific capabilities instead.
2. **Mounted container-runtime socket** (for example `/var/run/docker.sock`): lets an attacker start a new privileged container and mount the host. Never mount the runtime socket into a workload.
3. **Host PID namespace** (`hostPID: true`): the container sees and can signal or ptrace host processes. Keep it `false`; Pod Security Standards block it.
4. **Capability abuse**: `CAP_SYS_ADMIN` is near root, `CAP_NET_ADMIN` reconfigures interfaces, `CAP_SYS_PTRACE` traces any process. Drop all and add back only what is required.
5. **Writable hostPath volumes**: mounting `/etc` read-write lets an attacker edit `crontab` for persistence. Avoid hostPath; mount read-only where unavoidable.
6. **Kernel exploit from the container**: a shared-kernel CVE is reachable from container context. Seccomp reduces the syscall surface, patch the kernel, and use a sandbox runtime for stronger isolation.

### Sandbox runtimes

For high-risk or untrusted workloads, stronger isolation is available:

- **gVisor (runsc)** intercepts syscalls in a user-space kernel, trading some compatibility and performance for stronger isolation.
- **Kata Containers** run each pod in a lightweight VM, giving hardware-level isolation with container ergonomics at the cost of slower start-up.

```yaml
spec:
  runtimeClassName: kata-containers
  containers:
  - name: untrusted-workload
    image: untrusted-image:latest
```

## CIS Kubernetes Benchmark

The CIS Kubernetes Benchmark (Center for Internet Security) is the reference configuration-hardening standard, organised by component. Consult it directly rather than reproducing it; the headline areas:

- **Control plane**: API server (disable anonymous auth, enable audit logging and RBAC, encrypt etcd), etcd (TLS client auth, encryption at rest), controller manager and scheduler (disable profiling, least-privilege service accounts).
- **Worker nodes**: kubelet (disable anonymous auth, enable node restriction, rotate certificates), and file permissions on config files.
- **RBAC and service accounts**: disable token auto-mounting for the default service account, apply minimal RBAC, and never bind `cluster-admin` to a service account.
- **Network and pod security**: a default-deny network policy in every namespace, and Pod Security Standards at Restricted where the workload allows.

Open-source auditors include `kube-bench` (runs the CIS checks on a node) and `kube-hunter` (active testing of a cluster). Commercial KSPM tooling from platform vendors performs the same checks continuously; NIST SP 800-190 (Application Container Security Guide) is the companion narrative standard to the CIS control set.
