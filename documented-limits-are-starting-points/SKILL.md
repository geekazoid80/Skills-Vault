---
name: documented-limits-are-starting-points
description: "Use when about to declare \"can't\" / \"not supported\" / \"opaque from CLI\" / \"requires X permission\" based on a documented limitation (AGENTS.md, runbook, tooling-quirks list, MCP tool description, API doc, error message, harness restriction). Triggers include \"opaque from CLI\", \"requires X permission I don't have\", \"not exposed by the API\", \"the docs say not to\", \"the harness blocks this\", \"no direct query\", \"is not supported\", \"not possible without Y\". NOT for hard security boundaries that exist BY DESIGN (no personal-data egress, no SaaS aggregator dependency, no unauthenticated public surface, secrets in code, bypassing the port layer); those documented limits ARE terminal. Iron rule: every other documented limitation is a starting point for the adjacent capability path, not a wall. Before declaring blocked, scan for alternative API endpoint, different permission scope the tool already has, alternative tool exposing the same signal, fallback strategy (digest, scrape, compute-from-related-state). ALSO fires when a fetch or HTTP failure is about to be read as a fact about the host: \"403\", \"401\", \"blocked\", \"unreachable\", \"egress\", \"blocked by egress policy\", \"the site is blocking us\", \"source is down\", \"empty response\", \"empty body\", \"returns a JavaScript shell\", \"degraded run\", \"could not reach\". Retry the same URL through a different path (curl with a browser user-agent vs the built-in fetch tool) before declaring any source unreachable, name which paths were tried, and report three outcomes rather than two: nothing found, could not look, could not look WITH THIS TOOL."
---

# documented-limits-are-starting-points

> Skill marker: when this fires, emit `[skill: documented-limits-are-starting-points]` on its own line.

## Overview

When tooling docs, AGENTS.md, runbooks, or MCP tool descriptions say a thing isn't possible, that's almost always a STARTING POINT for finding the workaround, not a terminal wall. The documented limitation tells you which path is blocked; that's useful information. It does NOT tell you no path exists. Most "limitations" are scope-specific (this permission, this endpoint, this tool version) and have an adjacent path with overlapping capability.

The reflex to fix: when a doc says "can't", don't relay it to the user as a wall; run the four-path scan first, and only escalate if all four come up empty AND the limitation looks design-intentional.

## The iron rule

> Documented limitations are starting points for the workaround, NOT terminal walls.

Before declaring something blocked, run the four-path scan. If all four come up empty AND the limitation matches the red-flag carve-out below (security, compliance, architectural invariant, hard rule), THEN it's a wall.

## The four-path scan

When the doc says "X is not possible / opaque / requires Y you don't have":

1. **Adjacent endpoint / API.** Is there a different endpoint exposing overlapping data via a different field set? Often a "v1 doesn't support" maps to a "v2 does"; or one API surface mirrors another (Checks API ↔ Actions API; vault read ↔ vault kv get).

2. **Different permission scope you already have.** The blocked path needs scope X; what scope does your token / role / capability already carry that might cover an adjacent path? PATs often carry several scopes; one of them usually overlaps.

3. **Alternative tool exposing the same signal.** The wrong tool says no; another tool might say yes. Examples: SSHFS read when a CLI subcommand is missing; web scrape of a public page when the API doesn't expose it; a sibling MCP tool when the primary one's schema is stale.

4. **Fallback that computes from related state.** Sometimes the direct query is blocked but the answer is derivable from logs, audit trails, related entities, or a separately-stored materialised view.

Update the doc the moment you find a workaround. Future-you (or future-session) should not re-derive.

### Path 3 in detail: a failure from ONE tool path is not a fact about the host

The commonest version of this scan is the one most often skipped, because the "documented limit" is not
in a doc at all, it is an error you just received. A 403, a 401 without auth, an empty body, or a
JavaScript shell where the content should be tells you what happened to **that request, through that
tool**. It tells you nothing about whether the host will serve you.

Retry the same URL through a different path before concluding anything:

```sh
curl -s -m 30 -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" "<url>"
```

Two fetch paths do not share a user-agent, an egress route, or a reputation profile, so a bot-mitigation
front end can answer them differently, minutes apart, for the same URL. If `curl` returns content where
the built-in fetch returned 403, the block is that tool's egress path or its user-agent, not the host.
Say which it was, and use the path that works. Only call a source unreachable once **both** paths have
failed, and name the ones you tried.

**Report three outcomes, not two.** "Nothing found", "could not look", and "could not look with THIS
tool" are different facts, and collapsing the third into the second is what makes the error persist.
"Source unreachable" reads as a covered outcome, so nobody re-checks it; a recurring job then repeats the
same wrong conclusion every run, and consecutive runs agreeing starts to look like corroboration rather
than the same bug three times. It misdirects the fix too, sending someone to the firewall while the cause
sits in the tool.

**Record per-source quirks somewhere durable**, in the job's own prompt, its runbook, or a repo doc:
which sources need the alternative path, which are JavaScript-rendered and need a different endpoint
entirely, and which are genuinely blocked to everything. A source that fails every path is a real gap, so
name it and say what it costs. A noisy false gap is very good at hiding a quiet true one.

