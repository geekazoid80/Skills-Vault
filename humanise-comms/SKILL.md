---
name: humanise-comms
description: "Use for ALL human-bound communications (emails, Slack messages, PR descriptions and comments, GitHub issue text, commit messages, PR titles, customer-facing letters, status updates, prose docs, release notes, anything a human will read). NOT for code, configuration files, or machine-parsed payloads. Writes like a person, not an agent. No em dashes, ever (use a comma, semicolon, parentheses, or full stop instead). British / Pacific English spelling. Structure for an ask: background and project attribution first, then the ask, then a named real escalation contact (sourced from config, never invented), with technical detail tucked behind details blocks. For commit subjects + PR titles, check the project's CLAUDE.md / AGENTS.md for the established prefix convention (Conventional Commits feat:/fix: vs roadmap-feature-id form) before drafting; check git log if the project doc is silent. Tone is professional-direct, not corporate-padded."
metadata:
  version: 1.0.0
---

# Humanise Comms

> **Skill marker**: When applying this skill, begin your reply with `[skill: humanise-comms]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Trigger surface: every piece of writing a human will read. Emails, Slack messages, PR descriptions and comments, GitHub issue bodies, customer letters, vendor responses, status updates, release notes, prose docs.

NOT for code, configuration files, JSON / YAML payloads, machine-parsed text. Those have their own conventions.

**Core principle:** write like a person, not an agent. The reader should not be able to tell an LLM drafted it.

## The em-dash ban (zero tolerance)

No em dashes (`, `). Ever. They are the LLM tell.

Replace with:

| Instead of an em dash | Use |
|---|---|
| Setting off a parenthetical | A pair of commas, parentheses, or two full stops |
| Connecting two related clauses | A semicolon or a full stop |
| Introducing a list or summary | A colon or a full stop |
| Adding emphasis | A comma, or restructure the sentence |

### Worked rewrites

**Wrong:** "We reviewed the proposal yesterday, the team flagged three concerns, mostly around timing."

That comma chain is a polite American-style. Acceptable. The dash version below is what to avoid.

**Wrong:** "We reviewed the proposal yesterday, the team flagged three concerns, mostly around timing."

**Wrong (em-dash form):** "We reviewed the proposal yesterday, the team flagged three concerns, mostly around timing."

(Substitute em dashes mentally: "We reviewed the proposal yesterday X the team flagged three concerns X mostly around timing." That is the LLM register.)

**Right:** "We reviewed the proposal yesterday. The team flagged three concerns, mostly around timing."

**Right:** "We reviewed the proposal yesterday; the team flagged three concerns (mostly around timing)."

## British and Pacific English

| US | UK / Pacific |
|---|---|
| organize | organise |
| prioritize | prioritise |
| customize | customise |
| utilize | utilise |
| recognize | recognise |
| analyze | analyse |
| behavior | behaviour |
| color | colour |
| favor | favour |
| neighbor | neighbour |
| labor | labour |
| program (noun, broadcast / app) | programme (broadcast / event); program (computer code) |
| center | centre |
| meter (unit of length) | metre |
| defense | defence |
| license (noun) | licence; verb stays "license" in UK too |
| judgment | judgement |
| traveling | travelling |
| canceled | cancelled |

Numbers: "one in five" not "1 in 5" in prose. Dates: 9 May 2026, not May 9, 2026.

## Structure for an ask

When the message asks the reader to do something, structure it as:

1. **Background and project attribution.** One or two sentences. What is the project, why are you writing, why is the reader the right person.
2. **The ask.** Direct. One sentence. What you want the reader to do, by when.
3. **The named contact.** A real person sourced from the project's config (not invented), for follow-up if the reader cannot help.
4. **Technical detail behind a details block.** Use `<details>` (Markdown / GitHub / Notion) so the reader can skip past the detail unless they want it.

### Template

```
Hi <name>,

Background: <one or two sentences on the project and why this lands with the reader>.

Ask: <single sentence: what you want done, by when>.

If you cannot help, please loop in <real-person-from-config>.

<details>
<summary>Technical detail</summary>

<the chunky bits: error messages, stack traces, config snippets,
acceptance criteria, links to the runbook>

</details>

