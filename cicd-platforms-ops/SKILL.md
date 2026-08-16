---
name: cicd-platforms-ops
description: "Use for CI/CD PIPELINE-PLATFORM operations across GitHub Actions, GitLab CI, Jenkins, Azure DevOps Pipelines, and CircleCI: authoring pipelines, runners/agents, caching, artifacts, secrets, OIDC, matrix builds, reusable/templated pipelines, deployment gates, platform selection and migration. References: concepts.md, github-actions.md, gitlab-ci.md, jenkins.md, azure-devops.md, circleci.md, diagnostics.md. Triggers include \"ci/cd\", \"cicd\", \"pipeline\", \"github actions\", \"workflow yaml\", \"gitlab ci\", \".gitlab-ci.yml\", \"jenkins\", \"jenkinsfile\", \"declarative pipeline\", \"azure devops\", \"azure pipelines\", \"circleci\", \"config.yml orbs\", \"runner\", \"self-hosted runner\", \"gitlab runner\", \"jenkins agent\", \"build matrix\", \"reusable workflow\", \"pipeline caching\", \"build artifacts\", \"pipeline secrets\", \"OIDC ci\", \"deployment environment\", \"approval gate\", \"pipeline migration\", \"ci platform selection\", \"shared library\", \"composite action\", \"pipeline stages\", \"build pipeline\", \"release pipeline\", \"CI/CD strategy\", \"CI/CD comparison\". For GitOps continuous delivery (ArgoCD, Flux) see the gitops skill; for Terraform IaC in pipelines see terraform-iac-ops; for Ansible in pipelines see ansible-automation-platform; for CI secrets and OIDC hardening see secrets-hygiene; for GitHub Actions security specifics see secrets-hygiene."
license: MIT
metadata:
  version: 1.1.0
---

# CI/CD platforms operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: cicd-platforms-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

CI/CD pipeline platforms automate the loop from code commit to deployed artefact. This skill owns platform selection, pipeline authoring, runner and agent management, caching, artifact handling, secret injection, OIDC federation, matrix builds, reusable pipeline templates, deployment gates, and migration between platforms. The five platforms with dedicated references are GitHub Actions, GitLab CI, Jenkins, Azure DevOps Pipelines, and CircleCI. Foundational theory and cross-platform decision tools live in `references/concepts.md`.

## When to use

- Authoring or reviewing workflow YAML, Jenkinsfiles, or `azure-pipelines.yml`.
- Selecting or comparing CI/CD platforms for a new project or migration.
- Configuring runners, agents, executors, or autoscaling pools.
- Setting up caching, artifact passing, matrix builds, or parallel jobs.
- Injecting secrets via OIDC federation or platform secret stores.
- Designing reusable pipeline units (reusable workflows, shared libraries, templates, orbs, CI/CD components).
- Configuring deployment gates, manual approvals, and environment protection rules.
- Diagnosing failing builds, flaky runners, cache misses, or OIDC trust errors.

## When not to use

- **GitOps continuous delivery** (ArgoCD, Flux, FluxCD): these tools consume pipeline outputs but operate the delivery layer separately. See the gitops skill.
- **Terraform IaC authoring**: see `terraform-iac-ops`. That skill covers plan/apply discipline, module design, and HCP Terraform workspaces; this skill covers the CI runner that invokes Terraform.
- **Ansible playbook authoring**: see `ansible-automation-platform`. That skill owns playbook and role design; this skill covers CI pipelines that invoke Ansible.
- **Secret storage and rotation discipline**: see `secrets-hygiene`. This skill covers how secrets reach the pipeline at runtime; hygiene discipline (rotation, storage backend, never-commit rules) lives there.

## Platform selection

```
Already committed to a source-code host?
  GitHub  -> GitHub Actions (native, rich marketplace)           -> references/github-actions.md
  GitLab  -> GitLab CI (unified SCM + CI + registry + security) -> references/gitlab-ci.md
  Azure Repos / .NET / enterprise AAD -> Azure DevOps Pipelines  -> references/azure-devops.md

Need maximum flexibility, any SCM, or air-gapped / on-premises?
  -> Jenkins (self-hosted, 1800+ plugins)                        -> references/jenkins.md

Need fast Docker builds, multi-SCM, or Docker layer caching?
  -> CircleCI or GitLab CI                                       -> references/circleci.md
```

| Platform | Hosting model | Config format | Runner/agent model | Ecosystem | Best fit |
|---|---|---|---|---|---|
| GitHub Actions | GitHub.com + self-hosted | YAML per workflow | GitHub-hosted + self-hosted runners | Marketplace (Actions) | Code on GitHub, cloud-native, OIDC |
| GitLab CI | GitLab.com + self-managed | Single `.gitlab-ci.yml` | GitLab runners, multiple executors | CI/CD Catalog, templates | GitLab shop, DevSecOps, full platform |
| Jenkins | Self-hosted only | Groovy (Jenkinsfile) | Controller + agents (any label) | 1800+ plugins | Any SCM, air-gapped, existing investment |
| Azure DevOps | Azure + self-hosted | `azure-pipelines.yml` or classic UI | Microsoft-hosted + self-hosted agents | Marketplace tasks | Azure/.NET, enterprise governance, AAD |
| CircleCI | Managed service | `.circleci/config.yml` | CircleCI-hosted + self-hosted runners | Orbs | Fast Docker builds, multi-SCM, cost-optimised parallelism |

