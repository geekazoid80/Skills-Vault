---
name: software-composition-analysis
description: "Use for software composition analysis (SCA): analysing the open-source and third-party dependencies an application pulls in, finding known vulnerabilities in them, and inventorying and licence-checking them. Covers direct versus transitive dependencies, known-vulnerability detection against advisory databases, CVE and CVSS read in the dependency context, reachability analysis to cut false positives, dependency update and remediation strategy, the application SBOM (CycloneDX, SPDX, SWID) and how it is generated and consumed, and open-source licence types and their compliance risk. Triggers include \"SCA\", \"software composition analysis\", \"open source security\", \"open source vulnerabilities\", \"dependency scanning\", \"transitive dependency\", \"vulnerable dependency\", \"dependency update\", \"SBOM\", \"software bill of materials\", \"CycloneDX\", \"SPDX\", \"licence compliance\", \"license compliance\", \"copyleft\", \"reachability analysis\", \"supply chain\". Do NOT use for: vendor-neutral AppSec strategy and where SCA sits among SAST/DAST/WAF (see application-security); vulnerability-management programme design, CVSS/EPSS scoring, and remediation SLAs (see vulnerability-management); a single CVE lookup or NVD query (see nvd-cve); the container-IMAGE supply chain, image-layer SBOM, SLSA provenance, cosign/Sigstore signing, and admission control (see container-security). References dependency-and-vulnerability.md, sbom-and-licence.md."
license: MIT
metadata:
  version: 1.0.0
---

# Software composition analysis

