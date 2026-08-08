# CI/CD concepts

## Pipeline anatomy

A CI/CD pipeline is an automated sequence of steps that takes code from a commit to a deployed artefact. The four standard stages, in order:

```
Build -> Test -> Scan -> Deploy
```

| Stage | Purpose | Typical jobs |
|---|---|---|
| Build | Compile source, create a versioned artefact | Compile, package, build container image |
| Test | Verify correctness | Unit tests, integration tests, E2E tests |
| Scan | Security and quality assurance | SAST, SCA, DAST, coverage thresholds |
| Deploy | Release to an environment | Push image, apply manifest, run deploy script |

**Fail fast**: run the cheapest checks first (lint, unit tests). Block expensive integration tests if lint fails. Each stage gates the next; a failure in build never reaches deploy.

## Jobs, steps, stages, and pipelines

| Term | What it is |
|---|---|
| Step / task | A single command or action (run a script, call a tool) |
| Job | A collection of steps that run on the same runner or agent |
| Stage | A logical group of jobs that all run in the same pipeline phase |
| Pipeline / workflow | The entire automated process from trigger to completion |

Different platforms name these differently:

| Concept | GitHub Actions | GitLab CI | Jenkins | Azure DevOps | CircleCI |
|---|---|---|---|---|---|
| Pipeline | Workflow | Pipeline | Pipeline | Pipeline | Workflow |
| Stage | (no explicit stage; jobs run in parallel by default) | Stage | Stage | Stage | Workflow |
| Job | Job | Job | Stage | Job | Job |
| Step | Step | Script line | Step | Step | Step |

## Triggers

| Trigger type | When | Example use |
|---|---|---|
| Push | Code pushed to a branch | Build and test on every push to `main` |
| Pull request / merge request | PR opened, updated, or merged | Run tests before merge |
| Schedule | Cron-based timing | Nightly security scan |
| Manual | Human clicks a button | Production deployment approval |
| API / webhook | External event | Upstream dependency updated |
| Tag | Git tag created | Release build |
| Pipeline / workflow call | Called by another pipeline | Reusable deploy pipeline |

## Runners vs agents

The machine that executes a CI job is called a **runner** (GitHub Actions, GitLab CI, CircleCI) or **agent** (Azure DevOps, Jenkins). The same concept: compute capacity that picks up work and runs it.

### Hosted vs self-hosted

| Dimension | Hosted (platform-provided) | Self-hosted |
|---|---|---|
| Maintenance | Zero (platform manages) | You manage OS, patching, scaling |
| Cost | Per-minute billing | Infrastructure cost |
| Customisation | Limited (pre-installed tools) | Full control (GPU, custom tools, private network) |
| Security | Ephemeral (clean environment per job) | Persistent (requires hardening) |
| Network | Public internet access | Private VPC or on-premises access |

### Autoscaling

| Platform | Autoscaling solution |
|---|---|
| GitHub Actions | Actions Runner Controller (ARC) on Kubernetes |
| GitLab CI | Fleeting plugin, Docker autoscaler, Kubernetes executor |
| Azure DevOps | VMSS agents, container agents |
| Jenkins | Kubernetes plugin, EC2 plugin, Docker plugin |
| CircleCI | Resource classes (managed); self-hosted runners on your infrastructure |

## Caching strategies

Cache the artefacts that are expensive to regenerate and are the same across runs with the same input.

| Cache target | Impact | Key pattern |
|---|---|---|
| Dependencies (node_modules, .pip, .m2) | High: saves minutes | Hash of lock file (`package-lock.json`, `Pipfile.lock`) |
| Build outputs (compiled code) | Medium | Hash of source files |
| Docker layers | High for image builds | Registry cache or BuildKit cache mount |
| Tool binaries (terraform, kubectl) | Low: fast to download | Tool name and version string |

**Cache invalidation discipline**: use hash-based keys so a dependency change automatically busts the cache. Add a fallback key (prefix without the hash) so the first run after a dependency change gets a partial cache hit rather than a cold start.

