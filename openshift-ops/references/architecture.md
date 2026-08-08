# OpenShift architecture

## Cluster architecture

OpenShift Container Platform builds on Kubernetes and adds a managed platform layer:

```
+------------------------------------------------+
| OpenShift platform layer                       |
|   Web console (admin + developer)              |
|   OLM (Operator Lifecycle Manager)             |
|   Integrated registry                          |
|   Integrated monitoring (Prometheus stack)     |
|   Integrated logging (Loki / Elasticsearch)    |
|   Routes / HAProxy router                      |
|   Machine Config Operator                      |
|   Build system (S2I, Docker builds)            |
|   ImageStreams                                 |
+------------------------------------------------+
| Kubernetes (API server, etcd,                  |
|  scheduler, controller manager)                |
+------------------------------------------------+
| RHCOS / Fedora CoreOS (immutable)              |
+------------------------------------------------+
```

### RHCOS (Red Hat CoreOS)

All control-plane nodes must run RHCOS. Worker nodes can run RHCOS or RHEL.

Key characteristics:

- Immutable OS: no `yum install`, no SSH-based configuration changes.
- Managed via Ignition configs (first boot) and the MCO (ongoing).
- Automatic updates coordinated by the MCO.
- `rpm-ostree` based: atomic OS updates with rollback capability.
- CRI-O as the container runtime (not containerd).
- SELinux enforcing by default.

Node access: use `oc debug node/<name>` instead of SSH. This runs a privileged pod with the host filesystem mounted at `/host`.

## Cluster Operators

Every OpenShift platform component is managed as a Cluster Operator:

```bash
oc get clusteroperators
```

| Operator | Manages |
|---|---|
| `authentication` | OAuth server, identity providers |
| `cloud-credential` | Cloud provider credentials |
| `cluster-autoscaler` | Cluster autoscaler |
| `console` | Web console |
| `dns` | CoreDNS |
| `etcd` | etcd cluster |
| `image-registry` | Integrated image registry |
| `ingress` | HAProxy router (IngressController) |
| `kube-apiserver` | API server |
| `kube-controller-manager` | Controller manager |
| `kube-scheduler` | Scheduler |
| `machine-api` | Machine API (MAPI) for node provisioning |
| `machine-config` | MCO, node OS management |
| `monitoring` | Prometheus, Alertmanager, Thanos |
| `network` | OVN-Kubernetes (or the legacy OpenShift SDN) |
| `node-tuning` | Tuned profiles for node optimisation |
| `openshift-apiserver` | OpenShift API extensions |
| `storage` | CSI drivers, storage configuration |

The built-in Grafana was removed from cluster monitoring in OCP 4.11; the monitoring operator manages Prometheus, Alertmanager, and Thanos, and dashboards moved into the web console.

Cluster Operator states:

- **Available**: functioning correctly.
- **Progressing**: performing an operation (upgrade, configuration change).
- **Degraded**: functioning with errors or reduced capability.

Troubleshooting a degraded operator:

```bash
oc get co <operator-name> -o yaml   # check conditions and messages
oc logs -n openshift-<operator>-operator deploy/<operator>-operator
oc get events -n openshift-<operator>-operator --sort-by=.lastTimestamp
```

## Machine Config Operator (MCO) deep dive

### Architecture

```
MachineConfigController
  |-- Template Controller -> renders MachineConfig objects
  |-- Update Controller   -> coordinates node updates
  +-- Render Controller   -> merges MachineConfigs into rendered-MachineConfig

MachineConfigDaemon (runs on every node)
  |-- Watches for rendered-MachineConfig changes
  |-- Applies config (files, systemd units, kernel args)
  +-- Reboots the node if necessary
```

### Update flow

1. An admin applies a new MachineConfig (or the MCO generates one from cluster config).
2. The Render Controller merges all MachineConfigs for the pool into a `rendered-<pool>-<hash>`.
3. The Update Controller starts a rolling update (one node at a time by default).
4. For each node: cordon (prevent new pods), drain (evict existing pods, respecting PDBs), apply the config through the MachineConfigDaemon, reboot if the config requires it, then uncordon.

`maxUnavailable` controls parallelism. Default: 1. Set it on the MachineConfigPool:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: worker
spec:
  maxUnavailable: 2    # update two nodes at a time
```

### Common MachineConfig use cases

Custom kernel arguments:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-worker-kargs
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  kernelArguments:
  - "hugepages=2048"
  - "default_hugepagesz=2M"
```

Custom systemd unit:

```yaml
spec:
  config:
    ignition:
      version: 3.4.0
    systemd:
      units:
      - name: my-custom.service
        enabled: true
        contents: |
          [Unit]
          Description=My Custom Service
          [Service]
          ExecStart=/usr/local/bin/my-script.sh
          [Install]
          WantedBy=multi-user.target
```

Custom certificate trust:

```yaml
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - path: /etc/pki/ca-trust/source/anchors/internal-ca.crt
        mode: 0644
        contents:
          inline: |
            -----BEGIN CERTIFICATE-----
            ...
            -----END CERTIFICATE-----
```

## OLM architecture

### Components

