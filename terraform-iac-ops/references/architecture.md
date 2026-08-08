# Terraform architecture

## How Terraform works

Terraform reads all `.tf` files in the current directory, constructs a configuration graph, compares it against the state file and the real-world state reported by providers, generates a plan, and then executes the plan against provider APIs.

```
                    +--------------+
                    |  .tf files   |  HCL configuration
                    +------+-------+
                           |
                    +------v-------+
                    |   terraform  |  Core binary
                    |    plan      |
                    +------+-------+
                           |
              +------------+-----------+
              |            |           |
       +------v------+ +---v-----+ +---v-----+
       |  State File  | |Provider | |Provider |  Plugin protocol
       |  (backend)   | |  AWS    | | Azure   |  (gRPC)
       +-------------+ +----+----+ +----+----+
                            |           |
                       +----v----+ +----v----+
                       |  AWS    | |  Azure  |  Cloud APIs
                       |  APIs   | |  APIs   |
                       +---------+ +---------+
```

Three states drive every plan:
1. **Desired state** -- the HCL configuration in `.tf` files.
2. **Known state** -- the state file (what Terraform recorded after the last apply).
3. **Actual state** -- the real resource state queried from provider APIs during refresh.

## Provider plugin protocol

Providers are separate binaries that communicate with Terraform core via gRPC (protocol version 5 for the SDK v1; version 6 for the Terraform Plugin Framework).

### Provider lifecycle

1. **Discovery** -- Terraform reads `required_providers` blocks, downloads from the registry (or mirrors).
2. **Initialisation** -- `terraform init` downloads provider binaries to `.terraform/providers/`.
3. **Configuration** -- Provider block sets authentication, region, and endpoints.
4. **Schema exchange** -- Provider advertises its resource and data source schemas to core.
5. **CRUD operations** -- Core calls the provider's Create, Read, Update, Delete methods via gRPC.

### Provider configuration

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # >= 5.0.0, < 6.0.0
    }
  }
}

provider "aws" {
  region = "us-east-1"
  # Authentication: env vars (AWS_ACCESS_KEY_ID), shared config, IAM role, OIDC
}
```

Version constraint syntax:

| Constraint | Meaning |
|---|---|
| `= 5.0.0` | Exact version |
| `~> 5.0` | Compatible (>= 5.0.0, < 6.0.0) |
| `>= 5.0, < 5.5` | Range |

The lock file (`.terraform.lock.hcl`) records exact versions and content hashes. Commit it to version control for reproducible builds.

### Provider authentication patterns

| Provider | Preferred auth | Avoid |
|---|---|---|
| AWS | OIDC federation, IAM instance profile, SSO | Static access keys in provider block |
| Azure | Managed identity, OIDC, service principal + client cert | Client secret in provider block |
| GCP | Workload identity federation, service account (limited scope) | Key file in version control |

## State file internals

The state file is JSON. Key fields:

```json
{
  "version": 4,
  "terraform_version": "1.15.0",
  "serial": 42,
  "lineage": "unique-uuid",
  "outputs": {},
  "resources": [
    {
      "module": "module.vpc",
      "mode": "managed",
      "type": "aws_vpc",
      "name": "main",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 1,
          "attributes": {
            "id": "vpc-0abc123",
            "cidr_block": "10.0.0.0/16"
          }
        }
      ]
    }
  ]
}
```

### State semantics

- **serial** -- Incremented on every write; used for conflict detection.
- **lineage** -- UUID created on `terraform init`; prevents applying state from a different workspace.
- **resources** -- Each instance stores all attributes, including computed ones (IDs, ARNs).
- **Sensitive values** -- Marked in state but NOT encrypted by default. The backend must encrypt at rest.

### Backend comparison

| Backend | State storage | Locking | Encryption |
|---|---|---|---|
| S3 | S3 bucket | DynamoDB table (separate resource) | SSE-S3 or SSE-KMS |
| GCS | GCS bucket | Native (object versioning) | Google-managed or CMEK |
| Azure Blob | Storage container | Native (blob lease) | SSE or CMEK |
| HCP Terraform | HashiCorp-managed | Native (automatic) | HashiCorp-managed (Vault transit) |
| Consul | Consul KV | Native (session locking) | TLS and ACLs |
| pg (PostgreSQL) | PostgreSQL table | Advisory locks | TLS and column encryption |

S3 backend example:

```hcl
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "network/vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Dependency graph

Terraform builds a directed acyclic graph (DAG) of all resources and data sources:

1. **Implicit dependencies** -- Resource A references resource B's attribute; A depends on B automatically.
2. **Explicit dependencies** -- `depends_on` meta-argument forces ordering when there is no attribute reference.
3. **Parallel execution** -- Independent resources are created or destroyed in parallel (configurable via `-parallelism`).
4. **Destroy ordering** -- Reverse of creation order.

View the graph: `terraform graph | dot -Tsvg > graph.svg`

### Dependency issues

- **Cycles** -- Two resources referencing each other. Break with `depends_on` or by restructuring resources.
- **Implicit via provider** -- Resources sharing a provider share authentication. Provider config changes affect all of them.
- **Cross-module** -- Module outputs create dependencies between modules. Design module interfaces to minimise coupling.

## Plan/apply mechanics

### Plan phase

1. Read current state from backend.
2. Refresh: query each provider for real-world resource state (skip with `-refresh=false` when you know state is current).
3. Compare: desired (config) vs known (state) vs actual (refreshed).
4. Generate plan: list of create, update, destroy, or no-op actions.
5. Optionally save to file: `terraform plan -out=plan.tfplan`.

### Apply phase

1. Read the plan (from file or re-plan).
2. Walk the dependency graph in topological order.
3. For each resource: call the provider's CRUD method.
4. Update state after each successful operation.
5. Report results.