## Artifacts

Artifacts are the outputs of a CI/CD pipeline job that are stored and can be passed between jobs or downloaded later.

| Artifact type | Examples | Storage |
|---|---|---|
| Container images | Docker images | Container registry (ECR, ACR, GCR, GitHub Packages, GitLab Registry) |
| Packages | npm, PyPI, NuGet, Maven | Package registry |
| Binaries | Go, Rust, compiled C | Object storage (S3, GCS), release assets |
| Test reports | JUnit XML, coverage HTML, SBOM | Pipeline artifact store |

**Artifact versioning**: every build should produce a versioned, immutable artefact. Options:

- Semantic versioning: `v2.1.3`
- Git SHA: `sha-abc1234`
- Build number: `build-42`
- Composite: `v2.1.3-build42-abc1234`

Never use `:latest` as the only tag. It is a moving target; any rollback or environment promotion becomes ambiguous.

**Build once, promote**: build a single artefact in the build stage and promote the exact same image or package through staging to production. Never rebuild from source per environment; the rebuild may produce a different binary.

## Secrets management and OIDC

### Secret storage levels

| Level | Mechanism | Scope |
|---|---|---|
| Repository / project | Encrypted secrets in CI config | Single repository |
| Organisation / group | Org-level or group-level secrets | All repos in org or group |
| Environment | Environment-scoped secrets | Specific deployment target only |
| External | HashiCorp Vault, AWS Secrets Manager, Azure Key Vault | Cross-platform; best for large estates |

Secrets should be injected at runtime, never baked into container images or committed to source control.

### OIDC keyless authentication

Modern CI/CD platforms issue OIDC JSON Web Tokens (JWTs) that allow the pipeline to assume a cloud IAM role without storing static credentials.

```
CI/CD platform issues JWT -> Cloud IAM validates (issuer, audience, claims) -> issues short-lived credentials -> CI job uses temp credentials
```

Benefits: no static secrets to rotate; credentials are scoped to the specific workflow or project; full audit trail of which pipeline assumed which role.

Support:

| Platform | OIDC to AWS | OIDC to Azure | OIDC to GCP |
|---|---|---|---|
| GitHub Actions | `id-token: write` + `aws-actions/configure-aws-credentials` | Yes | Yes |
| GitLab CI | `CI_JOB_JWT_V2` native | Yes | Yes |
| Azure DevOps | Workload identity federation on service connections | Native | Yes |
| Jenkins | Plugin-based (AWS Credentials plugin, OIDC plugin) | Plugin-based | Plugin-based |
| CircleCI | Context + OIDC token (beta) | Yes | Yes |

## Matrix builds and parallelism

**Matrix builds**: run the same job across a set of input combinations (OS x language version x dependency version). Each combination becomes an independent job that can run in parallel.

```
        Build
          |
    +--+--+--+
    |     |     |
 Test   Test  Test
(Node 20) (Node 22) (Node 24)
    |     |     |
    +--+--+--+
          |
        Deploy
```

**Fan-out / fan-in**: one upstream job triggers many parallel downstream jobs; a single downstream job waits for all parallel jobs to complete before proceeding. Used for cross-platform or cross-browser test matrices.

**Parallel test splitting**: divide a test suite across N runners by file count or historical timing data. Each runner executes a shard; results are merged. CircleCI's `parallelism:` key and `circleci tests split --split-by=timings` are the canonical example; GitHub Actions matrix and GitLab CI parallel jobs serve the same purpose.

## Deployment strategies

| Strategy | How it works | Risk on bad deploy |
|---|---|---|
| Recreate | Tear down old, bring up new | Full downtime during transition |
| Rolling | Replace instances one at a time | Partial: some users hit new version, some old |
| Blue-green | Switch traffic from old (blue) to new (green) in one step | Zero downtime; rollback is fast (switch back) |
| Canary | Route a small percentage of traffic to new version first; ramp up | Minimised: only a fraction of users affected before rollback |

