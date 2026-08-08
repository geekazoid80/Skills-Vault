# Terraform diagnostics

## Local run workflow

For local Terraform operations the standard sequence is:

```bash
# 1. Initialise working directory
terraform init

# 2. Check format
terraform fmt -check -recursive

# 3. Validate configuration syntax and internal consistency
terraform validate

# 4. Generate and save the execution plan
terraform plan -out=plan.tfplan

# 5. Review the plan output carefully

# 6. Apply the saved plan (per change-control policy for production)
terraform apply plan.tfplan

# 7. Confirm outputs
terraform output
```

Destructive operations (`terraform destroy`) follow the same sequence with `terraform plan -destroy -out=destroy.tfplan` before applying.

If a Terraform MCP server is configured, these operations map to the following tools:

| Operation | Tool name | Key parameters |
|---|---|---|
| Initialise working directory | `terraform_init` | `working_dir` |
| Validate configuration | `terraform_validate` | `working_dir` |
| Format files | `terraform_fmt` | `working_dir` |
| Generate plan | `terraform_plan` | `working_dir`, `var_file`, `target` |
| Apply changes | `terraform_apply` | `plan_file`, `working_dir` |
| Destroy infrastructure | `terraform_destroy` | `working_dir` |
| Show outputs | `terraform_output` | `working_dir` |
| List state resources | `terraform_state_list` | `working_dir` |
| Import existing resource | `terraform_import` | `resource_address`, `resource_id`, `working_dir` |

Apply and destroy require prior plan review and must follow the organisation's change-control policy.

## Common errors

### State lock errors

```
Error: Error acquiring the state lock
Lock Info:
  ID:        xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Path:      s3://bucket/key/terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
  Version:   1.15.0
  Created:   2026-06-15 10:30:00.000000 UTC
```

Diagnosis:
1. Check if another `terraform apply` is legitimately running.
2. Check if a previous run crashed and left a stale lock.
3. Check the `Who` field: is it a CI pipeline or a person?

Resolution:
- Stale lock: `terraform force-unlock <LOCK_ID>` -- confirm no other operation is running first.
- Legitimate lock: wait for the other operation to complete.
- Prevention: use CI/CD with queued runs (HCP Terraform, Atlantis) to prevent concurrent operations.

### Provider authentication failures

```
Error: error configuring Terraform AWS Provider: no valid credential sources found
```

Diagnosis:
1. Check environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_PROFILE`.
2. Check shared credentials file: `~/.aws/credentials`.
3. Check IAM instance profile (EC2) or OIDC federation (CI/CD).
4. Check the `provider` block configuration.

Resolution:
- Set credentials via environment variables or AWS SSO: `aws sso login --profile myprofile`.
- In CI/CD: configure OIDC role assumption; see `references/best-practices.md` for the pipeline pattern.
- Verify IAM permissions cover all operations Terraform needs.

### Dependency cycle

```
Error: Cycle: aws_security_group.a, aws_security_group.b
```

Diagnosis: two or more resources reference each other, creating a circular dependency.

Resolution:
1. Break the cycle by using separate resources for the cross-reference:

```hcl
# Instead of inline security group rules that reference each other:
resource "aws_security_group_rule" "a_to_b" {
  security_group_id        = aws_security_group.a.id
  source_security_group_id = aws_security_group.b.id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
}
```

2. Use `depends_on` with a third resource that both depend on.
3. Restructure to eliminate the circular reference entirely.

### Plan shows unexpected changes (drift)

```
# aws_instance.web will be updated in-place
  ~ resource "aws_instance" "web" {
      ~ tags = {
          + "ManagedBy" = "manual-change"
        }
    }
