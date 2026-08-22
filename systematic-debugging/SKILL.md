---
name: systematic-debugging
description: Use when encountering any bug, test failure, unexpected behaviour, network outage, deploy failure, vendor integration glitch, or system-level anomaly, BEFORE proposing fixes. Triggers include "this is broken", "the deploy failed", "the API is returning 500s", "the cron didn't fire", "the LXC won't boot", "the firewall is dropping packets", "the OIDC handshake is failing", "logins are slow", "the migration crashed". Enforces the iron law NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST. Walks the four phases (root-cause investigation; pattern analysis; hypothesis and minimal test; implementation with single fix), with explicit guidance on building a fast deterministic pass/fail signal as the foundation of Phase 1. Covers code, sysadmin, network, vendor, and infra failure modes; widens the upstream's code-only examples into the broader operational surface (package or kernel updates, config drift, firmware change, vendor side-effect, certificate rotation, DNS hiccup). Localised customisation of obra/superpowers/skills/systematic-debugging with pass/fail-signal framing folded in from mattpocock/skills/engineering/diagnose.
metadata:
  version: 2.2.0
---

# Systematic Debugging

> **Skill marker**: When applying this skill, begin your reply with `[skill: systematic-debugging]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Random fixes waste time and create new bugs. Quick patches mask underlying issues. The same loop applies whether the failure is in code, on a host, on the network, or behind a vendor's API.

**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.

**Violating the letter of this process is violating the spirit of debugging.**

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you have not completed Phase 1, you cannot propose fixes.

## When to Use

Use for ANY technical issue:

- Code-side: test failures, runtime exceptions, build failures, integration glitches.
- Sysadmin: a host that won't boot, a service that won't start, a cron that did not fire, a process that crashes silently, a daemon eating CPU.
- Network: routing weirdness, dropped packets, DNS failures, certificate problems, MTU drama, firewall rule that "should" allow the traffic.
- Vendor / SaaS: an API returning 500s or 4xx unexpectedly, OIDC handshake failure, webhook never arriving, signature mismatch, rate-limit you "shouldn't" be hitting.
- Infra / deploy: LXC bring-up failure, migration that aborts, env-var boot check failing, OIDC config, secret rotation, first-deploy regression.

**Use this ESPECIALLY when:**

- Under time pressure (emergencies make guessing tempting).
- "Just one quick fix" seems obvious.
- You've already tried multiple fixes.
- Previous fix didn't work.
- You don't fully understand the issue.

**Don't skip when:**

- Issue seems simple (simple bugs have root causes too).
- You're in a hurry (rushing guarantees rework).
- A stakeholder wants it fixed NOW (systematic is faster than thrashing).

## The Four Phases

You MUST complete each phase before proceeding to the next.

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read errors carefully.**
   - Don't skip past errors, warnings, or stderr.
   - Often contain the exact solution.
   - Read stack traces and log lines completely.
   - Note line numbers, file paths, exit codes, response bodies, syslog timestamps.

2. **Reproduce consistently.**
   - Can you trigger it reliably?
   - What are the exact steps, requests, packets, or environmental conditions?
   - Does it happen every time, or only under load / at specific times / from specific clients?
   - If not reproducible: gather more data (more logging, packet captures, longer monitoring window). Don't guess.

   **Build a fast, deterministic pass/fail signal.** Reproducing once is not enough; the goal is a feedback loop you can run on demand. If you have a fast, deterministic, agent-runnable pass/fail signal for the bug, you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume that signal. If you don't have one, no amount of staring at code or config will save you. Spend disproportionate effort here.

   Ways to construct one, in roughly this order of preference:

   1. **Failing test** at whatever seam reaches the bug (unit, integration, e2e).
   2. **`curl` / HTTP script** against a running dev server or the failing endpoint.
   3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
   4. **Headless browser script** (Playwright, Puppeteer) that drives the UI and asserts on DOM, console, or network.
   5. **Replay a captured trace.** Save a real network request, payload, or event log to disk; replay it through the code path in isolation.
   6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
   7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run hundreds of random inputs and look for the failure mode.
   8. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version, firmware revision), automate "boot at state X, check, repeat" so you can `git bisect run` it (or the operational equivalent for sysadmin / network changes).
   9. **Differential loop.** Run the same input through old-version vs new-version (or two configs, two hosts, two vendors) and diff outputs.
   10. **HITL bash script.** Last resort. If a human must click, drive them with a structured script so the loop stays repeatable. Captured output feeds back to you.

   **Iterate on the loop itself.** Treat the loop as a product. Once you have one, ask: can it be faster (cache setup, skip unrelated init, narrow the test scope)? Sharper (assert on the specific symptom, not "didn't crash")? More deterministic (pin time, seed RNG, isolate filesystem, freeze network)? A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

   **Non-deterministic bugs.** The goal is not a clean repro but a higher reproduction rate. Loop the trigger hundreds of times, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not; keep raising the rate until it's debuggable.

   **When you genuinely cannot build a loop.** Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a captured artifact (HAR file, log dump, core dump, packet capture, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do NOT proceed to hypothesise without a loop.

3. **Check recent changes.**
   - What changed that could cause this? Across all surfaces, not just code.
   - Code: `git log`, recent commits, dependency bumps, config edits.
   - System: package updates, kernel updates, firmware changes, sudo / `auth.log`, scheduled job runs.
   - Network: device config diffs, ACL or firewall edits, BGP / OSPF events, certificate renewals, DNS record changes.
   - Vendor: announced API changes, deprecation notices, status-page incidents, account-quota changes.
   - Environmental: time-of-day correlation, traffic spike correlation, day-after-deploy correlation.

4. **Gather evidence at every component boundary.**

   When the system has multiple components (CI → build → signing; client → LB → API → service → database; user → DNS → reverse proxy → upstream → vendor API), debug at the boundaries before debugging inside any one component.

   ```
   For EACH component boundary:
     - Log / capture what data enters the boundary
     - Log / capture what data exits the boundary
     - Verify environment / config / credentials / certs / DNS / routing propagation
     - Check state at each layer

   Run once to gather evidence showing WHERE it breaks
   THEN analyse evidence to identify the failing component
   THEN investigate that specific component
   ```

   **Sysadmin / network examples:**

   ```bash
   # DNS layer
   dig +short api.vendor.example
   dig +trace api.vendor.example

   # TCP / TLS layer
   curl -v --resolve api.vendor.example:443:<ip> https://api.vendor.example/healthz

   # HTTP / app layer
   curl -i -H "Authorization: Bearer $TOKEN" https://api.vendor.example/v1/whoami

   # Certificate layer
   openssl s_client -connect api.vendor.example:443 -servername api.vendor.example </dev/null 2>/dev/null \
     | openssl x509 -noout -subject -issuer -dates

   # Reverse proxy / LB layer
   tail -n 200 /var/log/nginx/access.log | grep "$REQ_ID"
   tail -n 200 /var/log/nginx/error.log

   # System / service layer
   systemctl status <unit>; journalctl -u <unit> --since "10 min ago"
   ```

   The point is the same as the code-side example: each layer's output reveals where the chain actually breaks. You are not guessing which layer to suspect; you are letting the boundary evidence point at it.

5. **Trace data flow backward from the symptom.**

   Where does the bad value or bad behaviour first appear, and where did it originate? Keep tracing up (or "left", in pipeline terms) until you find the source. Fix at source, not at symptom.

   For sysadmin: if the cron didn't fire, check `cron` log → check the unit / timer → check the script's exit / permissions → check the file that script consumes → check what writes that file. The bug is rarely in the cron daemon itself.

   For network: if a packet is dropped, check the destination → return-path firewall → upstream router → MTU mismatch → policy-based routing rule. The drop is rarely random.

### Phase 2: Pattern Analysis

**Find the pattern before fixing:**

1. **Find working examples.**
   - Locate similar working code, hosts, devices, vendor calls in the same environment or codebase.
   - What works that's similar to what's broken? An equivalent service on a different host? Yesterday's run vs. today's? A neighbouring tenant whose request succeeds?

2. **Compare against references.**
   - Read the vendor's docs, RFC, manpage, or upstream source COMPLETELY for the relevant section. Don't skim.
   - Understand the pattern fully before applying.

3. **Identify differences.**
   - What is different between the working and the broken case? List every difference, however small.
   - Don't assume "that can't matter": kernel minor version, glibc version, certificate chain order, header capitalisation, trailing slash, client cipher suite. Any of these can be load-bearing.

4. **Understand dependencies.**
   - What other components, settings, or environmental conditions does this need?
   - What does the broken case assume that may not hold (DNS resolves, NTP synced, kernel module loaded, secret unexpired, downstream tenant in a sane state)?

### Phase 3: Hypothesis and Minimal Test

**Scientific method:**

1. **Form a single hypothesis.**
   - State clearly: "I think X is the root cause because Y."
   - Write it down (in the chunk's plan file or the runbook draft).
   - Be specific, not vague.

2. **Test minimally.**
   - Make the SMALLEST possible change to test the hypothesis.
   - One variable at a time.
   - Don't fix multiple things at once. If you change two things and the symptom resolves, you don't know which one mattered.

3. **The minimal test must not be able to damage the thing you are diagnosing.**
   - **Read the current state before you retry anything.** A failed call very often already did its work;
     an error is a statement about the response, not proof about the effect. Checking first is one call and
     it frequently ends the investigation outright.
   - **Never diagnose a failed write with another write against the live object.** Test against a
     throwaway target, or with a payload that changes nothing even when it succeeds (an empty-body write
     to a write-gated endpoint, a no-op update of the current value). A diagnostic write only causes
     damage in exactly the case you were testing for, which is the case where your assumption was wrong.
   - **Pair a negative result with a known-good control.** A bare failure cannot distinguish "denied" from
     "wrong URL", "invisible resource" or "dead credential". Without the control you have not learnt
     anything, you have just collected a symptom.
   - **Do not trust your own reading of which line a traceback points at** when a script makes several
     similar calls. Print a marker per call, or you will confidently diagnose the wrong one.
   - Worked case: a session investigating a `403` fired a real `PUT {"notes": "probe"}` at the live
     record. The `PUT` succeeded and destroyed a correction written a minute earlier. The 403 had come
     from a different call in the same script, and the original write had already landed, so the probe was
     both destructive and unnecessary. `secrets-hygiene` states the same discipline for credentials; it is
     not credential-specific and belongs here too.

4. **Verify before continuing.**
   - Did the hypothesis hold? Yes → Phase 4.
   - Didn't hold? Form a NEW hypothesis. DON'T add more fixes on top.

5. **When you don't know.**
   - Say "I don't understand X" out loud (in chat).
   - Don't pretend to know.
   - Ask the user / vendor / on-call peer.
   - Research more.

### Phase 4: Implementation

**Fix the root cause, not the symptom:**

1. **Create a failing repro.**
   - Code: a failing test (use `tdd`).
   - Sysadmin: a one-liner that reproduces the failure (so the fix can be verified by running it again).
   - Network: a `curl` / `dig` / packet capture that shows the broken behaviour from a clean shell.
   - Vendor: a minimal request (Postman / `curl`) that triggers the upstream failure deterministically.
   - You MUST have the repro before the fix.

2. **Implement a single fix.**
   - Address the root cause identified in Phase 1-3.
   - ONE change at a time.
   - No "while I'm here" improvements. No bundled refactoring. No bundled config sweeps.

3. **Verify the fix.**
   - Repro now passes / behaves correctly?
   - No other tests, services, or call paths broken?
   - Issue actually resolved end-to-end (not just at the layer you patched)?
   - Use `completion-gate` Layer 3 (the iron law) for the verification claim.

4. **If the fix doesn't work:**
   - STOP.
   - Count: how many fixes have you tried?
   - If < 3: return to Phase 1, re-analyse with the new information the failed fix gave you.
   - **If ≥ 3: STOP and question the architecture (step 5 below).**
   - DON'T attempt fix #4 without an architectural discussion via `AskUserQuestion`.

5. **If 3+ fixes failed: question the architecture.**

   **Patterns indicating an architectural problem:**

   - Each fix reveals new shared state / coupling / brittle layer in a different place.
   - Fixes require "massive refactoring" or "operations across all hosts" to implement.
   - Each fix creates new symptoms elsewhere.
   - The same vendor edge-case keeps biting under slightly different conditions.

   **STOP and question fundamentals:**

   - Is this pattern fundamentally sound?
   - Are we sticking with it through inertia?
   - Should we rework architecture (or replace the vendor / device / library) vs. continue fixing symptoms?

   Surface this via `AskUserQuestion` (per the standard "do not default-then-act" rule). Options: rework the architecture, file a bug with the vendor and accept the symptom temporarily, replace the component, accept the limit and document.

   This is NOT a failed hypothesis. This is a wrong architecture.

## Red Flags - STOP and Follow Process

If you catch yourself thinking:

- "Quick fix for now, investigate later".
- "Just try changing X and see if it works".
- "Add multiple changes, run the test once".
- "Skip the test, I'll manually verify".
- "It's probably X, let me fix that".
- "I don't fully understand but this might work".
- "Pattern says X but I'll adapt it differently" (without reading the pattern fully).
- "Here are the main problems: [lists fixes without investigation]".
- Proposing solutions before tracing data flow / packet flow.
- **"One more fix attempt" (when already tried 2+).**
- **Each fix reveals a new problem in a different place.**

**ALL of these mean: STOP. Return to Phase 1.**

**If 3+ fixes failed:** question the architecture (see Phase 4 step 5).

## Signals from the user that the approach is wrong

Watch for these redirections:

- "Is that not happening?" (you assumed without verifying).
- "Will it show us...?" (you should have added evidence-gathering).
- "Stop guessing." (you're proposing fixes without understanding).
- "Ultrathink this." (question fundamentals, not just symptoms).
- "We're stuck?" said in frustration (your approach isn't working).

When you see these: STOP. Return to Phase 1.

## Common Rationalisations

| Excuse | Reality |
|---|---|
| "Issue is simple, don't need process" | Simple issues have root causes too. Process is fast for simple bugs. |
| "Emergency, no time for process" | Systematic debugging is FASTER than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write the test after confirming the fix works" | Untested fixes don't stick. Test first proves it. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "It's the vendor's fault" | Maybe. Verify the failure boundary first; "vendor" is often the destination layer of an internal misconfiguration. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question the pattern. |

## Quick Reference

| Phase | Key activities | Success criteria |
|---|---|---|
| **1. Root Cause** | Read errors, reproduce, check recent changes, gather boundary evidence, trace backward | Understand WHAT and WHY |
| **2. Pattern** | Find working examples, compare against references, identify differences, map dependencies | Identify differences |
| **3. Hypothesis** | Form a single theory, test minimally, one variable | Confirmed or new hypothesis |
| **4. Implementation** | Create repro, single fix, verify end-to-end, escalate if 3+ fixes fail | Issue resolved, repro passes |

## When the process reveals "no root cause"

If systematic investigation reveals the issue is truly environmental, timing-dependent, vendor-side, or external:

1. You've completed the process.
2. Document what you investigated (in a runbook or ADR; do not let the lesson live only in chat).
3. Implement appropriate handling: retry with backoff, timeout with surface, alerting, runbook entry, vendor ticket.
4. Add monitoring / logging for future investigation.

**But:** the majority of "no root cause" cases are incomplete investigation.

## Cross-references

- `tdd`: how to write the failing test in Phase 4 step 1 when the failure is code-side.
- `completion-gate`: how to verify the fix in Phase 4 step 3 (the iron law of verification).
- `plan-time-tooling`: which other skills / MCPs to enumerate when the debug session graduates into a remediation chunk.
- `subagent-delegation`: when the debug session is large enough to spawn an `Explore` sub-agent for surface-mapping (e.g. "find every call site that uses this vendor endpoint").
- `prototype`: a prototype harness can be the Phase 1 feedback loop itself (a throwaway script that reproduces the bug deterministically); useful when the loop needs to be built before there's any real seam for a test.
- `to-issues`: if Phase 4 step 5 reveals an architectural problem (3+ failed fixes), the remediation may need to be sliced into independently-grabbable issues via to-issues.
- `triage`: incoming bug reports flow through triage; the "Reproduce (bugs only)" step there is the same loop as Phase 1 here.

## Bottom Line

No fixes without root cause. Four phases, in order. Test minimally, fix once, verify end-to-end. Three failed fixes is a signal about the architecture, not the next attempt. The same loop applies whether the failure is in code, on a host, on the network, or at a vendor.
