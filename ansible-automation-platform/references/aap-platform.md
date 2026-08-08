# Ansible Automation Platform (AAP)

## Platform architecture (AAP 2.5+)

```
+---------------------------------------------------------------+
|                      Platform Gateway                         |
|          Unified UI / SSO / Centralised Authentication        |
+------------------+------------------+------------------------+
|  Automation      |  Private         |  EDA Controller        |
|  Controller      |  Automation Hub  |  (Event-Driven Ansible)|
|  (formerly Tower)|                  |                        |
+------------------+------------------+------------------------+
|                   Automation Mesh (Receptor)                  |
|          Control Nodes <-> Hop Nodes <-> Execution Nodes      |
+---------------------------------------------------------------+
|                       PostgreSQL Database                     |
+---------------------------------------------------------------+
```

| Component | Purpose |
|---|---|
| **Platform Gateway** | Unified entry point: consolidates Controller, Hub, and EDA UIs; handles SSO (SAML, LDAP, OIDC) and centralised user management |
| **Automation Controller** | Job execution, scheduling, RBAC, workflows, REST API. Formerly Ansible Tower |
| **Private Automation Hub** | On-premises repository for collections, Execution Environments, and container images (built-in Pulp registry) |
| **EDA Controller** | Event-driven automation: rulebook activations, event sources, integration with Controller job templates |
| **Automation Mesh (Receptor)** | Peer-to-peer overlay network connecting control, hop, and execution nodes; replaces legacy isolated nodes |
| **PostgreSQL** | Stores job history, credentials, inventories, RBAC data, activity stream |

### Controller vs AWX

| Feature | AWX (open source) | Automation Controller (AAP) |
|---|---|---|
| Licence | Apache 2.0 | Red Hat subscription |
| Support | Community only | Red Hat SLA, 24/7 support |
| Authentication | Basic SSO | SAML, OIDC, LDAP, RADIUS, MFA |
| Certification | None | FIPS 140-2, SOC 2, FedRAMP |
| Automation Hub | None | Private Automation Hub included |
| EDA | Separate install | Integrated EDA Controller |
| Content | Community collections | Certified + Validated content |
| Scalability | Limited clustering | Full mesh networking, container groups |

AWX is suitable for dev / lab environments. Automation Controller is required for production, compliance, and enterprise-scale automation.

### Installation topologies (AAP 2.5)

AAP 2.5 introduced **containerised installation** using Podman, deprecating the RPM-based installer.

| Topology | Description |
|---|---|
| **Growth** | Single server: Controller + Hub + EDA + PostgreSQL on one host |
| **Enterprise** | Multi-server: separate hosts for Controller, Hub, EDA, DB; supports HA |
| **Operator (OpenShift)** | Kubernetes-native: operator-managed on Red Hat OpenShift |

---

## Automation Mesh (Receptor)

### Node types

| Node type | Runs jobs? | Runs services? | Purpose |
|---|---|---|---|
| **Control** | No | Yes | Runs Controller services only (web, dispatcher) |
| **Hybrid** | Yes | Yes | Default; runs Controller services AND executes jobs |
| **Execution** | Yes | No | Runs playbooks only; no Controller services |
| **Hop** | No | No | Relays traffic between nodes; does not run jobs or services |

All mesh communication uses port 27199/TCP (TLS-encrypted). This is the only port required between mesh nodes.

### Mesh diagnostics

```bash
# Check receptor service status
sudo systemctl status receptor

# View mesh status
receptorctl --socket /var/run/receptor/receptor.sock status

# View instances and capacity (run on Controller)
awx-manage list_instances

# Ping a specific node through the mesh
receptorctl --socket /var/run/receptor/receptor.sock ping exec1.dc2.example.com

# Check receptor logs
journalctl -u receptor -f
```

Common receptor errors:
- `certificate verify failed`: TLS cert mismatch or expired; check mutual TLS certificate chain.
- `connection refused`: receptor not running or firewall blocking 27199.
- `no route to node`: mesh topology broken or hop node down.

---

## Execution Environments (EEs)

