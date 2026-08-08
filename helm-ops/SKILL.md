---
name: helm-ops
description: "Authoring and operating Helm charts and releases on Kubernetes: chart structure (Chart.yaml, values.yaml, templates, _helpers.tpl, crds), Go and Sprig templating, values design and JSON-schema validation, release lifecycle (install, upgrade, rollback, history), chart dependencies and subcharts, OCI registry push/pull and install-by-digest, chart hooks, chart testing and linting, Helmfile multi-release orchestration, helm-secrets with SOPS, and the Helm 3 to Helm 4 (Server-Side Apply) changes. WHEN: \"Helm\", \"Helm chart\", \"helm install\", \"helm upgrade\", \"helm rollback\", \"helm template\", \"Chart.yaml\", \"values.yaml\", \"releases\", \"chart hooks\", \"subcharts\", \"chart dependencies\", \"OCI registry\", \"Helmfile\", \"helm-secrets\", \"chart testing\", \"helm lint\". Do NOT use for: operating the Kubernetes cluster Helm deploys onto (kubernetes-ops); choosing an orchestrator or distribution (container-orchestration-selection, openshift-ops, rancher-ops); GitOps continuous delivery that syncs Helm releases such as ArgoCD or Flux (cicd-platforms-ops, gh-actions-ci); chart and image security scanning, admission control and supply-chain integrity (container-security); storing or operating the secret backend behind helm-secrets (hashicorp-vault-ops, secrets-hygiene); or driving Helm through the Terraform Helm provider (terraform-iac-ops)."
license: MIT
metadata:
  version: 1.0.0
---

# Helm operations

> **Skill marker**: When applying this skill, begin your reply with `[skill: helm-ops]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill owns Helm, the Kubernetes package manager: authoring charts, writing Go and Sprig templates, designing values, managing the release lifecycle (install, upgrade, rollback, history), wiring dependencies and subcharts, publishing and consuming charts from OCI registries, running hooks and tests, and orchestrating multiple releases with Helmfile. It assumes Kubernetes is the chosen orchestrator and a cluster is already running; the orchestrator decision lives in `container-orchestration-selection`, and operating the cluster Helm deploys onto is `kubernetes-ops`. It covers helm-secrets at the operational level but routes secret storage and the backing store to `hashicorp-vault-ops` and `secrets-hygiene`.

Coverage spans Helm 3 and Helm 4. Helm 4 reached general availability in late 2025; the two major versions differ significantly (Server-Side Apply versus client-side three-way merge, WebAssembly versus exec plugins, kstatus versus rollout status, OCI by default), all in `## Helm 3 vs Helm 4`.

## When to use

- Authoring a chart: `Chart.yaml` metadata, `values.yaml` with sensible defaults, `templates/`, `_helpers.tpl` named templates, `values.schema.json` validation, `crds/`, and `NOTES.txt`.
- Writing Go and Sprig templates: conditionals, loops, named templates and `include`, whitespace control, `required` and `lookup`, checksum annotations for config-driven rollouts.
- Designing values: flat keys, grouped settings, secure defaults (non-root, read-only rootfs), optional features disabled by default, JSON-schema validation.
- Managing releases: `helm install`, `helm upgrade --install`, `helm rollback`, `helm history`, `helm uninstall`, and the `--atomic` / `--wait` / `--timeout` flags.
- Wiring dependencies: subcharts, `condition` and `tags` toggles, aliases for repeated dependencies, `Chart.lock`, and OCI dependency repositories.
- Publishing and consuming charts from OCI registries, including install-by-digest for supply-chain pinning.
- Writing hooks (pre/post-install, pre/post-upgrade, pre/post-rollback, test) with weights and delete policies.
- Testing and linting: `helm lint`, `helm template`, `helm test`, `helm install --dry-run`.
- Orchestrating multiple releases across environments with Helmfile; encrypting values files with helm-secrets and SOPS.

## When not to use