Thanks,
<sender>
```

## Commit messages and PR titles

The subject line is machine-parsed (it appears in `git log --oneline`, in changelogs, in release pages, in CI run titles) AND human-read in PR list views. The body is human-read end-to-end. Both surfaces fall under this skill.

### Convention discovery, always do this first

Different projects use different prefix conventions. The two common shapes:

| Shape | Example | Where you find it |
|---|---|---|
| **Conventional Commits** | `feat(infra): add pgBackRest role` | semantic-release projects, npm-published libraries, repos with a `.commitlintrc` |
| **Roadmap-feature-id form** | `RM-INFRA-04-PGBACKREST: pgBackRest ansible role + NFS mount` | projects with a roadmap doc (`docs/feature-roadmap.md`, `ROADMAP.md`); planning-heavy repos |

**Before drafting a commit or PR title:**

1. Check the project's `CLAUDE.md` / `AGENTS.md` for an explicit statement.
2. If silent, check `git log --oneline | head -20` to learn the established practice.
3. Match exactly. Do not mix forms. If the repo uses `RM-XXX: ...`, do NOT introduce `feat(scope):`, and vice versa.

If the project doc contradicts the actual git log (e.g. CLAUDE.md says "Conventional Commits" but every recent commit uses `RM-XXX: ...`), the git log is authoritative; flag the doc contradiction as a separate cleanup.

### Subject line

- One line; under 80 characters (under 70 if it goes in PR titles where GitHub UI truncates).
- Imperative mood: `add pgBackRest role`, NOT `added pgBackRest role` or `adds pgBackRest role`.
- Sentence case after the prefix: `RM-INFRA-04-PGBACKREST: add pgBackRest role`, not `... Add pgBackRest Role`.
- No trailing period.
- The PR-number suffix `(#42)` is added by GitHub on squash-merge; do not pre-write it.

### Body

- Wrap at 72 characters per line.
- Explain WHY, not WHAT. The diff shows the what; the body explains the motivation, the constraint that drove this design, the ADR it implements, the trade-off accepted.
- Reference the roadmap row + any ADR explicitly (`per ADR-0059`, `closes RM-INFRA-04-PGBACKREST`).
- Carved follow-ups: list them as bullet items at the bottom (`Carved follow-ups: RM-INFRA-04-OFFSITE, RM-OPS-NAS-AT-REST-ENCRYPT`).
- `Co-Authored-By: ...` trailer when a sub-agent (or another author) contributed substantively. One trailer per author. Goes at the very end after a blank line.

### Worked rewrite

**Wrong** (mismatched form + narrates the what):

```
feat: added new pgbackrest ansible role with NFS mount and added Vault Agent template
This commit adds the pgbackrest role under infra/proxmox/ansible/roles/
which installs pgbackrest, mounts NFS, creates a stanza, and adds an
archive_command override.
```

**Right** (matches repo convention + explains why):

```
RM-INFRA-04-PGBACKREST: pgBackRest ansible role + NFS mount + Vault Agent cipher render (T-008 PR-1)

Adds the v0.1 backup pipeline shape per ADR-0059: pgBackRest writes
encrypted backups over NFSv4 to an existing on-LAN NAS, with the cipher
key rendered by Vault Agent (live) or written from vars_prompt (staging)
into /etc/pgbackrest/conf.d/cipher.conf on the LXC. The cipher key NEVER
lands on the NAS; the NAS sees ciphertext only.

Role ordering: pgbackrest runs AFTER vault-agent on live so stanza-create
sees the rendered cipher. On a first live playbook run before the operator
populates Vault, cipher.conf is absent and stanza-create + the archive
override SKIP; a debug task warns the operator.

Carved follow-ups: RM-INFRA-04-OFFSITE (v0.2 cross-site replication),
RM-OPS-NAS-AT-REST-ENCRYPT (v0.2 Synology Encrypted Shared Folder),
RM-OPS-NFS-TRANSPORT-ENCRYPT (v0.2 Kerberos krb5p or NFS-over-TLS).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

The first form would fail a routing-table-style review (wrong prefix, narrates the diff, no ADR reference, no carved follow-ups, no co-author trailer).

## Tone rules

Professional-direct. Not corporate-padded. Not chummy. Not robotic.

### Banned phrases

| Phrase | Why banned | Replacement |
|---|---|---|
| "I hope this finds you well" | Filler, no information | Cut entirely |
| "Kindly" | Imperative dressed up as politeness | "Please" or just the verb |
| "Please be advised that" | Bureaucratic | Just state the thing |
| "As per our previous discussion" | "As per" is corporate dust | "As we discussed" or "From our earlier email" |
| "Going forward" | Corporate hedge for "from now" | "From now" |
| "Circle back" | Meeting-room idiom | "Follow up" or "Come back to" |
| "Touch base" | Same | "Check in" or "Speak again" |
| "Leverage" (as a verb) | Buzzword | "Use" |
| "Reach out" | Filler | "Contact", "Email", "Call" |
| "At your earliest convenience" | Passive-aggressive | "By <date>" or "When you can" |
| "Synergies" | Empty | Cut, restructure |

### Worked example: a corporate-padded message rewritten

**Before:**

> Hi John,
>
> I hope this email finds you well! I'm reaching out to circle back on our previous discussion regarding the leverage opportunities for our partnership. Going forward, I think we should touch base at your earliest convenience to align on the synergies between our teams. Kindly let me know your availability.
>
> Best regards,
> Alex

**After:**

> Hi John,
>
> Following up on the partnership conversation last Thursday. Are you free for a 30-minute call this week or next to settle on which of the three workstreams we own and which sit with your team?
>
> If this week is tight, Tuesday next week works on my side after 2pm SGT.
>
> If you would rather hand this to someone else on your side, please loop in Sara Tan (the integration owner per our project config).
>
> Thanks,
> Alex

The "after" carries more information in fewer words and reads like a person.

## Red flags

When you are about to send a comm, scan for:

- An em dash anywhere.
- A US spelling (organize, color, behavior, etc.).
- One of the banned phrases.
- A made-up contact name (the contact must come from config, not from your imagination).
- Missing background or attribution (reader has to infer why they got the message).
- A wall of technical detail not hidden behind `<details>`.
- "I hope this finds you well", "kindly", "please be advised", "going forward", "circle back".
- Any sentence longer than 30 words. Break it.

## Bottom Line

Write the way you would speak in a professional setting where everyone is busy. Direct, attributed, no padding. Technical detail behind a fold. No em dashes. British or Pacific English. Real names for follow-ups.
