---
name: completion-gate
description: Use before any claim of "done", "fixed", "passing", "ready to merge", or any expression of satisfaction with code state, AND before pushing any sub-agent diff that exceeds trivial scope, AND when finishing a development branch (verify, push, PR, cleanup). Combines the iron law of verification (no claim without fresh evidence; the gate function; red flags; rationalisation prevention) with the mandatory code-review trigger (run engineering:code-review on diffs over 50 LOC, public-contract changes, or new module additions; skip only for typo, single-line, or bookkeeping diffs) and the incremental write-then-verify-fast loop (typechecker, schema validators, lint preemptively after writes, without pausing to ask permission). Layer 2 includes the BASE_SHA / HEAD_SHA dispatch pattern, the four-severity response model (Critical / Important / Minor / push-back) for code-review subagent dispatch, the deep security-review pass (5-phase attack-surface + checklist sweep folded from getsentry/skills/find-bugs), and the reception discipline for incoming review feedback (no performative agreement, verify against codebase before implementing, ask if unclear, push back with technical reasoning); the dispatch pattern folded from obra/superpowers/skills/requesting-code-review and the reception discipline from obra/superpowers/skills/receiving-code-review. Layer 4 covers branch finishing (verify, push, PR with squash-merge convention, worktree cleanup); folded from obra/superpowers/skills/finishing-a-development-branch. Operational superset; further source skills will be folded in over time.
metadata:
  version: 1.3.0
---

# Completion Gate