```
CatalogSource (operator catalog)
   |
   v
OLM Operator (runs in openshift-operator-lifecycle-manager)
   |-- Resolves dependencies between operators
   |-- Creates InstallPlans
   +-- Creates ClusterServiceVersions
   |
   v
Catalog Operator
   |-- Watches CatalogSources
   |-- Resolves Subscriptions to specific operator versions
   +-- Creates or updates InstallPlans
   |
   v
InstallPlan
   |-- Lists all resources to create or update
   |-- Approval: Automatic or Manual
   +-- When approved, creates CSV + CRDs + RBAC + Deployments
```

### Operator dependency resolution

OLM resolves dependencies between operators automatically: if operator A depends on CRD X, OLM finds operator B that provides CRD X and installs B before A.

### Custom operator catalogs (air-gapped)

```bash
# Mirror an operator catalog to an internal registry
oc adm catalog mirror \
  registry.redhat.io/redhat/redhat-operator-index:v4.16 \
  registry.internal.example.com/olm \
  --insecure

# Create a CatalogSource pointing at the mirrored catalog
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: custom-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: registry.internal.example.com/olm/redhat-operator-index:v4.16
  displayName: Custom Catalog
  updateStrategy:
    registryPoll:
      interval: 30m
EOF
```

## Route controller (HAProxy router)

### Architecture

The IngressController operator manages the HAProxy instances that serve as the default router:

```
External traffic -> Load balancer -> HAProxy pods (router-default)
                                        |
                                        v
                                     Route evaluation (host + path matching)
                                        |
                                        v
                                     Backend Service -> Pods
```

The router runs as a Deployment in the `openshift-ingress` namespace. Default: 2 replicas.

### Route evaluation

Routes are evaluated by host match (exact hostname), then path match (path prefix if specified), then wildcard (`*.apps.cluster.example.com` if the wildcard policy allows).

### Performance tuning

```yaml
apiVersion: operator.openshift.io/v1
kind: IngressController
metadata:
  name: default
  namespace: openshift-ingress-operator
spec:
  tuningOptions:
    maxConnections: 50000
    threadCount: 4
    headerBufferBytes: 32768
    headerBufferMaxRewriteBytes: 8192
  replicas: 3
```

## Integrated image registry

OpenShift runs an internal registry at `image-registry.openshift-image-registry.svc:5000`:

```bash
# Check registry status
oc get configs.imageregistry.operator.openshift.io cluster -o yaml

# Expose the registry externally
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge --patch '{"spec":{"defaultRoute":true}}'

# Access the registry
oc registry login
podman login -u $(oc whoami) -p $(oc whoami -t) default-route-openshift-image-registry.apps.cluster.example.com
```

Storage backends: Azure Blob, AWS S3, GCS, OpenStack Swift, and a PVC on bare metal.

## Networking

### OVN-Kubernetes (default since OCP 4.12)

OpenShift's default CNI uses OVN (Open Virtual Network):

- Overlay networking via Geneve tunnels.
- Built-in NetworkPolicy enforcement.
- Hybrid networking (Linux and Windows nodes).
- EgressFirewall (cluster-scoped egress rules).
- EgressIP (stable source IPs for external communication).

The legacy OpenShift SDN was removed in OCP 4.17; clusters upgrading through that boundary must migrate to OVN-Kubernetes first.

### EgressFirewall

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressFirewall
metadata:
  name: default
  namespace: production
spec:
  egress:
  - type: Allow
    to:
      cidrSelector: 10.0.0.0/8
  - type: Allow
    to:
      dnsName: "*.internal.example.com"
  - type: Deny
    to:
      cidrSelector: 0.0.0.0/0
```

### EgressIP

Assign stable egress IPs to pods in a namespace (useful for firewall allowlisting):

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: production-egress
spec:
  egressIPs:
  - 192.168.1.100
  - 192.168.1.101
  namespaceSelector:
    matchLabels:
      env: production
```

## Security architecture

### SCC evaluation algorithm

When a pod is created:

```
1. Collect all SCCs accessible to the pod's ServiceAccount
   (via RoleBindings / ClusterRoleBindings granting the "use" verb on SCC resources).
2. Sort SCCs by restrictiveness (most restrictive first).
3. For each SCC:
   a. Check whether the pod's securityContext satisfies the SCC constraints.
   b. If yes, mutate the pod to fill in missing fields with SCC defaults.
   c. Assign this SCC to the pod.
4. If no SCC matches, reject the pod.
```

Default: all authenticated users can use the `restricted-v2` SCC.

### OAuth and identity

OpenShift includes an OAuth server for authentication:

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: ldap
    type: LDAP
    mappingMethod: claim
    ldap:
      url: "ldaps://ldap.example.com/ou=users,dc=example,dc=com?uid"
      bindDN: "cn=admin,dc=example,dc=com"
      bindPassword:
        name: ldap-bind-password
      insecure: false
      ca:
        name: ldap-ca
  - name: htpasswd
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
```

Supported identity providers: LDAP, Active Directory, OIDC, GitHub, Google, GitLab, Basic Auth, HTPasswd, Keystone, and Request Header.

### Certificate management

OpenShift manages internal certificates automatically: the API server serving cert, the ingress controller (router) certs, the etcd peer and client certs, and the kubelet certs.

Custom certificates can be set for the API server and ingress:

```bash
# Custom ingress cert
oc create secret tls ingress-cert \
  --cert=cert.pem --key=key.pem -n openshift-ingress

oc patch ingresscontroller default \
  -n openshift-ingress-operator \
  --type=merge \
  --patch='{"spec":{"defaultCertificate":{"name":"ingress-cert"}}}'
```
