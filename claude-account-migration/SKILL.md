---
name: claude-account-migration
description: "Use when moving Claude work from a personal account to a work Team or Enterprise account, or splitting personal and work use across two Claude accounts: claude.ai chats, memory and projects, Claude Code and Cowork sessions, scheduled tasks and cloud routines, or cleaning up the old account afterwards. Triggers include \"migrate my Claude account\", \"move my chats to the work account\", \"personal to team account\", \"export my Claude data\", \"sessions missing after I switched account\", \"sidebar is empty on the new account\", \"scheduled tasks gone after sign in\", \"import memory\", \"claude-code-sessions\", \"local-agent-mode-sessions\", \"clean up the old Claude account\". NOT for the vendor's same-email organisation migration on its own (use the built-in prompt, step 1), NOT for changing one account's plan, NOT for moving repositories or project files."
metadata:
  version: 1.0.0
---

# Claude account migration

> **Skill marker**: When applying this skill, begin your reply with `[skill: claude-account-migration]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Moving from a personal Claude account to a work account under a **different email** has no merge and no import. What you can move depends on where each thing is stored: on the vendor's servers (recreate it), in local files on the Mac (copy it), or both (copy the files, recreate the server side). Classify every category before touching anything.

**Core rule:** copy first, verify from disk, remove from the old account last, and never write into the account the app is currently signed in to.

The exact paths, file keys and log lines are in `references/local-data-layout.md` (stamped with the app version they were learnt on). Read it before any file-level step.

## Step 0: decide scope

- Ask what stays personal (a side venture, family items, personal finance). Classify by title only where the answer is obvious; list the ambiguous ones and ask. Moving personal material into a work account puts it under the work organisation's retention and admin access.
- Check the target plan includes what you will use (Claude Code, Projects and hand-off tasks sit on paid plans; read the vendor's current plan page, do not rely on memory).
- Keep the old account usable until the new one is verified. Cancel or downgrade last.

## What moves, and how

| Category | Lives | Move |
|---|---|---|
| Chats, projects, memory, connectors | server, per account | recreate; the export is a backup, not an import |
| Claude Code desktop sessions | local transcripts plus a per-account sidebar index | copy the index files |
| Scheduled tasks | prompts shared on disk; registry per account | copy registry entries |
| Cowork sessions | local, per account | copy files, rewrite stored paths |
| Cloud routines, web Claude Code sessions | server, per account | cannot move; recreate or replace |

## Procedure

1. **Same email on both?** Use the vendor's built-in migration (it prompts when you accept a Team invite; chats, projects and memory move; it is one way). Everything below is for different emails.
2. **Export first, before cancelling anything.** Settings > Privacy > Export data. The result is a manifest listing several zips (conversations, projects, memories, and others). Each link expires in 24 hours and may die after one use: open each once in a browser, never fetch with curl. Keep the zips.
3. **Filter and bundle the chats.** Read `conversations.json` from the zip without extracting it. Keep by keyword with a minimum-mentions threshold; print what is kept and what is excluded and get the owner to confirm the exclusions. Scan every chat for secret-looking strings and hold those back for the owner to review. Bundle into files of about 2 MB. When re-bundling after an exclusion, read and write with no newline translation, or every bundle changes and you re-upload all of them.
4. **Memory.** Write a work-only version of the memory text (profile, current work, preferences); leave out family and personal interests. Settings > Your Claude > Memory > Import memory, paste, Add to memory. Open Manage to verify the entries. To prune, use the "Tell Claude what to change" box, then open each entry that might mention the removed topic; an edit does not touch every entry.
5. **Chats as knowledge.** Create Private projects (the default visibility can be organisation-wide; check it). Project knowledge has a ceiling of roughly 5 MB of text; a project that is over it refuses more files ("Project knowledge exceeds maximum"), so split the bundles across projects. The browser upload tool takes at most 10 MB per call.
6. **Recreate projects.** Names and descriptions only; skip the vendor's stock starter project and any with no name. Project memory cannot be imported.
7. **Local sessions.** Find the target account's folder with a marker (see the reference), copy (never move) the session index files, include archived sessions and scheduled-run sessions, skip the live session, then verify each copy by hash. The app reads these folders at sign-in, not live. The first reply in a moved session re-reads the whole conversation because the earlier thinking belongs to the other organisation.
8. **Scheduled tasks.** The prompts live once on disk and are shared; the registry that says which tasks run is per account. Copy the recurring entries verbatim (they carry the approved-tool list) into the target registry; the create tool refuses an ID whose folder already exists. Only the signed-in account runs its tasks. Spent one-off checks need no move.
9. **Cowork sessions.** Copy the session file and its folder together, preserve symlinks, rewrite the old account and organisation path prefix inside the copied file, and compare file counts. The stored prompt carries the old identity and memory, so review it before resuming.
10. **Cloud routines and web sessions.** Not movable. Replace a purely date-driven routine with calendar events (an `.ics` imports cleanly and carries the checklist); otherwise recreate it from the export. The routine API can pause but not delete; the owner deletes in the web UI.
11. **Verify from disk, not from the sidebar.** The running app holds the old state in memory and the sidebar lags. Count files, compare hashes, read the registry.
12. **Clean the old account.** Only when the app is not running as that account (see the guard below). Move files into a dated backup folder with a manifest, never delete; dry run first; re-check after the app restarts, because the app re-saves sessions it holds in memory.
13. **Server-side leftovers** (chats, projects, memory in the old account) are the owner's to delete. State exactly what will go and that it cannot be undone. "Delete all chats" also removes what you meant to keep; selective deletion is per chat.

## The cleanup guard (what it must check)

- **Active account:** replay the app log in order. A logout line sets "nobody"; a login line sets the account; an initialisation line sets the account. Reading only the last initialisation line blocks you after a clean logout.
- **App running:** the main program only (`ps -axo comm=` equal to `/Applications/Claude.app/Contents/MacOS/Claude`). Helpers such as the Chrome-extension native host and crash reporters share the path and outlive a quit, so a broad `pgrep` never reaches zero.
- The app can log itself back in after a logout. Quit with Cmd+Q, confirm the main program count is 0, then run.
- **Never test a guard with its real flag.** A guard bug plus `--apply` is a real run. Test with the dry run or a synthetic log.

## Red flags

- Writing into the folder of the account the app is signed in to (the app can overwrite it).
- Assuming an account folder is the work account because it is not the personal one. Folder names are IDs, not emails; use a marker session.
- Moving instead of copying, or deleting instead of moving to a backup.
- Confirming a UI "Remove" without reading which file the dialog names (the hidden remove button of an adjacent card is easy to hit).
- Uploading chats that contain credentials to the work account without the owner's review.
- Pasting personal memory into the work account because it "is just memory".
- Declaring the old account clean from the sidebar instead of the files.
- A `pgrep` guard that never reaches zero, or one that ignores logouts.
- Deleting server-side data before the new account has been checked by the person who will use it.
- Claiming a session or routine "moved" when it is account-bound (web sessions, cloud routines).

## Bottom line

Different email means recreate the server side and copy the local files. Export before anything else, bundle with a secrets check, import a work-only memory, split chats across private projects under the size ceiling, copy the session and task files into the target account's folders while the app is signed in to the other account, verify by hash, then move the old copies to a backup with a guard that reads login state correctly. The owner deletes server-side data last.