> **Skill marker**: When applying this skill, begin your reply with `[skill: completion-gate]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Four layers, in order. Each catches a different class of problem.

1. **Incremental fast checks during work** (write-then-verify-fast). Catches type errors, broken schemas, broken doc lints before they propagate.
2. **Code-review pass before push.** Catches semantic bugs the test suite does not cover. Includes the reception discipline for incoming review feedback.
3. **The completion gate** (the iron law). Catches false claims. No "done" without fresh evidence in this turn.
4. **Branch finishing.** After Layer 3 passes, push to remote, open PR per the squash-merge convention, clean up the worktree per provenance.

**Core principle:** evidence before claims, always. Violating the letter is violating the spirit.

## Layer 1: Write-then-verify-fast (during work)

When code is written or edited that affects type-correctness, run the typechecker WITHOUT pausing to ask permission. Same for schema validators and structural lints. Treat as a tight loop: write, verify, fix, write, verify.

| What you wrote | Run immediately | Why |
|---|---|---|
| TypeScript change | `pnpm typecheck` or `tsc --noEmit` | Type errors are cheaper to find before moving on |
| Python change with type hints | `mypy` or `pyright` | Same |
| Rust change | `cargo check` | Same |
| Go change | `go build ./...` | Same |
| Prisma schema edit | `pnpm db:format && pnpm db:validate` | Catches schema-shape errors before migration generation |
| SQL migration | `pnpm db:check-portability` (or equivalent) | Catches dialect drift |
| AGENTS.md / docs structural move | `pnpm lint:agents-md` / doc-presence lint | Catches missing per-module AGENTS.md |
| Anything that touches the public API | Re-run the OpenAPI / schema-export script | Catches contract drift |

The full test suite is slower and noisier. Only run it when wrapping up the chunk or when behaviour changed. The fast checks above are the in-flight loop.

## Layer 2: Code-review pass before push

Before pushing any sub-agent diff (or any inline diff that exceeds the trivial bar), invoke the project's code-review skill on the diff. The local typecheck and tests catch what existing tests already cover; code-review catches what they do not (semantic bugs, missing error paths, N+1 queries, decorator misplacement, race conditions, the wrong exception bubbling up).

### Mandatory triggers (run, not "consider")

- Sub-agent diff that changes more than 50 LOC.
- Diff that touches a public contract (engine method signature, port shape, exported schema, controller pattern, env-var name, decorator placement).
- Diff that adds a new module or integration.

### Skip ONLY for trivial diffs

- Typo fixes.
- Single-line adjustments.
- Bookkeeping commits (status flips, archive appends, roadmap updates).

### How to invoke

#### Pin the diff with explicit SHAs

Folded from obra/superpowers/skills/requesting-code-review. Always dispatch the reviewer subagent against an explicit BASE / HEAD SHA pair, not against `HEAD~N` shorthand. The reviewer gets a precisely scoped diff and can't accidentally widen its review to commits the user didn't intend.

```bash
BASE_SHA=$(git rev-parse origin/main)   # or the parent task's commit for per-task review
HEAD_SHA=$(git rev-parse HEAD)
```

Then dispatch via the `Agent` tool (subagent_type=`general-purpose`) with the diff range, a one-paragraph DESCRIPTION of what the diff is meant to do, and the PLAN_OR_REQUIREMENTS the diff is meant to meet. The reviewer evaluates whether the diff matches the description and meets the requirements; it does NOT inherit the master's session context.

Mandatory reviews follow the trigger list above. Optional reviews are valuable in three more situations:

- When stuck (fresh perspective on the problem).
- Before refactoring (baseline check on the current code's correctness).
- After fixing a complex bug (verify the fix doesn't introduce a regression elsewhere).

#### Write the reviewer's brief honestly

Four rules on how the brief is worded. The failure they prevent is subtle: master, wanting to avoid another review round, quietly writes the brief so the review comes back clean.

- **Treat the implementer's report as unverified claims.** Verify against the diff, not against the report. Design rationales are claims too: "left it per YAGNI" or "kept it simple deliberately" is the implementer grading its own work, and a stated rationale never downgrades a finding's severity.
- **Never tell a reviewer to ignore something.** If the brief you are writing contains "do not flag", "don't treat X as a defect", "at most Minor", or "the plan chose this", stop. You are pre-judging the review to spare yourself a loop. (This is distinct from a legitimate threat-model scope boundary, as in the GHA reviewer's do-not-flag list, where the exclusions define what the reviewer is *for*.)
- **Do not ask a reviewer to re-run tests the implementer already ran** on the same code; the implementer's report carries that evidence. Warnings or other noise in the reported test output are themselves findings, because test output should be pristine.
- **Reviews are read-only on the checkout.** No mutation of working tree, index, HEAD, or branch state.

One rationalisation to name, because it defeats the whole layer rather than just weakening a brief:

| Excuse | Reality |
|---|---|
| "I'll just review the diff myself instead of dispatching a reviewer" | Reviewing inline burns the coordinator's context on the diff, permanently, and then reviews the work with the same assumptions that produced it. Dispatch, so the diff lives in the subagent's context and only findings come back. |

The companion excuse ("the reviewer needs my whole session history") is already answered above: the reviewer does NOT inherit master's session context, and that is the point, not a limitation to work around.

#### Act on the four severity levels

The reviewer subagent returns issues at four severity levels. Master's action per level:

| Severity | Action |
|---|---|
| **Critical** | Fix immediately. Do not push. Do not move to next task. |
| **Important** | Fix before proceeding (before push for inline diffs; before next task in a plan-execution loop). |
| **Minor** | Note for later. Acceptable to push the current diff and address in a follow-up. |
| **(Reviewer is wrong)** | Push back with technical reasoning. Show the code or tests that prove the reviewer's concern is misplaced. Request clarification rather than silently dismissing. Don't argue with valid feedback; do argue with bad feedback. |
| **(The requirement is wrong, not the diff)** | A reviewer can conclude the diff faithfully implements a plan that is itself defective. That is not a diff finding and it does not belong in the four levels above: present the finding and the plan or spec text it collides with, and ask which governs via `AskUserQuestion`. Do not have the implementer "fix" the diff into contradicting the plan, and do not dismiss the finding because the plan mandated it. |

Tell the reviewer this channel exists. Without it, a reviewer who spots a plan defect either files it as a Critical against innocent code or drops it.

If the reviewer's findings are non-trivial (multiple Important issues, or the fix would substantially change the diff), bring them to `AskUserQuestion` with the bundle / follow-up PR / accept-gap options (see the `subagent-delegation` skill for the four-option pattern).

This is in ADDITION to (not instead of) blast-radius grep and adjacent-pattern scan from `subagent-delegation`. Each catches a different class of issue:

- Blast-radius grep: who else uses this contract?
- Adjacent-pattern scan: where else does this same pattern exist?
- Code review: is the diff itself correct?

#### Deep security review pass (when stakes warrant)

Folded from getsentry/skills/find-bugs. Use when the diff touches user-facing input handling, authentication / authorisation, session state, persisted data, cryptography, or anything the GHA security review would also flag (workflows, hooks). Distinct from the standard code-review subagent: that one looks for general bugs and quality issues; this one is a focused security-and-bugs sweep with a structured checklist.

Run as a separate subagent dispatch with this brief:

**Phase 1: complete input gathering.** Get the full diff (`git diff <base>...HEAD`) for the branch. If output is truncated, read each changed file individually until every changed line has been seen. List all modified files before proceeding.

**Phase 2: attack surface mapping.** For each changed file, identify and list:

- All user inputs (request params, headers, body, URL components).
- All database queries.
- All authentication / authorisation checks.
- All session / state operations.
- All external calls (vendor API, downstream service, file system, shell).
- All cryptographic operations.

**Phase 3: security checklist (check EVERY item for EVERY relevant file).**

- Injection: SQL, command, template, header injection, NoSQL injection.
- XSS: outputs in templates properly escaped.
- Authentication: auth checks present on all protected operations.
- Authorisation / IDOR: access control verified, not just "user is authenticated".
- CSRF: state-changing operations protected.
- Race conditions: TOCTOU in any read-then-write patterns.
- Session: fixation, expiration, secure / httpOnly / sameSite flags.
- Cryptography: secure random sources, current algorithms, no secrets in logs.
- Information disclosure: error messages, logs, timing-side-channel attacks.
- DoS: unbounded operations, missing rate limits, resource exhaustion.
- Business logic: edge cases, state-machine violations, numeric overflow / underflow.

**Phase 4: verification per potential finding.** For each issue:

- Check whether it is already handled elsewhere in the changed code (don't double-report).
- Search for existing tests covering the scenario.
- Read surrounding context to verify the issue is real, not a false positive.

**Phase 5: pre-conclusion audit.** Before finalising, the subagent MUST:

1. List every file reviewed and confirm each was read completely.
2. List every checklist item and note whether issues were found or it was confirmed clean.
3. List any areas that could NOT be fully verified and why.
4. Only THEN provide the final findings.

**Output format per finding:**

- **File:Line** with a brief description.
- **Severity:** Critical / High / Medium / Low.
- **Problem:** what is wrong.
- **Evidence:** why this is real (not already fixed; no existing test).
- **Fix:** concrete suggestion.
- **References:** OWASP, RFCs, or other standards if applicable.

If nothing significant is found, the subagent says so. Do NOT invent issues.

Cross-reference: `subagent-delegation` § Specialist review dispatches catalogues the GHA security review (the workflow-side equivalent of this code-side deep pass).

#### Receiving review feedback (from a reviewer subagent OR from a human)

Folded from obra/superpowers/skills/receiving-code-review. The reception discipline applies to feedback from any source: a code-review subagent's return, a human PR reviewer's comments, a vendor's response, an internal reviewer's pushback.

**The response pattern (in order):**

1. **Read** the complete feedback without reacting.
2. **Understand** by restating the requirement in your own words (or ask if unclear).
3. **Verify** against the actual codebase or current state. The reviewer might be wrong; the code might already do what they're asking; the request might break something.
4. **Evaluate** technical soundness for THIS context (codebase, project conventions, constraints, prior ADRs).
5. **Respond** with technical acknowledgement or reasoned pushback.
6. **Implement** one item at a time, testing each, in this order: clarify every unclear item first, then blocking and security fixes, then the simple fixes, then the complex ones. Ordering matters because a complex fix built on a misunderstood item gets redone, and a security fix deferred behind cosmetics is a security fix that slips.

**When an item cannot be verified at step 3**, say so rather than guessing. Step 3 assumes verification is possible; when it is not (the behaviour needs a live environment, a vendor response, or data you do not have), the honest response is "I can't verify this without X. Should I investigate, ask you, or proceed on the assumption that Y?" Silently implementing an unverifiable suggestion is how a plausible-but-wrong review comment becomes committed code.

**Forbidden responses (no exceptions):**

- "You're absolutely right!"
- "Great point!" / "Excellent feedback!"
- "Thanks for catching that!" / any gratitude expression
- "Let me implement that now" before verification

These are performative and read as theatre. Replace with one of:

- A technical restatement of the requirement.
- A clarifying question.
- A technical pushback with reasoning.
- Just the fix, in code, with a one-line commit message naming the change.

If you catch yourself about to write "Thanks": delete it. State the fix instead.

**Handling unclear feedback:** if any item is unclear, STOP. Do not implement anything yet. Ask for clarification on the unclear items. Items may be related; partial understanding equals wrong implementation.

**When to push back:** when the suggestion breaks existing functionality, the reviewer lacks full context, the suggestion violates YAGNI (unused feature), the suggestion is technically incorrect for this stack, legacy or compatibility reasons exist, or the suggestion conflicts with prior architectural decisions (ADRs). How: technical reasoning, not defensiveness; ask specific questions; reference working tests or code; involve the user if architectural.

**Establishing the YAGNI case: grep before you build.** "Implement this properly" and "this should handle the general case" are the most common review suggestions, and the most common source of speculative code. Before building it out, grep the codebase for actual usage of the thing being generalised. If nothing uses it, the finding inverts: propose **removing** the partial implementation rather than completing it, and say what the grep showed.

This is the actionable half of the YAGNI pushback above. Listing YAGNI as a valid reason to push back is not much use without the one command that settles whether it applies.

**If you pushed back and were wrong:** "You were right; I checked X and it does Y. Implementing now." State the correction factually and move on. No long apology, no over-explaining.

**GitHub thread replies:** when replying to inline review comments on a GitHub PR, reply in the comment thread (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), not as a top-level PR comment. Keeps the conversation threaded next to the line of code.

## Layer 3: The completion gate (iron law)

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not run the verification command in this message, you cannot claim it passes.

### The gate function

Before claiming any status or expressing satisfaction:

1. **IDENTIFY:** what command proves this claim?
2. **RUN:** execute the FULL command (fresh, complete).
3. **READ:** full output, check exit code, count failures.
4. **VERIFY:** does output confirm the claim?
   - If NO: state actual status with evidence.
   - If YES: state claim WITH evidence.
5. **ONLY THEN:** make the claim.

Skip any step = lying, not verifying.

### Common failures

| Claim | Requires | Not sufficient |
|---|---|---|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test the original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

### Red flags (STOP)

- Hedge words: "should", "probably", "seems to".
- Expressions of satisfaction before verification: "Great!", "Perfect!", "Done!".
- About to commit, push, or open a PR without verification.
- Trusting agent success reports.
- Relying on partial verification.
- "Just this once".
- Tired and wanting work over.
- ANY wording implying success without having run verification in this turn.
- About to `git worktree remove --force` after a refusal. The refusal means files exist only in that worktree; `--force` destroys them. Show the human partner and ask (see Layer 4 Step 5).

### Rationalisation prevention

| Excuse | Reality |
|---|---|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter is not a compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion is not an excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so the rule doesn't apply" | Spirit over letter |

### Key patterns

**Tests:**
```
right:  Run test command, see 34/34 pass, then "all tests pass"
wrong:  "should pass now" / "looks correct"
```

**Regression tests (red-green):**
```
right:  Write the test, run (pass), revert the fix, run (MUST FAIL),
        restore the fix, run (pass)
