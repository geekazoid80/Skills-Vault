---
name: boundary-check
description: Run at every session boundary BEFORE acting - before you propose /compact, before you accept a park / standdown / quit / restart / "come back later" / sleep, at a chunk-shift (finishing one chunk and promoting the next), at EVERY chunk close (a PR lands + deploys, a fix is verified, bookkeeping is written - the gate runs BEFORE you offer next-chunk options or ask "what's next"; bookkeeping alone is NOT the gate), and whenever the user asks to verify memory + standing instructions are being followed. Every open item the chunk leaves behind must be actioned-to-completion or carry a single NAMED SSOT owner (person / cron / plan-file pickup step / peer session) - never a vague "worth a look". Does a FRESH-DISK walk of every standing-instruction source (global ~/.claude/CLAUDE.md + ~/.claude/memory/MEMORY.md and its linked files, the project memory index and its linked files, repo AGENTS.md/CLAUDE.md, the active plan file), reconciles the current session's work against each rule, fixes any drift, checks that every in-flight workstream and every spawned background task carries an open, current entry in the estate's work-coordination tracker if it has one, externalises un-saved insight, then emits the visible boundary-check stamp. Universal - all sessions, all projects. Manual triggers - "run the boundary gate", "gate check", "check memory and standing", "walk the standing instructions", "are memory and standing all followed", "commit the memory updates". Composes with reread-memory-before-planning, pre-park-externalisation, and the pre-compact coverage audit; this skill is the single runnable gate that fires those checks at a boundary instead of relying on recall.
---

# boundary-check

The single runnable gate for session boundaries. Its whole reason to exist: standing instructions get
**updated between sessions, AND mid-session by a concurrent sibling-worktree session editing shared project
memory**, and reasoning from **in-context recall** instead of a **fresh disk read** silently misses those
updates. A session-start read is NOT sufficient: in a multi-worktree setup the project memory index and its
linked files are a LIVE shared surface (another session can add a coordination hold, chip a follow-up, or
supersede a note while you work), so re-read from disk at every boundary, never trust the session-start
snapshot. This skill forces the fresh read, the reconcile, and a **visible stamp** so a skip is auditable
rather than silent.

## When it fires

Fire it, before doing the boundary action, at any of:

- **Before proposing `/compact`** (you cannot run compact yourself; the gate runs before you ask the user to).
- **Before accepting a park / standdown / quit / restart / sleep / "I'll come back to this".**
- **At a chunk-shift / chunk CLOSE** - a chunk lands (PR merged + deployed, fix verified, bookkeeping written)
  and you are about to promote the next. The trigger moment is BEFORE offering next-chunk options or asking
  "what's next": if you are about to type that question and no stamp was posted this chunk-close, stop and
  run the gate first. Bookkeeping (WORKLOG/memory/plan updates) alone is NOT the gate.
- **On manual trigger** - "run the boundary gate", "gate check", "are memory and standing followed", etc.

Every open item the chunk leaves behind must be either actioned to completion or carry a single NAMED SSOT
owner in its durable home - a person (operator), a scheduled job (cron), a plan-file pickup step the next
session executes, or a peer session. A passive "worth a glance" with no owner fails the gate.

By right it fires automatically at these moments in every session; the user may also trigger it manually.
When it fires, it runs as a real Skill invocation so the usual skill-use chip shows.

## The walk (fresh disk reads, never recall)

Run these in order. Every read is a **live Read/Bash of the file on disk this turn**, not a memory of what
it said earlier in the session.

0. **Re-derive today's date** from `date '+%Y-%m-%d %H:%M:%S %Z (%A)'` on the relevant host(s). Every dated
   artefact this turn uses that output, never a recalled date (feedback_date_drift_live_clock).

1. **Global standing instructions** - fresh Read of:
   - `~/.claude/CLAUDE.md` (all always-on rules + the skills table).
   - `~/.claude/memory/MEMORY.md` (the global index), then Read every linked file whose one-liner is
     relevant to what this session touched.

