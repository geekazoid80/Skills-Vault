# Testing types and routing

This reference describes what SAST, DAST, SCA, and WAF each are at a concept level, how they compose across build, test, deploy, and runtime, and how to route a request to the right technique discipline. The four techniques are complementary lenses on application risk seen at different times, not competing products. Each has its own dedicated vault technique skill for the depth: `static-application-security-testing`, `dynamic-application-security-testing`, `software-composition-analysis`, and `web-application-firewall`; this umbrella carries the concept-level description and the routing.

## The four techniques at a glance

| Technique | Full name | The question it answers | What it looks at | When in the pipeline |
|---|---|---|---|---|
| SAST | Static Application Security Testing | Is there a flaw in the code I wrote? | source code, without running it | development (IDE) and build (CI) |
| DAST | Dynamic Application Security Testing | Is there a flaw in the running application? | the running system, from the outside | test and runtime |
| SCA | Software Composition Analysis | Is there a known flaw in a dependency I pulled in? | the dependency tree and its metadata | build (CI) and continuously |
| WAF | Web Application Firewall | Can I block this attack in production? | live HTTP traffic, at the edge | deploy and runtime |

## SAST: static application security testing

SAST analyses source code (or bytecode, or a binary) without executing it. Its core method is taint analysis: tracking data from a source where untrusted input enters (an HTTP parameter, a header, a form field) to a sink where it could cause harm (a database query, a shell call, an HTML response), and flagging any path where the data reaches the sink without adequate validation or encoding. Because it reads the code directly, SAST sees the widest range of code-level flaw classes (injection, hardcoded secrets, weak cryptography, unsafe deserialisation) and can point at the exact line, which makes it the natural fit for developer feedback.

Strengths: earliest possible detection, precise location, broad language and flaw coverage, and no need for a running environment. Limits: it does not see runtime or configuration issues, and it produces false positives where a path is unreachable in practice, which is why a quality gate that triages findings is essential rather than optional. SAST sits in the IDE for real-time feedback and in CI as a build-stage scan and pull-request diff decoration.

## DAST: dynamic application security testing

DAST exercises the running application from the outside, with no knowledge of the source, by sending crafted requests and observing the responses. It is black-box testing: it sees what an external attacker sees. It excels at flaws that only manifest at runtime, misconfiguration, missing security headers, authentication and session weaknesses, and server-side behaviour that static analysis cannot infer. Driven by an API schema (OpenAPI, GraphQL introspection), it also performs API security testing systematically across every documented endpoint.

Strengths: finds real, exploitable, runtime-confirmed issues with a low false-positive rate, and is language-agnostic. Limits: it needs a deployed running environment, it only reaches the surface it can crawl or is pointed at, it cannot name the offending line, and it runs later in the lifecycle so its findings are more expensive to fix. DAST sits in the test stage against a deployed test environment and, scheduled, against production in operations.

## SCA: software composition analysis

SCA inventories the application's third-party and open-source dependencies (direct and transitive) and matches each against vulnerability databases (NVD, OSV, GitHub Advisory) and licence metadata. It answers OWASP A06 (vulnerable and outdated components) directly, and it produces the Software Bill of Materials (SBOM) that records exactly what shipped. Modern SCA adds reachability analysis, distinguishing a vulnerable dependency that is actually called from one that is merely present, which sharpens prioritisation.

Strengths: covers the large share of application code that is not written in-house, automates dependency-update pull requests, and supplies the SBOM audit trail. Limits: it depends on the completeness and timeliness of the vulnerability databases, and a raw vulnerable-version match without reachability over-reports. SCA sits in CI as a build gate and runs continuously so newly disclosed CVEs surface against already-shipped dependencies. The prioritisation and SLA framework for the CVEs SCA finds belong to `vulnerability-management`; the container image and artefact supply chain (SBOM at the image layer, SLSA provenance, cosign signing) belongs to `container-security`.

## WAF: web application firewall

A WAF sits in front of the running application and inspects live HTTP traffic, blocking or challenging requests that match attack signatures or violate policy (injection payloads, path traversal, known bad bots, request-rate abuse). It is a runtime control, not a testing tool: it does not find flaws in the code, it blocks attempts to exploit them while they remain unfixed. That makes it the last defensive layer and a valuable stop-gap (virtual patching a known vulnerability at the edge buys time to fix the code), but never a substitute for fixing the underlying flaw.

Strengths: immediate protection in production, mitigation for denial-of-service and automated abuse, and virtual patching. Limits: it operates on traffic patterns so it both misses novel attacks and raises false positives on legitimate traffic, requiring tuning; and it addresses the symptom, not the cause. A WAF sits at deploy (rules provisioned) and in runtime (monitored and tuned).

## How the four compose across the pipeline

The techniques are staged so that each covers what the others cannot, at the point in the lifecycle where it is cheapest and most effective:

```
Development   →   Build / CI      →   Test            →   Deploy / Runtime
  IDE SAST         SAST (full)         DAST                WAF (provision)
                   SCA                 API security tests  WAF (monitor + tune)
                   SBOM                                    scheduled DAST
                                                           continuous SCA
```

- **Build time** is where SAST and SCA do their work: the code and its dependencies are both available and nothing is running yet, so flaws are caught before deployment at the lowest cost.
- **Test time** is where DAST takes over: a deployed environment exists, so runtime and configuration flaws that SAST cannot see become visible.
- **Runtime** is where the WAF stands guard, DAST runs on a schedule against the live surface, and SCA keeps matching the shipped dependencies against newly disclosed vulnerabilities.

The composition principle: a flaw that SAST misses (runtime, configuration) DAST may catch; a flaw that neither catches (a zero-day in a dependency disclosed after release) SCA surfaces continuously; and an exploit attempt against any unfixed flaw the WAF can block at the edge while the fix is prepared. Choosing a single technique leaves a gap that one of the others was meant to cover.

## Routing to the technique disciplines

When a request is specifically about one technique, in depth, it routes to that technique's own discipline. SAST, DAST, SCA, and WAF are named here as the four testing techniques this umbrella covers at concept level; their dedicated technique skills land in a later change. Until those exist, answer technique-concept questions from this reference and, for tool-specific configuration, note that the depth is not yet a separate vault skill.

- A question about which technique fits a scenario, or how the four compose: answer here.
- A question about scoring or setting an SLA on the findings any technique produces: route to `vulnerability-management`.
- A question about the container or artefact supply chain behind SCA (image SBOM, provenance, signing, admission): route to `container-security`.
- A question about wiring any of these into a pipeline (workflow, runner, gate mechanics): route to `gh-actions-ci` or `cicd-platforms-ops`.
- A question about secret scanning as a pipeline stage: the credential lifecycle routes to `secrets-hygiene`.
