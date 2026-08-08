# GitLab CI

GitLab CI is tightly integrated with GitLab: source code, CI/CD, container registry, security scanning, package registry, and deployment are unified in one platform. Configuration is via `.gitlab-ci.yml` in the repository root. Current releases covered: 18.7, 18.8, 18.9.

## Pipeline structure

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - scan
  - deploy

variables:
  NODE_VERSION: "22"

default:
  image: node:${NODE_VERSION}
  cache:
    key: ${CI_COMMIT_REF_SLUG}
    paths:
      - node_modules/

build:
  stage: build
  script:
    - npm ci
    - npm run build
  artifacts:
    paths:
      - dist/
    expire_in: 1 hour

test:unit:
  stage: test
  script:
    - npm test
  coverage: '/Lines\s*:\s*(\d+\.?\d*)%/'

test:e2e:
  stage: test
  script:
    - npm run test:e2e
  services:
    - postgres:16
  variables:
    POSTGRES_DB: test
    POSTGRES_USER: runner
    POSTGRES_PASSWORD: secret

deploy:production:
  stage: deploy
  script:
    - ./deploy.sh
  environment:
    name: production
    url: https://myapp.example.com
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual
```

## Key directives

| Directive | Purpose | Example |
|---|---|---|
| `stages` | Define pipeline stages and their order | `stages: [build, test, deploy]` |
| `image` | Docker image for the job | `image: node:22` |
| `script` | Shell commands to execute | `script: [npm ci, npm test]` |
| `artifacts` | Files to pass between jobs (within a pipeline) | `artifacts: { paths: [dist/] }` |
| `cache` | Files to persist across pipeline runs | `cache: { paths: [node_modules/] }` |
| `services` | Docker service containers (databases, caches) | `services: [postgres:16, redis:8]` |
| `variables` | Environment variables | `variables: { NODE_ENV: production }` |
| `rules` | Conditional job execution (replaces `only`/`except`) | `rules: [{ if: '$CI_COMMIT_BRANCH == "main"' }]` |
| `needs` | DAG dependency; bypasses stage ordering | `needs: [build]` |
| `environment` | Deployment target with history and gates | `environment: { name: staging }` |
| `trigger` | Trigger child or multi-project pipelines | `trigger: { include: child.yml }` |
| `extends` | Inherit from another job definition | `extends: .deploy-template` |
| `include` | Include external YAML files or CI/CD components | `include: { template: Security/SAST.gitlab-ci.yml }` |

## Rules (conditional execution)

Prefer `rules:` over the legacy `only:`/`except:` syntax. Rules are evaluated top-to-bottom; the first match wins.

```yaml
deploy:
  rules:
    - if: $CI_COMMIT_TAG                                      # Run on tags
      when: always
    - if: $CI_COMMIT_BRANCH == "main"                        # Manual gate on main
      when: manual
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"       # Run on MRs
    - when: never                                             # Default: do not run
```

## Pipeline types

| Type | How | When to use |
|---|---|---|
| Basic | Linear stages; all jobs in a stage run before the next | Simple projects |
| DAG | `needs:` bypasses stage ordering; jobs start as soon as dependencies complete | Complex dependencies, faster pipelines |
| Parent-child | `trigger: { include: ... }` spawns a child pipeline | Monorepos, modular config |
| Multi-project | `trigger: { project: org/other-repo }` triggers another project's pipeline | Cross-repo orchestration |
| Merge request | `rules: [{ if: '$CI_PIPELINE_SOURCE == "merge_request_event"' }]` | PR-style CI with diff context |

### DAG example

```yaml
build:frontend:
  stage: build
  script: npm run build:frontend

build:backend:
  stage: build
  script: npm run build:backend

test:frontend:
  stage: test
  needs: [build:frontend]    # Starts immediately when build:frontend finishes
  script: npm run test:frontend

test:backend:
  stage: test
  needs: [build:backend]     # Does not wait for build:frontend
  script: npm run test:backend

deploy:
  stage: deploy
  needs: [test:frontend, test:backend]
  script: ./deploy.sh