- **Kubernetes cluster operations**: running the cluster Helm deploys onto (workloads, RBAC, namespaces, scheduling, node management, kubectl) is `kubernetes-ops`. Helm renders and applies manifests; the cluster that receives them is operated there.
- **Orchestrator and distribution selection**: choosing Kubernetes versus another orchestrator, or picking a distribution, is `container-orchestration-selection`. Distribution-specific operation is `openshift-ops` and `rancher-ops`. This skill packages workloads; those decide and operate the platform.
- **GitOps continuous delivery**: auto-sync, drift detection, and app-of-apps that continuously reconcile Helm releases (ArgoCD, Flux) are `cicd-platforms-ops` and `gh-actions-ci`. Helm is the packaging and templating layer; the pipeline or controller that invokes it on every commit lives there.
- **Container and Kubernetes security strategy**: chart and image scanning as a gate, admission control (OPA Gatekeeper, Kyverno, Pod Security Standards), and supply-chain integrity (SLSA, cosign, SBOM) are `container-security`. This skill pins digests and sets secure value defaults; the programme that enforces them is there.
- **Secret storage and the backend**: helm-secrets encrypts values files, but the KMS or age keys, the central secret store, and the handling discipline for any real credential are `hashicorp-vault-ops` and `secrets-hygiene`. Never commit a decrypted secret or a literal token.
- **Terraform Helm provider**: driving `helm_release` from Terraform, and the state and provider mechanics around it, are `terraform-iac-ops`. The chart and values are here; the IaC engine that applies them is there.
- **Service mesh selection**: `service-mesh-selection`. Installing a mesh via its Helm chart is here; choosing whether and which mesh to run is there.

## Classify the request first

Every request resolves to one of these, which determines the reference to load. Also identify the Helm major version; the boundaries that change behaviour are Helm 3 (client-side three-way merge, exec plugins) and Helm 4 (Server-Side Apply, wasm plugins, kstatus, OCI by default). If unclear, ask, then default guidance to Helm 4.

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture / internals | `Chart.yaml` fields, template rendering pipeline, values merge order, template objects, named-template mechanics, hooks lifecycle and execution order, SSA field ownership, OCI distribution protocol, release-storage Secrets, subchart value scoping, CRD handling | `references/architecture.md` |
| Chart design + operations | values design, schema validation, template patterns, chart testing, library charts, Helmfile orchestration, helm-secrets, dependency management, CI/CD integration | `references/best-practices.md` |
| Debugging / diagnostics | template render failures, release failures, hook problems, field-conflict errors, values resolution | inline `## Debugging` below, then `references/architecture.md` |
| Version-specific | Helm 3 to Helm 4 migration, SSA versus three-way merge, wasm versus exec plugins, kstatus, multi-document values | inline `## Helm 3 vs Helm 4` below |

## Core model (condensed)

**Helm renders Go templates into Kubernetes manifests, merges values, applies them, and records the result as a Secret.**

```
Chart.yaml + values.yaml + user values (-f, --set)
  -> values merge (user values override chart defaults)
  -> template engine (Go template + Sprig)
  -> YAML parse and validate (values.schema.json)
  -> apply to cluster (Server-Side Apply in Helm 4, three-way merge in Helm 3)
  -> release state stored as a Secret in the namespace
```

A **chart** is a directory of templates, default values, and metadata. `helm install` and `helm upgrade` merge the chart defaults with user-supplied values, render the templates, and apply the result. `helm upgrade --install` is the idempotent form to reach for in automation. Every apply increments the release revision, and `helm rollback` returns to an earlier one.

**Release state lives in the cluster, not on the client.** Helm stores each revision as a Secret named `sh.helm.release.v1.<release>.v<revision>` in the release namespace, holding the rendered manifest, the values, and metadata. Two releases with the same name in different namespaces are independent, and RBAC on Secrets in a namespace is RBAC on Helm releases there. The default history cap is ten revisions (`--history-max`).

**CRDs in `crds/` are install-only.** They are applied before templates, never templated, never upgraded, and never deleted on uninstall, because they are cluster-scoped and shared. Manage CRD upgrades separately (kubectl apply, a dedicated CRD chart, or an operator).