### Plan output symbols

| Symbol | Meaning |
|---|---|
| `+` | Create |
| `-` | Destroy |
| `~` | Update in-place |
| `-/+` | Destroy and recreate (replacement) |
| `<=` | Read (data source) |

## Resource lifecycle meta-arguments

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"

  lifecycle {
    create_before_destroy = true    # create new before destroying old
    prevent_destroy       = true    # block terraform destroy
    ignore_changes        = [tags]  # exclude from drift detection
    replace_triggered_by  = [aws_ami.latest.id]  # force replacement when dependency changes
  }
}
```

| Meta-argument | Effect |
|---|---|
| `create_before_destroy` | New resource created before old is destroyed |
| `prevent_destroy` | `terraform destroy` and replacements fail |
| `ignore_changes` | Listed attributes excluded from drift detection |
| `replace_triggered_by` | Force replacement when referenced resource or attribute changes |
| `precondition` (1.2+) | Validate assumptions before applying |
| `postcondition` (1.2+) | Validate results after applying |

## Module structure and composition

### Standard module layout

```
modules/
  vpc/
    main.tf          # resources
    variables.tf     # input variable declarations
    outputs.tf       # output value declarations
    versions.tf      # required_providers + terraform version constraint
    README.md        # documentation
```

### Module instantiation and composition

```hcl
module "vpc" {
  source  = "app.terraform.io/my-org/vpc/aws"  # private registry
  version = "~> 2.0"

  cidr_block  = "10.0.0.0/16"
  environment = var.environment
}

# Consume module output in another resource
resource "aws_instance" "web" {
  subnet_id = module.vpc.public_subnet_ids[0]
}
```

### Meta-arguments: count and for_each

```hcl
# for_each (preferred): uses stable map keys
resource "aws_subnet" "private" {
  for_each   = var.subnet_config
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value.cidr
}

# count (fragile with lists): removing an item shifts all indices
resource "aws_instance" "web" {
  count         = 3
  instance_type = "t3.micro"
}
```

Prefer `for_each` with a map over `count` with a list. Index-shifting on list changes causes unnecessary destroy/recreate cycles.

### Data sources

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"]
  }
}
```

### Dynamic blocks

```hcl
resource "aws_security_group" "web" {
  name = "web-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidrs
    }
  }
}
```

### For expressions

```hcl
locals {
  instance_ids = { for k, v in aws_instance.web : k => v.id }
  public_ips   = [for i in aws_instance.web : i.public_ip if i.public_ip != ""]
}
```

## State management operations

| Operation | Command | Use case |
|---|---|---|
| List resources | `terraform state list` | Inventory of managed resources |
| Show resource | `terraform state show aws_instance.web` | Inspect a resource's state |
| Move resource | `terraform state mv aws_instance.old aws_instance.new` | Refactor without destroy/recreate |
| Remove from state | `terraform state rm aws_instance.web` | Stop managing (does not destroy) |
| Import (CLI) | `terraform import aws_instance.web i-0abc123` | Adopt existing infrastructure |
| Import block (1.5+) | `import { to = aws_instance.web; id = "i-0abc123" }` | Declarative adoption |

### Moved blocks (refactoring, 1.1+)

```hcl
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}
```

`moved` blocks let you refactor resource addresses without destroying and recreating infrastructure. Terraform generates a plan that moves the state record, not the resource.

## Version-gated features

| Feature | Version | Notes |
|---|---|---|
| `moved` blocks | 1.1+ | Refactoring without destroy/recreate |
| `precondition` / `postcondition` | 1.2+ | In-config lifecycle validation |
| `check` blocks | 1.5+ | Continuous validation assertions |
| `import` blocks | 1.5+ | Declarative resource adoption |
| `terraform test` | 1.6+ | Native testing framework |
| Provider-defined functions | 1.8+ | Custom functions from provider schemas |
| Ephemeral resources | 1.10+ | Values never stored in state |
| `for_each` on `import` blocks | 1.14+ | Bulk import of existing resources |
| Multiple `validation` blocks per variable | 1.14+ | Richer input validation |
| Write-only resource attributes | 1.15+ | Provider attributes excluded from state storage |
| Terraform Stacks (HCP Terraform only) | 1.15+ | Multi-component orchestration with dependency ordering |
| `terraform plan -json` streaming | 1.15+ | Real-time structured output for CI/CD |

### Ephemeral resources (1.10+, stabilised in 1.14)

Ephemeral resources produce values that exist only during the plan/apply lifecycle and are never stored in state. Ideal for secrets, temporary credentials, and short-lived tokens.

```hcl
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db.id
}

resource "aws_db_instance" "main" {
  password = ephemeral.aws_secretsmanager_secret_version.db_password.secret_string
}
```

Values are fetched on every plan/apply; provider support is required.

### Terraform Stacks (1.15+, HCP Terraform only)

Stacks coordinate multiple Terraform configurations (components) with dependency ordering and unified lifecycle management:

```hcl
# stack.tfstack.hcl
component "network" {
  source = "./modules/network"
  inputs = { region = var.region }
}

component "compute" {
  source = "./modules/compute"
  inputs = {
    vpc_id    = component.network.vpc_id
    subnet_id = component.network.subnet_id
  }
}
```

A Stack deployment is one instance of the stack (one per environment). Stacks execution requires HCP Terraform or Terraform Enterprise.

## Workspaces (CLI)

CLI workspaces are separate state files within the same backend configuration. They suit simple environment separation where the configuration is identical and only the state differs.

```bash
terraform workspace new staging
terraform workspace select staging
terraform workspace list
```

Workspaces in HCP Terraform are different: each workspace is a fully independent unit with its own configuration, variables, and run history. See `references/terraform-cloud.md`.