```

## Runners and executors

| Executor | Isolation | Speed | Use case |
|---|---|---|---|
| Docker | Container per job | Fast | Default for most workloads |
| Kubernetes | Pod per job | Medium | Kubernetes-native, autoscaling |
| Instance (Fleeting) | Ephemeral VM per job | Medium | Cloud-native autoscaling (replaces Docker Machine) |
| Shell | None (runs on host) | Fastest | Simple, fully trusted environments |
| Virtual Machine | Full VM isolation | Slower | macOS, Windows, security-critical |

```bash
# Register a runner
gitlab-runner register \
  --url https://gitlab.example.com \
  --token <RUNNER_TOKEN> \
  --executor docker \
  --docker-image alpine:latest

# Verify and check status
gitlab-runner verify
gitlab-runner status
```

## Artifacts vs cache

| Aspect | Artifacts | Cache |
|---|---|---|
| Purpose | Pass files between jobs in the same pipeline | Speed up jobs across pipeline runs |
| Scope | Within a single pipeline run | Across pipeline runs (same cache key) |
| Upload | Always (when job succeeds) | Best-effort |
| Download | Explicit via `needs:` or stage dependency | Automatic on key match |
| Storage | GitLab server or object storage | Runner local or object storage |
| Retention | Configurable (`expire_in:`) | Evicted when storage is full |

### Cache configuration

```yaml
cache:
  key:
    files:
      - package-lock.json    # Key derived from lock file hash
    prefix: ${CI_COMMIT_REF_SLUG}
  paths:
    - node_modules/
  policy: pull-push          # pull: download only; push: upload only; pull-push: both
  fallback_keys:
    - ${CI_DEFAULT_BRANCH}   # Fall back to the default branch cache
```

## CI/CD variables

### Variable precedence (lowest to highest)

1. GitLab predefined variables (`CI_COMMIT_SHA`, `CI_PIPELINE_ID`, etc.)
2. Instance-level CI/CD variables
3. Group-level CI/CD variables
4. Project-level CI/CD variables
5. `.gitlab-ci.yml` `variables:` keyword
6. Job-level `variables:` keyword
7. Trigger/pipeline variables (API)
8. Manual pipeline variables (UI)

### Key predefined variables

| Variable | Value |
|---|---|
| `CI_COMMIT_SHA` | Full commit SHA |
| `CI_COMMIT_SHORT_SHA` | Short commit SHA (8 chars) |
| `CI_COMMIT_BRANCH` | Branch name (not set for tag pipelines) |
| `CI_COMMIT_TAG` | Tag name (not set for branch pipelines) |
| `CI_COMMIT_REF_SLUG` | Branch/tag name, slugified for use in URLs |
| `CI_PIPELINE_SOURCE` | How the pipeline was triggered |
| `CI_MERGE_REQUEST_IID` | MR internal ID |
| `CI_REGISTRY_IMAGE` | Container registry image path |
| `CI_JOB_TOKEN` | Auto-generated token for API access within the pipeline |
| `CI_PROJECT_DIR` | Full path to the project directory on the runner |

### Variable types

- **Protected**: only available on protected branches and tags.
- **Masked**: value is hidden in job logs (must meet regex constraints for masking to work).
- **File**: written to a temporary file; the variable contains the file path.

## Include, extends, and templates

```yaml
# Include a CI/CD component from the Catalog
include:
  - component: gitlab.com/components/sast@1.2.0
    inputs:
      stage: test

# Include from another project
include:
  - project: 'mygroup/ci-templates'
    ref: main
    file: '/templates/docker-build.yml'

# Include a GitLab-maintained security template
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
```

Template inheritance with `extends:` and hidden jobs (dot-prefix):

```yaml
.deploy-template:
  script:
    - echo "Deploying to $ENVIRONMENT"
    - ./deploy.sh
  environment:
    name: $ENVIRONMENT

deploy:staging:
  extends: .deploy-template
  variables:
    ENVIRONMENT: staging
  rules:
    - if: $CI_COMMIT_BRANCH == "main"

deploy:production:
  extends: .deploy-template
  variables:
    ENVIRONMENT: production
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual
```

## Environments and manual gates

```yaml
deploy:production:
  stage: deploy
  script: ./deploy.sh
  environment:
    name: production
    url: https://myapp.example.com
    deployment_tier: production
  rules:
    - if: $CI_COMMIT_BRANCH == "main"
      when: manual    # Human must click "play" to proceed
