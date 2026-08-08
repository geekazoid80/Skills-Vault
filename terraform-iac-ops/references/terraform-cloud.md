# HCP Terraform and Terraform Cloud

HCP Terraform (formerly Terraform Cloud, rebranded in 2023) is HashiCorp's managed SaaS platform for collaborative Terraform workflows. It provides remote state management, remote execution, policy enforcement, and team collaboration. Terraform Enterprise is the self-hosted equivalent for organisations that require air-gapped or private-network deployments.

## HCP Terraform vs Terraform Enterprise

| Aspect | HCP Terraform (Cloud) | Terraform Enterprise |
|---|---|---|
| Deployment | SaaS, hosted by HashiCorp | Self-hosted, your infrastructure |
| Maintenance | HashiCorp manages upgrades and scaling | Customer manages installation and upgrades |
| Network | Public internet (agents for private access) | Runs inside your network natively |
| Pricing | Per resource under management (RUM) | Annual licence |
| Air-gapped | No | Yes |
| Audit logging | Standard tier and above | Full audit logging |
| Custom concurrency | Tier-dependent | Configurable |

Both share: remote execution, VCS integration, Sentinel/OPA policies, private registry, teams, and SSO. Terraform Enterprise adds air-gapped support, custom concurrency, and full private-network operation.

## Architecture and hierarchy

```
Organisation
  +-- Projects                       # logical grouping
  |     +-- Workspaces               # each = 1 state file + config + variables
  |     |     +-- Runs               # plan/apply executions
  |     |     +-- Variables          # Terraform and environment variables
  |     |     +-- State Versions     # historical state snapshots
  |     |     +-- Run Triggers       # cross-workspace dependencies
  |     +-- Stacks                   # multi-workspace orchestration (1.15+)
  +-- Teams                          # groups of users with permissions
  +-- Policies (Sentinel / OPA)      # governance rules
  +-- Policy Sets                    # collections of policies applied to workspaces
  +-- Variable Sets                  # shared variables across workspaces and projects
  +-- Agent Pools                    # self-hosted execution agents
  +-- Private Registry               # internal modules and providers
```

## Workspaces

A workspace in HCP Terraform is fundamentally different from a CLI workspace. Each workspace encapsulates:

- One Terraform configuration (root module).
- One state file with full version history.
- Its own variables (Terraform and environment).
- Run history, logs, and plan outputs.
- Access controls, VCS connection, and execution settings.

### Workspace types (workflow modes)

| Type | Source of config | Trigger | Best for |
|---|---|---|---|
| VCS-connected | Linked repository and branch | Webhook on push or PR | GitOps teams, automated pipelines |
| CLI-driven | `terraform plan/apply` from local CLI | Manual CLI commands | Developers testing, CI/CD orchestrators |
| API-driven | Config uploaded via API | API call | Custom pipelines, complex automation |

VCS-connected is the most common. HCP Terraform registers webhooks automatically, triggers plans on push, and posts speculative plan results on pull requests.

CLI-driven uses the `cloud` block. Runs execute remotely in HCP Terraform but are initiated from the CLI; logs stream to the local terminal.

API-driven uploads a tarball of config via the API, then triggers a run. Requires more tooling but gives full control.

### Execution modes

| Mode | Where runs execute | State storage | Use case |
|---|---|---|---|
| Remote | HCP Terraform workers | HCP Terraform | Default; no local dependencies needed |
| Local | Your machine | HCP Terraform | Debugging, local provider access |
| Agent | Self-hosted agent behind firewall | HCP Terraform | Private network resources |

Configure via: Workspace > Settings > General > Execution Mode.

### Cloud block configuration (1.1+)

The `cloud` block replaces the legacy `remote` backend:

```hcl
terraform {
  cloud {
    organisation = "my-org"

    workspaces {
      name = "my-app-prod"
    }
  }
}
```

Tag-based workspace selection for multi-environment setups:

```hcl
terraform {
  cloud {
    organisation = "my-org"

    workspaces {
      tags = ["app:payments", "region:us-east-1"]
    }
  }
}
```