> **Skill marker**: When applying this skill, begin your reply with `[skill: software-composition-analysis]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Software composition analysis is the discipline of knowing what open-source and third-party code an application depends on, and managing the risk that code carries. Modern applications are mostly not their own code: the majority of a shipped artefact is pulled in from public registries, and most of that arrives transitively, several layers below anything a developer chose directly. SCA answers two questions about that borrowed code. First, does any of it carry a known vulnerability that an attacker could reach. Second, is any of it under a licence that creates a legal or commercial obligation the organisation cannot accept. The output is an inventory (the application SBOM), a prioritised list of vulnerable components, and a licence posture.

This skill owns application and library dependency analysis and the application SBOM. It does not own the container-image supply chain. That boundary is drawn explicitly below.

## When to use

- Mapping an application's dependency tree, separating direct from transitive dependencies, and understanding where a given package actually came from.
- Detecting known vulnerabilities in dependencies by comparing the tree against advisory databases, and reading a CVE and its CVSS score in the dependency context.
- Applying reachability analysis to cut a raw finding count down to the vulnerabilities whose code path the application actually invokes.
- Choosing a remediation path for a vulnerable dependency: upgrade the direct dependency, override the transitive version, or accept and track.
- Generating and consuming an application SBOM in CycloneDX or SPDX, and knowing which regulation or customer requirement is driving the request.
- Assessing open-source licence risk: classifying a licence as permissive, weak copyleft, strong copyleft, or commercially restricted, and setting a policy that fails CI on a blocked licence.

## When not to use

- **Vendor-neutral AppSec strategy and where SCA sits among the testing techniques**: route UP to `application-security`. That skill owns the OWASP Top 10, the secure SDLC, shift-left economics, and how SAST, DAST, SCA, and WAF compose across the pipeline. This skill is the SCA technique in depth, not the umbrella that places it.
- **Vulnerability-management programme design, CVSS/EPSS scoring, and remediation SLAs**: use `vulnerability-management`. SCA surfaces vulnerable-component findings; the risk-based prioritisation model, the EPSS and KEV enrichment, and the SLA framework that says when each severity must be fixed live there. This skill reads CVSS in the dependency context to triage, and hands the programme-level scoring across.
- **A single CVE lookup or an NVD query**: use `nvd-cve`. Looking up one identifier, reading its NVD record, or understanding the CVE and CVSS data model in the abstract belongs there. This skill uses those records as an input to dependency triage.
- **The container-IMAGE supply chain**: use `container-security`. Image-layer SBOMs, SLSA provenance, cosign and Sigstore signing, and admission control are its subject. See the boundary note directly below; it is the most common mis-route for this skill.

## Boundary with container-security (read this before routing)

SCA and container image scanning overlap in tooling and vocabulary, so the split is drawn by artefact, not by tool:

- **This skill owns the APPLICATION and LIBRARY layer.** The dependencies your code declares (the `package.json`, `pom.xml`, `requirements.txt`, `go.mod`, `Gemfile.lock` and the full transitive closure they resolve to), the vulnerabilities in those packages, their licences, and the application SBOM that inventories them.
- **`container-security` owns the container-IMAGE supply chain.** The OS packages baked into image layers, the image-layer SBOM, SLSA build provenance, signing an image with cosign or Sigstore, and admission control that verifies a signature before a workload runs.

A single scanner (syft, Trivy, Snyk) will happily do both, which is why the line is easy to blur. The test is: if the finding is about a library your application declared, it is this skill; if it is about how the image was built, layered, signed, or admitted, it is `container-security`. An application SBOM and an image SBOM are different documents describing different scopes, even when the same format and tool produce them.

## Classify the request first

Every request resolves to one of these, which determines the reference to load:

| Class | Examples | Where the depth lives |
|---|---|---|
| Dependencies and vulnerabilities | direct versus transitive, advisory data sources, CVE/CVSS in the dependency context, reachability analysis, upgrade/override/accept remediation, update automation | `references/dependency-and-vulnerability.md` |
| SBOM and licence | CycloneDX / SPDX / SWID formats, SBOM generation and consumption, regulatory drivers, permissive vs copyleft licences, licence policy and CI gating | `references/sbom-and-licence.md` |

## Core model (condensed)

**Most of the risk is in code nobody chose.** Direct dependencies are the ones a developer wrote into the manifest; transitive dependencies are everything those pull in, recursively, and they dominate both the count and the vulnerability surface. A vulnerable transitive package cannot be fixed by editing your own code, so SCA has to reason about the whole resolved tree, not the manifest.

**A known vulnerability is a match, not a verdict.** SCA compares the resolved tree against advisory databases and flags every component with a published CVE. That raw list overstates the real exposure, because most flagged vulnerabilities sit in code paths the application never calls. Reachability analysis is what turns a match into an actionable finding by asking whether the vulnerable function is actually invoked. Prioritise reachable, exploitable, fixable vulnerabilities in critical assets; do not treat the raw count as the workload.

**Remediation has three moves, in order of preference.** Upgrade the direct dependency so it ships a patched transitive version; if that is not available, override the transitive version directly; if no fix exists at all, accept the risk and record it in the SBOM so it is tracked rather than forgotten. Automating the safe upgrades (patch-level, no breaking change) keeps the tree fresh so the risky manual upgrades stay rare.

**The SBOM is the inventory the rest depends on.** A software bill of materials is a machine-readable list of every component in the application, in a standard format (CycloneDX or SPDX). It is increasingly required by regulation and by customers, and it is also the working artefact that vulnerability tracking and licence policy both read from. Generate it in the build, keep it current, and consume it rather than re-deriving the tree each time.

**Licence risk is a spectrum, not a yes/no.** Permissive licences (MIT, BSD, Apache 2.0, ISC) ask only for attribution. Copyleft licences (LGPL, MPL, GPL, AGPL) impose obligations that escalate from file-level to distribution-level to network-use, and AGPL over a network is the highest risk for a SaaS product. A licence policy names an approved list, a requires-review list, and a blocked list, and the SCA gate fails the build on a blocked licence before it ships.

**Anti-patterns:** treating the raw CVE count as the remediation backlog instead of filtering by reachability and exploitability; editing your own code to fix a vulnerability that lives in a transitive dependency; pinning nothing and letting the tree drift, then facing a wall of major upgrades at once; generating an SBOM once for an audit and never again, so it is stale the day after; ignoring licences until a deal's legal review surfaces an AGPL dependency in production; and scoring findings and inventing SLAs here instead of routing that to `vulnerability-management`.

## Reference router

| Need | Load |
|---|---|
| Direct vs transitive dependencies, advisory data sources, reading CVE/CVSS in the dependency context, reachability analysis, the upgrade/override/accept remediation ladder, update automation | `references/dependency-and-vulnerability.md` |
| SBOM formats (CycloneDX, SPDX, SWID), SBOM generation and consumption, the regulatory drivers, open-source licence classes and their risk, licence policy and CI gating | `references/sbom-and-licence.md` |

## Cross-references

- `application-security`: the vendor-neutral AppSec umbrella. It places SCA among SAST, DAST, and WAF across the pipeline; this skill is that SCA technique in depth. Route strategy and testing-type selection there.
- `vulnerability-management`: the VM programme, CVSS/EPSS/KEV scoring, and remediation SLAs. This skill triages dependency findings in context and routes programme-level scoring and SLA design there.
- `nvd-cve`: single-CVE lookup and the NVD data model. This skill consumes CVE and CVSS records as an input to dependency triage rather than explaining them from scratch.
- `container-security`: the container-image supply chain (image-layer SBOM, SLSA provenance, cosign/Sigstore signing, admission control). This skill owns the application and library layer and the application SBOM; that skill owns how the image is built, signed, and admitted. See the boundary note above.

Vendors such as Snyk Open Source, Mend, Black Duck, and Dependabot are named in the references as examples of SCA tooling; they are prose only and not vault skills.

## Red flags

- About to hand over the full raw CVE list as the remediation backlog instead of filtering to reachable, exploitable, fixable findings.
- About to try to patch a transitive-dependency vulnerability by changing application code rather than upgrading, overriding, or tracking it.
- About to leave the dependency tree unpinned and undated, storing up a wall of breaking major upgrades for later.
- About to generate an SBOM once for a compliance ask and never regenerate it, so it is stale immediately.
- About to defer all licence checking until a deal's legal review, when a build-time gate would have caught the blocked licence.
- About to score findings and set SLAs here instead of routing that to `vulnerability-management`.
- About to treat an image-layer or OS-package finding as this skill's when it belongs to `container-security`, or vice versa.
- About to explain the CVE and CVSS data model from scratch instead of routing the pure lookup to `nvd-cve`.

## Bottom line

Software composition analysis is how an application accounts for the code it did not write: it maps the full dependency tree (mostly transitive), matches it against advisory databases, and uses reachability to turn a flood of matches into the handful of vulnerabilities that actually matter, then remediates by upgrading, overriding, or tracking. In parallel it produces the application SBOM that inventories every component and drives both vulnerability tracking and a licence policy that gates copyleft and commercial risk out of the build. This skill owns the application and library layer and the application SBOM; the container-image supply chain is `container-security`. Route AppSec strategy to `application-security`, programme scoring and SLAs to `vulnerability-management`, and single-CVE lookups to `nvd-cve`.
