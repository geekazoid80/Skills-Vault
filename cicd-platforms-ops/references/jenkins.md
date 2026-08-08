# Jenkins

Jenkins is the most widely deployed self-hosted CI/CD automation server. It is open source, extensible through 1800+ plugins, and supports any SCM. Pipeline configuration is via `Jenkinsfile` (Groovy DSL) stored in the repository. Current LTS is 2.541+.

## Declarative pipeline

Declarative is the recommended syntax for new pipelines. It is structured, validated before execution, and supports stage-level restarts.

```groovy
// Jenkinsfile (Declarative)
pipeline {
    agent {
        docker {
            image 'node:22'
            args '-v /tmp:/tmp'
        }
    }

    environment {
        CI = 'true'
        DEPLOY_CREDS = credentials('deploy-credentials')
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        retry(2)
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    triggers {
        pollSCM('H/5 * * * *')
    }

    stages {
        stage('Build') {
            steps {
                sh 'npm ci'
                sh 'npm run build'
            }
        }

        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'npm run test:unit'
                    }
                }
                stage('Integration Tests') {
                    steps {
                        sh 'npm run test:integration'
                    }
                }
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            input {
                message 'Deploy to production?'
                ok 'Deploy'
                submitter 'ops-team'
            }
            steps {
                sh './deploy.sh'
            }
        }
    }

    post {
        always {
            junit '**/test-results/*.xml'
            archiveArtifacts artifacts: 'dist/**', fingerprint: true
        }
        failure {
            mail to: 'team@example.com',
                 subject: "Failed: ${currentBuild.fullDisplayName}",
                 body: "Build failed: ${env.BUILD_URL}"
        }
        cleanup {
            cleanWs()
        }
    }
}
```

## Scripted pipeline

Scripted pipeline offers full Groovy flexibility when Declarative constraints are too restrictive. Use it sparingly; Declarative is preferred.

```groovy
// Jenkinsfile (Scripted)
node('linux') {
    try {
        stage('Checkout') {
            checkout scm
        }

        stage('Build') {
            sh 'npm ci && npm run build'
        }

        stage('Test') {
            parallel(
                'Unit': { sh 'npm run test:unit' },
                'E2E':  { sh 'npm run test:e2e' }
            )
        }

        stage('Deploy') {
            if (env.BRANCH_NAME == 'main') {
                input 'Deploy to production?'
                sh './deploy.sh'
            }
        }

    } catch (e) {
        currentBuild.result = 'FAILURE'
        throw e
    } finally {
        junit '**/test-results/*.xml'
        cleanWs()
    }
}
```

## Declarative vs Scripted

| Aspect | Declarative | Scripted |
|---|---|---|
| Syntax | Structured, opinionated | Free-form Groovy |
| Learning curve | Lower | Higher (requires Groovy knowledge) |
| Flexibility | Limited (use `script {}` blocks for Groovy) | Unlimited |
| Validation | Validated before execution | Fails at runtime |
| Stage-level restart | Supported (CloudBees) | Not supported |
| Recommendation | Default for new pipelines | When Declarative is too restrictive |

## Agent configuration

```groovy
// Any available agent
agent any

// Agent with label
agent { label 'linux && docker' }

// Docker container
agent {
    docker {
        image 'maven:3.9-eclipse-temurin-21'
        label 'docker-capable'
        args '-v $HOME/.m2:/root/.m2'
    }
}

// Kubernetes pod
agent {
    kubernetes {
        yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          containers:
          - name: maven
            image: maven:3.9
            command: ['sleep', '99d']
          - name: docker
            image: docker:latest
            command: ['sleep', '99d']
        '''
    }
}

// No default agent; allocate per stage
agent none
```

## Agent labels

Labels organise agents by capability. Assign labels when registering an agent; match labels in the pipeline:

| Label example | Meaning |
|---|---|
| `linux` | Linux OS |
| `windows` | Windows OS |
| `docker` | Docker available on the host |
| `gpu` | GPU available |
| `large` | High-resource node |
| `zone-a` | Specific network segment |

## Shared libraries

Shared libraries provide reusable Groovy code (global variables and classes) across all pipelines that reference the library. Libraries are stored in a separate Git repository.

```
shared-library/
  vars/
    buildApp.groovy       # Global variable callable as buildApp()
    deployApp.groovy
  src/
    com/myorg/
      Pipeline.groovy     # Class library
  resources/
    templates/            # Non-Groovy static files
```

```groovy
// vars/buildApp.groovy
def call(Map config = [:]) {
    pipeline {
        agent { label config.agent ?: 'linux' }
        stages {
            stage('Build') {
                steps { sh "${config.buildCommand ?: 'make build'}" }
            }
            stage('Test') {
                steps { sh "${config.testCommand ?: 'make test'}" }
            }
        }
    }
}
```

```groovy
// Consumer Jenkinsfile
@Library('my-shared-library@main') _

buildApp(
    agent: 'docker',
    buildCommand: 'npm run build',
    testCommand: 'npm test'
)
```

