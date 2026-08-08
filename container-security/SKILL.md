---
name: container-security
description: "Vendor-neutral container and Kubernetes security across the full lifecycle from build to runtime: image scanning, admission control, Pod Security Standards, Kubernetes-native RBAC, network policies, in-cluster secrets handling, runtime protection, software supply-chain integrity, and service-mesh mTLS. WHEN: \"container security\", \"Kubernetes security\", \"K8s security\", \"image scanning\", \"admission control\", \"OPA Gatekeeper\", \"Kyverno\", \"Pod Security Standards\", \"Kubernetes RBAC\", \"network policy\", \"supply chain security\", \"container runtime security\", \"SBOM\", \"cosign\", \"container escape\", \"CIS Kubernetes Benchmark\", \"SLSA\", \"service mesh mTLS\". Do NOT use for: cloud posture and CNAPP taxonomy (CSPM/CWPP/CIEM/DSPM), which routes to cloud-security-posture; host and OS-agent endpoint runtime detection, which routes to endpoint-detection-response; general identity and RBAC beyond Kubernetes-native RBAC, which routes to identity-access-management; secret-store systems, which route to hashicorp-vault-ops and secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Container and Kubernetes security

> **Skill marker**: When applying this skill, begin your reply with `[skill: container-security]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for securing containers and Kubernetes across the full lifecycle, from build to runtime. It owns the cross-tool reasoning: how a container differs from a VM at the security boundary, how images are scanned and gated, how admission control enforces policy at deployment time, how Pod Security Standards, Kubernetes-native RBAC, and network policies harden the cluster, how runtime protection watches a running workload, and how supply-chain controls and service-mesh mTLS close the ends. Vendor platforms (Aqua, Sysdig, Falco, Prisma Cloud, Wiz) are named only as routing context; the depth here is the model that survives a platform or CNI migration.

## When to use

- Designing a defence-in-depth container security strategy across build, registry, admission, runtime, and infrastructure.
- Explaining how image scanning works, and setting CI/CD gate policy on the findings.
- Authoring admission-control policy: OPA Gatekeeper constraints, Kyverno validate/mutate rules, or Pod Security Standards profiles.
- Hardening Kubernetes-native RBAC, network policies, and the API server against escalation and lateral movement.
- Reasoning about container escape vectors, sandbox runtimes (gVisor, Kata), and CIS Kubernetes Benchmark hardening.
- Adding supply-chain integrity: SLSA provenance, cosign/Sigstore signing and verification, SBOM generation and use.
- Planning runtime protection and service-mesh mTLS for east-west traffic.

## When not to use

- **Cloud posture and CNAPP taxonomy** (CSPM, CWPP, CIEM, DSPM, agentless cloud scanning, multi-cloud posture): use `cloud-security-posture`. That skill owns the cloud-platform taxonomy and references this one for the container and Kubernetes depth it needs.
- **Host and OS-agent endpoint runtime detection** (EDR/XDR on the node itself, process-lineage detection at the operating-system layer): use `endpoint-detection-response`. Container runtime protection here is orchestrator-aware; the host agent sees the node.
- **General identity and RBAC beyond the cluster** (corporate IdP, workforce SSO, joiner-mover-leaver, entitlement review): use `identity-access-management`. This skill owns only Kubernetes-native RBAC and workload identity.
- **Secret-store systems** (deploying and operating a central secrets manager): use `hashicorp-vault-ops`; for the handling discipline (gitignored files, rotation, per-deployment identity) use `secrets-hygiene`. This skill covers how secrets reach a pod, not how the store itself is run.
- **General Kubernetes operations, container runtimes, and service-mesh setup** (cluster lifecycle, scheduling, mesh installation): use `kubernetes-ops` for cluster operations, `container-orchestration-selection` and `container-runtime-selection` to choose an orchestrator or runtime, and `service-mesh-selection` for mesh choice and installation. This skill owns the security angle on those surfaces, not their day-to-day operation.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Security model + cluster architecture | containers vs VMs, namespaces and cgroups, defence-in-depth layers, admission architecture, Pod Security Standards, RBAC, network policies, container escape, CIS Benchmark | `references/concepts.md` |
| Admission-control policy authoring | OPA Gatekeeper ConstraintTemplate/Constraint, Kyverno validate/mutate, Sigstore signature-verification policy, Gatekeeper-vs-Kyverno choice | `references/admission-control-examples.md` |
| Supply chain + scanning + runtime | image scanning methodology and CI gates, SLSA, cosign/Sigstore, SBOM, runtime protection, seccomp/AppArmor, service-mesh mTLS | `references/supply-chain-and-runtime.md` |

## Core model (condensed)

A container is a process isolated by kernel namespaces and constrained by cgroups; it shares the host kernel rather than sitting behind hardware isolation like a VM. That single fact drives the whole model: a root process that finds a kernel or misconfiguration flaw can escape to the host, so **isolation is a configuration you earn, not a default you inherit**.

Defence in depth runs across the lifecycle, and no single layer is sufficient:

1. **Supply chain**: source and build integrity (SLSA provenance, signed artefacts, SBOM).
2. **Build**: minimal base images, pinned digests, no secrets baked into layers.
3. **Image scanning**: a pre-registry gate for CVEs, secrets, and misconfigurations.
4. **Registry**: authentication, content trust, signature enforcement.
5. **Admission control**: the deployment-time gate that validates, mutates, or rejects workloads.
6. **Runtime**: seccomp, AppArmor, and behavioural monitoring of the running container.
7. **Network**: network policies and service-mesh mTLS for east-west traffic.
8. **Infrastructure**: RBAC, etcd encryption, and API-server hardening on the control plane.

**Scanning is a gate, not a report.** Prioritise findings by real-world risk, not raw CVSS: known-exploited (CISA KEV) first, then high severity with a public exploit, then fix-availability and whether the vulnerable code is actually loaded at runtime. Always block on hardcoded secrets with no threshold.

**Admission control is where policy becomes enforcement.** Built-in Pod Security Admission enforces the three Pod Security Standards profiles (Privileged, Baseline, Restricted) per namespace by label. OPA Gatekeeper (Rego) and Kyverno (Kubernetes-native YAML) add custom validate and mutate logic. A security-enforcing webhook should run `failurePolicy: Fail` and be highly available, so a downed webhook cannot become an open door.

**Least privilege is the recurring theme.** Drop all capabilities and add back only what is needed; run as non-root with no privilege escalation; scope RBAC to specific verbs, resources, and namespaces; start network policy from default-deny and open only the flows you need; give each workload its own service account and cloud identity rather than a shared token.

**Anti-patterns:** running privileged containers or mounting the container-runtime socket; binding `cluster-admin` to service accounts or developers; wildcards in RBAC verbs or resources; leaving a namespace with no network policy; treating a base64 Kubernetes Secret as encrypted; baking a secret into an image layer that history still holds; trusting an unsigned image from an untrusted registry; and leaving service-to-service traffic in plaintext inside the cluster.

## Reference router

| Need | Load |
|---|---|
| Containers vs VMs, namespaces and cgroups, the defence-in-depth layers, admission-controller architecture and webhook failure policy, Pod Security Standards profiles, Kubernetes RBAC and dangerous permissions, service-account tokens and workload identity, network policies and CNI comparison, container escape vectors, sandbox runtimes, CIS Kubernetes Benchmark | `references/concepts.md` |
| OPA Gatekeeper ConstraintTemplate and Constraint YAML, Kyverno validate and mutate ClusterPolicy YAML, a Sigstore image-signature-verification policy, and the Gatekeeper-vs-Kyverno decision | `references/admission-control-examples.md` |
| Image-scanning methodology, vulnerability prioritisation and CI/CD gate policy, SBOM formats and use, SLSA levels, cosign/Sigstore signing and verification, runtime protection and seccomp/AppArmor, service-mesh mTLS and SPIFFE/SPIRE | `references/supply-chain-and-runtime.md` |

## Cross-references

- `cloud-security-posture`: the cloud-side umbrella (CSPM/CWPP/CIEM/DSPM); it references this skill for the container and Kubernetes depth that CNAPP coverage assumes.
- `kubernetes-ops`, `container-orchestration-selection`, `container-runtime-selection`, `service-mesh-selection`: the operational and selection siblings for clusters, runtimes, and meshes; this skill owns the security angle on those surfaces, they own day-to-day operation and platform choice.
- `endpoint-detection-response`: the host-agent runtime sibling; container runtime protection here is orchestrator-aware, the EDR agent watches the node.
- `identity-access-management`: the corporate identity surface beyond the cluster; Kubernetes-native RBAC lives here, workforce and federation identity live there.
- `hashicorp-vault-ops`: operating the central secret store this skill injects from; the pod-side patterns (External Secrets Operator, sealed secrets, agent sidecar) live here.
- `secrets-hygiene`: the handling discipline for any token or credential in a manifest, a scan config, or a signing pipeline; never commit a real literal.
- `utc-timestamps`: admission, audit, and runtime-event correlation depend on UTC, NTP-synchronised clocks; skewed time corrupts the cluster timeline.

## Red flags

- About to allow a privileged container, a mounted runtime socket, or a hostPath onto a sensitive directory.
- About to bind `cluster-admin` to a service account, or write a wildcard verb or resource into a Role.
- About to ship a namespace to production with no default-deny network policy.
- About to gate CI on raw CVSS alone, ignoring KEV, exploit availability, and whether the code is loaded at runtime.
- About to run a security-enforcing admission webhook with `failurePolicy: Ignore` or no high-availability plan.
- About to treat a Kubernetes Secret as encrypted when etcd encryption at rest is not enabled.
- About to admit an unsigned image, or verify a signature against a key you cannot attest to.
- About to leave service-to-service traffic in plaintext when the mesh could enforce strict mTLS.

## Bottom line

A container is a shared-kernel process, so isolation is earned through configuration at every layer. Scan as a gate and prioritise by real-world risk, enforce policy at admission with a fail-closed webhook, and apply least privilege to RBAC, capabilities, and network flow. Sign what you ship, know what is inside it through an SBOM, and encrypt east-west traffic with mTLS. When the question moves to cloud posture, the host agent, corporate identity, or the secret store itself, hand off to the sibling skill that owns it.
