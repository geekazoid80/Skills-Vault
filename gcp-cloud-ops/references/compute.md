# GCP Compute Reference

> Prices are us-central1, on-demand unless noted. Verify at https://cloud.google.com/pricing.

---

## 1. Compute Engine (IaaS VMs)

### Machine Type Families

| Family | Series | Use Case | vCPU:Memory |
|--------|--------|----------|-------------|
| General Purpose | E2 | Cost-optimised, dev/test | 1:0.5-8 GB |
| General Purpose | N2/N2D | Balanced production | 1:1-8 GB |
| General Purpose | N4 | Latest gen (Emerald Rapids) | 1:1-8 GB |
| Compute Optimised | C3/C3D | HPC, gaming, single-thread | 1:2-4 GB |
| Memory Optimised | M3 | SAP HANA, in-memory DBs | 1:14.9 GB |
| Accelerator Optimised | A2 | ML training (A100 GPUs) | Fixed configs |
| Accelerator Optimised | A3 | ML training (H100, 200 Gbps GPU-GPU) | Fixed configs |
| Accelerator Optimised | G2 | ML inference (L4 GPUs) | Fixed configs |

### Custom Machine Types (Unique to GCP)

Specify exact vCPU (1-96) and memory (0.9-6.5 GB per vCPU). Eliminates over-provisioning.

- Extended memory: up to 12 GB/vCPU for memory-intensive workloads.
- Available for N1, N2, N2D, E2 families.
- No AWS or Azure equivalent; those platforms force fixed instance sizes.

### Pricing Reference (on-demand, per hour)

- e2-medium (2 vCPU, 4 GB): ~$0.034
- n2-standard-8 (8 vCPU, 32 GB): ~$0.388
- c3-standard-8 (8 vCPU, 32 GB): ~$0.408
- a2-highgpu-1g (12 vCPU, 85 GB, 1xA100): ~$3.67

### Sustained Use Discounts (SUDs)

Automatic discount, no commitment needed:

| Monthly Usage | Discount |
|--------------|---------|
| 0-25% | Full price |
| 25-50% | 20% off |
| 50-75% | 40% off |
| 75-100% | 60% off |

**Effective discount for 100% usage: ~30%.**

Applies to N1, N2, N2D, C2. Does NOT apply to E2, Tau, A2, A3 (already have optimised pricing).

SUDs and CUDs do not stack; CUDs replace SUDs for committed resources.

### Committed Use Discounts (CUDs)

| Term | Discount |
|------|----------|
| 1-year | Up to 57% |
| 3-year | Up to 70% |

- **Resource-based CUDs:** Commit to vCPU and memory quantities. Applies across project/region regardless of instance type.
- **Spend-based CUDs:** Commit to hourly spend for GPUs and local SSDs.
- CUD sharing across projects within a billing account must be explicitly enabled.

### Spot VMs

60-91% discount on spare capacity. No maximum lifetime (unlike legacy preemptible VMs).

- 30-second reclaim warning. No SLA, no live migration.
- Best for: batch, CI/CD, data processing, fault-tolerant workloads.

### Live Migration

GCP transparently migrates VMs during host maintenance. Sub-second network blip; no downtime for host OS updates, hardware repairs, or security patches. This is the default behaviour and a unique GCP differentiator.

### Sole-Tenant Nodes

Dedicated physical servers for compliance, BYOL (Windows/Oracle), and isolation. Per-node pricing with ability to overcommit.

### Rightsizing Recommender

Analyses the last 8 days of utilisation. Recommendations cover resize, change type, and stop-idle-instance actions. Cost impact estimates are included.

---

## 2. Cloud Run (Serverless Containers)

### What Makes Cloud Run Unique

Full OCI containers on fully managed serverless infrastructure. No cluster, no node pools, no Kubernetes YAML. Deploy a container, get an HTTPS endpoint. This is GCP's strongest serverless differentiator.

### Execution Models

- **Services:** Long-running, request-driven. HTTP/1.1, HTTP/2, gRPC, WebSockets.
- **Jobs:** Batch/task execution, run to completion. Array jobs for parallel processing.

### Concurrency Model (Major Differentiator)

A single instance handles up to **1,000 concurrent requests** (configurable 1-1000).

