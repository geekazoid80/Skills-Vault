# CI/CD diagnostics

Cross-platform troubleshooting reference. For platform-specific deep dives, check the relevant reference file after triaging the failure category here.

## Triage flow

```
Pipeline failed or not triggered?
  Not triggered  -> check trigger config, YAML syntax, branch filters
  Failed build   -> check build logs, dependency installation, tool versions
  Failed test    -> check test output, service availability, flakiness
  Failed deploy  -> check credentials/OIDC, environment gates, target availability
  Runner offline -> check runner/agent status, network, registration
  Cache miss     -> check cache key, expiry, storage backend
```

## Pipeline not triggering

**Diagnosis checklist:**

1. Is the config file in the right location and on the right branch?
   - GitHub Actions: `.github/workflows/*.yml` on the branch receiving the event
   - GitLab CI: `.gitlab-ci.yml` in the repository root
   - Jenkins: `Jenkinsfile` in the repository root (or custom path configured on the job)
   - Azure DevOps: `azure-pipelines.yml` (or configured path) on the target branch
   - CircleCI: `.circleci/config.yml`

2. Is there a YAML syntax error?
   - GitHub Actions: check the Actions tab for workflow registration errors
   - GitLab CI: use CI Lint (`gitlab-ci-lint .gitlab-ci.yml` or the CI Lint API)
   - Azure DevOps: use the pipeline validation button in the UI
   - CircleCI: `circleci config validate`

3. Do the branch/path/tag filters match the actual event?
   - Double-check `branches:`, `tags:`, `paths:` filters; they are case-sensitive
   - GitLab CI: verify `rules:` conditions against `$CI_COMMIT_BRANCH`, `$CI_COMMIT_TAG`, `$CI_PIPELINE_SOURCE`
   - Azure DevOps: separate `trigger:` (push) and `pr:` (pull request) blocks; they are independent

4. Is the workflow or pipeline disabled?
   - GitHub Actions: check Settings > Actions for disabled workflows
   - GitLab CI: check Settings > CI/CD > General Pipelines for disabled state
   - Jenkins: check the job's disabled flag on the configure page

5. GitLab CI duplicate pipelines: use `workflow:rules` to suppress branch pipelines when a merge request pipeline is running for the same commit.

## Build failures

### Dependency installation fails

- Check that the package manager lock file is committed and matches the manifest.
- Cache keys must include the lock file hash. A corrupted or stale cache can produce a mix of old and new packages; bust the cache by incrementing the version prefix (`v1-` to `v2-`).
- For private registries: verify credentials are injected correctly and the registry hostname is reachable from the runner.

### Tool version mismatch

- Pin all tool versions explicitly in the config. Never rely on `latest` or the default version installed on the host runner.
- GitHub Actions: use the appropriate `setup-*` action with an explicit version (`node-version: '22'`).
- GitLab CI: set `image:` explicitly at the job level.
- Azure DevOps: use the tool installer task (`NodeTool@0`) with `versionSpec`.

### Compilation or build errors

Read the full build output. Look for:

- Missing environment variables (check if the variable is defined at the right scope)
- Missing files from a previous job (check artifacts/workspace setup)
- Network access to external registries or APIs (runner may be in a private network)

## Test failures

### Flaky tests

- Re-run the failed job a second time. If it passes, the test is non-deterministic.
- Check for race conditions, shared state, or order-dependent tests.
- Isolate the flaky test and run it in isolation to confirm.
- Add retries at the test level (platform-specific test runner retry flags) for genuinely flaky external dependencies.

### Service container not ready

When using database or cache service containers, the CI job starts before the service is fully initialised. Add a readiness check:

```yaml
# GitLab CI example
before_script:
  - apt-get update && apt-get install -y postgresql-client
  - until pg_isready -h postgres -U runner; do sleep 1; done

# GitHub Actions example
services:
  postgres:
    image: postgres:16
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
```

### Test timeout

- Increase the job timeout or parallelise the test suite.
- Use test splitting to distribute the test suite across multiple runner instances.
- Profile which tests are slowest and optimise or parallelise them.

## Runner / agent offline or capacity issues

### Runner not picking up jobs

**GitHub Actions self-hosted runner:**

```bash
# Check runner status
gh api repos/{owner}/{repo}/actions/runners

# Restart runner service
sudo ./svc.sh stop && sudo ./svc.sh start

# Re-register (if token expired)
./config.sh remove --token <REMOVE_TOKEN>
./config.sh --url https://github.com/org/repo --token <REG_TOKEN>
```

**GitLab runner:**

```bash
gitlab-runner list
gitlab-runner verify
gitlab-runner status
gitlab-runner restart
```

Check that the runner's tags match the tags specified in the job. A runner with no tags only picks up jobs with no tags. A runner with tags only picks up jobs that explicitly request those tags.

**Jenkins agent offline:**

