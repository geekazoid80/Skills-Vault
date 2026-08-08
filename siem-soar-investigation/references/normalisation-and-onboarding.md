# Normalisation and onboarding

The data pipeline that decides detection quality: how logs are collected, parsed, normalised, enriched, stored, and retained, and which sources to onboard first. Garbage in, garbage out: detection quality is capped here.

## Log-management lifecycle

### Collection

| Method | Description | Use case |
|---|---|---|
| Agent-based | Software agent on the host pushes logs | Endpoints, servers (Splunk UF, Elastic Agent, WEF) |
| Agentless | Pull via API, syslog, or WMI/WinRM | Network devices, cloud APIs, SaaS |
| Syslog | RFC 5424/3164 over UDP/TCP/TLS | Firewalls, routers, Linux, appliances |
| API polling | Scheduled REST calls | Cloud services (CloudTrail, O365, Okta) |
| Event streaming | Kafka, Event Hubs, Pub/Sub, Kinesis | High-volume, low-latency pipelines |
| File monitoring | Watch directories for changes | Legacy and flat-file logs |

### Parsing

Extract structured fields from raw text:

- **Regex extraction** - most flexible, highest maintenance.
- **JSON/XML/CSV** - structured formats parsed natively, lowest effort.
- **Key-value** - `field=value` patterns common in syslog.
- **Grok patterns** - named regex (Elastic, LogScale) for common formats.
- **LEEF/CEF** - structured syslog formats from security products (QRadar LEEF, ArcSight CEF).

### Normalisation

Map vendor-specific field names to a common schema. Without it, cross-source correlation is impossible.

```
Raw:  src_ip=10.0.0.1, dest_ip=192.168.1.1, action=allow
CIM:  src_ip=10.0.0.1, dest_ip=192.168.1.1, action=allowed
ECS:  source.ip=10.0.0.1, destination.ip=192.168.1.1, event.outcome=success
ASIM: SrcIpAddr=10.0.0.1, DstIpAddr=192.168.1.1, EventResult=Success
UDM:  principal.ip=10.0.0.1, target.ip=192.168.1.1, security_result.action=ALLOW
```

| Standard | Platform | Key concept |
|---|---|---|
| CIM (Common Information Model) | Splunk | Data models with standard field names; acceleration for dashboards |
| ECS (Elastic Common Schema) | Elastic | Hierarchical naming (`process.name`, `source.ip`) |
| ASIM (Advanced SIM) | Sentinel | Unifying parsers that normalise at query time |
| UDM (Unified Data Model) | Chronicle/SecOps | Entity-centric schema for security telemetry |
| OCSF (Open Cybersecurity Schema Framework) | Cross-platform | AWS-originated open standard, growing adoption |

### Enrichment

Add context after normalisation:

- **GeoIP** - map addresses to location.
- **ASN lookup** - the organisation owning an IP.
- **Threat intelligence** - match IOCs (IPs, domains, hashes) against feeds.
- **Asset inventory** - criticality, owner, business unit.
- **Identity context** - map usernames to people, roles, departments.
- **WHOIS/DNS** - domain age, registrar, resolution history.

### Indexing and storage

| Approach | Platforms | Trade-offs |
|---|---|---|
| Inverted index | Splunk, Elastic | Fast full-text search; storage overhead for index structures |
| Columnar | QRadar (Ariel), Sentinel (Log Analytics) | Efficient aggregations; slower full-text search |
| Index-free (compressed raw + bloom filters) | LogScale | Minimal storage overhead, streaming search; cold data slower |
| Hybrid | Chronicle (UDM + raw) | Structured search on UDM, raw kept for forensics |

### Retention

| Requirement | Typical retention | Driver |
|---|---|---|
| Real-time detection | 0-90 days (hot) | SOC operations, active investigations |
| Investigation/hunt | 90-365 days (warm) | Incident response, threat hunting |
| Compliance (PCI DSS) | 1 year online + 1 year archive | PCI DSS Requirement 10.7 |
| Compliance (HIPAA) | 6 years | HIPAA audit-trail requirements |
| Compliance (SOX) | 7 years | Financial audit trail |
| Legal hold | Indefinite | Litigation preservation |

## Onboarding strategy: prioritise by detection value

| Priority | Log sources | Detection value |
|---|---|---|
| P1 Critical | EDR, identity (AD/Entra), email gateway, firewall/proxy | Core visibility for ~80% of attack techniques |
| P2 High | Cloud audit (CloudTrail, Azure Activity, GCP Audit), DNS, DHCP | Lateral movement, cloud compromise, C2 |
| P3 Medium | Application logs, VPN, DLP, vulnerability scanners | Insider threat, exfiltration, vuln correlation |
| P4 Low | Network flow (NetFlow/IPFIX), PCAP metadata, printer logs | Forensic enrichment, compliance, niche detections |

Onboard P1 first and map each source to specific detections before ingesting it. A source with no detection plan is cost without value.

## Cost optimisation

Ingestion volume drives SIEM cost. Common tactics:

1. **Tiered storage** - hot/warm/cold/frozen; not all data needs fast search (Splunk SmartStore, Sentinel basic logs, Elastic frozen tier).
2. **Filter at source** - drop verbose debug, health checks, success-only auth before ingestion.
3. **Summary indexing** - pre-aggregate stats for reporting; keep raw data shorter.
4. **Log routing** - send compliance-only logs to cheap object storage; send security-relevant logs to the SIEM.
5. **Data-model acceleration** - pre-compute common searches to avoid full-index scans.
6. **Commitment tiers** - vendor discounts for committed volume (Sentinel commitment tiers, Splunk workload pricing).
7. **Event sampling** - for extremely high-volume, low-fidelity sources (NetFlow), sample rather than ingest everything.

## Cross-references

- `siem-soar-investigation`: the umbrella; condensed core and routing.
- `references/detection-engineering.md`: detections match on the fields produced here; normalisation quality caps detection quality.
- `graylog-log-investigation`: Graylog index sets, rotation, and retention as a concrete implementation of the storage/retention model above.
- `compliance-benchmark-audit`: the regulatory drivers behind the retention table.
- `utc-timestamps`: normalise all event times to UTC; mixed time zones break correlation.