Execution Environments are container images that package ansible-core, Python dependencies, and collections into a portable, reproducible runtime. They replace Python virtualenvs (deprecated in AAP 2.x).

### Default EEs

| Image | Contents |
|---|---|
| `ee-minimal-rhel9` | ansible-core + ansible.builtin only |
| `ee-supported-rhel9` | ansible-core + Red Hat certified collections |
| `ee-29-rhel9` | ansible-core 2.16 + supported collections (AAP 2.5) |

### Building custom EEs

```yaml
# execution-environment.yml (v3 schema)
---
version: 3

images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9:latest

dependencies:
  galaxy:
    collections:
      - name: amazon.aws
        version: ">=7.0.0"
      - name: community.general
      - name: ansible.windows
  python:
    - boto3>=1.28.0
    - botocore>=1.31.0
    - pywinrm>=0.4.3
    - jmespath
  system:
    - openssh-clients [platform:redhat]
    - sshpass [platform:redhat]

additional_build_steps:
  append_final:
    - RUN ansible-galaxy collection list
```

```bash
# Build the EE image
ansible-builder build \
  --tag my-custom-ee:1.0 \
  --container-runtime podman \
  --file execution-environment.yml \
  --verbosity 3

# Verify
podman run --rm my-custom-ee:1.0 ansible --version
podman run --rm my-custom-ee:1.0 ansible-galaxy collection list

# Push to Private Automation Hub
podman login hub.example.com
podman tag my-custom-ee:1.0 hub.example.com/my-custom-ee:1.0
podman push hub.example.com/my-custom-ee:1.0

# Run a playbook with a specific EE locally
ansible-navigator run site.yml --eei my-custom-ee:1.0 --mode stdout
```

### EE build troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Could not find a version that satisfies the requirement` | Python package unavailable for platform | Check availability on RHEL 9; consider a different base image |
| `Collection 'x.y' not found` | Galaxy server unreachable or collection not published | Verify `ansible.cfg` Galaxy server URL |
| `COPY failed: file not found` | Missing dependency files | Ensure `requirements.txt`, `requirements.yml`, `bindep.txt` exist |
| Image too large | Too many collections or system packages | Only include collections the EE actually needs |

---

## Organisations, teams, users, and RBAC

```
Organisation (top-level tenant)
  |- Teams (groups of users)
  |     |- User A (admin role on this object)
  |     |- User B (execute role)
  |     |- User C (read role)
  |- Projects
  |- Inventories
  |- Credentials
  |- Job Templates
  |- Workflow Templates
```

### Built-in roles

| Role | Scope | Permissions |
|---|---|---|
| **System Administrator** | Global | Full access |
| **System Auditor** | Global | Read-only access to everything |
| **Admin** | Per-object | Full control of the specific object |
| **Execute** | Job / Workflow Template | Launch jobs, view results |
| **Use** | Credential / Inventory / Project | Attach to job templates (cannot view secrets) |
| **Update** | Project / Inventory | Trigger SCM sync or inventory refresh |
| **Read** | Per-object | View configuration and results |

### Authentication sources

Configure via **Platform Gateway > Settings > Authentication** (AAP 2.5+):

| Method | Notes |
|---|---|
| LDAP | `AUTH_LDAP_SERVER_URI`, `AUTH_LDAP_BIND_DN`, user search config |
| SAML | IdP metadata URL, SP Entity ID, certificate / key pairs |
| OIDC | Client ID, Client Secret, provider URL |
| RADIUS | Server, port, shared secret |
| Local | Built-in database (default) |

---

## Projects

A project is a collection of playbooks sourced from version control.

| Setting | Description |
|---|---|
| **SCM Type** | Git (most common), Subversion, Red Hat Insights, Archive |
| **SCM URL** | Repository URL (`https://` or `git@`) |
| **SCM Branch / Tag / Commit** | Pin to a specific branch, tag, or commit hash |
| **SCM Credential** | SSH key or token for private repos |
| **Update on Launch** | Pull latest before each job run (adds latency) |
| **Cache Timeout** | Seconds to cache project between syncs (0 = always update) |