```

GitLab Environments track deployment history, rollback links, and per-environment secret access. Approval rules (GitLab 16.4+) allow requiring named approvers before a manual job can be triggered.

## OIDC to cloud

GitLab CI issues OIDC JWTs (`CI_JOB_JWT_V2`) that cloud providers can validate to issue short-lived credentials. This eliminates the need for static cloud credentials in CI/CD variables.

```yaml
deploy:
  id_tokens:
    CLOUD_TOKEN:
      aud: https://vault.example.com
  script:
    - vault login -method=jwt role=my-role jwt=$CLOUD_TOKEN
```

For AWS, configure an IAM identity provider for `https://gitlab.com` and reference `CI_JOB_JWT_V2` via the `id_tokens:` keyword.

## Security scanning integration

GitLab provides built-in security scanning templates:

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Container-Scanning.gitlab-ci.yml
  - template: Security/DAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
```

Findings appear in the merge request security widget and the security dashboard (GitLab Ultimate). Project maintainers can require that MRs have no new critical vulnerabilities before merge.

## Workflow rules (prevent duplicate pipelines)

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never    # Suppress branch pipeline when MR exists
    - if: $CI_COMMIT_BRANCH
```

## Notable features by version

### 18.7
- **CI/CD Catalog GA**: searchable registry of reusable CI/CD components; versioned with semantic versioning; consumable via `include: { component: ... }`.
- **Pipeline execution policies**: group-level mandatory CI/CD jobs that project maintainers cannot override; used for enforcing security scans and compliance checks (GitLab Ultimate).
- **Job token scope improvements**: `CI_JOB_TOKEN` default scope restricted to the current project; cross-project access requires explicit allowlisting.
- **Runner fleet visibility dashboard**: fleet-wide utilisation metrics, queue wait time, and runner version distribution.

### 18.8
- **CI Steps (beta)**: typed, reusable units of work with defined inputs/outputs; compose steps within jobs using `steps:` keyword; steps are versioned and shareable via the CI/CD Catalog.
- **Component testing framework**: tooling for testing CI/CD components before publishing (`gitlab-ci-component-test`).
- **Kubernetes executor enhancements**: topology spread constraints, resource request auto-tuning, ephemeral volume support, improved orphaned pod cleanup.

### 18.9
- **CI Steps (maturing)**: output passing between steps; step-level retry and timeout; conditional step execution; local step definitions.
- **Conditional includes**: `include:` directives support `rules:` for including components only when conditions are met.
- **Advanced caching**: distributed cache shared across runners via object storage (S3/GCS); configurable compression (gzip, zstd, none); cache hit/miss metrics.
- **Security policy automation**: auto-remediation policies; policy-as-code in `.gitlab/security-policies/`; expanded scan result filtering.

## MCP pipeline operations (via the GitLab MCP server)

When a GitLab MCP server is available, the following operations are supported for monitoring and pipeline management. All write operations require explicit operator confirmation before invocation.

**Read operations:**

| Operation | Tool | Key parameters |
|---|---|---|
| List pipelines | `list_pipelines` | `project_id`, `status`, `ref` |
| Get pipeline details | `get_pipeline` | `project_id`, `pipeline_id` |
| List pipeline jobs | `get_pipeline_jobs` | `project_id`, `pipeline_id` |
| Get job log | `get_pipeline_job_log` | `project_id`, `job_id` |

**Write operations (require confirmation):**

| Operation | Tool | Precondition |
|---|---|---|
| Trigger new pipeline | `create_pipeline` | Verify branch exists; confirm with operator |
| Retry failed pipeline | `retry_pipeline` | Confirm pipeline is in failed state; confirm with operator |
| Cancel running pipeline | `cancel_pipeline` | Verify pipeline is running; confirm with operator |

Credential safety: never expose personal access tokens in logs, comments, or error messages. Tokens are passed via environment variable (`GITLAB_PERSONAL_ACCESS_TOKEN`), not inline in tool parameters.