- AWS Lambda: strictly 1 invocation per instance.
- Cloud Run amortises cold-start cost across many requests, dramatically lowering cost at high throughput.
- Set concurrency=1 only when code is not thread-safe.

### Pricing (per-second, 100 ms minimum)

- vCPU: $0.0000240/vCPU-second
- Memory: $0.0000025/GiB-second
- Requests: $0.40/million
- Free tier: 2M requests, 360K GiB-seconds, 180K vCPU-seconds/month

### CPU Allocation Modes

- **Request-based (default):** CPU allocated only during request processing. Cheapest for intermittent traffic. Container frozen between requests.
- **Always-on CPU:** CPU always allocated. Required for background processing and WebSockets. Approximately 2.5x the per-second rate.

### Scaling

- **Min instances:** Keep N warm (eliminates cold starts at the cost of idle time).
- **Max instances:** Hard cap for cost protection.
- **Startup CPU boost:** Extra CPU during startup for heavy frameworks.
- Typical cold start: 200 ms to 2 s.

### When to Choose Cloud Run

| Comparison | Guidance |
|-----------|---------|
| vs Cloud Functions | Prefer Cloud Run for custom runtimes, larger instances, concurrency control, long connections, or portable containers |
| vs GKE | Use Cloud Run for zero-ops, stateless, request-driven workloads; use GKE for stateful apps, GPU, or complex networking |
| vs App Engine | Cloud Run is the modern replacement |

---

## 3. Cloud Functions (FaaS)

### 1st Gen vs 2nd Gen

| Capability | 1st Gen | 2nd Gen (built on Cloud Run) |
|------------|---------|------------------------------|
| Timeout | 9 min | 60 min (HTTP) |
| Instance size | 8 GB / 2 vCPU | 32 GB / 8 vCPU |
| Concurrency | 1 request/instance | Up to 1,000/instance |
| Traffic splitting | No | Yes |
| Triggers | HTTP, Pub/Sub, GCS, Firestore | All of 1st Gen + Eventarc (120+ types) |

**Always use 2nd Gen.** 1st Gen is legacy. 2nd Gen is Cloud Run under the hood.

Pricing: $0.40/M invocations + compute (same rates as Cloud Run). Free tier: 2M invocations, 400K GB-seconds.

---

## 4. Google Kubernetes Engine (GKE)

### Autopilot vs Standard

| Aspect | Autopilot | Standard |
|--------|-----------|----------|
| Node management | Google-managed | Self-managed |
| Pricing | Per-pod resource requests | Per-node (whole VMs) |
| Scaling | Automatic | Manual + autoscaler |
| Security | Hardened, no SSH | Full node access |
| GPU/TPU | Yes (Spot pods) | Yes (full control) |
| DaemonSets | Restricted | Full support |
| Cost at >80% utilisation | More expensive | Cheaper |

### Autopilot Pricing

- vCPU: $0.0445/hr (regular), $0.0148/hr (Spot)
- Memory: $0.0049/GB-hr (regular), $0.0016/GB-hr (Spot)
- No cluster management fee.

### Standard Pricing

- Cluster management fee: $0.10/hr ($73/mo).
- Nodes: standard Compute Engine pricing.

### Cost Optimisation

1. **Spot pods in Autopilot:** 60-91% savings for fault-tolerant workloads.
2. **CUDs apply** to GKE Standard node usage.
3. **GKE cost allocation:** Track costs per namespace, label, or team.
4. **Cluster autoscaler + VPA:** Right-size pods and nodes.
5. **Node auto-provisioning:** Selects optimal VM sizes for pending pods.
6. **Multi-tenant clusters:** Share a cluster instead of one-per-team (saves $73/mo per cluster avoided).

### GKE Networking

- **Dataplane V2** (eBPF/Cilium): default for Autopilot.
- Gateway API support (native, multi-cluster).
- Multi-cluster Services (MCS) for cross-cluster service discovery.
- GKE Ingress integrated with Cloud Load Balancing.

### GKE Enterprise (formerly Anthos)

Multi-cluster management across GCP, on-premises, and other clouds. Includes Config Sync (GitOps), Policy Controller (OPA), and managed Service Mesh (Istio). Additional cost: $0.01/vCPU-hour.

---

## 5. App Engine

