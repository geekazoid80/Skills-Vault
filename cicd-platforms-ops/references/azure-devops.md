# Azure DevOps Pipelines

Azure DevOps is Microsoft's integrated DevOps platform providing Boards, Repos, Pipelines, Test Plans, and Artifacts. This reference covers Azure Pipelines (the CI/CD component). Configuration is via `azure-pipelines.yml` for YAML pipelines (preferred) or the classic GUI.

## YAML pipeline structure

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include:
      - main
  paths:
    exclude:
      - docs/**

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: production-vars       # Variable group from library
  - name: buildConfiguration
    value: 'Release'

stages:
  - stage: Build
    jobs:
      - job: BuildJob
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '22.x'
          - script: |
              npm ci
              npm run build
            displayName: 'Build application'
          - publish: $(System.DefaultWorkingDirectory)/dist
            artifact: webapp

  - stage: Deploy
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployProd
        environment: production
        strategy:
          runOnce:
            deploy:
              steps:
                - download: current
                  artifact: webapp
                - task: AzureWebApp@1
                  inputs:
                    appName: 'myapp'
                    package: '$(Pipeline.Workspace)/webapp'
```

## Core concepts

| Concept | Description |
|---|---|
| Trigger | When the pipeline runs (push, PR, schedule, manual) |
| Pool | Where jobs run (Microsoft-hosted or self-hosted agents) |
| Stage | Major pipeline division (Build, Test, Deploy) |
| Job | Work unit that runs on a single agent |
| Deployment job | Special job type with environment tracking and deployment strategy |
| Step | Individual task, script, or checkout |
| Task | Pre-built action from the Marketplace (`AzureWebApp@1`, `NodeTool@0`) |
| Variable group | Shared variables across pipelines; can be linked to Azure Key Vault |
| Service connection | Authentication to external services (Azure, AWS, Docker, GitHub, Kubernetes) |
| Environment | Deployment target with approvals, gates, history, and resource tracking |

## Triggers

```yaml
# CI trigger (push)
trigger:
  branches:
    include: [main, release/*]
  paths:
    include: [src/**]
  tags:
    include: [v*]

# PR trigger
pr:
  branches:
    include: [main]
  paths:
    include: [src/**]

# Scheduled trigger
schedules:
  - cron: '0 2 * * *'
    displayName: 'Nightly build'
    branches:
      include: [main]
    always: false    # Only run if code changed since last scheduled run

# Disable CI trigger (manual only)
trigger: none
```

## Agent pools

| Pool type | Description | Use case |
|---|---|---|
| Microsoft-hosted | Fresh managed VMs, cleaned after each job | Default for most workloads |
| Self-hosted | Your infrastructure | Private network, custom tools, compliance requirements |
| VMSS agents | Azure VM Scale Set with autoscaling | Cost-effective self-hosted at scale |
| Container agents | Docker or Kubernetes-based | Lightweight, fast provisioning |

Microsoft-hosted images: `ubuntu-latest`, `ubuntu-22.04`, `windows-latest`, `macOS-latest`.

## Templates and reuse

Azure DevOps supports four levels of YAML templates:

| Level | Templates | Example |
|---|---|---|
| Step | Individual steps within a job | Build steps, test steps |
| Job | Entire job definition | Build job, test matrix |
| Stage | Entire stage with multiple jobs | Deploy stage with approvals |
| Pipeline | Full pipeline via `extends:` | Organisation-standard pipeline |

```yaml
# templates/build-template.yml
parameters:
  - name: nodeVersion
    type: string
    default: '22'
  - name: buildCommand
    type: string
    default: 'npm run build'

steps:
  - task: NodeTool@0
    inputs:
      versionSpec: '${{ parameters.nodeVersion }}'
  - script: npm ci
    displayName: 'Install dependencies'
  - script: ${{ parameters.buildCommand }}
    displayName: 'Build'
```

```yaml
# azure-pipelines.yml (consuming the template)
stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - template: templates/build-template.yml
            parameters:
              nodeVersion: '22'
```

### Extending from a template (full pipeline)

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: MyOrg/pipeline-templates

extends:
  template: standard-pipeline.yml@templates
  parameters:
    buildSteps:
      - script: npm run build
```

`extends:` enables organisation-wide pipeline standards enforced via required template checks.

## Deployment strategies

```yaml
# Rolling deployment
strategy:
  rolling:
    maxParallel: 2
    deploy:
      steps:
        - script: deploy.sh

# Canary deployment
strategy:
  canary:
    increments: [10, 20, 50]
    deploy:
      steps:
        - script: deploy.sh
    on:
      success:
        steps:
          - script: verify.sh
      failure:
        steps:
          - script: rollback.sh

# Simple single-run deployment
strategy:
  runOnce:
    deploy:
      steps:
        - script: deploy.sh
```

## Environments and approvals

Environments are configured in the Azure DevOps portal (Pipelines > Environments). The pipeline references the environment by name:

```yaml
- deployment: DeployProd
  environment: production
```

Approval and gate types configurable in the environment settings:

- Manual approval (required reviewers with optional instructions)
- Business hours gate
- Azure Monitor alerts gate
- REST API check
- Required template (enforce pipeline template)
- Branch control (restrict which branches can deploy)

Deployment history, rollback links, and resource tracking (Kubernetes, virtual machines) are available per environment.

## Service connections

| Type | Auth method | Use case |
|---|---|---|
| Azure Resource Manager | Service principal, managed identity, workload identity federation | Deploy to Azure |
| Docker Registry | Username/password, service principal | Push/pull container images |
| GitHub | PAT, OAuth, GitHub App | Access GitHub repositories |
| Kubernetes | Kubeconfig, service account | Deploy to Kubernetes |
| SSH | Private key | Deploy to Linux servers |
| Generic | Username/password, token | Custom integrations |

**Best practice**: use workload identity federation (OIDC) for Azure Resource Manager service connections. No client secrets to rotate; credentials are short-lived and scoped to the pipeline run.

## Variable scoping and syntax

Azure DevOps uses three distinct expression syntaxes:

```yaml
# Compile-time (template parameters; available during YAML parsing)
${{ variables.myVar }}

# Runtime macro (most common; expanded before the step runs)
$(myVar)

# Runtime expression (conditions and dependencies)
$[variables.myVar]
```

Variable scopes (narrowest wins): step variables > job variables > stage variables > pipeline variables > variable group.

## Output variables

```yaml
# Producer job
- script: echo "##vso[task.setvariable variable=myOutput;isOutput=true]value"
  name: stepName    # Must have a name to reference

# Consumer job (same stage)
variables:
  myVar: $[ dependencies.ProducerJob.outputs['stepName.myOutput'] ]

# Consumer job (different stage)
variables:
  myVar: $[ stageDependencies.BuildStage.ProducerJob.outputs['stepName.myOutput'] ]
```

## Key predefined variables

| Variable | Value |
|---|---|
| `Build.SourceBranch` | `refs/heads/main` or `refs/pull/123/merge` |
| `Build.SourceBranchName` | `main` |
| `Build.SourceVersion` | Commit SHA |
| `Build.BuildId` | Unique build ID |
| `Build.Reason` | `IndividualCI`, `PullRequest`, `Schedule`, `Manual` |
| `System.DefaultWorkingDirectory` | Agent working directory |
| `Pipeline.Workspace` | Pipeline workspace directory |
| `Agent.OS` | `Linux`, `Windows_NT`, `Darwin` |

## Artifacts feeds

Azure Artifacts provides hosted package feeds for npm, NuGet, Maven, Python, and Cargo packages. Pipelines can publish to and restore from Artifacts feeds as part of the build and deploy lifecycle. Feeds integrate with upstream sources (npmjs.com, nuget.org, PyPI) for proxy and caching.

## CLI operations

```bash
# List pipeline runs
az pipelines runs list --org https://dev.azure.com/myorg --project myproject

# Show run details
az pipelines runs show --id 123 --org https://dev.azure.com/myorg --project myproject

# Trigger a run
az pipelines run --name "My Pipeline" --branch main --org https://dev.azure.com/myorg --project myproject
```