### CLI authentication

```bash
# Interactive login: opens browser, stores token in ~/.terraform.d/credentials.tfrc.json
terraform login

# Login to Terraform Enterprise
terraform login tfe.mycompany.com
```

Token can also be set via environment variable:

```bash
export TF_TOKEN_app_terraform_io="<your-token>"
# For TFE: export TF_TOKEN_tfe_mycompany_com="<your-token>"
```

### Workspace settings reference

| Setting | Description | UI path |
|---|---|---|
| Auto-apply | Skip manual approval after plan | Settings > General > Apply Method |
| Working directory | Subdirectory containing `.tf` files | Settings > General > Terraform Working Directory |
| Terraform version | Pin to a specific version | Settings > General > Terraform Version |
| Execution mode | Remote, local, or agent | Settings > General > Execution Mode |
| Auto-destroy | Schedule infrastructure destruction | Settings > Destruction and Deletion |
| Remote state sharing | Which workspaces can read state | Settings > General > Remote State Sharing |

## Variables and variable sets

### Variable types

| Type | Purpose | Example |
|---|---|---|
| Terraform variable | Maps to `variable` blocks in config | `instance_type = "t3.micro"` |
| Environment variable | Set in shell before `terraform` runs | `AWS_REGION = "us-east-1"` |

Both types can be marked **sensitive** (write-only, encrypted at rest; never displayed in UI or logs).

### Variable precedence (highest to lowest)

1. Workspace-specific variables.
2. Workspace-scoped variable sets (alphabetical by set name breaks ties).
3. Project-scoped variable sets.
4. Organisation-scoped variable sets.

### Variable sets

Variable sets are reusable groups of variables applied across multiple workspaces or projects. Common uses: shared cloud credentials, environment-specific defaults (region, tags), and organisation-wide standards.

Configure via: Organisation Settings > Variable Sets > Create Variable Set. Choose scope: all workspaces, specific projects, or specific workspaces.

## State management in HCP Terraform

HCP Terraform manages state automatically: encryption at rest (Vault transit backend), automatic locking during runs, and full version history. No S3 buckets, DynamoDB tables, or GCS backends to configure.

### State rollback

Navigate to Workspace > States, select a version, click the Advanced toggle, then "Roll back to this state version". The workspace must not be locked.

### Cross-workspace data access

Preferred: `tfe_outputs` data source (exposes only outputs; more secure):

```hcl
data "tfe_outputs" "network" {
  organisation = "my-org"
  workspace    = "network-prod"
}

resource "aws_instance" "web" {
  subnet_id = data.tfe_outputs.network.values.subnet_id
}
```

Alternative: `terraform_remote_state` (exposes entire state; tighter coupling). Use `tfe_outputs` whenever possible.

## Run lifecycle

```
Queue -> Plan -> Cost Estimation -> Policy Check -> Apply
  |        |           |               |              |
  |        |           |               |              +-- state updated
  |        |           |               +-- Sentinel / OPA evaluation
  |        |           +-- monthly cost delta shown
  |        +-- terraform plan executes
  +-- one run at a time per workspace
```

### Run types

| Type | Purpose | Trigger |
|---|---|---|
| Plan and apply | Full run: plan then apply | VCS push, CLI, API, UI |
| Plan only | Plan without apply option | UI (plan only), speculative |
| Speculative plan | Read-only plan on PR/MR; no apply | Pull request webhook |
| Destroy plan | Plan to destroy all resources | UI queue destroy, API |
| Refresh-only | Update state without config changes | UI, CLI (`-refresh-only`) |

### Run triggers (cross-workspace dependencies)

When workspace A's apply succeeds, automatically queue a plan in workspace B.

Configure via: Workspace B > Settings > Run Triggers > Add Source Workspace.

Example cascade:

```
network-prod (apply succeeds)
    +--triggers--> compute-prod (plan queued)
                       +--triggers--> app-prod (plan queued)
```

Each workspace can have up to 20 source workspaces.

## Workspace operations via the Terraform MCP server

