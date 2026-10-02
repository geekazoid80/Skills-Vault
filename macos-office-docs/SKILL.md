---
name: macos-office-docs
description: "Use when turning a .pptx or .docx into a PDF to look at on a Mac (visual QA of a deck or document using Microsoft PowerPoint or Word driven by AppleScript or osascript, no LibreOffice), or when changing an EXISTING .docx or .pptx in place while keeping its formatting (rename, literal text substitution, add a table row or section, harmonise wording). Symptoms and trigger phrases include osascript exits 0 but no PDF appears, 'AppleEvent timed out (-1712)', the Office sandbox refusing /private/tmp, python-pptx save drops parts or media, 'edit the deck without regenerating it', a Box Drive file that is read-only, Word reverting my edit or spawning a conflict copy, textutil to read a docx. NOT for generating a new deck or document from scratch, NOT for headless or Linux rendering, NOT for Google Docs or Slides."
metadata:
  version: 1.0.3
---

# macOS Office Docs

> **Skill marker**: When applying this skill, begin your reply with `[skill: macos-office-docs]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Two halves of working with an Office file on a Mac. **Part A** renders a `.pptx` or `.docx` to a PDF so you can look at it. **Part B** changes an existing document in place without regenerating it and without losing its house format. Read Part B before editing, Part A before rendering.

**Core principle:** look at the document in the renderer the audience will use (Office itself), and change a document at the level that preserves every part of it. Both halves fail silently: a clean run, exit 0, and no PDF, or a saved deck that has quietly lost parts.

**Version stamp.** Learnt 2026-08-06 on macOS (Darwin 25.5.0) with Microsoft PowerPoint for Mac, `pdftoppm` from Homebrew Poppler, python-docx 1.2.0 and python-pptx 1.0.2. LibreOffice was not installed.

## When this does NOT fire

- Building a new deck or document from nothing: use a generation skill.
- Unattended, headless or Linux work: LibreOffice is the right tool there, because the Office route below needs a logged-in GUI session and can raise a one-time automation prompt.
- Google Docs or Slides.

## Part A: render a .pptx to PDF with Office AppleScript

```bash
osascript <<'APPLESCRIPT'
with timeout of 540 seconds
  tell application "Microsoft PowerPoint"
    repeat while (count of presentations) > 0
      close presentation 1 saving no
    end repeat
    open POSIX file "/abs/path/deck.pptx"
    save presentation 1 in POSIX file "/Users/<me>/Downloads/deck.pdf" as save as PDF
  end tell
end timeout
APPLESCRIPT
pdftoppm -jpeg -r 110 ~/Downloads/deck.pdf slide     # slide-1.jpg ... zero-padded from 10 pages up
```

**Word works the same way.** Verified headless twice: a 14-page policy `.docx` on 2026-08-09 and a one-page throwaway on 2026-10-02, both to PDF in `~/Downloads`. Only the dictionary terms differ:

```bash
osascript <<'APPLESCRIPT'
with timeout of 540 seconds
  tell application "Microsoft Word"
    open POSIX file "/abs/path/doc.docx"
    set d to active document
    save as d file name "/Users/<me>/Downloads/doc.pdf" file format format PDF
    close d saving no
  end tell