```bash
# Trigger project sync via API
curl -k -X POST \
  -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/projects/7/update/

# Check project sync status
curl -k -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/projects/7/
```

Via the AAP MCP server (if configured): use tools `list_projects`, `get_project`, `update_project`, `get_project_update`, `get_project_update_logs`.

---

## Inventories

### Inventory types

| Type | Description |
|---|---|
| **Static** | Manually defined hosts and groups in the Controller UI or via API |
| **Dynamic (Source-based)** | Syncs from AWS, Azure, GCP, VMware, Satellite, and others |
| **Constructed** | Combines multiple input inventories with custom Jinja2 grouping logic |
| **Smart** (deprecated) | Migrate to constructed inventories |

### Dynamic inventory sources

| Source | Collection plugin | Credential type |
|---|---|---|
| AWS EC2 | `amazon.aws.aws_ec2` | Amazon Web Services |
| Azure RM | `azure.azcollection.azure_rm` | Microsoft Azure RM |
| GCP | `google.cloud.gcp_compute` | Google Compute Engine |
| VMware vCenter | `community.vmware.vmware_vm_inventory` | VMware vCenter |
| Red Hat Satellite | `theforeman.foreman.foreman` | Red Hat Satellite 6 |

### Inventory management via the AAP MCP server

Available tools (when the AAP MCP server is configured, using `AAP_URL` and `AAP_TOKEN`):

| Tool | Purpose |
|---|---|
| `list_inventories` | Retrieve all inventories |
| `get_inventory` | Fetch details for a specific inventory by ID |
| `create_inventory` | Create a new inventory |
| `delete_inventory` | Remove an inventory |
| `list_hosts` | List all hosts in an inventory |
| `get_host_details` | Get details for a host |
| `get_host_facts` | Get gathered facts for a host |
| `add_host_to_inventory` | Add a host with optional variables |
| `update_host` | Modify host properties |
| `delete_host` | Remove a host |
| `get_failed_hosts` | List hosts with active failures |
| `list_groups` | Show all groups in an inventory |
| `create_group` | Create a group |
| `add_host_to_group` | Associate a host with a group |
| `remove_host_from_group` | Remove a host from a group |
| `list_inventory_sources` | Show dynamic inventory sources |
| `sync_inventory_source` | Trigger a manual sync |

Workflow: `list_inventories` -> `list_hosts` -> `get_failed_hosts` -> `get_host_facts` to audit inventory coverage.

---

## Credentials

### Built-in credential types

| Type | Used for | Key fields |
|---|---|---|
| **Machine** | SSH / WinRM to managed hosts | Username, password, SSH key, become password |
| **SCM** | Git / SVN repository access | Username, password / token, SSH key |
| **Vault** | Ansible Vault decryption | Vault password, Vault ID |
| **Amazon Web Services** | AWS API calls | Access key, Secret key, STS token |
| **Microsoft Azure RM** | Azure API calls | Subscription ID, Client ID, Secret, Tenant |
| **Google Compute Engine** | GCP API calls | Service account JSON key |
| **Network** | Network device CLI / API | Username, password, authorise password |
| **Container Registry** | Pull EE images | Registry URL, username, password |

### External credential lookups

External credential plugins retrieve secrets at runtime from external vaults (configured per credential field in the Controller UI):

| External system | Notes |
|---|---|
| HashiCorp Vault | Server URL, Role ID, Secret ID, KV path and version |
| AWS Secrets Manager | Region, Secret Name |
| Azure Key Vault | Vault URL, client credentials, Secret Name / Version |
| CyberArk CCP | AppID, Safe, Object |
| CyberArk Conjur | Account, Variable path |

---

## Job templates

### Key settings