When a Terraform MCP server is configured, workspace operations can be invoked programmatically:

| Operation | Tool name | Key parameters |
|---|---|---|
| List workspaces | `list_workspaces` | `organisation` |
| Get workspace details and variables | `get_workspace` | `organisation`, `workspace_name` |
| Create workspace | `create_workspace` | `organisation`, `name`, `execution_mode`, `terraform_version` |
| Update workspace configuration | `update_workspace` | `workspace_id`, fields to change |
| Delete workspace | `delete_workspace` | `workspace_id` |
| Trigger a run | `trigger_run` | `workspace_id`, `message` |
| Get run status | `get_run_status` | `run_id` |
| List runs | `list_runs` | `workspace_id` |
| Cancel a run | `cancel_run` | `run_id` |

These operations are available via the Terraform MCP server with the Workspaces toolset enabled.

## Registry search via the Terraform MCP server

| Operation | Tool name | Key parameters |
|---|---|---|
| Search providers | `search_providers` | `query` |
| Get provider details | `get_provider_details` | `namespace`, `provider_name` |
| List provider versions | `list_provider_versions` | `namespace`, `provider_name` |
| Search modules | `search_modules` | `query` |
| Get module details | `get_module_details` | `namespace`, `module_name`, `provider` |
| List module versions | `list_module_versions` | `namespace`, `module_name`, `provider` |

Public Registry requires no authentication. Private modules require a `TFE_TOKEN`.

## VCS integration

### Supported providers

| Provider | Webhooks | PR speculative plans |
|---|---|---|
| GitHub (github.com and GitHub Enterprise) | Push, PR | Yes |
| GitLab (gitlab.com and self-managed) | Push, MR | Yes |
| Azure DevOps (Services and Server) | Push, PR | Yes |
| Bitbucket (Cloud and Server) | Push, PR | Yes |

### How VCS triggers work

1. Connect VCS provider to HCP Terraform (Organisation Settings > VCS Providers).
2. Create workspace linked to repo and branch.
3. HCP Terraform registers a webhook on the repository.
4. On push to tracked branch: full run queued (plan and apply).
5. On PR/MR targeting tracked branch: speculative plan; results posted as commit status.

### Branch-based workspace pattern

| Workspace | Branch | Auto-apply |
|---|---|---|
| `app-dev` | `develop` | Yes |
| `app-staging` | `staging` | Yes |
| `app-prod` | `main` | No (manual approval) |

## Policy as code

### Sentinel

Sentinel is HashiCorp's policy-as-code framework, native to HCP Terraform and Terraform Enterprise. Policies evaluate between plan and apply.

Enforcement levels:

| Level | Behaviour |
|---|---|
| Advisory | Logged but never blocks a run |
| Soft mandatory | Blocks the run; users with override permission can bypass |
| Hard mandatory | Blocks the run; no override possible |

Example: require tags on all AWS instances:

```python
import "tfplan/v2" as tfplan

aws_instances = filter tfplan.resource_changes as _, rc {
  rc.type is "aws_instance" and
  rc.mode is "managed" and
  (rc.change.actions contains "create" or rc.change.actions contains "update")
}

main = rule {
  all aws_instances as _, instance {
    instance.change.after.tags contains "Environment" and
    instance.change.after.tags contains "Owner"
  }
}
```

Policy sets group policies and assign them to workspaces. Store policies in a VCS repo for version control.

### OPA (Open Policy Agent)

HCP Terraform also supports OPA/Rego policies as an alternative to Sentinel. OPA policies evaluate the JSON plan output. Sentinel and OPA can run side by side.

### Run tasks

Run tasks integrate third-party tools at specific stages of the run lifecycle:

| Stage | When | Example use |
|---|---|---|
| Pre-plan | Before plan starts | Validate config files, check naming conventions |
| Post-plan | After plan, before policy check | Security scanning (Snyk, Wiz), cost analysis (Infracost) |
| Pre-apply | After approval, before apply | Final compliance gate, change-control ticket per change-control policy |
| Post-apply | After apply completes | Notify systems, update CMDB |