end timeout
APPLESCRIPT
```

Word may already be running, so address only the document you opened and close only that one. Do not name an AppleScript variable `before` or `after`; both are reserved words and fail with a `-2741` syntax error. **Word does not fail the way trap 1 below describes.** Re-tested on 2026-10-02 with a throwaway document. Saving the PDF into an agent scratchpad under `/private/tmp/claude-501/...` worked (a valid PDF). Saving to a plain `/private/tmp/<name>.pdf` did not return quietly with no file: the call ran into the AppleEvent timeout (`-1712`) after 90 seconds, produced no file, and left the document open with `close` refused (`-1708`), including after a retry. That is consistent with Word waiting on a file-access dialog that only a person at the screen can answer, though the dialog itself was not seen. It is probably what the older "Word hangs on a permission dialog" folklore was describing. So in Word a wrong output path is not a cheap probe: write to `~/Downloads`, do not experiment with other locations, and when a call times out look at the Word window before retrying. PowerPoint's silent no-file behaviour was not re-tested in that run.

### The two traps (both silent in PowerPoint; see the Word note above)

1. **The Office sandbox refuses writes outside the user's standard folders and returns NO error and NO file.** Saving into `/private/tmp/...` (including an agent scratchpad under it) gives a clean `osascript` run, exit 0, empty output, and no PDF anywhere. It is not a permission error you can catch. **Write to `~/Downloads` (or `~/Documents`, `~/Desktop`) and move the file afterwards.** Reading an input from `/private/tmp` is fine; only the write is blocked. Isolate it by changing only the output path. For a live operator, reuse the SAME output path across iterations, since each new location can prompt for access.
2. **The default AppleEvent timeout is 120 seconds and an image-heavy deck exceeds it.** The result is `execution error: Microsoft PowerPoint got an error: AppleEvent timed out. (-1712)`. That is a client-side timeout, NOT a failure: the app had opened the file and kept working. Confirm with `tell application "Microsoft PowerPoint" to return name of every presentation` before retrying, and wrap everything in `with timeout of 540 seconds`.

### Other interface facts

- `close presentation 1 saving no` inside `repeat while (count of presentations) > 0` works. `repeat with p in (every presentation) ... close p` throws `-50 Parameter error`.
- An open document can be addressed by name: `set p to presentation "deck.pptx"`.
- **Dead end:** `sdef "/Applications/Microsoft PowerPoint.app"` emits nothing useful, so the dictionary cannot be grepped for verbs. Use the classic Office terms (`save ... in ... as save as PDF`) directly.
- **Dead end:** System Events UI scripting fails `-1728 osascript is not allowed assistive access`. The Office app's own dictionary needs no assistive access, so never route through System Events for this.
- Office bundles its own fonts under `/Applications/Microsoft PowerPoint.app/Contents/Resources/DFonts` (Calibri, Aptos and others) even when Font Book and `system_profiler SPFontsDataType` do not list them. A deck in Calibri renders true in Office while a font check against the system list says it is missing. Check DFonts before concluding a font will substitute.

### Why Office rather than LibreOffice for visual QA

Office is the renderer the audience will actually use, so text fit, font metrics and layout are exact. LibreOffice substitutes fonts it lacks, which makes overflow checks unreliable (the first-party `pptx` skill says the same).

## Part B: change an existing .docx or .pptx and keep its format

**Read text:** `textutil -convert txt -stdout file.docx`. For a pptx, read with `python-pptx` (read-only) or unzip `ppt/slides/slide*.xml`.

**Rename or literal substitution:** unzip, `sed -i '' 's/OLD/NEW/g'` the relevant `*.xml` parts, and rezip preserving **every** part:

```bash
(cd ex && zip -q -X -r OUT '[Content_Types].xml' _rels docProps word $(ls -d customXml 2>/dev/null))
```

For a pptx use `ppt` in place of `word`. Check with `unzip -t`.

**docx content edits** (add a section, insert a table row, rewrite a paragraph): `python-docx` is safe and format-preserving. Clone an existing paragraph or row element (`copy.deepcopy(p._p)` or `deepcopy(row._tr)`, then `addprevious` / `addnext`) so styles and list numbering carry over. Set text by putting all of it in `run[0]` and clearing `runs[1:]`. `Document.save()` is fine for docx.

### python-pptx `save()` is LOSSY for a deck you must keep faithful

`Presentation.save()` repackages the deck and **drops parts** (75 entries became 56 in one deck, including the empty `ppt/media/` directory) even though the slide edits applied correctly. Use `python-pptx` to IDENTIFY the exact text, then make the change at the XML level (unzip, edit `ppt/slides/slide*.xml`, rezip preserving all parts). Verify the `unzip -l` entry count against the original before the file goes anywhere.

- Slide text usually sits contiguous in one `<a:t>`, and `&` is stored as `&amp;`, so a full-string replacement works if you XML-escape `& < >` in both the search and replace strings.
- Misses come from (a) a paragraph split across runs and (b) a curly apostrophe (U+2019) in the XML against a straight `'` in your key. Fall back to replacing a short apostrophe-free fragment, or just the offending character.

### Synced cloud folders (Box Drive) and Word

- **Box marks synced files read-only** (`-r--------`) after upload. `chmod u+w` before overwriting, or `cp` fails "Permission denied". That is not necessarily an open-file lock; check `lsof` and the `~$` lock files to tell them apart.
- **A file open in Word during your write** produces a Box conflict copy `name (user).docx`, and the open Word session can save the OLD content back over your write. Symptoms: your change is missing on re-read and a twin file appears. Tell them apart by content (grep for the change), keep the correct one, and open the FRESH synced copy afterwards, never a stale Word window. Ask the operator to close Word before you write.
- **Deleting a synced file** (a stale conflict copy): `mv` it to `~/.Trash/` so it is recoverable (Box keeps its own trash too), never `rm`. Re-confirm the delete with the operator at the time.

### House style: scanning for em dashes

If the house style bans em dashes, scan for U+2014 with a literal glyph match or a Python codepoint check (`chr(0x2014) in line`), never a PCRE byte-escape such as `\xe2\x80\x94`. Some `grep` builds (ugrep) silently fail to match a byte-escape and the scan false-passes. Replace a `Label`, dash, `value` pairing with a colon and prose em dashes with a comma or semicolon. On terse slides a plain-hyphen range such as `3-5 yrs` is fine.

## Red flags

- A render command that exited 0 with no PDF, and a conclusion that Office "cannot export" (check the output path first).
- Retrying after `-1712` without asking the app what it is doing; it is probably still working.
- Saving a deck you must keep faithful with `python-pptx` `save()`.
- Rezipping with a hand-picked file list that omits a part, or skipping the `unzip -l` count against the original.
- Overwriting a Box-synced file without checking whether Word has it open.
- `rm` on a synced file instead of `mv` to the Trash.
- Retrying a timed-out Word save, or trying another output folder, without looking at the Word window first; a pending access dialog wedges the document.

## Bottom line

Render with Office itself, write the PDF into `~/Downloads` and move it, and wrap the call in a long timeout; treat `-1712` as a slow job, not a failure. Edit at the XML level (or with `python-docx` for content) and never save a deck you must preserve through `python-pptx`; confirm the part count against the original. Close Word before writing into a synced folder. The Word recipe is the same shape, with its own dictionary terms and a different failure on a bad output path (a hang, not a silent no-file).
