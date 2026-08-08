# Posture and workload protection

Posture management asks whether the cloud is configured securely; workload protection asks whether what runs on it is safe and behaving normally. This reference covers the misconfiguration categories CSPM checks, the agentless-versus-agent trade-off that separates posture from runtime protection, the operating workflow for each, and the maturity model that sequences a cloud security programme.

## Misconfiguration categories

CSPM checks a large but finite configuration surface. Knowing the categories is knowing where posture actually fails in practice. These are the recurring high-signal areas across providers.

### Storage
- Publicly readable object storage (buckets, blob containers).
- Bucket or object policies granting public or unconditioned cross-account access.
- Unencrypted volumes and unencrypted storage at rest.
- Missing access logging on storage.
- No object-lock or write-once protection for regulated data.

### Networking
- Security groups or network security groups allowing inbound from anywhere on management ports (SSH, RDP).
- Overly permissive rules on databases (reachable from anywhere).
- Peering connections with broad, unsegmented routing.
- Internet-exposed management interfaces.
- Missing network flow logs.

### Identity and access management
- Root or global-admin usage with active credentials and no MFA.
- Long-lived programmatic access keys that are never rotated.
- Wildcard policies granting all actions on all resources.
- Cross-account trust relationships without conditions.
- MFA not enforced.
- Static long-lived credentials where short-lived tokens are possible.

### Compute
- Instances with an unhardened metadata service (the version that allows credential theft by server-side request forgery).
- Unpatched operating systems carrying critical vulnerabilities.
- Public machine images containing sensitive data.
- Instances in public subnets with no need to be.
- Missing endpoint protection.

### Data
- Unencrypted databases.
- Database snapshots shared to public or unintended accounts.
- Missing encryption in transit.
- Sensitive data in storage without server-side encryption.
- Secrets held in environment variables instead of a secrets manager.

### Logging and monitoring
- Management-plane audit logging disabled or not capturing management events.
- Log-integrity validation disabled.
- No cloud-native threat detection service enabled.
- No alerting on root-account activity.
- No alerting on IAM policy changes.

The storage, networking, and IAM categories are where the highest-severity posture failures cluster, because they are the categories that most directly create the exposed-plus-privileged-plus-sensitive attack paths developed in `attack-paths-and-toxic-combinations.md`.

## Agentless versus agent-based

The deployment model is the defining architectural choice, and it maps cleanly onto the posture-versus-runtime split.

| Dimension | Agentless (API and snapshot) | Agent-based (in-workload) |
|---|---|---|
| How it works | reads cloud provider APIs for configuration; scans storage snapshots for workload vulnerability data | runs inside the workload, observing processes, files, and network in real time |
| Deployment friction | very low; credentials and permissions only, no software on workloads | higher; agent must be installed, updated, and maintained per workload |
| Posture coverage | strong; this is how CSPM works | not its purpose |
| Vulnerability coverage | good; snapshot scanning finds OS and library vulnerabilities | good; sees installed packages directly |
| Runtime coverage | weak; a snapshot is a point in time, blind to live behaviour | strong; behavioural detection of an active attack, drift, and process activity |
| Best for | fast, broad visibility across the estate; compliance baseline; posture | runtime detection and response on high-value or high-risk workloads |

The practical rule: use agentless for posture and broad vulnerability coverage across the whole estate, and reserve agents for the workloads where live runtime detection is worth the operational cost. Deploying agents everywhere when agentless would answer the question is a common way to stall a programme on rollout friction; deploying no agents at all leaves runtime attacks invisible. The right answer is agentless-broad plus agent-selective.

## Posture management workflow

CSPM is continuous, not a one-off scan. The operating loop:

1. **Connect and discover.** Grant the platform read access to the provider APIs and enumerate the estate (accounts, subscriptions, projects, resources). Coverage gaps here, an unmonitored account or region, are where posture blind spots live.
2. **Assess against a baseline.** Evaluate configuration against the chosen benchmark (CIS Foundations as the usual baseline, plus any regulatory framework in scope). This produces findings mapped to controls.
3. **Prioritise by attack path, not count.** Rank findings by whether they sit on an exploitable path to a crown-jewel asset, per `attack-paths-and-toxic-combinations.md`, rather than by raw count or isolated severity.
4. **Remediate, with ownership.** Route each finding to the team that owns the resource (platform, application, or cloud team), not to security alone. High-confidence, low-blast-radius findings can be auto-remediated with guardrails; the rest are ticketed with an owner and a due date.
5. **Prevent recurrence with shift-left.** Push the same checks into infrastructure-as-code scanning and CI/CD so the misconfiguration is caught in a pull request before it reaches production, rather than found again on the next scan.
6. **Re-assess continuously.** The configuration surface changes daily; posture is measured continuously and drift is caught as it happens.

## Workload protection workflow

CWPP protects the running workloads and produces two distinct kinds of signal:

- **Vulnerability findings** (OS packages, language libraries) from snapshot scanning or an agent. These are the input to the vulnerability programme: their CVSS/EPSS/KEV scoring, prioritisation order, and remediation SLAs are owned by `vulnerability-management`. This skill uses them only as legs of an attack path.
- **Runtime signals** (a shell spawned in a container, an unexpected outbound connection, a crypto-mining process, configuration drift) from an agent. These feed detection and response, the CDR pillar, and are the live counterpart to configuration-time posture.

For container workloads specifically, image scanning, admission control, and runtime detection at the orchestrator level are the depth of `container-security`; here containers are one CWPP surface among VMs and serverless.

## Cloud security programme maturity model

A programme matures by adding pillars in an order that builds on visibility already established. Trying to buy the top of the model before the base is why platforms sit unused.

**Level 1, visibility.** CSPM deployed with baseline benchmark scanning. Management-plane audit logging enabled across accounts. Centralised logging. Alerting on the most critical misconfigurations. The goal is simply to see the posture.

**Level 2, risk reduction.** CSPM findings triaged and being remediated with ownership. Workload vulnerability scanning in place. CIEM analysis surfacing the most over-privileged identities. Auto-remediation for high-confidence findings. CI/CD security scanning (infrastructure-as-code and image scanning) catching issues pre-deployment.

**Level 3, proactive defence.** Full CNAPP with attack-path analysis correlating the pillars. CWPP with runtime protection on high-value workloads. CDR with behavioural threat detection. DSPM covering regulated data stores. Developer security training and genuine shift-left adoption.

**Level 4, optimised.** Risk-based prioritisation that fixes only what sits on a real attack path. Automated remediation with guardrails. Continuous compliance measurement rather than periodic audit. Threat-intelligence integration. A cloud red-team or penetration-testing programme validating that the paths the platform reports are the paths that matter.

The maturity axis and the pillar-deployment order are the same axis: posture first for visibility, then workload protection for the running estate, then entitlements as IAM complexity grows, then data posture when regulated data is in play, then full correlation for attack-path-driven prioritisation. Where a programme leads with one provider, the per-provider hardening operations live in `aws-cloud-ops`, `azure-cloud-ops`, and `gcp-cloud-ops`; the cross-provider posture target is what this skill sets.