Configure via: Organisation Settings > Run Tasks > Create Run Task, then attach to workspaces via Settings > Run Tasks.

## Self-hosted agents

Agents enable HCP Terraform to provision resources in private networks without exposing those networks to the internet.

```
HCP Terraform <-- HTTPS (outbound only) --> Agent (your network)
                                                |
                                          Private APIs
                                          (vSphere, on-prem DB, etc.)
```

The agent polls HCP Terraform for jobs; all connections are outbound from the agent. No inbound firewall rules are needed.

### Agent setup

```bash
# Docker
docker run -e TFC_AGENT_TOKEN=<token> \
           -e TFC_AGENT_NAME=agent-1 \
           hashicorp/tfc-agent:latest

# Binary
./tfc-agent -token=<token> -name=agent-1
```

Create the agent token in: Organisation Settings > Agents > Create Agent Pool > Generate Token.

Assign the pool to a workspace via: Workspace > Settings > General > Execution Mode > Agent > select pool.

### Agent status

| Status | Meaning | Action |
|---|---|---|
| Idle | Connected, waiting for jobs | Normal |
| Busy | Executing a run | Normal |
| Unknown | Lost communication | Check network and agent process |
| Errored | Unknown for 2+ hours, auto-transitioned | Restart agent, check logs |
| Exited | Agent shut down cleanly | Restart if needed |

Unknown agents count against the organisation's agent allowance. Restart or remove them.

## Dynamic provider credentials (OIDC)

Eliminates static cloud credentials by using OIDC-based workload identity. HCP Terraform issues a short-lived JWT per run, which is exchanged for temporary cloud credentials.

How it works:
1. Configure trust between the cloud provider and HCP Terraform (OIDC identity provider).
2. Set workspace environment variables to enable dynamic credentials.
3. Each run receives a unique JWT signed by HCP Terraform.
4. The cloud provider validates the JWT and returns short-lived credentials.

AWS configuration (set these workspace environment variables):

| Variable | Value |
|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true` |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::ACCOUNT:role/tfc-role` |

Azure: set `TFC_AZURE_PROVIDER_AUTH = true`, `TFC_AZURE_RUN_CLIENT_ID`, `TFC_AZURE_RUN_TENANT_ID`.

GCP: set `TFC_GCP_PROVIDER_AUTH = true`, `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_PROJECT_NUMBER`, `TFC_GCP_WORKLOAD_PROVIDER_NAME`.

## Advanced features

### Drift detection (Plus tier)

Automatically detects when real infrastructure diverges from the Terraform state:
- Runs a background refresh on a schedule (default: every 24 hours after last successful run).
- Compares refreshed state to configuration.
- Displays "Drift detected" status on workspace.
- Sends notifications (email, Slack, webhook).

Requires: Terraform >= 0.15.4, remote or agent execution mode.

### Continuous validation (Plus tier)

Evaluates `check` blocks and `postcondition` blocks on a schedule (Terraform >= 1.3.0). When a check fails, the workspace shows a health warning without blocking runs.

### Ephemeral workspaces and auto-destroy

Configure workspaces to automatically destroy infrastructure after a period of inactivity:

```hcl
resource "tfe_workspace" "dev" {
  name         = "my-app-dev"
  organisation = "my-org"

  auto_destroy_activity_duration = "7d"   # destroy after 7 days of inactivity
}
```

### Private module registry

Publish internal modules for organisation-wide reuse:
1. Connect a VCS repository following the naming convention `terraform-<PROVIDER>-<NAME>`.
2. Create semantic version tags (e.g. `v1.0.0`).
3. HCP Terraform imports the module and tracks new tags as versions.

Using a private module:

```hcl
module "vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"
  version = "~> 2.0"
}
```

## TFE provider (workspace-as-code)

Manage HCP Terraform itself with Terraform: workspaces, variables, teams, and policies as code.

