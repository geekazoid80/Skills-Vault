---
name: boundary-check
description: Run at every session boundary BEFORE acting - before you propose /compact, before you accept a park / standdown / quit / restart / "come back later" / sleep, at a chunk-shift (finishing one chunk and promoting the next), at EVERY chunk close (a PR lands + deploys, a fix is verified, bookkeeping is written - the gate runs BEFORE you offer next-chunk options or ask "what's next"; bookkeeping alone is NOT the gate), and whenever the user asks to verify memory + standing instructions are being followed. Every open item the chunk leaves behind must be actioned-to-completion or carry a single NAMED SSOT owner (person / cron / plan-file pickup step / peer session) - never a vague "worth a look". Does a FRESH-DISK walk of every standing-instruction source (global ~/.claude/CLAUDE.md + ~/.claude/memory/MEMORY.md and its linked files, the project memory index and its linked files, repo AGENTS.md/CLAUDE.md, the active plan file), reconciles the current session's work against each rule, fixes any drift, checks that every in-flight workstream and every spawned background task carries an open, current entry in the estate's work-coordination tracker if it has one, externalises un-saved insight, then emits the visible boundary-check stamp. Where the standing-instruction store is version controlled, do not judge whether a file changed, ask the store for the delta (log since session start, status for a peer's uncommitted edit, last-touch on the standing files) and read what actually moved. The per-file read-ledger is its OWN step, posted after the reads and BEFORE the first action that acts, never bundled into the closing stamp, and derived from the Read calls actually issued rather than the ones planned; a ledger written at the end describes what happened instead of gating what happens next, and a ledger composed from intent is a false statement rather than an incomplete task. Universal - all sessions, all projects. Manual triggers - "run the boundary gate", "gate check", "check memory and standing", "walk the standing instructions", "are memory and standing all followed", "commit the memory updates". Also fires on the phrases that mean the gate is about to be ticked from recall - "unchanged since my session-start read", "I already read that this session", "nothing has changed since I checked", "ask the store what moved", "delta re-read", "a peer's uncommitted edit". At a park / standdown / quit it also has the session clear its OWN worktree, as the LAST tool call of the session, because nothing else does (ending a session does not remove a worktree and neither does archiving one) and because removing the tree you are standing in partway through a turn strands the rest of the close; only your own, never a peer's, without --force. Composes with reread-memory-before-planning, pre-park-externalisation, using-git-worktrees (which owns the disposal mechanics this gate only times), and the pre-compact coverage audit; this skill is the single runnable gate that fires those checks at a boundary instead of relying on recall.
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

## If your environment has a dedicated gate agent, dispatch it rather than walking inline

Some setups pair this skill with a **dedicated read-only agent whose whole job is to run this walk**,
report the drift, and return the stamp. Where one exists, invoking this skill is the cue to **dispatch that
agent**, not to execute the steps yourself in the working session. Two reasons: the context that just did
the chunk's work should not also be the one that scores it, since a self-audit waves through the very thing
it should catch; and a separate read-only pass is harder to run on momentum. Keep the decisions and any
fixes in the working session, the agent only walks and reports. Where no such agent exists, run the walk
here as written.

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

**A boundary is not the only moment the ground moves.** Publishing a durable, outward-facing artefact needs
its own narrower re-read immediately beforehand, which is `reread-memory-before-planning`'s final-write rule,
not this gate's job.

## The walk (fresh disk reads, never recall)

### First, ask the store what moved

The walk below is thorough and therefore expensive, and an expensive gate does not get skipped outright, it
gets **downgraded into a confident assertion**: "unchanged since my session-start read". That sentence is a
judgement about a file you did not look at.

Where the standing-instruction store is under version control, you do not have to make that judgement. Ask
the store:

```
git -C <store> log --since="<session start>" --format="%h %ad %s" --date=format:"%H:%M"
git -C <store> status --short
git -C <store> log -1 --format=%ad -- <standing files>
```

**The `status` call is not optional, and it is not redundant with the log.** It is the only one that surfaces
a peer's edit that is written to disk but not yet committed, which no amount of re-reading committed state
will ever show. Where a dirty path matters, `git diff -- <path>` to see whose change it is.

Rules:

- **Run the delta at every boundary, before ticking anything.** It costs one call.
- **Never tick "unchanged" from recall, from an mtime alone, or from a session-start snapshot.** An mtime says
  the file did not move; it does not put the contents in front of you, and it is silent on the uncommitted
  case entirely.
- **When the delta is non-empty, read those files and say what changed.** Naming the commits that landed is
  the evidence; "I checked and it was fine" is not.

What this buys you is a **delta instead of an all-or-nothing choice**: read what actually moved, and say so,
rather than re-reading everything or nothing. What it does not buy you is a way out of the walk. **The delta
tells you what moved, not what is relevant.** A file you have never opened is unread however quiet it has
been, so a quiet delta narrows re-reading *across* boundaries within a session, it never substitutes for the
first read or for the ledger below.

If the store is not version controlled, say so and run the full walk.

The reason this earns its own step: a session ticked the global rules file as unchanged without checking, and
left the global memory index on a snapshot taken two hours earlier, while that store took **21 commits** in
the interim, three of them touching standing files and one landing twelve minutes before the gate. Nothing in
the artefacts contradicted the stamp. The operator caught it.

### Then walk the sources

Run these in order. Every read is a **live Read/Bash of the file on disk this turn**, not a memory of what
it said earlier in the session.

0. **Re-derive today's date** from `date '+%Y-%m-%d %H:%M:%S %Z (%A)'` on the relevant host(s). Every dated
   artefact this turn uses that output, never a recalled date (feedback_date_drift_live_clock).

1. **Global standing instructions** - fresh Read of:
   - `~/.claude/CLAUDE.md` (all always-on rules + the skills table).
   - `~/.claude/memory/MEMORY.md` (the global index), then Read **every file it links**. Not a relevant
     subset, not the ones whose one-liner looks related: every one. A file you judge irrelevant is still
     opened, then noted why.

2. **Project standing instructions** - compute the encoded project dir (the absolute project path with every
   `/` replaced by `-`), then fresh Read:
   - `~/.claude/projects/<encoded>/memory/MEMORY.md` and **every file it links**, on the same terms.
   - Any project coverage-audit note it points to (e.g. a `compact_coverage_audit` entry).

3. **Repo standing instructions** - fresh Read of the repo's root `AGENTS.md` / `CLAUDE.md` and any module
   `AGENTS.md` under paths this session edited.

4. **The active plan file** - fresh Read of `~/.claude/plans/<current>.md` (its standing-reminder block +
   current chunk).

If a source does not exist, note it and move on; do not invent one.

## Emit the read-ledger HERE, before the first action that acts

This is a step of its own, and its position in the turn is the whole rule. **Post the ledger after the reads
and before you reconcile, fix, or commit anything.** Not bundled into the closing stamp.

Every other check in this skill can be audited from the artefacts afterwards. This one cannot, so it needs
its own evidence: one line per file the walk names, each marked `read ✓` only from a real Read of that path
**this turn**. A file you did not open is listed as what it actually was, `grepped` or `not read`, never
quietly omitted and never rounded up to a tick.

**Why the placement is the rule and not a formatting preference.** A ledger written at the end is scored
against work already done, so every gap in it is retrospective and costless, and the honest move (stop, go
and read the file) is the expensive one. Written before acting, the same gap is a blocker, which is the only
thing that ever makes it get closed. Same words, opposite function, purely from where they sit in the turn.
A gate that reports is not a gate.

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

**There is no relevance test, and a large index does not earn one.** Read every link, however many there
are. Seventeen or a hundred, the answer is the same, and growth is not an exemption: when the count rises,
read the larger set. The reason is the one this whole section rests on, that the file you skip is where the
rule you are about to break lives, and you cannot know which file that is *before* reading it. Judging
relevance from a one-line index entry is exactly the judgement the index is too thin to support.

**Which boundaries trigger the full read.** Reading every link at *every* boundary is a real cost: a routine
chunk-close can spend a whole full-breadth read re-walking a corpus that the self-contained work could not
have violated. So the full read is scoped to **high-stakes boundaries**:

- starting or executing a build, standing up a new repo, running a migration;
- editing a schema, a contract, a credential, or an access path;
- a cross-repo change;
- a **park / standdown / quit**, where ephemeral state must survive the gap;
- acting on a convention that lives in a linked file (an identifier, a naming rule, an access posture);
- a scheduled or otherwise unattended run whose own contract has it write into such a convention: it opens
  or closes a tracker entry under a naming and notes standard, files a finding under a shared id scheme, or
  posts under a house style. The bullet above is then met **by construction on every fire**, so the
  classification is not a judgement the fire has to make.

**That last bullet names no job, deliberately, and it needs its own line even though the bullet above
already covers these runs on the substance.** Such runs classify themselves routine anyway, because "acting
on a convention" reads like something a session decides it is doing, while a scheduled run reads its own
work as bookkeeping. A by-name list of the runs it applies to would decay faster than the criterion does, so
state the criterion here, where it reaches runs nobody has built yet, and state the read scope in the run's
own prompt as well, where it reaches the fire. Neither half is sufficient alone: a fire reads its own
instructions and may never open the file this rule lives in.

**Routine boundaries get a fixed CORE read instead:** the global rules file, the global memory index, the
project memory index, the repo AGENTS.md, and the active plan file, all fresh from disk. This is NOT the
withdrawn relevance filter returning: the routine read is a fixed set, never a judged subset of links, and
this scopes only WHICH boundaries fire the full read, not how much is read when one does, still every link.
**When unsure whether a boundary is high-stakes, treat it as high-stakes and read all**: the doubt is the
signal.

This supersedes an earlier allowance here for a "declared partial walk" chosen by the surfaces a session
touched. It was wrong twice over. It contradicted the paragraph directly above it, which already said an
irrelevant-looking link is still opened. And it had already been rejected in practice: a session that read
the index, opened one link and declared the rest a declared partial had its plan sent back with "from file".
Declaring a partial walk makes the gap visible, which is better than hiding it, but visible is not the same
as permitted.

What survives is the honesty requirement, not the shortcut. **State the denominator every time** ("59 of 59,
and the index holds 59"), because a count is the only thing that distinguishes a complete walk from one that
merely reads as complete. A partial walk presented as a complete one remains the worst outcome, harder to
catch than an admitted gap because it now looks like diligence.

The ledger is the forcing function. Without it the walk degrades into "I am familiar with these files",
which holds right up to the boundary where a rule changed, a peer edited one, or the rule you never opened
is the one this session needed.

### Derive the ledger from the reads you issued, never from the ones you planned

A ledger emitted at the right moment, in the right shape, and simply **not true** is worse than a late one.
A late ledger at least describes real work. One composed from what you *meant* to read manufactures false
assurance, and because it is indistinguishable from a real one nobody re-checks it, the author least of all.

- **Derive it from the tool calls you actually made**, not from the plan. The question is never "which files
  did I intend to open", it is "which Read calls did I issue this turn". If reconstructing that is hard, that
  difficulty IS the signal that the ledger is guesswork.
- **A self-authored list is not evidence.** Writing filenames into a file and diffing them against a
  directory listing audits your memory, not your reads. It passes cleanly while being entirely wrong.
- **State the denominator and check it.** "All of them" conceals an unread remainder; "59 of 59, and the
  directory holds 59" does not.
- **A paged file quotes its line count.** A Read with a limit silently returns a subset that looks complete,
  so say how many pages it took and to what total.
- **A partial read reported as complete is a false statement**, not merely an incomplete task. Rank it that
  way: correct it the moment you notice, before continuing the work that rested on it.

Two instances, both reported as completed coverage and both false. A session planned twelve batch-reads of
59 linked files, ran seven, and reported all 59 read; the 22 it skipped included the very rule it was
auditing. Correcting that, it then "audited" itself by typing a filename list into a file and diffing it
against a listing, which certified sixteen more files it had never opened and reported 72 of 72. In the same
session it read 75 lines of a 350-line standing file and called that a fresh read, and the unread remainder
held the rule it went on to break.

## Reconcile and fix (the point of the walk)

For each rule surfaced by the walk, check the **current session's actual artefacts** against it and **fix
drift now**, in this turn, before the boundary:

- **Voice** - British/Pacific spelling, no em dashes, human tone in everything written this session
  (commits, PR text, docs, memory, plan). Sweep any stray em dash you added.
- **Coverage / cross-reference** - every artefact created this session is linked from the place that should
  point to it (README/AGENTS/index/plan); no orphaned doc, no dangling `[[link]]` or path, no stale pointer.
  **Name the stores and rescan all three**, because a claim retired in one survives in the others: the
  **repo tree** (the docs this session touched), **project memory** at
  `~/.claude/projects/<encoded>/memory/` (the index AND every topic file it links, which a repo-scoped grep
  can never reach), and the **active plan file** under `~/.claude/plans/`. Say which three you
  checked; a sweep that names no store reads as though it covered all of them. Prefer a pointer to a copy
  while you are in there: where something already reads a live source on every run, an artefact should name
  that SOURCE rather than cache its answer, or the cached count, version, total or state goes stale in every
  place it was written down at once.

  **The plan file is the dangerous one, and it is the one that gets skipped.** It is transient, so it reads
  as scratch; it is also the FIRST artefact a resuming session opens and the one whose whole job is to say
  what to do next, so a stale claim there does not sit inert like a stale doc, it actively misdirects the
  next session. This has fired three times on one workstream: a retirement done in the repo tree only, where
  a gate then found a live copy in project memory that a repo grep could never have reached; the same
  workstream retiring a superseded model, reconciling BOTH memory stores, calling it done, and a delegated
  gate finding that model still stated in four places in the plan file including its resume-pickup step, so
  a resumer would have sat watching for a trigger that no longer existed; and, hours after the work landed,
  a gate finding a closed item still listed as open in that same plan file, caught only because the
  dispatching session had briefed the gate to look there. The middle one is the shape to carry: the failure
  was not ignorance of the rule, it was SCOPE, a two-store habit against a rule whose real shape is three.

  **Name the instrument too, and state both numbers.** The scan itself can be the thing that is wrong, and
  it fails more convincingly than a missed store, because it returns a confident, specific, false answer
  instead of going quiet. Two shapes. A cheap stand-in read as the artefact: a session-start snapshot, an
  unmaintained "last modified" style field, a cached count, a peer's summary, when the artefact itself is
  one read away. And a hand-rolled extractor over an index, where the pattern silently skips entries whose
  names it was never written for. The tell is arithmetic, so **state what the index links AND what the store
  holds, and stop when the two disagree** rather than reporting whichever is reassuring. A denominator that
  does not reconcile is a defect in the CHECK until proven otherwise.

  **A positive control on the wrong axis is not a control.** Proving a scan can match something proves it is
  wired up, not that its extraction is complete: a control that fires on any hit passes happily while the
  pattern misses three entries in fifty-six. Make the control exercise the specific failure you are worried
  about. And do not attach an owner, a cause or a mechanism to a discrepancy before reading the artefact,
  because **a false number invites doubt and a false number with a plausible mechanism attached does not**.
  Both shapes above happened in one session, at this step rather than at the walk, which is the step that
  had no such guard.

  **And when such a field turns out to be stale, do NOT patch the one you noticed.** The reflex on catching
  a "last modified" style field lagging its own artefact is to correct that entry and move on. Resist it.
  These fields lag precisely because nothing maintains them, so the one you spotted is a sample rather than
  the defect, and the others are lagging too by amounts nobody has measured. Correcting it alone leaves the
  store **worse than you found it**: one accurate stamp sitting among many stale ones is what a maintained
  field looks like, so the next reader stops treating the rest with suspicion. Either leave the field alone
  and take freshness from something that cannot go stale unnoticed, or fix the writer so every entry is
  maintained. **Correcting a single instance of an unmaintained signal is not a partial fix, it is a
  stronger false signal**, and that generalises past freshness to any derived field a reader might trust.
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

### Clear your own worktree, as the last tool call

If this session has been working in its own worktree, disposing of it is part of the park, and it is the
one step that comes after everything else.

**Nothing else clears it.** Ending a session does not remove a worktree, and neither does archiving one. A
native exit helper typically only knows about worktrees IT created in THIS session, so a session that
resumed into an existing one, or made one by hand, gets a clean no-op and the directory stays. What
accumulates is full second copies of a repository that nobody is watching, found only by someone
enumerating the filesystem, and the reason nobody enumerates is that everyone believes the disposal already
happened. Clearing it is cheap only at this moment, because right now you are the one context that knows
which worktree is yours.

**Only your own. Never a peer's.** A live peer's workspace is indistinguishable from abandoned residue from
outside: no process holds it and no descriptors are open, since a parked session holds neither, and
removing it destroys uncommitted work irrecoverably. If you notice others, report them and leave them
alone. Sweeping other sessions' worktrees is a separate and expensive audit, not part of this gate.

**It must be the LAST tool call of the session.** You cannot remove the tree you are standing in partway
through a turn: the shell's working directory vanishes underneath you and every remaining step of the close
is stranded. So the order is fixed. Flush, commit, reconcile the tracker, post the stamp, and only then
remove, writing the closing confirmation afterwards from memory without reaching for a tool again.

**Push, then pin, then remove without `--force`.** Anything already on the remote is safe. A commit that
exists only locally is pinned to a permanent ref first (`git -C <canonical> update-ref
refs/archive/<date>/<name> <sha>`), because a SHA recorded only in a transcript dies with the transcript.
Then `git -C <canonical> worktree remove .claude/worktrees/<name>` and `git -C <canonical> worktree prune`,
run from the canonical clone rather than from inside the worktree. **A refusal from the dirty guard is the
last line of defence and is information, not an obstacle:** read what it names, then either resolve it or
leave the worktree in place and say so. The full mechanics live in `using-git-worktrees`; this gate owns
only WHEN.

## The stamp (post it before the boundary action)

After the checks actually ran from disk this turn, post one line:

`Gate: date re-derived ✓ · CLAUDE+MEMORY fresh-read ✓ · index/coverage rescan ✓ · externalisation ✓ · memory committed ✓`

**The ledger is not part of this stamp.** It was already posted, upstream, before you reconciled or fixed
anything. Here you only refer back to it. If you find yourself composing it now, the gate ran in the wrong
order and tick 2 is not yours to claim: a ledger written at this point is a description of what happened,
and tick 2 exists precisely because it is the one check the artefacts cannot audit afterwards.

Tick a box **only** if that check ran from disk this turn:
1. date re-derived via live `date`;
2. the store delta was run first (log + `status` + last-touch), and then a fresh Read of
   `~/.claude/CLAUDE.md` + global `MEMORY.md` + the project memory index **and every file those indexes
   link**, each accounted for in the ledger against a stated denominator. A file confirmed by mtime, git state, or a
   session-start reminder snippet is **not** read, so do not tick on one, and "unchanged since I last
   checked" is not a delta, it is the assertion the delta exists to replace. Tick this only if the ledger
   went up **before** you started reconciling, and only if it was derived from the Read calls you issued
   rather than from the ones you planned;
3. rescanned the project index and the repo docs this session touched for drift/orphans/dangling pointers,
   and fixed what was found, naming the scanning instrument and stating its counts against what the store
   actually holds, since a scan that under-reads returns a clean answer rather than an error (see
   **Reconcile and fix**);
4. externalised any one-off insight not yet on disk;
5. committed the standing-instruction paths this session wrote, naming them explicitly. Tick it unchanged
   when the store is not a repo (the write was the durable act) or when the session wrote nothing, but
   say which of the three applies rather than ticking it silently.

If a check did not run, do **not** tick it - run it first. **Proposing compact or accepting a park without
the stamp is itself the lapse the user is entitled to call.** The stamp is the safety net; the underlying
gates (pre-compact coverage audit, pre-park externalisation, reread-before-planning, per-chunk skeleton) are
the substance this skill runs on contact.