2. **Project standing instructions** - compute the encoded project dir (the absolute project path with every
   `/` replaced by `-`), then fresh Read:
   - `~/.claude/projects/<encoded>/memory/MEMORY.md` and every linked file relevant to this session.
   - Any project coverage-audit note it points to (e.g. a `compact_coverage_audit` entry).

3. **Repo standing instructions** - fresh Read of the repo's root `AGENTS.md` / `CLAUDE.md` and any module
   `AGENTS.md` under paths this session edited.

4. **The active plan file** - fresh Read of `~/.claude/plans/<current>.md` (its standing-reminder block +
   current chunk).

If a source does not exist, note it and move on; do not invent one.

### Emit a read-ledger, because this is the one check that passes on assertion

Every other check in this skill can be audited from the artefacts afterwards. This one cannot, so it needs
its own evidence: **post a read-ledger with the stamp**, one line per file the walk names, each marked
`read ✓` only from a real Read of that path **this turn**. A file you did not open is listed as what it
actually was, `grepped` or `not read`, never quietly omitted and never rounded up to a tick.

Three near-misses that feel like reading and are not:

- **Verifying instead of reading.** An mtime, a clean `git diff`, or "unchanged since I last checked" proves
  the file did not move. It does not put the contents in front of you, and a rule you have not read cannot
  be applied however current it is.
- **The injected copy.** A session-start reminder that pastes a standing file is a snapshot taken before the
  session did any work, and for anything it merely indexes it is a pointer layer. It is not a read.
- **Grepping for what you expect.** A grep answers the question you already had. The rule you are about to
  break is in the part you did not think to search for.

**The linked files are where the substance lives.** An index one-liner cannot carry an identifier, an access
path, a naming convention or a notes standard, so reading an index and skipping its links is the same defect
as reading nothing. Reading *some* of the links is also that defect, because the one you skipped is where
the rule you are about to break lives. A linked file you judge irrelevant is still opened, then noted why.

**Ledger per index, not per session.** The walk names more than one index: a global standing index, a
project index, sometimes a repo one. A ledger that covers one of them exhaustively while leaving another at
index-only reads as complete precisely *because* it is long, and the asymmetry is invisible to the person
who wrote it. Give each index its own ledger section and close each off explicitly.

Which one gets skipped is predictable. The index nearest the task feels relevant and the broader one feels
like background, when the relationship is the other way round: the near index holds what the work **is**,
the broad one holds the rules the work must **obey**. So the skipped index is reliably the one carrying the
rule about to be broken.

Where an index is genuinely too large to open in full, name which of its links you opened and which you did
not, choosing by the surfaces this session actually touched rather than by what reads as interesting. A
declared partial walk is honest and usable. A partial walk presented as a complete one is the same failure
this section exists to prevent, only harder to catch, because it now looks like diligence.

The ledger is the forcing function. Without it the walk degrades into "I am familiar with these files",
which holds right up to the boundary where a rule changed, a peer edited one, or the rule you never opened
is the one this session needed.

## Reconcile and fix (the point of the walk)

For each rule surfaced by the walk, check the **current session's actual artefacts** against it and **fix
drift now**, in this turn, before the boundary:

- **Voice** - British/Pacific spelling, no em dashes, human tone in everything written this session
  (commits, PR text, docs, memory, plan). Sweep any stray em dash you added.
- **Coverage / cross-reference** - every artefact created this session is linked from the place that should
  point to it (README/AGENTS/index/plan); no orphaned doc, no dangling `[[link]]` or path, no stale pointer.