```hcl
terraform {
  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.57"
    }
  }
}

provider "tfe" {
  # Token from TFE_TOKEN env var or terraform login
}

resource "tfe_project" "payments" {
  organisation = "my-org"
  name         = "payments"
}

resource "tfe_workspace" "api_prod" {
  name              = "payments-api-prod"
  organisation      = "my-org"
  project_id        = tfe_project.payments.id
  terraform_version = "~> 1.15.0"
  working_directory = "infrastructure/api"
  auto_apply        = false
  execution_mode    = "remote"

  vcs_repo {
    identifier     = "my-org/payments-api"
    branch         = "main"
    oauth_token_id = tfe_oauth_client.github.oauth_token_id
  }
}

resource "tfe_variable" "environment" {
  key          = "environment"
  value        = "production"
  category     = "terraform"
  workspace_id = tfe_workspace.api_prod.id
}

resource "tfe_variable_set" "aws_creds" {
  name         = "aws-credentials"
  organisation = "my-org"
}

resource "tfe_run_trigger" "network_to_api" {
  workspace_id  = tfe_workspace.api_prod.id
  sourceable_id = tfe_workspace.network_prod.id
}
```

Authenticate the TFE provider:

```bash
export TFE_TOKEN="<team-or-user-token>"
terraform init && terraform plan
```

## Troubleshooting HCP Terraform

### State lock conflict

```
Error: Error locking state: Error acquiring the state lock
```

In HCP Terraform, state locking is automatic. If a run fails mid-apply, the lock may persist. Unlock via: Workspace > Settings > Locking > Unlock.

API unlock:

```bash
curl -s -X POST \
  -H "Authorization: Bearer $TFC_TOKEN" \
  https://app.terraform.io/api/v2/workspaces/ws-abc123/actions/unlock
```

### Provider authentication failure

```
Error: error configuring Terraform AWS Provider: no valid credential sources found
```

Check workspace variables: ensure cloud credentials are set as environment variables, or that dynamic credentials variables (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`) are configured correctly.

### Missing configuration files

```
Error: No configuration files found
```

Check the working directory setting for the workspace. For VCS-connected workspaces, the working directory must match the subdirectory containing `.tf` files.

### VCS webhook issues

Runs not triggering on push:
1. Check VCS provider webhook delivery logs for HTTP 4xx/5xx responses.
2. Verify the webhook URL points to `app.terraform.io`.
3. Confirm the tracked branch matches the push target.
4. Queue one manual run first: workspaces with zero runs ignore webhooks.
5. Check trigger paths if using a monorepo.

Speculative plans not posting to PRs:
1. Verify OAuth token has the `repo` scope (GitHub).
2. Check VCS provider connection status in Organisation Settings > VCS Providers.
3. Look for delivery failures in the VCS provider's webhook logs.

### Agent connectivity

Agent shows Unknown or Errored:
1. Verify outbound HTTPS connectivity to `app.terraform.io:443`.
2. Check the agent process is running: `docker ps` or `ps aux | grep tfc-agent`.
3. Inspect agent logs for authentication or network errors.
4. Verify the agent token is valid and not expired.
5. Check proxy or firewall settings if behind a corporate network.

Runs stuck in "Planning" with agent execution:
1. Verify at least one agent in the pool is idle.
2. Check agent pool assignment matches workspace configuration.
3. Review agent logs for crash or OOM during plan.

### Sentinel policy debugging

Policy fails unexpectedly:
1. Click the policy check in the run UI to see evaluation details.
2. Use `sentinel test` locally with mock data from the failed run.
3. Download mock data: Run > Policy Check > Download Sentinel Mocks.
4. Verify the policy's imports match the expected Terraform plan structure.

### Performance issues

Large state files (>50 MB):
- Decompose into smaller workspaces.
- Remove unnecessary resources from state (`terraform state rm`).

Run queue backlog:
- Only one run executes per workspace at a time.
- Cancel stale queued runs via UI or API.
- Avoid unnecessary VCS triggers with precise trigger paths.
- Split high-churn workspaces.

Concurrent run limits by tier:

| Tier | Concurrent runs |
|---|---|
| Free | 1 |
| Standard | 3 |
| Plus | Configurable |
| Enterprise | Configurable |