**Anti-patterns:** unbounded or `latest` chart and image versions instead of pinned tags or digests; using `template` where `include` is needed (only `include` can be piped to `nindent`/`toYaml`); missing `{{- -}}` whitespace trimming that breaks YAML parsing; unquoted string values that render as integers; putting CRD lifecycle in `crds/` and expecting upgrades; skipping `helm diff` before a production upgrade; omitting `--atomic` in CI so a failed upgrade leaves a stuck release; and committing decrypted secrets alongside values files.

## Chart structure

```
mychart/
├── Chart.yaml             # Chart metadata (required)
├── values.yaml            # Default values (required)
├── values.schema.json     # JSON Schema for values validation (recommended)
├── charts/                # Dependency subcharts
├── templates/             # Go template Kubernetes manifests
│   ├── _helpers.tpl       # Named templates / partials
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── NOTES.txt          # Post-install user instructions
│   └── tests/
│       └── test-connection.yaml
├── crds/                  # CRDs (applied first, never templated or upgraded)
└── .helmignore            # Exclude patterns from the chart package
```

`Chart.yaml` uses `apiVersion: v2` for Helm 3 and 4 charts; `version` is the chart's own SemVer and `appVersion` tracks the application independently. `type: library` charts provide named templates for other charts to import and cannot be installed directly. Full field reference is in `references/architecture.md`.

## Templating

Helm uses Go templates with the Sprig function library. Common constructs:

```yaml
# Variable access
{{ .Values.image.repository }}
{{ .Release.Name }}
{{ .Release.Namespace }}
{{ .Chart.Name }}

# Conditional
{{- if .Values.ingress.enabled }}
# render ingress
{{- end }}

# Loop
{{- range .Values.config.extraEnv }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# Named template (defined in _helpers.tpl)
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

# Include a named template (pipeable to nindent/toYaml)
{{ include "myapp.fullname" . }}

# With: set the scope
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

Use `include`, not `template`, to call named templates: only `include` captures the output as a string that can be piped to functions like `nindent`. Common Sprig functions are `default`, `quote`, `nindent`, `toYaml`, `b64enc`, `sha256sum`, `lookup`, `required`, `fail`, `ternary`, and `dict`.

**`required`** fails the render if a value is unset, giving a clear error before the cluster is touched:

```yaml
image: {{ required "image.repository is required" .Values.image.repository }}
```

**`lookup`** queries existing cluster resources during render:

```yaml
{{- $secret := lookup "v1" "Secret" .Release.Namespace "my-secret" -}}
{{- if $secret }}
# secret exists
{{- end }}
```

**Checksum annotation** rolls pods when a ConfigMap changes:

```yaml
metadata:
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

## Values and schema

Make everything configurable with secure, sensible defaults: flat keys where possible, related settings grouped, every value commented, optional features (ingress, autoscaling) disabled by default, and security defaults on (non-root, read-only rootfs, dropped capabilities). Validate with `values.schema.json` so typos in value names and wrong types are caught during `helm install`, `helm upgrade`, `helm lint`, and `helm template`, before the cluster is touched.

Values merge in order, later overriding earlier: the chart's `values.yaml`, then the parent chart's values (for subchart values), then `-f` / `--values` files in order, then `--set` and `--set-string`, then `--set-file`. Helm 4 also supports multiple YAML documents (`---`) within a single values file, later documents overriding earlier. Value design patterns and a worked schema are in `references/best-practices.md`.

## Releases and rollback

```bash
# Install or upgrade idempotently (the automation default)
helm upgrade --install <release> <chart> -n <ns> --create-namespace -f values.yaml

# Roll back to an earlier revision
helm rollback <release> <revision> -n <ns>

# Inspect revision history
helm history <release> -n <ns>

# Uninstall
helm uninstall <release> -n <ns>
```

For production upgrades, `--wait` blocks until resources are ready, `--timeout` bounds the wait, and `--atomic` rolls back automatically on failure so a broken upgrade does not leave a stuck release. Always preview with `helm diff upgrade` (the helm-diff plugin) before applying in production. Revision history and the release-storage Secrets are covered in `references/architecture.md`.