| Setting | Description |
|---|---|
| **Job Type** | Run (execute) or Check (dry run / `--check`) |
| **Inventory** | Target hosts; can be overridden with Prompt on Launch |
| **Project** | Source of playbooks |
| **Playbook** | Specific playbook file from the project |
| **Execution Environment** | Container image for the runtime |
| **Credentials** | One or more credentials (machine, cloud, vault, etc.) |
| **Limit** | Restrict to specific hosts / groups (host pattern) |
| **Job Tags / Skip Tags** | Run or skip tagged tasks |
| **Verbosity** | 0 (Normal) through 5 (WinRM Debug) |
| **Extra Variables** | YAML / JSON vars passed as `--extra-vars` |
| **Job Slicing** | Split inventory into N slices; each slice runs in parallel |
| **Survey** | User-facing form for runtime variables with validation |

### Running jobs via the AAP MCP server

```
list_job_templates  -> find the template
run_job             -> launch with optional extra_vars / limit
job_status          -> poll until finished
job_logs            -> retrieve execution output
```

### Launching jobs via the REST API

```bash
# Launch a job template
curl -k -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "limit": "webservers",
    "extra_vars": {"app_version": "2.1.0", "target_env": "production"}
  }' \
  https://controller.example.com/api/v2/job_templates/14/launch/

# Poll job status
curl -k -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/jobs/4832/

# Get job stdout
curl -k -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/jobs/4832/stdout/?format=txt
```

### Surveys

Surveys present a runtime input form to the user launching the job; Controller validates the inputs before running:

```json
{
  "spec": [
    {
      "question_name": "Target Environment",
      "variable": "target_env",
      "type": "multiplechoice",
      "choices": ["dev", "staging", "production"],
      "required": true,
      "default": "dev"
    },
    {
      "question_name": "Application Version",
      "variable": "app_version",
      "type": "text",
      "required": true,
      "min": 5,
      "max": 20
    }
  ]
}
```

---

## Workflow job templates

Workflows chain job templates, project syncs, inventory syncs, and approval gates into a directed graph.

### Edge types

- **On Success** (green): next node runs if this one succeeds.
- **On Failure** (red): next node runs if this one fails.
- **Always** (blue): next node runs regardless.

### Convergence modes

- **Any** (default): node runs when ANY parent completes with the expected status.
- **All**: node runs only when ALL parents complete with the expected status.

### Approval nodes

Approval nodes pause the workflow and wait for a human to approve or deny before continuing. They support an optional timeout.

```bash
# Approve a pending approval node via API
curl -k -X POST \
  -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/workflow_approvals/42/approve/

# Deny
curl -k -X POST \
  -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/workflow_approvals/42/deny/
```

Gate production job executions behind approval nodes or per change-control policy.

---

## Schedules

Schedules attach to job templates, workflow templates, project syncs, and inventory syncs. AAP uses RFC 5545 RRULE format.

```bash
# Create a schedule via API
curl -k -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Nightly Patching",
    "unified_job_template": 14,
    "rrule": "DTSTART:20240101T060000Z RRULE:FREQ=DAILY;INTERVAL=1",
    "enabled": true
  }' \
  https://controller.example.com/api/v2/schedules/
```

DTSTART uses UTC. Adjust for your timezone; the UI converts automatically.

---

## Private Automation Hub

| Content type | Description |
|---|---|
| **Certified Collections** | Red Hat and partner-certified; synced from `console.redhat.com` |
| **Validated Collections** | Community-tested; synced from `console.redhat.com` |
| **Custom Collections** | Internally developed; published by your team |
| **Execution Environments** | Container images served from the built-in Pulp registry |

```bash
# Configure ansible.cfg to prefer Private Automation Hub
[galaxy]
server_list = automation_hub, galaxy

[galaxy_server.automation_hub]
url=https://hub.example.com/api/galaxy/content/published/
token=<your-hub-token>

# Build and publish a custom collection
ansible-galaxy collection build
ansible-galaxy collection publish \
  my_namespace-my_collection-1.0.0.tar.gz \
  --server https://hub.example.com/api/galaxy/content/inbound-custom/ \
  --token $HUB_TOKEN
```

---

## Event-Driven Ansible (EDA)

### Architecture

```
Event Source -> EDA Controller -> Decision Engine (Drools) -> Action
(Webhook,       (Rulebook          (Evaluates conditions)    (Run Job Template,
 Kafka,          Activation)                                  Run Playbook,
 Alertmanager)                                               Debug, Set Fact)
```

