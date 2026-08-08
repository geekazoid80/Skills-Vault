# Terraform best practices

## Repository structure

```
infrastructure/
+-- modules/                    # reusable modules
|   +-- vpc/
|   +-- eks-cluster/
|   +-- rds-instance/
+-- environments/               # environment-specific root configs
|   +-- dev/
|   |   +-- main.tf
|   |   +-- variables.tf
|   |   +-- terraform.tfvars
|   |   +-- backend.tf
|   +-- staging/
|   +-- prod/
+-- global/                     # shared resources (IAM, DNS zones)
|   +-- iam/
|   +-- dns/
+-- terragrunt.hcl              # optional DRY wrapper
```

### File naming conventions

| File | Contents |
|---|---|
| `main.tf` | Primary resources and module calls |
| `variables.tf` | All input variable declarations |
| `outputs.tf` | All output value declarations |
| `versions.tf` | `terraform {}` block: required version + required providers |
| `backend.tf` | Backend configuration (or include in `versions.tf`) |
| `locals.tf` | Local value definitions |
| `data.tf` | Data source lookups |
| `terraform.tfvars` | Variable values (environment-specific; do not commit secrets) |

### Naming conventions

- **Resources**: `snake_case`, descriptive, no technology prefix (the resource type already contains it).
  - Preferred: `aws_instance.web_server`, `aws_s3_bucket.logs`
  - Avoid: `aws_instance.aws-web-server-instance-1`
- **Variables**: `snake_case`, descriptive; include unit when it matters (`timeout_seconds`, `disk_size_gb`).
- **Modules**: directory names that match purpose (`vpc`, `eks-cluster`).
- **Outputs**: match the resource attribute they expose (`vpc_id`, `cluster_endpoint`).

## Module design

### Single responsibility

A module does one thing well: creates a VPC, or an EKS cluster, not both. Composition at the root module level combines modules; individual modules stay focused.

### Expose only what's needed

Outputs are the module's public API. Do not expose internal resource IDs or computed attributes that callers do not need. Callers should depend on the output contract, not on internals.

### Version constraints

Pin provider and module versions. Use `~>` for minor-version flexibility within a major version:

```hcl
terraform {
  required_version = "~> 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Commit `.terraform.lock.hcl` to ensure all team members and CI use exactly the same provider binaries.

### Variable validation

Validate inputs early to catch bad values before they reach provider APIs:

```hcl
variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# Multiple validation blocks per variable (1.14+)
variable "instance_type" {
  type = string

  validation {
    condition     = can(regex("^t3\\.", var.instance_type))
    error_message = "Instance type must be in the t3 family."
  }

  validation {
    condition     = !contains(["t3.nano"], var.instance_type)
    error_message = "t3.nano is too small for production workloads."
  }
}
```

### No hardcoded values

Every configurable value flows through a variable with a sensible default. Hard-coding account IDs, region names, or AMI IDs in resources makes modules non-reusable and brittle to change.

## State management

### State isolation strategy

Separate state files by blast radius and change frequency:

| Layer | State key example | Change frequency | Blast radius |
|---|---|---|---|
| Networking | `network/vpc/terraform.tfstate` | Rarely | High (everything depends on it) |
| Data stores | `data/rds/terraform.tfstate` | Occasionally | Medium |
| Compute | `compute/eks/terraform.tfstate` | Frequently | Medium |
| Application | `app/api/terraform.tfstate` | Very frequently | Low |

Avoid monolithic state files. A large state file slows plan operations, increases the blast radius of mistakes, and makes concurrent team work harder.

### Cross-state references

Prefer decoupled references via a parameter store over tight state-to-state coupling:

```hcl
# Preferred: read from SSM / Secrets Manager (decoupled)
data "aws_ssm_parameter" "vpc_id" {
  name = "/infrastructure/network/vpc_id"
}