## Dependencies and OCI registries

Declare dependencies in `Chart.yaml` and pin their versions:

```yaml
dependencies:
  - name: postgresql
    version: "~13.0"                                   # patch-flexible SemVer range
    repository: "oci://registry-1.docker.io/bitnamicharts"
    condition: postgresql.enabled                        # toggle via values
  - name: redis
    version: "18.x.x"
    repository: "oci://registry-1.docker.io/bitnamicharts"
    alias: cache                                         # reference as .Values.cache
    tags:
      - backend                                          # enable/disable by tag group
```

```bash
helm dependency update ./mychart     # download dependencies into charts/
helm dependency build ./mychart      # rebuild from Chart.lock
```

Commit `Chart.lock` for reproducible builds. `condition` takes precedence over `tags`, and a subchart sees only its own value scope plus `.Values.global`.

OCI distribution is the default in Helm 4 and replaces the legacy `helm repo add` plus `index.yaml` model:

```bash
helm package ./mychart
helm push mychart-1.5.0.tgz oci://registry.example.com/charts
helm install myapp oci://registry.example.com/charts/mychart --version 1.5.0

# Install by digest (supply-chain pinning, Helm 4)
helm install myapp oci://registry.example.com/charts/mychart@sha256:abc123...

helm registry login registry.example.com -u user -p token
```

Compatible registries include Docker Hub, GHCR, ECR, ACR, GCR, Harbor, and Quay. The OCI distribution protocol is detailed in `references/architecture.md`.

## Hooks

Hooks are resources annotated with `helm.sh/hook`, executed at points in the release lifecycle: `pre-install`, `post-install`, `pre-upgrade`, `post-upgrade`, `pre-delete`, `post-delete`, `pre-rollback`, `post-rollback`, and `test`. Hook **weights** order execution (`-5` runs before `5`); **delete policies** are `before-hook-creation`, `hook-succeeded`, and `hook-failed`. Hooks are not part of the release, so without a delete policy the resources persist.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

## Testing and linting

```bash
helm lint ./mychart -f values.yaml                    # static and schema checks
helm template myrelease ./mychart -f values.yaml      # render locally, no cluster
helm install myrelease ./mychart --dry-run --debug    # server dry-run (SSA in Helm 4)
helm test <release> -n <ns>                           # run test hooks against a release
```

A test lives in `templates/tests/` as a Pod annotated `helm.sh/hook: test`; `helm test` runs it against a deployed release and reports pass or fail. In CI, lint and `--dry-run` on every change, install into a throwaway namespace, run `helm test`, then uninstall. Fuller CI patterns are in `references/best-practices.md`.

## Helmfile and helm-secrets

**Helmfile** manages multiple releases declaratively across environments, with `needs` for ordering and per-environment values files:

```bash
helmfile diff                    # preview changes
helmfile apply                   # diff, then sync only what changed
helmfile -e staging sync         # apply a specific environment
```

**helm-secrets** encrypts values files with SOPS (AWS KMS, GCP KMS, Azure Key Vault, age, or PGP backends) so encrypted values can sit in Git next to plaintext values:

```bash
helm secrets install myapp ./mychart -f values.yaml -f secrets.yaml
```

The encryption keys, the KMS or age key material, and the central secret store are not this skill's remit: route secret storage and rotation to `hashicorp-vault-ops` and the handling discipline to `secrets-hygiene`. Never commit a decrypted secrets file or a literal token.

## Debugging

```bash
helm template myrelease ./mychart -f values.yaml > rendered.yaml   # inspect output
helm template myrelease ./mychart -s templates/deployment.yaml     # one template
helm template myrelease ./mychart --debug                          # show computed values
helm install myrelease ./mychart --dry-run --debug                 # validate against cluster
helm show values ./mychart                                         # default values
```

Most render failures are whitespace or quoting: missing `{{- -}}` trims leave blank lines that break YAML parsing, and an unquoted numeric-looking string renders as an integer (use `| quote`). Field-conflict errors on upgrade are a Helm 3 three-way-merge symptom; Helm 4's Server-Side Apply removes most of them by tracking field ownership.

