# Pipeline and triage

This reference covers where a DAST stage belongs in a CI/CD pipeline, why the target environment matters (staging versus pre-prod versus production), how to control scan timing and scope so a scan stays bounded and safe, the scan profile that fits each environment, and how to triage findings and re-test after a fix. It decides where DAST attaches and how it is scoped; authoring the workflow and its gate mechanics belongs to the CI/CD skills.

## Why DAST needs a deployed target

DAST tests a running application, so a pipeline that runs DAST must first deploy the application somewhere reachable, then point the scan at it. This is the structural difference from static analysis or dependency scanning, which run against the repository with nothing deployed. A DAST stage therefore has a hard dependency on a deploy stage and a readiness check:

- Deploy the build to a test environment as a pipeline stage.
- Wait for the application to become healthy (poll a health endpoint until it responds) before starting the scan, so the scan does not race the deploy and report a dead target as findings.
- Run the scan against that environment's URL.
- Publish the results in a machine-readable format (for example SARIF) so the pipeline and the security backlog can ingest them.

## Choosing the target environment

Where the scan points decides both its value and its risk.

- **Staging or pre-prod is the home of active scanning.** These environments mirror production configuration closely enough that findings are representative, but hold disposable data and can absorb the side effects of an active scan. A full active scan belongs here.
- **Production is passive-only, if it is scanned at all.** Active scanning against production risks data modification, denial of service, and lockouts against real users. If production is monitored by DAST, it is in passive mode, observing real traffic for misconfiguration and header regressions without sending attack payloads.
- **A developer's local instance** is for on-demand passive checks or a narrow active scan of the single feature under development, not a full scan.

The closer the target's configuration is to production, the more trustworthy the findings; the further its data is from real, the safer active scanning is. Staging is the sweet spot because it can be both.

## Scan timing and scope control

An unbounded scan is both slow and dangerous. Two levers keep it in hand: how long it runs, and what it is allowed to touch.

**Timing.** Match scan duration to where it runs in the pipeline. A gate that blocks a pull request must finish in minutes, so it runs a passive scan or a short active scan limited to the endpoints the change touched. A deep scan runs on a schedule (overnight against staging) where hours are available and no developer is waiting.

**Scope control.** Tell the scanner exactly what is in and out of bounds:

- **Allowlist the target.** Constrain every request to the application under test (for example only the staging host and its paths) so the scan cannot wander onto third-party domains, shared services, or production.
- **Denylist the dangerous endpoints.** Exclude logout and session-invalidation routes (so the scan does not log itself out), and exclude irreversible or costly actions (delete, payment, bulk-email, provisioning) so an active payload cannot fire them.
- **Cap the scan.** Set a maximum duration and crawl depth so an active scan on a gate cannot run away.
- **Prefer passive mode where side effects are unacceptable.** If the only available target carries any risk, passive-only removes the side-effect class entirely.

## Scan profiles per environment

A single scan configuration does not fit every point in the pipeline. Match the profile to the environment and the time budget:

| Environment | Scan type | Scope | Cadence |
|---|---|---|---|
| Developer local | Passive only, or narrow active | The single page or feature under development | On demand |
| Pull-request gate (CI) | Active, tightly limited | Endpoints the change touched | Minutes, blocking |
| Staging | Full active scan | The whole application | Overnight, scheduled |
| Pre-prod | Full active scan | The whole application, production-like config | Before release |
| Production | Passive only | All real traffic | Continuous, non-blocking |

The pull-request profile trades depth for speed: it catches obvious regressions on changed surface without holding up the merge. The staging and pre-prod profiles trade speed for depth: they run the full active scan where there is time and no user waiting. Production, if scanned, only observes.

## Triage and re-test

A scan report is an input to triage, not a fix list. Because DAST findings are runtime-confirmed, the false-positive rate is lower than static analysis, but it is not zero, and untriaged findings that flood a backlog get the whole programme ignored.

**Common false positives to expect:**

- Cross-site-scripting payload reflected into a non-HTML response (for example echoed in a JSON body that is never rendered in a browser context, so not exploitable).
- An SQL error string in a response that the scanner reads as an injection indicator when the application merely surfaces database errors.
- Rate-limiting or lockout responses (a burst of 429s) that the scanner counts as failures rather than a working control.

**The triage steps:**

1. **Reproduce.** Can the finding be reproduced by hand against the running application? A finding that will not reproduce is not actionable.
2. **Check context.** Is the response actually rendered or executed in a context where the payload matters, or is it inert (reflected into a non-executing sink)?
3. **Assess severity.** Weigh the real exploitability and impact, and route the finding to `vulnerability-management` for the scoring model and SLA rather than scoring it here.
4. **Suppress with a reason.** If it is a confirmed false positive, suppress it and record why, so the next scan does not re-raise it and the next person does not re-investigate it. An undocumented suppression is a landmine for the next reviewer.

**Feeding the backlog.** Configure the pipeline to raise findings above a severity threshold into the tracker (an issue per new finding), carrying the reproduction (request/response pair), the OWASP category, the recommended fix, and the scanner version and scan date. This keeps the audit trail attached to the finding.

**Re-test, do not assume.** After a fix ships, re-run the scan (or the targeted check) against the running application to confirm the finding is actually closed. DAST is uniquely suited to this because it verifies against runtime behaviour: a fix that looks right in code but does not change the response is caught only by re-testing the running app. A finding is not resolved until a re-test confirms it.

## Where this stops and the CI/CD skills take over

This reference decides where a DAST stage sits, what environment it targets, how it is scoped, and how its output is triaged and re-tested. Authoring the actual workflow (the runner, the job graph, the pass/fail gate, secret injection for scan credentials) is the province of `gh-actions-ci` and `cicd-platforms-ops`; the scoring model and remediation SLA that consume the triaged findings are the province of `vulnerability-management`.