wrong:  "I have written a regression test" without the red-green cycle
```

**Build:**
```
right:  Run build, see exit 0, then "build passes"
wrong:  "linter passed" (linter does not check compilation)
```

**Requirements:**
```
right:  Re-read the plan, build a checklist, verify each, report gaps
        or completion
wrong:  "tests pass, phase complete"
```

**Agent delegation:**
```
right:  Agent reports success, check the VCS diff, verify changes,
        report actual state
wrong:  Trust the agent report
```

## Layer 4: Branch finishing

Folded from obra/superpowers/skills/finishing-a-development-branch. Once Layer 3 (the iron law) confirms the work is genuinely done, the chunk is ready to land. The fixed workflow in this vault is push-then-PR-with-squash-merge-and-delete-branch, NOT a 4-option menu (the upstream's local-merge and discard options aren't part of the standard workflow here).

### Step 1: Verify tests one more time

You already ran the verification command in Layer 3 to support the "done" claim. Re-running it as the first step of finishing is cheap insurance against the gap between "I claimed done" and "the work is actually about to land". If the test command was slow and you ran a partial check earlier, run the full suite now.

### Step 2: Detect environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# Capture WORKTREE_PATH here, while still inside the workspace. Step 5 changes
# directory before cleanup and needs this value; re-deriving it there resolves
# against the main repo root instead and the cleanup silently no-ops.
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

This determines cleanup behaviour at the end (see Step 5). The submodule guard from `using-git-worktrees` applies.

**Do not reorder Step 2 and Step 5.** The capture above has to happen before any directory change, which is why it lives in Step 2 rather than next to the cleanup that consumes it. Upstream shipped exactly this bug and fixed it in v6.2.0; this vault's ordering was already correct, so the comment is here to stop a future edit from "tidying" the capture down into Step 5.

### Step 3: Push and open PR

**First, confirm the base branch.** A bare `gh pr create` silently targets the repository's default branch. That is usually right and occasionally expensive: merging into the wrong base is painful to undo, and "When NOT to use Layer 4" below already acknowledges that stacked-PR sequences happen in this vault, which is exactly the case where the default is wrong.

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null   # what this branch tracks
BASE=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
echo "opening PR against: $BASE"
```