### Rulebook structure

```yaml
---
- name: Respond to webhook events
  hosts: all
  sources:
    - ansible.eda.webhook:
        host: 0.0.0.0
        port: 5000

  rules:
    - name: Restart service on critical alert
      condition: event.payload.status == "critical"
      action:
        run_job_template:
          name: "Restart Application"
          organization: "Default"
          job_args:
            extra_vars:
              target_host: "{{ event.payload.host }}"

    - name: Log informational events
      condition: event.payload.status == "info"
      action:
        debug:
          msg: "Informational event: {{ event.payload.message }}"
```

### Event source plugins

| Plugin | Source | Use case |
|---|---|---|
| `ansible.eda.webhook` | HTTP POST | GitHub, ServiceNow, custom apps |
| `ansible.eda.kafka` | Apache Kafka topics | Streaming event platforms |
| `ansible.eda.alertmanager` | Prometheus Alertmanager | Infrastructure monitoring alerts |
| `ansible.eda.url_check` | HTTP endpoint polling | Health check monitoring |
| `ansible.eda.file_watch` | Local file changes | Config drift detection |
| `ansible.eda.aws_sqs_queue` | AWS SQS | Cloud event processing |

### Decision Environments (DEs)

Decision Environments are container images for EDA rulebook activations (analogous to EEs for playbooks).

```yaml
# decision-environment.yml
---
version: 3
images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-25/de-supported-rhel9:latest
dependencies:
  galaxy:
    collections:
      - ansible.eda
  python:
    - aiokafka
    - aiohttp
```

### EDA operations via the AAP MCP server

Available tools (when the AAP MCP server is configured with `EDA_URL` and `EDA_TOKEN`):

| Tool | Purpose |
|---|---|
| `list_activations` | List all rulebook activations and their state |
| `get_activation` | Details for a specific activation |
| `create_activation` | Create a new activation |
| `enable_activation` | Enable a disabled activation |
| `disable_activation` | Disable an active activation |
| `restart_activation` | Restart an activation |
| `delete_activation` | Delete an activation |
| `list_rulebooks` | List available rulebooks |
| `get_rulebook` | Details for a rulebook |
| `list_decision_environments` | List decision environment images |
| `create_decision_environment` | Register a new decision environment |
| `list_event_streams` | List event stream sources |

Activations process events in real-time; enabling or disabling affects live automation. Gate activation changes in production per change-control policy.

---

## ansible-lint in CI

ansible-lint validates playbooks and roles before they reach the Controller.

Via the AAP MCP server (if configured with `ansible-lint` installed locally):

| Tool | Purpose |
|---|---|
| `lint_playbook` | Lint playbook content with configurable profiles |
| `lint_file` | Lint a specific Ansible file |
| `lint_role` | Lint an entire role directory |
| `list_rules` | Show available lint rules with optional tag filtering |
| `validate_syntax` | Quick syntax-only validation |
| `check_best_practices` | Evaluate against best practices with severity |
| `analyze_project` | Comprehensive report on an entire Ansible project |
| `get_ansible_lint_version` | Return installed ansible-lint version |

Profiles (in increasing strictness): `min`, `basic`, `moderate`, `safety`, `shared`, `production`. Use `production` for production deployments; `basic` during development.

Lint gates before AAP job execution:
1. `validate_syntax` to catch YAML / syntax errors.
2. `check_best_practices` to catch idiomatic issues.
3. `lint_playbook --profile production` for a comprehensive check.
4. Only launch the job template if lint passes.

---

## REST API

### Authentication

```bash
# Create a Personal Access Token (PAT)
curl -k -X POST \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{"description": "CI/CD Token", "scope": "write"}' \
  https://controller.example.com/api/v2/tokens/

export TOKEN="your-token-value"
```

### Common API endpoints