# Alternative: direct state reference (tighter coupling, may expose sensitive outputs)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "network/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}
```

In HCP Terraform, prefer the `tfe_outputs` data source over `terraform_remote_state`; it exposes only outputs, not the full state.

### Environment separation

Two common approaches:

| Approach | How | Tradeoffs |
|---|---|---|
| Separate directories | `environments/dev/`, `environments/prod/` with identical modules called with different `tfvars` | Explicit; easy to review; slight duplication in root config |
| CLI workspaces | One directory, `terraform workspace select prod` | Less duplication; risk of accidentally applying to the wrong workspace |

For significant production differences, separate directories are clearer. CLI workspaces work well when environments are nearly identical and the only difference is variable values.

## Security

### Secret handling in state

1. Never commit secrets to `.tfvars` or `.tf` files. Inject via environment variables, Vault, or CI secret stores.
2. Mark sensitive variables: `sensitive = true` suppresses values from plan/apply output.
3. Encrypt state at rest: enable SSE on S3/GCS/Azure Blob backends or use HCP Terraform (encrypted by default).
4. Restrict state access: the state backend contains all resource attributes, including secrets. Apply least-privilege IAM on the backend.
5. Use OIDC for CI/CD: GitHub Actions, GitLab CI, and other modern CI systems can assume cloud roles via OIDC without static credentials.

```hcl
variable "database_password" {
  type      = string
  sensitive = true  # hidden in plan/apply output
}
```

### Ephemeral resources for secrets (1.10+)

Use ephemeral resources for values that must never enter state at all:

```hcl
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db.id
}
```

### Policy as code

| Tool | Scope | Integration |
|---|---|---|
| Sentinel | Terraform Enterprise and HCP Terraform only | Native (pre-plan, post-plan, post-apply) |
| OPA / Rego | Any Terraform | Conftest on plan JSON, or OPA server |
| Checkov | Any Terraform | CLI or CI/CD; 1000+ built-in rules |
| tfsec (Trivy) | Any Terraform | CLI or CI/CD; security-focused rules |

## CI/CD integration

### Pipeline pattern

```
PR opened:
  -> terraform fmt -check
  -> terraform validate
  -> tflint (or checkov)
  -> terraform plan -out=plan.tfplan
  -> post plan output as PR comment

PR merged to main:
  -> terraform plan (re-plan to confirm no drift since PR was opened)
  -> manual approval gate (for production)
  -> terraform apply plan.tfplan
```

### Key practices

1. **Plan on PR, apply on merge.** Never apply directly from a developer's machine in production.
2. **Save the plan file.** `terraform plan -out=plan.tfplan` ensures what was reviewed is exactly what gets applied.
3. **Post plan output to the PR.** Reviewers see every create, update, and destroy before approving.
4. **OIDC authentication.** No static credentials stored in CI secrets.
5. **Lock the provider lock file.** Commit `.terraform.lock.hcl` for reproducible builds.
6. **Limit parallelism in CI.** `terraform apply -parallelism=10` to avoid API rate limiting from cloud providers.

## Performance

### Large state files

- **Split state** into smaller, independent state files by layer (see State isolation strategy above).
- **Use `terraform plan -refresh=false`** when you know state is current to skip the refresh phase.
- **Provider caching.** Set `TF_PLUGIN_CACHE_DIR` to avoid re-downloading provider binaries across workspaces on the same machine.
- **`-target` sparingly.** `terraform plan -target=aws_instance.web` gives short-term relief for slow plans; it is not a substitute for state decomposition.

### Module optimisation

- Avoid `count` on modules with many resources. Each count index creates a separate instance of every resource in the module; adding or removing from the middle of a count list triggers mass destroy/recreate.
- Prefer `for_each` over `count` for anything that may grow or shrink.
- Cache data source results in `locals` if the same data source is referenced multiple times.

## Common mistakes

1. **`count` with a list.** Removing an item shifts all indices, causing unnecessary destroy/recreate. Use `for_each` with a map.
2. **Not committing `.terraform.lock.hcl`.** Without it, `terraform init` may download different provider versions in CI versus local.
3. **Overusing `depends_on`.** Use only when implicit dependencies are insufficient. Overuse serialises the dependency graph and slows plan/apply.
4. **Mixing inline blocks and separate resources.** For example, `aws_security_group` inline `ingress`/`egress` blocks conflict with `aws_security_group_rule` resources. Pick one pattern per resource.
5. **Not using `moved` blocks for refactoring.** Renaming a resource or moving it into a module without a `moved` block destroys and recreates it.
6. **Importing without reconciling config.** After `terraform import`, always run `terraform plan` and confirm the plan shows no changes before considering the import complete.

## Tagging strategy

Consistent tagging is essential for cost allocation, security controls, and operational visibility:

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terraform"
    Owner       = var.team
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  tags          = merge(local.common_tags, { Name = "web-${var.environment}" })
}
```

Enforce tagging via Sentinel, OPA, or Checkov policies in CI to prevent untagged resources from reaching production.