If this branch was cut from anything other than `$BASE`, pass `--base <branch>` explicitly. When in doubt, ask: "this branch split from X, should the PR target X or main?"

```bash
git push -u origin <branch-name>
gh pr create --base "$BASE" --title "<concise title under 70 chars>" --body "$(cat <<'EOF'
## Summary

<2-3 bullets of what changed>

## Test plan

- [ ] <verification steps the reviewer can run>
EOF
)"
```

The PR title and body live elsewhere (project conventions, `humanise-comms` for tone). The point of this step is the mechanical push-and-create.

Also verify the pushed ref before opening the PR: `git ls-remote origin refs/heads/<branch>` should equal `git rev-parse HEAD`. Server truth, and it is shallow-clone-safe where `git rev-parse origin/<branch>` is not.

### Step 4: Merge with squash and delete-branch

The standard pattern in this vault. After review (or immediately for trivial PRs the user has authorised auto-merge for):

```bash
gh pr merge <pr-number> --squash --delete-branch
```

This deletes the remote branch as part of the merge. The local branch survives until you explicitly delete it (see Step 5).

### Step 5: Cleanup workspace

After the merge:

- **Local branch.** Switch off the branch first (`git switch --detach origin/main` or check out main), then `git branch -D <branch-name>`. Git refuses to delete a branch that is checked out in any worktree, so this step has to come after switching.
- **Worktree, if applicable.** If the worktree path is under `.claude/worktrees/`, the harness owns cleanup; do NOT remove it manually. The harness will clean up when the session ends. If you created a manual worktree under some project-local path (rare in this vault per `using-git-worktrees`), use `git worktree remove` from the main repo root, then `git worktree prune` to clean up stale registrations. If `git worktree remove` is refused (`contains modified or untracked files`), the worktree holds files that exist nowhere else, uncommitted plans, notes, or scratch work. Do NOT `--force` on your own initiative. Show what is at stake (`git -C "$WORKTREE_PATH" status --porcelain -uall`) and ask which of three: commit them to the branch before cleanup, move them into the main repo root, or delete them (unrecoverable). Carry out the choice, then remove the worktree.
- **Pruning remote-tracking refs.** `git fetch --prune` after the merge to remove the now-stale `origin/<branch-name>` ref.