```

Diagnosis: someone modified the resource outside Terraform (console, CLI, another tool).

Resolution:
1. If the manual change should be kept: update the Terraform config to match, then re-run `terraform plan` to confirm no changes.
2. If the manual change should be reverted: `terraform apply` to enforce declared state.
3. If the attribute should be ignored permanently: add `lifecycle { ignore_changes = [tags] }`.

### Resource already exists

```
Error: creating EC2 Instance: InvalidParameterValue: The instance ID 'i-0abc123' already exists
```

Diagnosis: the resource exists in the cloud but not in Terraform state. Common after manual creation, state loss, or `terraform state rm` without destroying.

Resolution:
1. Import the existing resource: `terraform import aws_instance.web i-0abc123`
2. Or use import blocks (1.5+):
   ```hcl
   import {
     to = aws_instance.web
     id = "i-0abc123"
   }
   ```
3. Run `terraform plan` after import and iterate until the plan shows no changes.

### Bulk import with for_each (1.14+)

```hcl
import {
  for_each = var.existing_instance_ids
  to       = aws_instance.imported[each.key]
  id       = each.value
}
```

Useful for adopting large numbers of pre-existing resources.

### Provider version constraint conflict

```
Error: Failed to query available provider packages
locked provider registry.terraform.io/hashicorp/aws 5.30.0 does not match configured version constraint ~> 5.40
```

Resolution:
1. Update the lock file: `terraform init -upgrade`.
2. Or adjust the version constraint in `versions.tf`.
3. Review the provider changelog for breaking changes between the versions involved.

## Debugging workflows

### Enable detailed logging

```bash
export TF_LOG=DEBUG          # TRACE, DEBUG, INFO, WARN, ERROR
export TF_LOG_PATH=terraform.log
export TF_LOG_PROVIDER=DEBUG  # provider-specific logging only
export TF_LOG_CORE=WARN       # core-only logging at WARN

terraform plan 2>&1 | tee plan-output.log
```

### Inspect state

```bash
# List all resources in state
terraform state list

# Show specific resource (all attributes)
terraform state show aws_instance.web

# Pull remote state to local file for inspection
terraform state pull > state.json

# Produce plan in machine-readable JSON for analysis
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json
```

### Validate configuration

```bash
# Syntax and internal consistency
terraform validate

# Format check (CI-friendly, exits non-zero if files are not formatted)
terraform fmt -check -recursive

# Security and compliance scanning
checkov -d .
trivy config .
```

## State recovery

### Corrupted state

1. Check for backups: S3 versioning, GCS object versioning, or `.terraform.tfstate.backup`.
2. Restore from backup: download the previous version from the backend.
3. Re-import resources if no backup exists.

### Lost state

If state is completely lost but infrastructure exists:

1. Create `.tf` files describing the existing infrastructure.
2. Import each resource: `terraform import <resource_address> <resource_id>`.
3. Run `terraform plan` and iterate until the plan shows no changes.
4. Tools like `terraformer` can generate config from existing cloud resources; treat output as a starting point, not final config.

### State surgery

```bash
# Remove a resource from state (stops managing it; does not destroy it)
terraform state rm aws_instance.old_server

# Move a resource (refactoring)
terraform state mv aws_instance.old_name aws_instance.new_name
terraform state mv module.old_module.aws_instance.web module.new_module.aws_instance.web

# Replace provider reference in state (e.g. after provider fork)
terraform state replace-provider hashicorp/aws registry.example.com/aws
```

## Refactoring with moved blocks

`moved` blocks (1.1+) refactor resource addresses without destroying and recreating infrastructure:

```hcl
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}
```

Terraform generates a plan that moves the state record. The resource is not destroyed. Remove the `moved` block after the change is applied and the state migration is confirmed.

## Import workflows

### CLI import

```bash
terraform import aws_instance.web i-0abc123
terraform plan   # confirm plan shows no changes
```

### Declarative import block (1.5+)

```hcl
import {
  to = aws_instance.web
  id = "i-0abc123"
}
```

Running `terraform plan` with an import block shows the proposed import. Running `terraform apply` executes it and optionally generates the resource configuration using `terraform plan -generate-config-out=generated.tf`.

## Provider-defined functions (1.8+)

Major providers expose custom functions callable in HCL expressions. Useful for ARN parsing, CIDR arithmetic, and encoding utilities without external data sources:

```hcl
locals {
  decoded_arn = provider::aws::arn_parse(aws_instance.web.arn)
  account_id  = local.decoded_arn.account
}
```

## Common performance issues

### Slow plan with large state

- Run `terraform plan -refresh=false` when state is known-current to skip the refresh phase.
- Decompose monolithic state into smaller files (see `references/best-practices.md` for isolation strategy).
- Cache provider binaries with `TF_PLUGIN_CACHE_DIR`.

### Slow graph execution

- Reduce unnecessary `depends_on` usage; it serialises the graph.
- `-parallelism=N` (default 10) controls concurrent provider operations. Increase for large applies; decrease if hitting API rate limits.

### Module count vs for_each

Using `count` on modules with many resources means every count index is a full instance of every resource. Removing an item from the middle destroys and recreates everything at a higher index. Use `for_each` with a map for stable keys.