- **Family-close stale-forward-ref scan (fold-vault only, when a skill family's last PR lands)** - when the
  boundary closes a fold FAMILY (a group of related skills whose final member just landed), grep the WHOLE
  vault for the forward-ref idioms - `not yet in this vault`, `not yet adopted`, `when adopted`,
  `forthcoming`, `forward placeholder`, `no sibling skill to route to` - not just the new skill's exact name,
  and repoint every hit whose referenced skill now exists. `forthcoming` is load-bearing: a skill body that
  still calls a landed skill "forthcoming" is the exact defect that sat undetected across several prior
  closes. Sibling skills authored earlier in the family often route a capability out worded as a discipline
  or family ("the CNAPP family is not yet in this vault"), so a name-only grep misses them; match the ref
  CONTENT, not the file path. Leave genuine absences (a capability the vault really lacks) and the
  append-only `merged-skills-registry` rows untouched (their "forthcoming" is past-tense fold history, not a
  live claim), and do not treat a long `description:` co-occurrence as a stale ref.
- **Follow-ups / commitments (no prose-only, no chip-only)** - every cross-repo / cross-agent follow-up or
  deferred commitment mentioned this session is captured in a *durable* home (project/global memory, AGENTS,
  or the plan file), not left only in prose. A `spawn_task` chip alone is NOT durable: chips and their
  completion signals do not survive a Claude Code app restart (feedback_spawn_task_restart_verify), so back
  every chip with a one-line memory note. If you said "I'll note / flag / follow up on X" and X is only in
  the transcript, write it down now.
- **Work-coordination tracker** - if the estate keeps a shared work-coordination tracker (a board, a project,
  an issue tracker where concurrent sessions and people register what they are working on), then every
  in-flight workstream this session holds, and every background task it spawned, has an **open, current
  entry** there: created if missing, notes refreshed with progress-to-date plus the explicit next action,
  and closed the moment the work lands. This is not the same check as the follow-ups bullet above: a durable
  memory note records the commitment for YOU, a tracker entry makes it visible to a PEER. A workstream
  absent from the tracker is invisible, so two sessions can duplicate the same build, or a peer can sit
  waiting on something that already shipped; a stale open entry is worse than none. Where the estate pins a
  specific tracker, access path, entry-naming convention or notes standard, that estate rule governs, so
  check for it rather than improvising one here. If the estate keeps no such tracker, note that and move on.
- **Resource registry** - every durable resource created/handed over this session is catalogued in a durable
  home with its real identifier + access command + credential location (never the secret); the plan holds
  only a pointer.
- **Secrets** - no secret value written to any tracked file, transcript, or memory; `.example`/adapter
  templates carry schema only.
- **Task hygiene** - TaskList reflects reality (completed marked, stale deleted); >3 in-flight items are in
  TaskCreate not plan prose.
- **Dates** - every dated row written this turn matches the Step-0 live clock.

Anything off: fix it in this turn. A found-but-unfixed drift is not a passed gate.

## Externalise

Scan the session for one-off material useful later but not yet on disk (vendor research, a tactical decision,
a config convention, an architectural sketch). Write each to its right durable home (repo `docs/`, an ADR, a
runbook, project or global memory) before the boundary. If a prior externalisation hint has since been
absorbed into a permanent home, trim/delete it.

**A reusable procedure, gotcha, or recurring instruction belongs in a skill, not only a memory note.** When
the finding would help a future session do a task correctly (an operational recipe, a trap, a workflow, a
repeated preference), fold it into the relevant existing skill (add the section or trigger phrases) or author
a new one via `author-skill`; a memory note is the fallback when no skill fits. The boundary is the moment to
act on the always-on "promote repeated guidance to a skill" rule, while the finding is fresh, rather than
leaving it to decay in the transcript.

## Commit what you wrote (only if the store is version-controlled)

Everything above says "write it to a durable home", and for an unversioned store the write IS the durable
act. **Once the standing-instruction store is under version control, that stops being true.** An uncommitted
file survives a crash, but it does not survive the failure version control was added for: another session
overwriting it. So when the store is a repo, the gate is not passed until the writes are committed.

Check once per boundary, from the store's root (`git rev-parse --show-toplevel`, or `git status` returning
"not a git repository"):