## Environments and approval gates

An **environment** represents a deployment target (staging, production). Environments carry:

- Deployment history and audit trail
- Protection rules (required reviewers, branch restrictions, wait timers)
- Environment-scoped secrets

An **approval gate** pauses the pipeline and requires a named reviewer to approve before the deploy job proceeds. This is the primary human control point between automated testing and production deployment. Every platform implements this differently:

| Platform | Mechanism |
|---|---|
| GitHub Actions | Environment protection rules: required reviewers, wait timer, branch policy |
| GitLab CI | `when: manual` on deploy job, or Environments with approval rules |
| Jenkins | `input` step in Declarative pipeline |
| Azure DevOps | Environment approvals and checks (REST API check, business hours gate, required template) |
| CircleCI | `type: approval` job in workflow |

## Pipeline-as-code principles

1. **Version-controlled configuration**: pipeline config lives in the repository, not in a UI. Changes go through code review.
2. **Reproducibility**: the same commit always produces the same pipeline run. Pin all tool versions; avoid "latest" references.
3. **Reuse over copy-paste**: extract shared pipeline logic into reusable units (reusable workflows, shared libraries, templates, orbs, CI/CD components).
4. **Immutable artefacts**: build once, promote the same binary. Never rebuild per environment.
5. **Least-privilege tokens**: each job only holds the permissions it needs. Prefer OIDC over long-lived credentials.
6. **Automated quality gates**: tests, coverage thresholds, and security scans are the primary gate; human approval is a secondary gate for production.

## Cross-platform feature and selection matrix

| Feature | GitHub Actions | GitLab CI | Jenkins | Azure DevOps | CircleCI |
|---|---|---|---|---|---|
| Config format | YAML (per-workflow) | YAML (single file) | Groovy (Jenkinsfile) | YAML or classic UI | YAML (`config.yml`) |
| Hosting | GitHub.com + self-hosted | GitLab.com + self-managed | Self-hosted only | Azure + self-hosted | Managed + self-hosted |
| Source integration | GitHub native | GitLab native | Any SCM (Git, SVN) | Azure Repos, GitHub, Bitbucket | Any SCM |
| Reusable unit | Reusable workflow, composite action | CI/CD component, include template | Shared library | YAML template, `extends` | Orb |
| Secrets | Repo/org/env secrets | CI/CD variables, Vault | Credentials plugin, Vault | Variable groups, Azure Key Vault | Contexts, project env vars |
| OIDC/keyless | Native (AWS, Azure, GCP) | Native (JWT) | Plugin-based | Native workload identity federation | Yes (context OIDC) |
| Caching | `actions/cache` | `cache:` directive | Custom (stash/unstash) | Pipeline caching task | `restore_cache`/`save_cache` |
| Docker layer caching | Via registry cache or BuildKit | DinD or registry cache | Docker plugin | Container job layer cache | `docker_layer_caching: true` (machine executor, premium) |
| Cost model | Free tier + per-minute | Free tier + per-minute | Free OSS + infrastructure | Free tier (5 users) + per-agent | Free tier + credit-based |

## Migration paths

| From | To | Key considerations |
|---|---|---|
| Jenkins | GitHub Actions | Rewrite Jenkinsfiles as YAML workflows; replace plugins with marketplace Actions; migrate credentials to repository/environment secrets |
| Jenkins | GitLab CI | Map stages to GitLab stages; replace plugins with CI/CD components or templates; migrate job configs |
| Travis CI | GitHub Actions | Near 1:1 YAML mapping; automated migration tool available |
| Azure DevOps | GitHub Actions | Microsoft provides migration tooling; variable groups become repository/environment secrets |
| CircleCI | GitHub Actions | Orbs become marketplace Actions or composite actions; `config.yml` becomes workflow YAML |
| GitLab CI | GitHub Actions | `stages:` becomes job `needs:`/sequencing; CI/CD variables become secrets; runners become self-hosted runners |