| Endpoint | Description |
|---|---|
| `/api/v2/ping/` | Health check (no auth required) |
| `/api/v2/me/` | Current user info |
| `/api/v2/job_templates/` | List / create job templates |
| `/api/v2/job_templates/{id}/launch/` | Launch a job |
| `/api/v2/workflow_job_templates/{id}/launch/` | Launch a workflow |
| `/api/v2/jobs/{id}/` | Job details |
| `/api/v2/jobs/{id}/stdout/` | Job output |
| `/api/v2/inventories/` | List / create inventories |
| `/api/v2/projects/{id}/update/` | Trigger project sync |
| `/api/v2/schedules/` | List / create schedules |
| `/api/v2/activity_stream/` | Audit trail |
| `/api/v2/workflow_approvals/{id}/approve/` | Approve a workflow approval |
| `/api/v2/config/` | Controller configuration and licence info |

### awx CLI

```bash
# Install
pip install awxkit

# Configure
export CONTROLLER_HOST=https://controller.example.com
export CONTROLLER_OAUTH_TOKEN=your-token

# Common operations
awx job_templates list --all
awx job_templates launch 14 --extra_vars '{"env": "prod"}'
awx jobs get 4832
awx jobs stdout 4832
awx projects update 7
awx inventories list --all

# Export / import configuration as code
awx export --all > aap-config.json
awx import < aap-config.json
```

---

## Performance tuning

| Setting | Effect | Guidance |
|---|---|---|
| **Forks** | Parallel host connections per job | Match to EE / node resources; 50-100 for beefy nodes |
| **Job Slicing** | Split inventory across N parallel job runs | Use for large inventories (500+ hosts); each slice runs on a separate node |
| **Verbosity** | Log level (0-5) | Keep at 0 or 1 in production; higher levels generate large stdout |
| **Fact Caching** | Store gathered facts for reuse | Enable for environments with frequent runs against the same hosts |

### Controller maintenance

```bash
# Clean up old job data (keep last 90 days)
awx-manage cleanup_jobs --days 90

# View all instances and capacity
awx-manage list_instances

# Gather analytics
awx-manage gather_analytics

# Check database integrity
awx-manage check_db
```

---

## Backup and restore

```bash
# AAP 2.5 containerised backup
cd /path/to/ansible-automation-platform-containerized-setup-bundle-2.5-*/
sudo ./setup.sh -b

# Restore
sudo ./setup.sh -r
```

Version match required: the target AAP version must match the backup version exactly. Test restores regularly in a non-production environment.

For OpenShift operator deployments, use the `AutomationControllerBackup` and `AutomationControllerRestore` CRDs.

---

## Logging and auditing

The activity stream records every change: user actions, object changes, job launches, credential modifications.

```bash
# Query activity stream via API
curl -k -H "Authorization: Bearer $TOKEN" \
  "https://controller.example.com/api/v2/activity_stream/?order_by=-timestamp&page_size=50"
```

External logging integration (Splunk, Logstash, Loggly) is configured at **Automation Controller > Settings > Logging** or via `/api/v2/settings/logging/`. Log categories: `job_events` (task results), `activity_stream` (CRUD), `system_tracking` (fact data), `awx.analytics.job_lifecycle` (state transitions).

---

## Job failures: common causes

| Error | Cause | Resolution |
|---|---|---|
| `couldn't resolve module/action 'x.y.z'` | Collection missing from EE | Build custom EE with the required collection |
| `denied: requested access to the resource is denied` | EE in Private Hub requires auth | Attach Container Registry credential to the EE in Controller |
| Job stuck in **Pending** | No capacity or receptor offline | Check `awx-manage list_instances` for node health |
| `Timeout waiting for privilege escalation prompt` | `become` password wrong or sudoers misconfigured | Verify machine credential; check `!requiretty` in sudoers |
| `the playbook: site.yml could not be found` | Project sync failed or wrong playbook path | Verify project sync succeeded; check filename exactly |
| `No hosts matched` | Limit pattern or inventory filter returns no hosts | Check inventory and host pattern; ensure dynamic source synced |

Job log retrieval workflow (via the AAP MCP server): `list_jobs` or `list_recent_jobs` -> `job_status` to confirm state -> `job_logs` to read execution output.
