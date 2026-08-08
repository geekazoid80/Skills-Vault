# Admission-control policy examples

Worked OPA Gatekeeper and Kyverno policy, plus a Sigstore image-signature-verification policy, and the decision between the two engines. Load this when the task is to author or review a deployment-time policy. The architecture behind admission control (the request lifecycle, webhook failure policy, Pod Security Standards) lives in `concepts.md`.

## Choosing an engine

Both OPA Gatekeeper and Kyverno enforce policy at admission; they differ mainly in how you express a policy.

| Aspect | OPA Gatekeeper | Kyverno |
|---|---|---|
| Policy language | Rego (powerful, but a learning curve) | Kubernetes-native YAML/JSON |
| Learning curve | Steep | Gentle for teams already fluent in Kubernetes YAML |
| Mutation support | Limited (assign mutations) | Strong (strategic-merge and JSON patch) |
| Audit mode | Yes | Yes |
| Resource generation | No | Yes (create resources as a side effect) |
| Best fit | Complex policy logic, an existing OPA investment | Kubernetes-native teams, simpler policy, mutation and generation |

A common pattern is to run Pod Security Admission for the baseline profiles and add one of these engines for the organisation-specific rules that the profiles do not cover.

## OPA Gatekeeper

Gatekeeper splits a policy in two: a `ConstraintTemplate` holds the Rego logic and defines a new CRD kind, and a `Constraint` of that kind applies it with parameters and a match scope.

```yaml
# ConstraintTemplate: the policy logic
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }

---
# Constraint: applies the template with parameters
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-app-label
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    labels: ["app", "environment", "owner"]
```

## Kyverno

Kyverno policies are plain Kubernetes resources. A `validate` rule blocks a non-compliant object; a `mutate` rule patches an object as it is admitted. Set `validationFailureAction: Enforce` to reject, or `Audit` to log only.

```yaml
# validate: block privileged containers
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
spec:
  validationFailureAction: Enforce
  rules:
    - name: privileged-containers
      match:
        any:
        - resources:
            kinds: ["Pod"]
      validate:
        message: "Privileged mode is not allowed"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(privileged): "false"

---
# mutate: add default resource limits
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-default-resources
spec:
  rules:
    - name: add-resource-limits
      match:
        any:
        - resources:
            kinds: ["Pod"]
      mutate:
        patchStrategicMerge:
          spec:
            containers:
              - (name): "*"
                resources:
                  limits:
                    memory: "512Mi"
                    cpu: "500m"
```

## Signature verification with Sigstore

A Kyverno `verifyImages` rule enforces supply-chain integrity at admission: an image from a matched registry must carry a valid cosign signature before the pod is admitted. This is where the signing done in the pipeline (see `supply-chain-and-runtime.md`) becomes an enforced gate.

```yaml
# Require signed images from a trusted registry
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-signed-images
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-image-signature
      match:
        any:
        - resources:
            kinds: ["Pod"]
      verifyImages:
      - imageReferences:
        - "registry.example.com/*"
        attestors:
        - entries:
          - keys:
              publicKeys: |-
                -----BEGIN PUBLIC KEY-----
                <cosign public key>
                -----END PUBLIC KEY-----
```

For keyless verification, the same rule form matches on the Sigstore certificate identity (the OIDC issuer and subject) instead of a static public key, so there is no key to distribute or rotate.

## Operational notes

- A security-enforcing policy should run behind a webhook with `failurePolicy: Fail` and a high-availability deployment, so a downed policy engine cannot silently admit non-compliant workloads. See `concepts.md` for the failure-policy trade-off.
- Roll a new policy out in audit mode first (Gatekeeper audit, or Kyverno `Audit`), review the violations against existing workloads, then switch to enforce. Enforcing an untested policy against a running cluster blocks legitimate deployments.
- Scope each policy with a precise match block. A `Pod`-only match misses the controllers that create pods; match the workload kinds you actually deploy, or the pod controllers, as the policy intends.