### Quick reference for Layer 4

| Step | Action |
|---|---|
| 1 | Re-run verification (Layer 3 evidence is fresh; this is the belt-and-braces) |
| 2 | Detect environment (worktree vs normal repo, submodule guard) |
| 3 | Confirm the base branch; `git push -u origin <branch>`; verify `git ls-remote` equals local HEAD; `gh pr create --base <base>` |
| 4 | `gh pr merge <pr-number> --squash --delete-branch` |
| 5 | Switch off branch; `git branch -D <branch>`; let harness handle worktree if path is `.claude/worktrees/`; `git fetch --prune` |

### When NOT to use Layer 4

- The branch is part of a stacked-PR sequence and merging it would orphan the children. Hold the merge or use the rebase-and-replace pattern (see PR #5/#6/#7's history for the worked example).
- The PR has open required reviews, failing CI, or merge conflicts. Resolve before invoking Layer 4.
- The user explicitly says "hold this PR for now" or "don't merge yet".

## When to apply

ALWAYS before:

- Any variation of success or completion claims.
- Any expression of satisfaction.
- Any positive statement about work state.
- Committing, opening a PR, or marking a task complete.
- Moving to the next task.
- Delegating to a sub-agent (the gate applies to the work the sub-agent says it finished, too).

The rule applies to:

- Exact phrases ("done", "passing", "fixed").
- Paraphrases and synonyms ("looks good", "ready to merge", "wrapped").
- Implications of success.
- ANY communication suggesting completion or correctness.

## Bottom Line

Layer 1: incremental checks while you work, no permission needed. Layer 2: code-review on every meaningful diff before push, plus the reception discipline for incoming feedback (no performative agreement, verify before implementing). Layer 3: no claim of done without fresh evidence in this turn. Layer 4: push, PR, squash-merge with delete-branch, cleanup. Run the command, read the output, THEN claim the result. This is non-negotiable.