See `references/concepts.md` for the deeper decision matrix and migration paths between platforms.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Concepts | Pipeline anatomy, triggers, jobs/steps, runners vs agents, caching strategies, artifacts, secrets and OIDC pattern, matrix builds, fan-in/fan-out, deployment strategies, environments and approval gates, cross-platform feature matrix, migration paths | `references/concepts.md` |
| GitHub Actions | Workflows, events, runners (hosted + self-hosted), actions (marketplace, composite, reusable workflows), matrix, caching, artifacts, secrets and environments, OIDC to cloud, concurrency, permissions | `references/github-actions.md` |
| GitLab CI | `.gitlab-ci.yml` structure, stages/jobs/rules, runners and executors, cache vs artifacts, CI/CD variables, `include`/`extends`/templates, parent-child and multi-project pipelines, environments, manual gates, OIDC; notable 18.x features | `references/gitlab-ci.md` |
| Jenkins | Declarative vs Scripted pipeline, Jenkinsfile, stages/steps/post, agents and labels, shared libraries, plugins, credentials binding, parameters, parallel, multibranch pipelines | `references/jenkins.md` |
| Azure DevOps | Azure Pipelines YAML, stages/jobs/steps, templates and extends, agent pools (Microsoft-hosted + self-hosted), variable groups, service connections and workload identity federation (OIDC), environments, approvals and checks, artifacts feeds | `references/azure-devops.md` |
| CircleCI | config.yml, jobs/workflows, orbs, executors (docker/machine/macOS/Windows), caching and workspaces, contexts and project env vars, matrix/parameters, approval jobs, dynamic config | `references/circleci.md` |
| Diagnostics | Cross-platform troubleshooting: failing builds, flaky tests, runner/agent offline or capacity, cache misses, secret not injected, OIDC trust failures, artifact errors, YAML syntax errors, permission errors, slow pipelines, debugging techniques per platform | `references/diagnostics.md` |

## Pipeline design in one screen

Cross-platform discipline that applies regardless of the platform chosen:

```
Build -> Test -> Scan -> Deploy (stage)
                           |-> gated deploy (approval required)
```

- **Fail fast**: run cheapest checks (lint, unit tests) first; block before expensive integration tests.
- **Cache dependencies**: hash the lock file; restore before install, save after. Saves minutes per run.
- **OIDC over long-lived tokens**: modern platforms issue short-lived OIDC JWTs to assume cloud roles. No static keys to rotate or leak.
- **Reproducible runners**: pin tool versions; use container-based runners where possible; never rely on "whatever is installed on the host".
- **Immutable artifacts**: build once, promote the same image/package through staging to production. Never rebuild per environment.
- **Gated deploys**: require a passing quality gate (test + scan thresholds) before manual approval unlocks production deployment.
- **Least-privilege tokens**: scope the CI token to only what the job needs; never grant write-all at the workflow level.

## Cross-references

- `secrets-hygiene`: CI secrets and OIDC federation hardening, GitHub Actions permissions block discipline, never-echo-secrets rule, token scoping.
- `terraform-iac-ops`: Terraform plan/apply in CI pipelines; saved-plan discipline, remote state, OIDC role assumption in runners.
- `ansible-automation-platform`: Ansible playbook execution in CI pipelines; execution environment setup, check-mode-first discipline.
- `gh-actions-ci`: Focused GitHub Actions recipe skill covering changelog automation (tag-to-tag), mkdocs strict staging, and `gh run list` as a Checks substitute. Cross-reference for GitHub-specific recipes; this skill is the broad multi-platform umbrella.
- `systematic-debugging`: when a pipeline failure is the symptom of a deeper infrastructure or code problem, diagnose root cause before re-running.

## Red flags

- Long-lived cloud credentials stored as CI secrets instead of OIDC federation. Rotate to OIDC.
- Secrets echoed in job logs, even through debug steps or environment dumps. Use masking; never `echo $SECRET`.
- `pull_request_target` event combined with `actions/checkout` of fork code and access to secrets (GitHub Actions privilege escalation path).
- Unpinned third-party actions or orbs referenced by mutable tag (`@v4`, `@latest`) rather than SHA or locked version. Supply-chain risk.
- Self-hosted runners shared across public repository PRs. Fork PRs can send untrusted code to your infrastructure.
- No branch protection or environment gate on the production deploy job. Anyone who can merge a PR can ship to production.
- Building the same artifact from source in each environment instead of promoting the build artifact from staging.
- `CI_DEBUG_TRACE: "true"` (GitLab) or `ACTIONS_STEP_DEBUG: true` (GitHub Actions) left enabled in production pipelines; these expose all variable values including secrets.

## Bottom line

Pick the platform that fits where your code lives and your compliance constraints. Load the matching reference for tool depth. Design pipelines around the build-once/promote-same-artifact principle with OIDC authentication and gated deploys. For secrets discipline and OIDC hardening, delegate to `secrets-hygiene`.
