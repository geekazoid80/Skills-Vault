# GCP Observability Reference

---

## Section 1: Cloud Logging

### MCP Server

- **Endpoint**: `https://logging.googleapis.com/mcp` (Streamable HTTP)
- **Auth**: OAuth 2.0 via Google IAM (service account key via `GOOGLE_APPLICATION_CREDENTIALS`, or `gcloud auth application-default login`)
- **Requires**: `GCP_PROJECT_ID` environment variable

### Available Tools (6)

| Tool | What It Does |
|------|--------------|
| `list_log_entries` | Search and retrieve log entries (primary tool for debugging, error hunting, and audit) |
| `list_log_names` | Discover what logs exist in a project (find available log sources) |
| `get_bucket` | Get details of a specific log bucket (storage container for logs) |
| `list_buckets` | List all log buckets in a project |
| `get_view` | Get a specific log view (fine-grained access filter on a bucket) |
| `list_views` | List log views in a bucket |

### Workflow: VPC Flow Log Analysis

When investigating GCP network traffic:

1. **Discover logs**: `list_log_names` to find `compute.googleapis.com/vpc_flows`
2. **Query flow logs**: `list_log_entries` filtered by source/destination IP, port and protocol, action (ALLOWED/DENIED), and time range
3. **Denied traffic**: Filter for `reporter="DEST"` and denied connections
4. **Top talkers**: Aggregate by source/destination IP and bytes
5. **Cross-reference**: Use Cloud Monitoring (Section 2) for network metrics during the same period
6. **Report**: Traffic analysis with security findings

### Workflow: Firewall Log Investigation

When investigating GCP firewall rule activity:

1. **Discover logs**: `list_log_names` to find `compute.googleapis.com/firewall`
2. **Query firewall logs**: `list_log_entries` filtered by rule name, action (ALLOWED/DENIED), source/destination IP, and port
3. **Denied connections**: Find blocked traffic patterns
4. **Rule effectiveness**: Which rules are hitting most frequently?
5. **Report**: Firewall activity summary with recommendations

### Workflow: Audit Trail Investigation

When investigating GCP API activity (equivalent of AWS CloudTrail):

1. **Admin activity logs**: `list_log_entries` for `cloudaudit.googleapis.com/activity` to see who created, modified, or deleted resources
2. **Data access logs**: `list_log_entries` for `cloudaudit.googleapis.com/data_access` to see who read what
3. **Filter by principal**: Narrow to a specific user or service account
4. **Filter by method**: Narrow to specific API calls (e.g., `compute.instances.delete`)
5. **Time window**: Focus on the incident period
6. **Report**: Audit timeline with responsible principals and actions

### Workflow: Troubleshooting with Logs

When debugging a GCP issue:

1. **Application logs**: `list_log_entries` for the affected service
2. **Error filtering**: Filter by severity (`ERROR`, `CRITICAL`, `EMERGENCY`)
3. **Instance logs**: Filter by `resource.labels.instance_id` for specific VMs
4. **Correlate**: Match timestamps with Cloud Monitoring alert violations (Section 2)
5. **Bucket check**: `list_buckets` to verify log retention settings
6. **Report**: Root cause analysis with log evidence

### Common GCP Log Sources

| Log Name | What It Contains |
|----------|------------------|
| `compute.googleapis.com/vpc_flows` | VPC flow logs: source/dest IP, port, bytes, packets, action |
| `compute.googleapis.com/firewall` | Firewall rule hits: allowed/denied connections with rule name |
| `cloudaudit.googleapis.com/activity` | Admin activity audit: resource create/modify/delete events |
| `cloudaudit.googleapis.com/data_access` | Data access audit: read operations on resources |
| `cloudaudit.googleapis.com/system_event` | System events: Google-initiated actions (live migration, etc.) |
| `compute.googleapis.com/shielded_vm_integrity` | Shielded VM boot integrity verification |
| `dns.googleapis.com/dns_queries` | Cloud DNS query logs |
| `loadbalancing.googleapis.com/requests` | Load balancer access logs |
| `networksecurity.googleapis.com/firewall_threat` | Cloud IDS / Firewall threat detection |

### Log Query Filter Examples

```
# VPC flow logs -- denied traffic to port 443
resource.type="gce_subnetwork"
logName="projects/PROJECT/logs/compute.googleapis.com%2Fvpc_flows"
jsonPayload.disposition="DENIED"
jsonPayload.connection.dest_port=443

# Firewall -- denied SSH attempts
resource.type="gce_subnetwork"
logName="projects/PROJECT/logs/compute.googleapis.com%2Ffirewall"
jsonPayload.disposition="DENIED"
jsonPayload.connection.dest_port=22

# Audit -- who deleted VMs in the last hour
logName="projects/PROJECT/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="compute.instances.delete"
timestamp>="2026-01-01T00:00:00Z"

# DNS queries from specific source
resource.type="dns_query"
jsonPayload.sourceIP="10.0.1.50"
```