## Helm 3 vs Helm 4

Guidance defaults to Helm 4 when the version is unknown. The differences that change behaviour:

| Feature | Helm 3 | Helm 4 |
|---|---|---|
| Apply strategy | Client-side three-way merge | Server-Side Apply (SSA) |
| Plugin system | Exec-based | WebAssembly (wasm) |
| Resource readiness | Rollout status | kstatus |
| OCI support | Experimental, then GA | Default recommended |
| Multi-document values | No | Yes (YAML `---` delimiters) |
| Install by digest | No | Yes (`oci://...@sha256:...`) |

**SSA impact**: Helm 4 tracks field ownership, so fields Helm does not manage (annotations added by operators, labels added with kubectl) survive an upgrade without the "modified by another client" conflicts that plagued Helm 3. Use `--force` to take ownership of a field another manager owns.

**Migration**: Helm 4 can manage releases created by Helm 3. Run `helm upgrade` with the Helm 4 binary to migrate a release; SSA applies on the next upgrade. SSA mechanics are in `references/architecture.md`.

## Cross-references

- `container-orchestration-selection`: the umbrella that decides Kubernetes versus another orchestrator; this skill packages workloads once Kubernetes is chosen.
- `kubernetes-ops`: operating the cluster Helm deploys onto (workloads, RBAC, namespaces, scheduling). Helm renders and applies manifests; the cluster that receives them is operated there.
- `openshift-ops`, `rancher-ops`: distribution-specific operation for the platforms in this family.
- `container-security`: chart and image scanning as a gate, admission control, and supply-chain integrity. Pin digests and set secure value defaults here; take the enforcement programme from there.
- `hashicorp-vault-ops`, `secrets-hygiene`: the secret store and key material behind helm-secrets, and the handling discipline for any real credential. Never commit a decrypted secret.
- `cicd-platforms-ops`, `gh-actions-ci`: GitOps and CD pipelines (including ArgoCD and Flux) that invoke Helm on every commit. The chart and values are here; the reconciliation loop is there.
- `terraform-iac-ops`: driving Helm through the Terraform Helm provider (`helm_release`).
- `service-mesh-selection`: choosing whether and which service mesh to run; installing a mesh via its Helm chart is here.

## Red flags

- About to ship an unpinned or `latest` chart or image version instead of a pinned tag or digest.
- About to use `template` where `include` is needed, so the output cannot be piped to `nindent` or `toYaml`.
- About to render without `{{- -}}` whitespace trimming, producing blank lines that break YAML parsing.
- About to pass an integer-looking string unquoted, so it renders as an integer in a string context.
- About to put CRD lifecycle in `crds/` and expect `helm upgrade` to update them (it never does).
- About to run a production `helm upgrade` with no `helm diff` preview and no `--atomic`, risking a stuck failed release.
- About to commit a decrypted secrets file or a literal token alongside values instead of encrypting with helm-secrets and routing storage to the secret store.
- About to hit the etcd 1.5 MB per-object limit with a large chart, because release Secrets store the rendered manifest; split the chart.
- About to assume a Helm 3 field-conflict error applies under Helm 4, whose Server-Side Apply resolves most of them.

## Bottom line

Helm renders Go and Sprig templates into Kubernetes manifests, merges values with secure defaults, applies them (Server-Side Apply in Helm 4, three-way merge in Helm 3), and records each revision as a Secret in the namespace. Build charts with commented values and a JSON schema, pin dependency and image versions, publish and install through OCI (by digest for supply-chain pinning), and gate every production upgrade with `helm diff`, `--wait`, `--timeout`, and `--atomic`. Keep CRD lifecycle out of `crds/`, use `include` not `template`, and quote string values. Bring the orchestrator choice from `container-orchestration-selection`, operate the cluster with `kubernetes-ops`, take the security programme from `container-security`, and keep secret material in `hashicorp-vault-ops` and `secrets-hygiene`.