Full rationale and the origin incident live in
[the fetch-403 memory entry](../../memory/feedback_fetch_tool_403_retry_other_path.md).

## Red-flag carve-out: when the wall IS terminal

The scan is for SCOPE-INCIDENTAL limitations (a missing scope, a stale tool, an under-documented API). Some limitations exist BY DESIGN as hard boundaries, and the scan must NOT try to defeat them:

- **Security boundaries.** Personal data leaving a regulated zone; secrets in code; bypassing an auth gate; routing live data through a SaaS without a DPA.
- **Compliance boundaries.** Cross-jurisdiction data movement that violates residency rules; audit-trail tampering; consent bypass.
- **Architectural invariants the codebase enforces.** Bypassing the port / adapter boundary; mutating an append-only record; skipping a multi-tenant scope filter; sidestepping RBAC.
- **Documented "do not" lists.** Anything in a project's CLAUDE.md / AGENTS.md "Hard rules, never violated" section, or an ADR that explicitly forbids the path.

If the documented limitation is in one of these categories, STOP. The doc is the rule, not the starting point. The four-path scan is for working around scope-incidental gaps in tooling, not for evading designed-in safety rails.

## Worked examples

### 1. Actions API for missing `Checks: Read` (the case that prompted this skill)

- **Doc says:** "`gh pr checks` requires `Checks: Read` on the token. Without it, check status is opaque from the CLI."
- **Wrong reflex:** "I can't see CI status. The user will have to check the PR page."
- **Scan:**
  1. Adjacent endpoint? Yes: `/repos/{owner}/{repo}/actions/runs?branch=<b>` uses `Actions: Read`.
  2. Different scope? Confirmed: the PAT carries `Actions: Read/Write` per install requirements.
- **Workaround:** `gh run list --branch <b> --json status,conclusion,name,headSha,databaseId` + `gh run view <id> --log-failed`. Same useful signal via a different API.
- **Follow-up:** update AGENTS.md so the next session inherits the workaround.

### 2. Vault Agent render-state introspection when no CLI exists

- **Doc says:** "no CLI to inspect Vault Agent's render state from outside the LXC".
- **Scan:**
  3. Alternative tool? Yes: `vault status` + `vault read sys/health` from the live LXC using the agent's token surfaces render state via Vault's HTTP API.
- **Workaround:** documented one-liner in the runbook; no SSHing-in-and-reading-files needed.

### 3. Fallback: derive state from a downstream signal

- **Doc says:** "`fail2ban-client status` requires SSH into the live LXC; not available from CI or external scripts."
- **Wrong reflex:** "we can't know current ban state without ops poking around on the LXC."
- **Scan:**
  4. Compute from related state? Yes: the alert pipeline writes a GH Issue per banned IP-prefix labelled `fail2ban:<first-2>.xx.xx`; an open issue with that label is equivalent to "this prefix is currently banned (or recently was, awaiting operator close)". `gh issue list --label fail2ban: --state open --json title,labels` gives an upstream-of-fail2ban view of the ban set without touching the LXC.
- **Workaround:** ban-state surveys run from anywhere with the GH API; no LXC SSH needed. Equivalence is approximate (the issue queue covers events the alerter opened issues for, not necessarily every transient ban), but it's the best non-LXC view.

### 4. When the wall IS terminal (red-flag carve-out applies)

- **Doc says:** AGENTS.md hard rule 7: "Personal data never goes to a third-party cloud we don't have a DPA with."
- **Reflex worth resisting:** "but the Asana API would let us mirror tickets that include applicant names; let's just hash the names".
- **Right move:** STOP. The doc is the rule. Asana doesn't have a DPA for personal data; hashing names doesn't change that. The Asana mirror gets non-personal metadata only, or it doesn't ship. Don't run the scan.

## Red flags (about-to-violate signals)

- About to say "can't be done" / "not exposed" / "opaque from CLI" / "blocked by docs" without first running the four-path scan.
- Treating a tool's missing subcommand as the same as the capability being missing.
- Accepting an error message at face value without checking whether it's scope-related (try a different endpoint or permission first).
- About to report a source as unreachable / blocked / behind egress policy on the strength of ONE fetch path's error. Retry through a second path first, then say which paths you tried.
- Writing "could not look" when what happened was "could not look with this tool". The second is fixable in one call; the first sends someone to the firewall.
- Re-deriving a workaround you've used before because the workaround isn't documented; the fix is to UPDATE the doc, not to keep re-deriving each session.
- Running the scan on a hard rule (security / compliance / architectural invariant). The scan is for scope-incidental limits, not designed-in boundaries. If the carve-out applies, STOP.
- Telling the user "the docs say X is impossible" as if that closes the discussion; the right framing is "the docs flag this path as blocked; here's what I tried next".

## Bottom line

When a doc says "you can't", the doc is telling you where the front door is locked, not that the building has no doors. Run the four-path scan first: adjacent endpoint, different scope, alternative tool, fallback from related state. If all four come up empty AND the limitation is design-intentional (security, compliance, architectural invariant, hard rule), THEN it's a wall. Most of the time, it isn't.

Update the doc the moment you find the workaround so the next session doesn't re-derive.
