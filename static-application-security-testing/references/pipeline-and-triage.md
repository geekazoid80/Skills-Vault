# Pipeline and triage

This reference covers the operational half of SAST: where it attaches in the development lifecycle, how incremental and pull-request scanning keep it fast enough to be tolerable, how to design a quality gate that blocks the right findings without drowning developers, how SARIF carries findings between tools, and how to triage and suppress findings so the noise floor stays low and auditable. The analysis engine finds candidates; this discipline decides which ones a human ever sees and which ones stop a merge.

## Where SAST attaches in the lifecycle

SAST is useful at two points, and mature programmes run both:

- **IDE (development):** the analysis runs as the developer types or saves, flagging a flaw at the moment and place it is introduced. This is the cheapest possible feedback, and it is advisory, never blocking. A lighter, faster rule set runs here; the full analysis runs in CI.
- **CI (build):** the analysis runs on every push or pull request as a pipeline stage. This is where the quality gate lives and where a finding can block a merge. It is also where the full, expensive inter-procedural analysis runs, because CI can afford minutes that an editor cannot.

Scheduled full scans of the whole codebase complement both: they run the deepest rule set against everything (not just changed code), catch findings that incremental scanning skipped, and feed trend metrics and the security backlog rather than gating a specific merge.

## Incremental and pull-request scanning

A full deep scan of a large codebase can take too long to sit in front of every pull request. Incremental scanning keeps SAST fast enough to gate:

- **Changed-file or diff scanning:** analyse only the files touched by the change, or the new and modified code relative to a baseline commit. This keeps a pull-request scan in the low-minutes range that developers tolerate.
- **Baseline comparison:** compare the current findings against a recorded baseline so the gate can distinguish newly introduced findings from pre-existing ones. Blocking a merge only on new findings is the single most important move for adoption: it holds the line on fresh code without demanding the team first clear years of legacy debt.
- **Pull-request decoration:** annotate the findings inline on the diff in the code host, so the developer sees the flaw on the exact line they just wrote, in the review they are already doing, rather than in a separate dashboard they must be trained to visit.

Incremental scanning trades completeness for speed and belongs on the pull-request path; the scheduled full scan restores completeness off the critical path.

## Quality-gate design

A quality gate is the rule that turns a set of findings into a pass or fail decision. Designing it is where SAST succeeds or gets ignored:

- **Gate on new code, not the whole backlog.** Fail the build on findings introduced by this change; track pre-existing findings separately. Gating the entire backlog at once floods developers and gets the gate disabled.
- **Gate on high confidence and high severity first.** Start by blocking only the findings the tool is most confident about at the highest severities, and keep everything else as advisory. A gate that blocks on low-confidence medium findings trains developers to override it, which destroys its authority.
- **Grow the gate over time.** Tighten the threshold as the false-positive rate drops and the team's trust rises. The gate is a ratchet, not a fixed switch: introduce feedback first, then a baseline, then blocking, then a stricter blocking bar.
- **Keep the pull-request scan fast.** A gate that adds many minutes to every pull request is a gate developers learn to resent and route around. Fast incremental scanning is a precondition for a credible gate, not a separate concern.

Some tools distinguish a confirmed vulnerability from a security hotspot (a security-sensitive construct that needs a human judgement about whether it is actually a flaw). Treat hotspots as review prompts, not automatic gate failures, or the gate inherits their noise.

### Maturity levels

A useful ladder for placing a programme and choosing the next step:

- **Level 1:** SAST runs, results are reviewed manually, nothing is gated.
- **Level 2:** SAST runs in CI, the gate blocks on high-severity new findings, results are tracked in a backlog.
- **Level 3:** SAST runs in the IDE and CI plus scheduled full scans, gated by severity and confidence, with custom rules for organisation-specific patterns and metrics on a dashboard.
- **Level 4:** SAST is tied to the threat model, carries custom rules for business-logic patterns, drives SLA-based remediation, and is supported by developer security champions.

The point of the ladder is to move one rung at a time. Jumping straight to a strict gate over an untuned tool produces the flood that gets SAST switched off.

## SARIF as the interchange format

SARIF (Static Analysis Results Interchange Format), an OASIS standard, is the common representation for static-analysis findings. It matters because it decouples the scanner from everything downstream:

- A finding carries its rule id, message, severity, physical location (file, line, region), and often the code-flow steps of the taint path, in a structured form any consumer can read.
- Code hosts ingest SARIF to render findings inline on pull requests and in a security tab without bespoke parsing per tool.
- A backlog or aggregation layer merges SARIF from several tools into one view, deduplicating and tracking a finding across scans by its stable location and rule.

Prefer emitting and consuming SARIF over hand-parsing a tool's native output: the disposition, the baseline comparison, and the code-host decoration all rely on the structured form. Where a tool offers only native output, converting to SARIF at the boundary keeps the rest of the pipeline tool-agnostic.

## False-positive triage and suppression hygiene

A false-positive rate is inherent to static analysis (see the "what SAST misses" section of `concepts-and-analysis.md`), so triage is a standing practice, not a one-off cleanup. Every finding gets a disposition:

- **True positive:** a real flaw. Fix it, ideally in the same change that introduced it, then re-scan to confirm the finding clears.
- **False positive:** the tool is wrong (an unreachable path, an unrecognised custom sanitiser, a construct that is safe in context). Suppress it with a recorded reason.
- **Accepted risk:** a real flaw the organisation has decided not to fix now. Track it as an accepted risk with an owner and a review date, not as a silent suppression.

**Suppression hygiene** keeps the suppression list from becoming a blanket that hides the next real issue:

- **Record a reason on every suppression.** A suppression with no justification is indistinguishable from a bug being hidden. The reason makes the decision auditable later.
- **Scope the suppression as narrowly as possible.** Suppress a specific finding at a specific location, not a whole rule across the repository. A broad rule-level disable silently swallows every future instance, including real ones.
- **Prefer fixing the tool's model over suppressing the symptom.** If a custom sanitiser is causing many false positives, register it so the whole class clears legitimately, rather than suppressing each finding one by one.
- **Keep suppressions in version control and review them.** Inline suppression annotations and configuration files both belong in the repository so a suppression goes through the same review as code, and stale suppressions can be found and removed.
- **Exclude the right paths, deliberately.** Test fixtures, generated code, and vendored dependencies are common, legitimate exclusions, but each exclusion is a blind spot and should be a considered choice, not a default sweep. Vendored dependency risk belongs to composition analysis, not SAST.

The objective of the whole triage loop is a low, trusted noise floor: a developer who sees a SAST finding on their pull request should believe it, because the false positives have been dispositioned and the suppressions are auditable. That trust is what a quality gate spends, and suppression hygiene is what keeps refilling it.

## Where the boundaries sit

- **Pipeline authoring and gate mechanics** (writing the workflow, the runner, the failing-step wiring) belong to `gh-actions-ci` and `cicd-platforms-ops`. This reference decides what the SAST stage should check and when it should block; those build the stage.
- **Scoring a confirmed finding, and setting a remediation SLA on it,** belong to `vulnerability-management`. Triage here produces a confirmed true positive; the CVSS/EPSS scoring and the SLA framework are that programme's job.
- **A hardcoded-secret finding** can surface in a SAST run, but the credential lifecycle, the gitignored-secret pattern, and the leak-response procedure belong to `secrets-hygiene`.
