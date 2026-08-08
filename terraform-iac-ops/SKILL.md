---
name: terraform-iac-ops
description: "Use for Terraform / OpenTofu infrastructure-as-code OPERATIONS: authoring HCL configurations, planning and applying changes, managing state, designing modules, detecting drift, integrating with CI pipelines, and operating HCP Terraform / Terraform Cloud workspaces. References: architecture.md, best-practices.md, terraform-cloud.md, diagnostics.md. Triggers include \"terraform\", \"opentofu\", \"HCL\", \"infrastructure as code\", \"terraform plan\", \"terraform apply\", \"terraform state\", \"state file\", \"remote backend\", \"terraform module\", \"module registry\", \"terraform import\", \"drift detection\", \"terraform workspace\", \"HCP Terraform\", \"Terraform Cloud\", \"tfstate\", \"state locking\", \"terraform refresh\", \"for_each\", \"dynamic blocks\", \"provider configuration\", \"terraform init\", \"terraform destroy\", \"plan review\", \"terraform CI\", \"tflint\", \"terraform validate\", \"sentinel policy\", \"OPA terraform\", \"ephemeral resources\", \"provider-defined functions\", \"moved blocks\", \"terraform test\", \"Terraform Stacks\", \"variable validation\", \"terraform fmt\", \"terraform backend\", \"S3 backend\", \"GCS backend\", \"azurerm backend\", \"DynamoDB lock table\", \"terraform lock file\", \"OIDC terraform\", \"dynamic credentials\", \"tfe provider\", \"private module registry\", \"run triggers\", \"variable sets\", \"agent pool\", \"speculative plan\". For non-Terraform IaC (Bicep, CloudFormation, Pulumi) and GitOps see the respective skills; for cloud provider service selection see aws-cloud-ops, azure-cloud-ops, or gcp-cloud-ops; for Ansible configuration management see ansible-automation-platform and ansible-network-modules."
license: MIT
metadata:
  version: 1.0.0
---

# Terraform IaC operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: terraform-iac-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Terraform (and its open-source fork OpenTofu) manage infrastructure through declarative HCL configurations, a provider plugin model, and a state file that records what the tool manages. This skill owns the full IaC operations loop: configuration authoring, plan review, safe applies, state management, module design, drift handling, and cloud-platform integration via HCP Terraform. Security posture of credentials and state lives in `secrets-hygiene`; cloud-provider service selection lives in the cloud-ops skills.

## When to use

- Writing, reviewing, or refactoring HCL configurations for any provider.
- Running or interpreting `terraform plan` / `terraform apply` / `terraform import` / `terraform state` operations.
- Designing module structure, variable contracts, and output interfaces.
- Managing remote backends (S3, GCS, Azure Blob, HCP Terraform) and state locking.
- Investigating or reconciling infrastructure drift.
- Setting up CI/CD pipelines for Terraform (format checks, validate, plan-on-PR, apply-on-merge).
- Operating HCP Terraform / Terraform Cloud: workspaces, runs, variable sets, policy enforcement, private registry, agents.
- Troubleshooting plan/apply errors, state lock issues, provider authentication failures, dependency cycles, or corrupt state.

## When not to use

- **Non-Terraform IaC**: AWS CloudFormation, Azure Bicep, Pulumi, or CDK; see respective skills or documentation.
- **GitOps continuous delivery** (Flux, Argo CD): these consume Terraform outputs but are not Terraform operations.
- **Cloud-provider service selection** (which EC2 type, which managed DB): see `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`.
- **Ansible configuration management**: see `ansible-network-modules` and the `ansible-automation-platform` skill.

## Core model

Terraform compares three states on every plan: desired state (HCL configuration), known state (state file), and actual state (provider API calls). The plan diff drives the apply. Providers are separate plugin binaries communicating via gRPC; they map HCL resource blocks to cloud API calls. The state file is the binding between resource addresses in HCL and real resource IDs. It must be stored remotely, locked during operations, and encrypted at rest because it can contain sensitive values.