1. Check the agent process on the host (`ps aux | grep remoting.jar` for SSH agents; `ps aux | grep agent.jar` for JNLP agents).
2. Verify network connectivity between the Jenkins controller and the agent.
3. Check agent logs at `$JENKINS_HOME/logs/slaves/<agent-name>/`.
4. For JNLP agents: restart with `java -jar agent.jar -url https://jenkins.example.com -secret <SECRET> -name <NAME>`.

**Azure DevOps agent:**

1. Check the agent pool in Organization Settings > Agent Pools.
2. Verify the agent is online, not paused, and not disabled.
3. Check job demands match agent capabilities.
4. Run `./run.sh` (interactive mode) on the agent machine to see startup errors.

### Runner disk full

```
No space left on device
```

- GitHub Actions: add a disk-space cleanup step at the start of the job (remove large pre-installed tool directories not needed for the build).
- Jenkins: configure build retention (`buildDiscarder(logRotator(numToKeepStr: '10'))`) and add `cleanWs()` to `post { always { } }`.
- Self-hosted runners generally: prune Docker images (`docker system prune -a`) and workspace directories regularly.

## Cache miss

**Diagnosis:**

1. The cache key did not match. Cache keys are exact-match (primary key) with prefix fallback (restore keys). Check that the key template evaluates to the expected string.
2. The cache expired. GitHub Actions: 7 days without access. CircleCI: 15 days. GitLab CI: evicted when cache storage is full.
3. The cache is scoped to a different branch. Most platforms scope caches per branch. Add a fallback key to the default branch prefix.
4. The storage backend is unreachable (self-hosted runners using S3 or GCS for cache storage; check network access and credentials).

**Resolution patterns:**

- Bust a stale cache by incrementing a version prefix in the key: `v1-deps-` to `v2-deps-`.
- Add a fallback restore key that matches partial prefixes so cold-start runs get partial cache hits.
- Verify that the `save_cache` (CircleCI) or artifact upload step succeeds in the run that should populate the cache.

## Secret / credential not injected

**GitHub Actions:**

1. Check the secret scope. An environment-scoped secret requires the job to reference that environment with `environment:`. An organisation secret requires the repository to be in the access policy.
2. Fork PRs cannot access secrets by design (`pull_request` events from forks).
3. Secret names are case-sensitive.

**GitLab CI:**

1. Protected variables are only available on protected branches and tags.
2. Masked variables must meet regex constraints for masking to work in logs.
3. Check the variable scope: instance, group, or project.

**Jenkins:**

1. Credentials must be wrapped in `withCredentials([...])` blocks. They are not available as environment variables unless explicitly bound.
2. Check the credential ID matches the stored credential exactly (case-sensitive).

**Azure DevOps:**

1. A variable group linked to Azure Key Vault requires the service connection to have `Get` and `List` permissions on the Key Vault.
2. Secret variables cannot be referenced in template compile-time expressions (`${{ }}`) because they are not available at parse time.

## OIDC trust failures

```
Error: Could not assume role / OIDC token validation failed
```

**Checklist:**

1. The cloud IAM role's trust policy includes the correct OIDC issuer URL for the platform:
   - GitHub Actions: `https://token.actions.githubusercontent.com`
   - GitLab CI: `https://gitlab.com` (or your self-managed instance URL)
   - Azure DevOps: federation identity matches the service connection configuration
   - CircleCI: `https://oidc.circleci.com/org/<your-org-id>`

2. The `sub` (subject) claim in the trust policy matches the actual claim in the JWT. Claims vary by platform and include the repository, branch, or environment.

3. The `aud` (audience) claim matches what the platform sends. For GitHub Actions this defaults to the repository owner.

4. The workflow/job has the required permission to generate the OIDC token:
   - GitHub Actions: `id-token: write` in the `permissions:` block
   - GitLab CI: `id_tokens:` keyword with audience configured

5. The cloud provider IAM role session duration is compatible with the job duration.

## Artifact upload / download errors

**Upload fails:**

- Check artifact size limits. GitHub Actions: 2 GB per file. GitLab CI: configurable in Admin settings (default 100 MB). Azure DevOps: 10 GB per artifact.
- Check disk space on the runner before the upload step.
- Check that the file path specified in `paths:` or `artifact:` actually exists.

**Download fails / artifact not found in downstream job:**

- Confirm the upstream job succeeded and the artifact was uploaded.
- GitHub Actions: `needs: [build]` is required in the downstream job to download artifacts from an upstream job in the same workflow.
- GitLab CI: check `needs: [{ job: build, artifacts: true }]` or ensure jobs are in consecutive stages.
- Azure DevOps: use `download: current` with the correct `artifact:` name.

## YAML syntax and indentation errors

All CI/CD platforms use YAML. Common errors:

```
# Tab characters (YAML requires spaces)
job:
	script: ...    # Tab character -> parser error

# Colon in unquoted value
variables:
  MSG: Hello: World    # Needs quoting -> "Hello: World"

# Typo in key name (ignored silently or surfaced as "unknown key")
scrpt:    # Should be 'script'
  - npm test
```