### Important Rules

- **Remote MCP server**: hosted by Google, no local install needed
- **OAuth 2.0 authentication**: uses IAM for access control
- **Project-scoped**: logs are scoped to the configured GCP project
- **Log queries have cost implications**: Cloud Logging charges for data scanned beyond the free tier (50 GB/month free)
- **Retention varies**: Admin activity logs retain for 400 days; Data access logs retain for 30 days by default; VPC flow log retention depends on bucket configuration

---

## Section 2: Cloud Monitoring

### MCP Server

- **Endpoint**: `https://monitoring.googleapis.com/mcp` (Streamable HTTP)
- **Auth**: OAuth 2.0 via Google IAM (service account key via `GOOGLE_APPLICATION_CREDENTIALS`, or `gcloud auth application-default login`)
- **Requires**: `GCP_PROJECT_ID` environment variable

### Available Tools (6)

| Tool | What It Does |
|------|--------------|
| `list_timeseries` | Query time series data: CPU, memory, network, disk metrics for any GCP resource |
| `list_metric_descriptors` | Discover available metric types in a project (find what you can monitor) |
| `list_alert_policies` | List all alerting policies: conditions, notification channels, thresholds |
| `get_alert_policy` | Get details of a specific alerting policy |
| `list_alerts` | List current and past alert violations (what is firing right now) |
| `get_alert` | Get details of a specific alert violation |

### Workflow: GCP Network Monitoring

When asked how GCP network performance looks:

1. **Check alerts**: `list_alerts` to find any active alert violations
2. **VM network metrics**: `list_timeseries` for `compute.googleapis.com/instance/network/received_bytes_count` and `sent_bytes_count`
3. **Packet drops**: `list_timeseries` for `compute.googleapis.com/instance/network/received_packets_dropped_count`
4. **Firewall metrics**: `list_timeseries` for `compute.googleapis.com/firewall/dropped_packets_count`
5. **Load balancer metrics**: `list_timeseries` for `loadbalancing.googleapis.com/https/request_count` and `total_latencies`
6. **Report**: Network health dashboard with any issues flagged

### Workflow: Alert Investigation

When investigating GCP alerts:

1. **List active alerts**: `list_alerts` to find what is currently firing
2. **Get alert details**: `get_alert` to see the condition, threshold, and affected resource
3. **Get policy**: `get_alert_policy` to see what triggers this alert and the notification channels configured
4. **Pull metrics**: `list_timeseries` for the affected metric to see the spike or anomaly
5. **Cross-reference**: Use Cloud Logging (Section 1) for correlated log entries
6. **Report**: Alert investigation with root cause and timeline

### Workflow: Resource Health Check

When checking GCP infrastructure health:

1. **Discover metrics**: `list_metric_descriptors` filtered by service (compute, networking, loadbalancing)
2. **VM CPU/Memory**: `list_timeseries` for `compute.googleapis.com/instance/cpu/utilization` and memory metrics
3. **Disk I/O**: `list_timeseries` for `compute.googleapis.com/instance/disk/read_bytes_count` and write metrics
4. **Network throughput**: `list_timeseries` for network sent/received bytes
5. **Alert status**: `list_alert_policies` and `list_alerts` to check for policies in violation
6. **Report**: Infrastructure health dashboard with severity ratings

### Common GCP Network Metrics

| Metric | What It Tells You |
|--------|--------------------|
| `compute.googleapis.com/instance/network/received_bytes_count` | Inbound network throughput per VM |
| `compute.googleapis.com/instance/network/sent_bytes_count` | Outbound network throughput per VM |
| `compute.googleapis.com/instance/network/received_packets_dropped_count` | Dropped inbound packets (congestion) |
| `compute.googleapis.com/instance/network/sent_packets_dropped_count` | Dropped outbound packets (congestion) |
| `compute.googleapis.com/firewall/dropped_packets_count` | Packets dropped by VPC firewall rules |
| `loadbalancing.googleapis.com/https/request_count` | HTTP(S) LB request rate |
| `loadbalancing.googleapis.com/https/total_latencies` | HTTP(S) LB end-to-end latency |
| `loadbalancing.googleapis.com/https/backend_latencies` | Backend response time behind LB |
| `vpn.googleapis.com/tunnel_established` | Cloud VPN tunnel state (1=up, 0=down) |
| `vpn.googleapis.com/sent_bytes_count` | Bytes sent through VPN tunnel |
| `router.googleapis.com/bgp/received_routes_count` | BGP routes received by Cloud Router |
| `interconnect.googleapis.com/link/received_bytes_count` | Cloud Interconnect link throughput |

### Important Rules

- **Remote MCP server**: hosted by Google, no local install needed
- **OAuth 2.0 authentication**: uses IAM for access control
- **Project-scoped**: metrics are scoped to the configured GCP project
- **Read-only**: monitoring queries do not modify anything