Register the shared library under Manage Jenkins > Configure System > Global Pipeline Libraries.

## Credentials management

```groovy
// Username and password
withCredentials([usernamePassword(
    credentialsId: 'dockerhub',
    usernameVariable: 'DOCKER_USER',
    passwordVariable: 'DOCKER_PASS'
)]) {
    sh 'docker login -u $DOCKER_USER -p $DOCKER_PASS'
}

// SSH key
withCredentials([sshUserPrivateKey(
    credentialsId: 'deploy-key',
    keyFileVariable: 'SSH_KEY'
)]) {
    sh 'ssh -i $SSH_KEY user@server deploy.sh'
}

// Secret text (API token)
withCredentials([string(
    credentialsId: 'api-token',
    variable: 'API_TOKEN'
)]) {
    sh 'curl -H "Authorization: Bearer $API_TOKEN" https://api.example.com'
}

// Secret file (kubeconfig)
withCredentials([file(
    credentialsId: 'kubeconfig',
    variable: 'KUBECONFIG'
)]) {
    sh 'kubectl get pods'
}
```

Credentials are stored in the Jenkins credential store and injected at runtime. They are masked in logs automatically. Use the Credentials Binding plugin for all secret access; never hardcode credentials or pass them as plain string parameters.

## Key plugins

| Plugin | Purpose |
|---|---|
| Pipeline | Jenkinsfile support (Declarative + Scripted) |
| Git | Git SCM integration |
| Docker Pipeline | Docker agent and build support |
| Kubernetes | Kubernetes pod-based agents |
| Credentials Binding | Inject credentials into builds |
| Blue Ocean | Modern pipeline visualisation UI |
| Pipeline Utility Steps | readJSON, writeJSON, readYaml, zip/unzip |
| Warnings Next Generation | Static analysis result aggregation |
| JUnit | Test result reporting |
| Timestamper | Timestamps on console output |
| Build Discarder | Automatic old build cleanup |
| Role Strategy | Fine-grained RBAC |
| Matrix Authorization | Per-project permissions |
| OWASP Dependency-Check | Dependency vulnerability scanning |

## Multibranch pipelines

A multibranch pipeline automatically discovers branches and pull requests in a repository and creates a pipeline for each. Configuration is via the branch-specific `Jenkinsfile`. Status is tracked per branch. Deleted branches are pruned automatically.

## MCP job and build operations (via the Jenkins MCP server)

When a Jenkins MCP server is available, the following operations are supported. All write operations require explicit operator confirmation before invocation. The MCP server is a Jenkins plugin running natively inside Jenkins via Streamable HTTP transport.

**Read operations:**

| Operation | Tool | Key parameters |
|---|---|---|
| List all jobs | `getJobs` | `nameFilter` (regex), `offset`, `limit` |
| Get job details | `getJob` | `fullName` (supports folder paths: `folder/job-name`) |
| Get build details | `getBuild` | `jobFullName`, `buildNumber` |
| Check queue item | `getQueueItem` | `queueId` |
| View pipeline run history | `getPipelineRuns` | `jobFullName` |
| Retrieve build log | `getBuildLog` | `jobFullName`, `buildNumber`, `start` (byte offset for pagination) |
| Search log by pattern | `searchBuildLog` | `jobFullName`, `buildNumber`, `pattern` (regex) |
| Get pipeline-specific log | `getPipelineRunLog` | `jobFullName`, `runId` |
| Get job SCM configuration | `getJobScm` | `jobFullName` |
| Get build SCM details | `getBuildScm` | `jobFullName`, `buildNumber` |
| List changesets (commits) | `getBuildChangeSets` | `jobFullName`, `buildNumber` |
| Find jobs by repository | `findJobsWithScmUrl` | `scmUrl` |
| Verify authentication | `whoAmI` | (none) |
| Check instance health | `getStatus` | (none) |

**Write operations (require confirmation):**

| Operation | Tool | Precondition |
|---|---|---|
| Trigger a build | `triggerBuild` | Verify job exists via `getJob`; confirm parameters with operator; returns queue item ID |
| Update build metadata | `updateBuild` | Confirm with operator; set display name or `keepLog: true` |

**Workflow for build triggering**: always call `getJob` first to confirm the job exists and inspect its parameter definitions (String, Boolean, Choice, Text, Password, Run types). Present parameters and proposed values to the operator for confirmation before calling `triggerBuild`. Track the queue item via `getQueueItem` until the build starts, then monitor with `getBuild`.

**Log retrieval discipline**: for large logs (hundreds of MB on verbose builds), call `searchBuildLog` with a pattern (`ERROR|FATAL|Exception|FAILURE|timeout`) before retrieving the full log. Use the `start` byte-offset parameter to paginate through large logs.

**Folder-aware job names**: Jenkins jobs in folders use path notation (`folder1/folder2/job-name`). Always pass the full folder path.

**Credential safety**: never log or display raw API tokens. Credentials are managed via environment variables, not passed inline.