**Validation commands:**

| Platform | Command |
|---|---|
| GitHub Actions | `gh workflow list` to check registration; `act -l` to list locally |
| GitLab CI | `gitlab-ci-lint .gitlab-ci.yml` or CI Lint UI |
| Jenkins | Pipeline Syntax generator at `<jenkins>/pipeline-syntax/` |
| Azure DevOps | Validate button in the pipeline edit UI |
| CircleCI | `circleci config validate` |

## Permission and scope errors

**GitHub Actions:**

```
Error: Resource not accessible by integration
```

Add the required permission to the `permissions:` block at the workflow or job level.

**GitLab CI job token:**

As of 18.7, `CI_JOB_TOKEN` is scoped to the current project by default. Cross-project access requires explicit allowlisting in Settings > CI/CD > Job token permissions.

**Jenkins Groovy sandbox:**

```
RejectedAccessException: Scripts not permitted to use method ...
```

Approve the method in Manage Jenkins > In-process Script Approval, move the code to a shared library (runs outside the sandbox), or use a plugin step that implements the same operation safely.

## Slow pipelines

**Diagnosis:**

1. Add timestamps to job output and identify which step consumes the most time.
2. Check for sequential steps that could run in parallel.
3. Check agent/runner provisioning time (Kubernetes pod startup, Docker image pull time).
4. Check whether caching is saving time or whether the cache upload/download itself is the bottleneck (too-large cache).

**Common fixes:**

- Parallelise independent jobs. Do not wait for lint to finish before starting tests if they are independent.
- Use test splitting to distribute tests across multiple runner instances.
- Cache dependency directories with hash-based keys.
- Use shallow clones where full history is not needed (`fetch-depth: 1` in GitHub Actions; `GIT_DEPTH: 1` in GitLab CI).
- Prefer lightweight base images in Docker-based runners.

## Debugging techniques per platform

### GitHub Actions

Enable verbose logging by setting repository secrets:

- `ACTIONS_RUNNER_DEBUG = true`: verbose runner diagnostics
- `ACTIONS_STEP_DEBUG = true`: verbose step output (includes all commands)

Or use "Re-run jobs" > "Enable debug logging" in the Actions UI. For local testing: `act push -W .github/workflows/ci.yml`.

### GitLab CI

Enable debug trace (includes all variable values; never leave enabled in production):

```yaml
test:
  variables:
    CI_DEBUG_TRACE: "true"
  script:
    - npm test
```

For debugging running jobs: use the interactive web terminal (GitLab Premium) by clicking "Debug" on a running job. For local execution: `gitlab-runner exec docker test:unit --docker-image node:22`.

### Jenkins

**Replay**: navigate to a failed build, click "Replay", edit the Jenkinsfile script in the UI, and re-run without committing. Useful for iterating on pipeline logic.

**Script Console** (Manage Jenkins > Script Console): run arbitrary Groovy to inspect state:

```groovy
// List all jobs and last build result
Jenkins.instance.allItems(Job.class).each {
    println "${it.fullName} - ${it.lastBuild?.result}"
}

// Check agent status
Jenkins.instance.computers.each {
    println "${it.name}: ${it.isOnline() ? 'ONLINE' : 'OFFLINE'}"
}
```

The Script Console runs with full admin privileges. Use with caution in production.

### Azure DevOps

Enable system diagnostics:

```yaml
variables:
  System.Debug: true
```

Or enable via "Run pipeline" > "Enable system diagnostics" checkbox. Log issue commands:

```yaml
- script: |
    echo "##vso[task.logissue type=warning]This is a warning"
    echo "##vso[task.logissue type=error]This is an error"
```

### CircleCI

SSH into a running container for interactive debugging: use "Rerun job with SSH" in the CircleCI UI. An SSH session is available for up to 2 hours after the job completes. Not available for self-hosted runners.

Validate the expanded config (with orbs resolved): `circleci config process .circleci/config.yml > processed.yml`.

## Jenkins build log retrieval (via the Jenkins MCP server)

When a Jenkins MCP server is available, retrieve and search build logs programmatically:

1. Start with `searchBuildLog` using patterns such as `ERROR|FATAL|Exception|FAILURE|timeout` to locate relevant sections before pulling the full log.
2. Use `getBuildLog` with `jobFullName` and `buildNumber`. For large logs, use the `start` byte-offset parameter to paginate.
3. Use `getPipelineRunLog` for pipeline-structured job logs.

## GitLab pipeline status retrieval (via the GitLab MCP server)

When a GitLab MCP server is available:

1. Use `list_pipelines` with `status: "failed"` and `ref: "main"` to find failing pipelines.
2. Use `get_pipeline_jobs` to list all jobs within a pipeline and their statuses.
3. Use `get_pipeline_job_log` to retrieve the console output for a specific failing job.