See `references/architecture.md` for provider plugin protocol, state file internals, dependency graph mechanics, and backend comparison.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Provider plugin protocol, state file internals, dependency graph, plan/apply mechanics, backend comparison (S3, GCS, Azure Blob, HCP, Consul, pg), workspace model, lifecycle meta-arguments, module composition, data sources, for/dynamic expressions, version-gated features (1.14 / 1.15) | `references/architecture.md` |
| Best practices | Module design conventions, repository structure, remote state organisation, environment separation, DRY patterns, variable validation, naming, secret handling in state, policy-as-code (Sentinel / OPA), tagging strategy, version pinning, pre-commit (fmt / validate / tflint) | `references/best-practices.md` |
| HCP Terraform / Terraform Cloud | Workspace types (VCS / CLI / API-driven), runs lifecycle, speculative plans, remote state sharing, variable sets, run triggers, dynamic provider credentials (OIDC), private module registry, agents, drift detection, continuous validation, no-code provisioning, Sentinel / OPA policies, TFE provider, API automation | `references/terraform-cloud.md` |
| Diagnostics | Plan/apply errors, state lock stuck, provider auth failures, dependency cycles, drift reconciliation, import workflows, refactoring with `moved` blocks, `TF_LOG` debugging, state surgery, recovering corrupt or lost state, local init/plan/apply/destroy run workflow | `references/diagnostics.md` |

## The plan-apply loop in one screen

Safe change discipline for every environment:

```
1. terraform init          # initialise working directory, download providers
2. terraform validate      # syntax and internal consistency check
3. terraform plan -out=plan.tfplan   # save the plan; what was reviewed = what gets applied
4. Review the plan         # human checks every +/-/~/−/+ symbol before proceeding
5. terraform apply plan.tfplan       # apply the saved plan; no surprises
```

Key constraints:
- Remote state and locking are mandatory for any shared environment. Never apply with local state in a team.
- In CI: plan on PR (post plan output as a comment); apply only after merge and manual approval for production.
- Never apply an unreviewed plan. Never use `terraform apply -auto-approve` in production.
- `-target` is an emergency tool, not a routine workflow. Partial applies leave state inconsistent.
- `force-unlock` requires confirming no operation is in progress before use.

## Cross-references

- `aws-cloud-ops`, `azure-cloud-ops`, `gcp-cloud-ops`: cloud-provider service and networking operations that Terraform provisions. Provider authentication patterns and OIDC federation details live in those skills; surface-level auth guidance is in `references/architecture.md`.
- `ansible-network-modules`: Ansible handles OS-level configuration management; Terraform handles infrastructure provisioning. The two tools are complementary, not overlapping.
- `secrets-hygiene`: state files can contain sensitive attribute values (passwords, API keys, certificates); handle the state backend, state pull output, and CI credentials per the hygiene discipline. Never log or commit state files.
- `systematic-debugging`: when a plan error or provider failure is itself the symptom of a deeper infrastructure problem, diagnose root cause before re-applying.
- `gh-actions-ci`: Terraform plan/apply pipelines commonly run in GitHub Actions; consult this skill for runner setup, OIDC role assumption, and environment protection rules.
- `utc-timestamps`: all Terraform run timestamps, drift detection schedules, and auto-destroy dates must be expressed in UTC.

## Red flags

- Applying without a saved plan file (`terraform apply` without `-out`). The plan that was reviewed may differ from the plan that runs.
- Local state (`terraform.tfstate` on disk) in a multi-person or CI environment. Any concurrent operation will corrupt state.
- Secrets in plaintext in `.tfvars`, `.tf` files, or state without backend encryption. Mark variables `sensitive = true`; encrypt the state backend at rest.
- Using `-target` as a routine workflow instead of an emergency measure. Targeted applies leave the rest of the configuration unreconciled and can silently break downstream dependencies.
- `terraform force-unlock` without first confirming no other operation is running. Unlocking a live operation corrupts state.
- Committing `.terraform/` or `terraform.tfstate` to version control.
- Using `count` with lists where `for_each` with a map would be stable. Index-shifting on list changes causes unnecessary destroy/recreate cycles.
- Ignoring `moved` blocks when refactoring resource addresses. Renaming without a `moved` block destroys and recreates the resource.
- Applying in production directly from a developer's local machine instead of through a reviewed CI pipeline.

## Bottom line

Load the reference that matches the request. For architectural or state questions, use `references/architecture.md`. For module design and CI integration, use `references/best-practices.md`. For HCP Terraform workspace operations, use `references/terraform-cloud.md`. For errors and recovery, use `references/diagnostics.md`. All production applies follow the saved-plan discipline: plan, review, apply the file.
