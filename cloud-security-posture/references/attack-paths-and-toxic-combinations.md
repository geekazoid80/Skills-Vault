# Attack paths and toxic combinations

Cloud attacks are not on-premises attacks moved to someone else's data centre. The perimeter is identity, the primary entry is a misconfiguration, and lateral movement happens through IAM roles and cloud APIs rather than through the network. The consequence for posture work is decisive: risk is the exploitable path an attacker would actually walk, not the tally of findings a scanner produces. This reference develops the attack-pattern model, the toxic-combination idea, and how to trace a path to a crown-jewel asset.

## Why cloud attacks differ

Three properties reshape the threat model:

- **Identity is the perimeter.** There is no single network edge to defend. An identity with the right permissions can reach a resource from anywhere the API is reachable, so a stolen credential or an over-privileged role is the equivalent of being inside the network.
- **Misconfiguration is the dominant vector.** Because the customer owns the configuration surface and it changes constantly, the most exploited weaknesses are things the customer set: a public bucket, an open management port, a disabled log, a wildcard IAM policy. These are not vendor bugs; they are posture.
- **Lateral movement is API-driven.** Movement between resources happens by assuming roles, chaining trust relationships, and calling control-plane APIs, not by exploiting host-to-host network paths. This is why entitlement analysis (CIEM) is central rather than peripheral.

## Cloud attack patterns (MITRE ATT&CK for cloud)

MITRE maintains cloud-specific ATT&CK matrices spanning IaaS, SaaS, and the major providers. Mapping findings to a shared attacker model keeps posture work grounded in what adversaries actually do. The phases and the posture control that blunts each:

| Phase | Common cloud techniques | Posture control that blunts it |
|---|---|---|
| Initial access | phishing for cloud credentials, exploiting a public-facing app, stolen API keys, misconfigured storage | MFA, credential hygiene, CSPM for public exposure |
| Execution | function abuse, compute user-data injection, cloud-function exploitation | least-privilege execution roles, code signing |
| Persistence | creating IAM users or keys, backdoor functions, modifying cloud functions | audit-log monitoring, IAM change alerting, CIEM |
| Privilege escalation | policy attachment, role chaining, pass-role abuse, assume-role chains | CIEM net-effective permissions, just-in-time access |
| Defence evasion | disabling audit logging, deleting logs, creating shadow resources in another region | immutable logging, threat detection, CDR |
| Credential access | stealing instance metadata credentials, secret-manager scraping, function environment variables | enforce hardened metadata service, secrets in a dedicated vault |
| Discovery | describing cloud resources, enumerating IAM, listing buckets | anomaly detection, API call-rate monitoring |
| Lateral movement | cross-account role assumption, service-account pivoting | least-privilege cross-account trust, guardrail policies |
| Collection | staging data in object storage, database snapshot sharing | DSPM, storage bucket-policy scanning |
| Exfiltration | direct storage transfer, replication to an attacker-controlled account | DSPM, network egress monitoring |
| Impact | ransomware via storage encryption, resource deletion, crypto mining | immutable backups, anomaly detection, CDR |

Several techniques recur often enough to name specifically. Stealing credentials from an instance metadata service (the classic server-side-request-forgery-to-credential-theft chain) is blunted by enforcing the session-token-required version of the metadata service. Valid-account abuse of compromised IAM users or service accounts is why stale-credential detection matters. Account-manipulation persistence (adding access keys or attaching roles to a compromised principal) is why IAM-change alerting is not optional. Transferring data to an attacker-controlled cloud account is a cloud-native exfiltration route with no on-premises analogue. Consult the MITRE ATT&CK cloud matrices directly for the authoritative technique catalogue and identifiers rather than relying on a paraphrase.

## Toxic combinations

A **toxic combination** is a multi-factor risk in which conditions that are individually acceptable, or individually only modest, combine into a critical one. It is the single most important idea in cloud posture, because it explains why a finding count is the wrong unit of risk.

The canonical example:

- an internet-exposed compute instance with a critical, exploitable vulnerability, plus
- a metadata service that allows credential theft, plus
- an instance role that can read a sensitive storage bucket, plus
- sensitive data (PII) in that bucket.

No single element is a crisis. The public instance is normal. A vulnerability is one of thousands. The role is doing its job. The data is where data lives. Together they are a complete path from exploitation to breach, and a scanner reporting them as four separate medium findings has buried the one thing that matters under noise.

Recurring toxic-combination patterns worth recognising:

- **Exposed plus vulnerable plus privileged:** a public-facing resource, a critical vulnerability, and a role with broad permissions. The classic breach chain.
- **Exposed plus sensitive data:** public-facing storage that holds classified data. The simplest and one of the most common.
- **Lateral-movement chain:** an over-privileged identity, a cross-account trust relationship, and a sensitive resource in the target account.
- **Credential-theft path:** compute with an unhardened metadata service, a high-privilege instance role, and a sensitive target the role can reach.
- **Shadow access:** a service account with unused but broad permissions attached to a public workload, so compromising the workload inherits the breadth.

## Attack-path analysis

An **attack path** is the ordered sequence of steps from an initial foothold to a high-value target. Modern CNAPP platforms model the estate as a directed graph (resources, identities, permissions, network reachability, and data classification are nodes and edges) and compute the paths that connect an exposed entry point to a crown-jewel asset. Conceptually:

```
[Internet]
  -> [exploitable vulnerability on an exposed workload]
  -> [credential theft from the instance metadata service]
  -> [the workload's instance role]
  -> [assume a more privileged role]
  -> [read a sensitive storage bucket]
  -> [exfiltrate PII]
```

This is the reasoning behind the graph and attack-path features of the major platforms (named in `platform-selection.md`). The practical discipline it enables:

1. **Anchor on the crown jewels.** Start from what an attacker wants (sensitive data stores identified by DSPM, production systems, identity infrastructure) and work backwards. A path that ends nowhere valuable is not urgent; a short path that ends at regulated data is.
2. **Find the exposed entry points.** Internet-reachable workloads, public storage, and externally assumable roles are where a path can begin. External discovery of unknown internet-facing entry points is `attack-surface-management` and `defender-easm` work; this skill traces the path inward once an entry point is known.
3. **Trace reachability through identity.** Follow the permission and trust edges (net-effective permissions from CIEM) to see what each hop can reach. This is where a chain of individually-reasonable roles becomes a privilege-escalation route.
4. **Cut the path at its cheapest edge.** A path has several edges; breaking any one severs it. Removing one over-broad permission, hardening one metadata service, or making one bucket private can neutralise a path more cheaply than patching every vulnerability along it. Prioritise the edge whose removal breaks the most paths.
5. **Re-evaluate continuously.** The estate changes daily, so a path that did not exist yesterday can appear when a role is widened or a resource is exposed. Posture is a continuous assessment, not a one-off audit.

## What this changes about prioritisation

The finding count is the wrong unit. Ranking cloud risk means ranking exploitable paths to crown-jewel assets, then cutting the cheapest edge on the highest-value paths first. A thousand isolated medium findings with no path between them and any crown jewel matter less than one short, exploitable path to regulated data. Where a leg of a path is a workload vulnerability, its CVSS/EPSS/KEV scoring and its remediation SLA are decided under `vulnerability-management`; this skill decides whether that vulnerability sits on a path worth cutting at all.
