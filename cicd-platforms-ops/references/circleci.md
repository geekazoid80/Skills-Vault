# CircleCI

CircleCI is a managed CI/CD platform optimised for fast builds and Docker-native workflows. Configuration is via `.circleci/config.yml`. CircleCI ships updates continuously as a managed service.

## Config structure

```yaml
# .circleci/config.yml
version: 2.1

orbs:
  node: circleci/node@6.0
  aws-cli: circleci/aws-cli@4.0

executors:
  node-executor:
    docker:
      - image: cimg/node:22.0
    resource_class: medium

jobs:
  build:
    executor: node-executor
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run:
          name: Build application
          command: npm run build
      - persist_to_workspace:
          root: .
          paths: [dist]

  test:
    executor: node-executor
    parallelism: 4
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run:
          name: Run tests (split by timing)
          command: |
            circleci tests glob "test/**/*.test.ts" | \
            circleci tests split --split-by=timings | \
            xargs npm test --

  deploy:
    executor: node-executor
    steps:
      - attach_workspace:
          at: .
      - aws-cli/setup
      - run:
          name: Deploy
          command: ./deploy.sh

workflows:
  build-test-deploy:
    jobs:
      - build
      - test:
          requires: [build]
      - deploy:
          requires: [test]
          filters:
            branches:
              only: main
          context: production-aws
```

## Executors

| Executor | Isolation | Use case |
|---|---|---|
| Docker | Container | Most builds, fast startup |
| Machine | Full Linux VM | Docker-in-Docker, kernel access, Docker layer caching |
| macOS | macOS VM | iOS/macOS builds |
| Windows | Windows VM | .NET, Windows-specific builds |
| ARM | ARM VM | ARM architecture builds |
| Self-hosted runner | Your infrastructure | Private networks, custom hardware, compliance |

## Resource classes

| Class | vCPU | RAM | Credits/min |
|---|---|---|---|
| `small` | 1 | 2 GB | 5 |
| `medium` | 2 | 4 GB | 10 |
| `medium+` | 3 | 6 GB | 15 |
| `large` | 4 | 8 GB | 20 |
| `xlarge` | 8 | 16 GB | 40 |
| `2xlarge` | 16 | 32 GB | 80 |

Choose the smallest class that keeps the job within the time budget. Parallel test splitting is usually more cost-effective than upgrading the resource class.

## Orbs (reusable packages)

Orbs are shareable packages of CircleCI configuration (commands, jobs, executors). They are versioned and published to the CircleCI Orb Registry.

```yaml
orbs:
  node: circleci/node@6.0           # Node.js setup and caching
  docker: circleci/docker@2.0        # Docker build and push
  aws-cli: circleci/aws-cli@4.0      # AWS CLI setup
  kubernetes: circleci/kubernetes@1.0 # kubectl setup
  slack: circleci/slack@4.0           # Slack notifications
  terraform: circleci/terraform@3.0   # Terraform CLI

# Orb commands handle common patterns with built-in caching
jobs:
  build:
    docker:
      - image: cimg/base:current
    steps:
      - checkout
      - node/install-packages    # Orb command with dependency caching
```

Pin orbs to a specific version (`circleci/node@6.0`, not `circleci/node@latest`) to avoid breaking changes from upstream updates.

## Caching

```yaml
steps:
  - restore_cache:
      keys:
        - deps-v1-{{ checksum "package-lock.json" }}   # Exact match
        - deps-v1-                                     # Fallback prefix match
  - run: npm ci
  - save_cache:
      key: deps-v1-{{ checksum "package-lock.json" }}
      paths:
        - node_modules
```

Cache keys expire after 15 days. Caches are branch-scoped with fallback to the default branch. Version your cache keys (`v1-`, `v2-`) to bust stale caches without waiting for expiry.

### Docker Layer Caching (DLC)

DLC caches individual Docker build layers between runs. It requires the `machine` executor (or `setup_remote_docker` with the DLC feature). This is a premium feature billed per DLC run.

```yaml
jobs:
  build-image:
    machine:
      image: ubuntu-2404:current
      docker_layer_caching: true
    steps:
      - checkout
      - run: docker build -t myapp .
```

## Workspaces (passing files between jobs)

Workspaces persist files between jobs within the same workflow run. Unlike caches, workspaces are per-workflow, not shared across runs.

```yaml
jobs:
  build:
    steps:
      - run: npm run build
      - persist_to_workspace:
          root: .
          paths: [dist, package.json]

  deploy:
    steps:
      - attach_workspace:
          at: .    # Restores dist/ and package.json from build job
      - run: ./deploy.sh
```

## Parallelism and test splitting

```yaml
jobs:
  test:
    parallelism: 4    # Run 4 containers in parallel
    steps:
      - checkout
      - run:
          name: Split and run tests
          command: |
            TESTS=$(circleci tests glob "spec/**/*_spec.rb" | \
                    circleci tests split --split-by=timings)
            bundle exec rspec $TESTS
      - store_test_results:
          path: test-results    # Upload results to improve future timing splits
```

Test splitting by historical timing (wall-clock time per test file) produces an evenly balanced split across parallel containers, minimising the longest-running container's time.

## Contexts (shared secrets)

Contexts are named groups of environment variables scoped to an organisation or project. They can be restricted to specific branches or security groups.

```yaml
workflows:
  deploy:
    jobs:
      - deploy:
          context:
            - aws-production     # Injects AWS credentials
            - slack-notifications
```

## Pipeline parameters

```yaml
# Declare pipeline-level parameters
parameters:
  deploy_env:
    type: string
    default: staging

jobs:
  deploy:
    steps:
      - run: echo "Deploying to << pipeline.parameters.deploy_env >>"
```

Trigger a parameterised pipeline via the API:

```bash
curl -X POST "https://circleci.com/api/v2/project/gh/org/repo/pipeline" \
  -H "Circle-Token: $CIRCLECI_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"parameters": {"deploy_env": "production"}}'
```

## Approval jobs (manual gates)

```yaml
workflows:
  deploy:
    jobs:
      - test
      - hold-for-approval:
          type: approval
          requires: [test]
      - deploy:
          requires: [hold-for-approval]
          filters:
            branches:
              only: main
```

An approval job pauses the workflow until a user approves via the CircleCI UI or API. Only then does the downstream job (deploy) become eligible to run.

## Dynamic config

Dynamic config allows a setup workflow to generate and execute a secondary pipeline config at runtime. Used for monorepo path-based builds:

```yaml
# .circleci/config.yml (setup workflow)
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1.0

jobs:
  generate-config:
    executor: ...
    steps:
      - checkout
      - run: ./scripts/generate-config.sh > /tmp/generated-config.yml
      - continuation/run:
          configuration_path: /tmp/generated-config.yml
```

## OIDC authentication

CircleCI supports OIDC tokens via contexts. The `$CIRCLE_OIDC_TOKEN` environment variable is available in jobs that use an OIDC-enabled context. Use this to assume cloud roles without storing static credentials.

## CLI reference

```bash
# Validate config locally
circleci config validate

# Run a job locally
circleci local execute --job build

# Process config (expand orbs and parameters)
circleci config process .circleci/config.yml

# Test splitting
circleci tests glob "test/**/*.test.ts"
circleci tests split --split-by=timings < test-files.txt
```
