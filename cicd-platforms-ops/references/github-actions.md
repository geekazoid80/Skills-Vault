# GitHub Actions

GitHub Actions is a managed CI/CD platform integrated into GitHub. Workflow configuration lives in `.github/workflows/` as YAML files. GitHub ships platform updates continuously; there is no discrete version to pin.

For focused GitHub Actions recipes (changelog automation, mkdocs strict staging, `gh run list` as a Checks substitute) see the vault skill `gh-actions-ci`.

## Workflow structure

```yaml
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Least-privilege: set restrictive default, override per job
permissions:
  contents: read

env:
  NODE_VERSION: '22'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
      - run: npm ci
      - run: npm test
      - run: npm run build
```

## Events and triggers

| Event | When | Key options |
|---|---|---|
| `push` | Code pushed | `branches`, `tags`, `paths`, `paths-ignore` |
| `pull_request` | PR opened or updated | `branches`, `types` (opened, synchronize, closed) |
| `workflow_dispatch` | Manual trigger | `inputs` (typed parameters) |
| `schedule` | Cron (UTC) | `cron` expression |
| `release` | GitHub release created | `types` (published, created) |
| `workflow_call` | Called by another workflow | `inputs`, `outputs`, `secrets` |
| `repository_dispatch` | API webhook | `types` (custom event types) |

## Runner types

| Runner | OS | Use case |
|---|---|---|
| `ubuntu-latest` | Ubuntu 24.04 | Default for most workloads |
| `ubuntu-22.04` | Ubuntu 22.04 | Specific OS version |
| `windows-latest` | Windows Server 2022 | .NET, PowerShell |
| `macos-latest` | macOS (Sequoia) | iOS, macOS builds |
| `self-hosted` | Any | Private network, GPU, custom tools, private registries |

**Cost multipliers**: Linux is 1x; Windows is 2x; macOS is 10x. Default to Linux runners unless the workload specifically requires Windows or macOS.

## Permissions (GITHUB_TOKEN)

Always declare least-privilege permissions at the workflow level and override per job:

```yaml
# Workflow-level default
permissions:
  contents: read

jobs:
  deploy:
    permissions:
      contents: read
      id-token: write       # OIDC for cloud auth
      packages: write       # Push container images
      pull-requests: write  # Comment on PRs
```

Setting `permissions:` at the workflow level disables the default read-write `GITHUB_TOKEN` for jobs that do not override it. Always include this block.

## Matrix builds

```yaml
jobs:
  test:
    strategy:
      fail-fast: false          # See all failures, not just the first
      matrix:
        os: [ubuntu-latest, windows-latest]
        node: [20, 22]
        exclude:
          - os: windows-latest
            node: 20
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - run: npm ci && npm test
```

## Caching

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      npm-${{ runner.os }}-
```

Many setup actions have built-in caching; prefer those over `actions/cache` directly:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 22
    cache: 'npm'    # Built-in npm/yarn/pnpm cache handling
```

**Cache limits**: 10 GB per repository; caches not accessed in 7 days are evicted. Older caches are evicted first when the limit is reached.

## Artifacts

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: build-output
    path: dist/
    retention-days: 7

# In a subsequent job
- uses: actions/download-artifact@v4
  with:
    name: build-output
    path: dist/
```

## OIDC to cloud (keyless authentication)

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
      aws-region: ap-southeast-1
      # No static credentials; OIDC federation issues temporary credentials
```

Configure the IAM role's trust policy to match `token.actions.githubusercontent.com` as the OIDC issuer and scope by `sub` claim (`repo:org/repo:ref:refs/heads/main`).

## Reusable workflows

```yaml
# .github/workflows/reusable-deploy.yml
on:
  workflow_call:
    inputs:
      environment:
        required: true
        type: string
    secrets:
      deploy_key:
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - run: echo "Deploying to ${{ inputs.environment }}"

# Caller workflow
jobs:
  deploy-staging:
    uses: ./.github/workflows/reusable-deploy.yml
    with:
      environment: staging
    secrets:
      deploy_key: ${{ secrets.DEPLOY_KEY }}
```

Reusable workflows are called with `uses:` at the job level (not the step level). They can be in the same repository or another repository.

## Composite actions

Local, reusable action bundled with the repository:

```yaml
# .github/actions/setup-project/action.yml
name: Setup Project
description: Install dependencies and build
inputs:
  node-version:
    default: '22'
runs:
  using: composite
  steps:
    - uses: actions/setup-node@v4
      with:
        node-version: ${{ inputs.node-version }}
        cache: 'npm'
    - run: npm ci
      shell: bash
```

Called from any workflow step with `uses: ./.github/actions/setup-project`.

## Environments and approval gates

```yaml
jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://myapp.example.com
    steps:
      - run: ./deploy.sh
```

Configure protection rules in GitHub Settings > Environments:

- Required reviewers (named users or teams)
- Wait timer before deployment begins
- Deployment branch or tag policies
- Custom deployment protection rules (via webhook)

## Concurrency control

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true    # Cancel previous run on same branch/PR
```

Use `cancel-in-progress: false` for deploy jobs where an in-flight production deploy should not be cancelled by a new push.

## Expression language

```yaml
# Context variables
${{ github.sha }}                          # Full commit SHA
${{ github.ref_name }}                     # Branch or tag name
${{ github.actor }}                        # User who triggered
${{ github.event.pull_request.number }}    # PR number
${{ runner.os }}                           # Linux / Windows / macOS

# Functions
${{ contains(github.event.head_commit.message, '[skip ci]') }}
${{ startsWith(github.ref, 'refs/tags/v') }}
${{ hashFiles('**/package-lock.json') }}
${{ toJSON(matrix) }}

# Status checks (in if: conditions)
if: ${{ success() }}
if: ${{ failure() }}
if: ${{ always() }}
if: ${{ cancelled() }}
```

## Security best practices

**Pin actions to SHA, not tag**:

```yaml
# Risk: tag can be silently moved to point to malicious code
- uses: actions/checkout@v4

# Safe: SHA is immutable
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

Use Dependabot or Renovate to keep SHA pins updated automatically (`.github/dependabot.yml` with `package-ecosystem: github-actions`).

**Fork safety**:

- `pull_request` events from forks cannot access repository secrets by design.
- Never combine `pull_request_target` with `actions/checkout` of PR code plus secret access. This is a known privilege-escalation path that allows a fork PR to access production secrets.
- Require approval for first-time contributors before their workflow runs.

**Secret hygiene in workflows**:

- Use environment-scoped secrets for deployment credentials; restrict access to the environment.
- Never echo or print secrets, even in debug steps.
- Use `echo "::add-mask::$SECRET"` if a computed value (derived from a secret) appears in log output.
- Prefer OIDC over static credentials for cloud providers.

## Workflow organisation

```
.github/
  workflows/
    ci.yml              # Main CI pipeline
    deploy.yml          # Deployment pipeline
    release.yml         # Release automation
    _reusable-*.yml     # Reusable workflows (prefix convention)
  actions/
    setup-project/      # Composite actions
      action.yml
  dependabot.yml
```

## Monorepo patterns

```yaml
on:
  push:
    paths:
      - 'services/api/**'
      - 'libs/shared/**'    # Also trigger on shared library changes
```

Dynamic matrix from changed files using `dorny/paths-filter` or similar allows building only the services that changed, rather than the entire monorepo on every push.

## Path-based skipping

```yaml
on:
  push:
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.gitignore'
```