- **Standard:** Auto-scales to zero, limited runtimes, sandbox execution, free daily quotas. Good for simple zero-ops HTTP apps.
- **Flexible:** Custom Docker containers on VMs; does NOT scale to zero (minimum 1 instance always running).
- **Guidance:** Standard is still valid for simple HTTP apps that benefit from the free tier. For everything else, prefer Cloud Run.

---

## 6. Operational Tooling (MCP)

### GCP Compute Engine MCP Server

The `gcp-compute-ops` MCP server connects to the GCP REST API over a remote HTTP (SSE) endpoint.

**Auth requirements:**

- Transport: remote HTTP with Server-Sent Events.
- Auth: OAuth 2.0 (service account JSON key or Application Default Credentials).
- Project scoping: `GCP_PROJECT_ID` environment variable (required). All tool calls are scoped to this project unless the tool explicitly accepts a `project_id` parameter.

**Write-operation gating:** Any tool that creates, modifies, or deletes a Compute Engine resource requires a ServiceNow change request (CR) number supplied as a parameter. The server validates the CR is in "Approved" state before executing the call. Read-only tools (List, Get, Describe) have no CR requirement.

### Infrastructure Audit Workflow

Use this sequence to produce a baseline inventory and flag anomalies before a change window or cost review.

1. Call `gcp_list_instances` for each region to enumerate all running and stopped VMs, capturing machine type, zone, status, and labels.
2. Call `gcp_get_instance_details` on instances without a `env` or `owner` label to identify untagged resources; flag for labelling.
3. Call `gcp_list_disks` and cross-reference against the instance inventory; any disk with no `users` entry is an orphaned persistent disk accruing cost.
4. Call `gcp_get_rightsizing_recommendations` to pull Recommender suggestions; sort by projected monthly saving and present the top 10.
5. Call `gcp_list_snapshots` and check `creationTimestamp` against the retention policy; snapshots older than the policy window are candidates for deletion.
6. Summarise findings as: orphaned disks, untagged instances, rightsizing opportunities, stale snapshots, and any instances running without SUDs or CUDs covering them.

### VM Troubleshooting Workflow

Use when a VM is unreachable, crashing, or performing below baseline.

1. Call `gcp_get_instance_details` to confirm power state, zone, machine type, and attached disks.
2. Call `gcp_get_serial_port_output` (port 1) to read boot-time kernel and init messages; look for filesystem errors, OOM kills, or failed unit messages.
3. Call `gcp_get_guest_attributes` to confirm the guest OS agent is responding and to read any custom attributes set by the provisioning pipeline.
4. Call `gcp_list_operations` filtered to the instance resource; recent operations (disk attach, metadata update, live-migration event) that correlate with the reported start of the issue narrow the cause.
5. If the issue is network-related, call `gcp_test_connectivity` (source: the VM's primary NIC; destination: target IP/port) to get a path trace through VPC firewall rules and routes.
6. For persistent boot failure, call `gcp_get_instance_details` to confirm the boot disk is attached and not in a detached or read-only state; if the disk is healthy, use the rescue-disk procedure (attach the boot disk to a second VM as a secondary disk, inspect the filesystem, reattach).

### Capacity Planning Workflow

Use when sizing a new environment, projecting scale-out cost, or evaluating a migration from on-premises.

1. Call `gcp_list_machine_types` for the target region to confirm which families and sizes are available (availability varies by zone).
2. For each candidate machine type, call `gcp_get_machine_type` to retrieve the vCPU/memory/GPU configuration and the on-demand hourly rate.
3. Model the baseline on-demand cost; then apply SUD at 100% utilisation (~30% effective discount for N-family) to get the committed equivalent without a CUD.
4. Model 1-year and 3-year CUD scenarios using the discount table in Section 1; CUDs are resource-based (vCPU + memory quantities), so they survive instance-type changes within the same family.
5. For fault-tolerant components (batch, CI, data pipelines), model a Spot VM alternative at 60-75% discount and factor in the expected reclaim rate for the workload class.
6. Call `gcp_get_quota` for the target project and region to verify that vCPU, IP address, and persistent disk quota are sufficient; quota increase requests can take 24-48 hours, so submit early.
7. Present the three-scenario table (on-demand, CUD-3yr, Spot) with estimated monthly cost, SLA impact, and the minimum on-demand buffer needed to maintain the SLA.