- **Not a repo** - the disk write was the durable act. Nothing to do; say so and move on.
- **A repo** - commit, with the one constraint below.

**Commit ONLY the paths this session wrote. Never `git add -A`, `git add .`, or `git commit -a`.** A
standing-instruction store is usually shared by concurrent sessions, so a blanket add sweeps up whatever
half-finished edits the peers have in flight and lands them in history under your message, attributed to
your reasoning. Name the paths explicitly:

```
git -C <store> commit -- path/one.md path/two.md
```

`commit -- <paths>` takes those paths whatever the index holds, so it neither disturbs nor inherits a
peer's staged state. Keep a running list of what you write as you write it; reconstructing it at the
boundary from `git status` is exactly the mistake, because that output includes everyone's work, not yours.

Two things NOT to do in a shared store: never `git checkout` / `restore` / `reset` a file you did not write
just to get a clean status (that silently destroys a peer's uncommitted work), and do not push unless the
store has a remote AND pushing is the established habit. A local commit is the whole requirement here.

If a park is the boundary, the commit happens BEFORE the stop, since it is part of flushing state rather
than new work.

## Park-only extra

If the boundary is a park / standdown / quit (not a compact), also run the full
**pre-park-externalisation** flush: TaskList snapshot, background subprocess IDs + re-poll commands, resolved
AskUserQuestion answers, TCC/permission state, in-progress uncommitted edits, and the SESSION RESTART PICKUP
order - all into the plan file, before confirming the park.

**No dangling dependency crosses the standdown (always).** Every pending action this session leaves behind
must be in one of two terminal states, never a bare "pending X": (a) **completed here**, or (b) a
**self-sufficient handoff** another agent or owner can start AND finish - a durable recipe (exact
host/path/command + what to verify) with a NAMED owner (a running task, the operator, or a scheduled job)
and, where feasible, its own actionable flag (spawn_task chip backed by a memory note, since chips do not
survive an app restart). Walk every loose end: if it can be closed now, close it; if not, turn it into a
proper handoff; if it can be neither, it BLOCKS standdown - surface it and resolve before standing down. No
unwritten prose, no unrecorded chunk, no vague pending (feedback_no_dangling_bits_at_standdown). Then STOP
(park means stop; do not push/merge/start-next after).

## The stamp (post it before the boundary action)

After the checks actually ran from disk this turn, post one line:

`Gate: date re-derived ✓ · CLAUDE+MEMORY fresh-read ✓ · index/coverage rescan ✓ · externalisation ✓ · memory committed ✓`

**Post the read-ledger with it.** Tick 2 is the only check here that cannot be audited from the artefacts
afterwards, so without the ledger it passes on assertion, and a gate that ticks a fresh read it did not do
will keep passing over the exact rule that would have caught the session's mistake.

Tick a box **only** if that check ran from disk this turn:
1. date re-derived via live `date`;
2. fresh Read of `~/.claude/CLAUDE.md` + global `MEMORY.md` + the project memory index **and the linked
   files relevant to what this session touched**, each accounted for in the ledger. A file confirmed by
   mtime, git state, or a session-start reminder snippet is **not** read, so do not tick on one;
3. rescanned the project index and the repo docs this session touched for drift/orphans/dangling pointers,
   and fixed what was found;
4. externalised any one-off insight not yet on disk;
5. committed the standing-instruction paths this session wrote, naming them explicitly. Tick it unchanged
   when the store is not a repo (the write was the durable act) or when the session wrote nothing, but
   say which of the three applies rather than ticking it silently.

If a check did not run, do **not** tick it - run it first. **Proposing compact or accepting a park without
the stamp is itself the lapse the user is entitled to call.** The stamp is the safety net; the underlying
gates (pre-compact coverage audit, pre-park externalisation, reread-before-planning, per-chunk skeleton) are
the substance this skill runs on contact.
