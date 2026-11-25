---
name: dependency-install-strategy
description: "Use when about to install a package, library, runtime, or CLI tool, or set up a project's language environment, on any host (workstation, NUC, CI box, container). Triggers include \"pip install\", \"apt install\", \"brew install\", \"npm/pnpm install\", \"missing dependency\", \"ModuleNotFoundError\", \"externally-managed-environment / PEP 668\", \"set up a venv\", \"should I use uv\", \"requirements.txt / pyproject\", \"which python\", \"install X on the NUC\". Decides HOW to install: prefer the system/local package manager for version-flexible deps it carries at an acceptable version; drop to a project-local venv/uv (pinned, auto-activating) only when a specific version is required or the manager does not carry it. Never --break-system-packages a PEP-668 system interpreter as the default. Composes with the refresh-the-package-index-first rule, the ask-before-install rule (get the go-ahead), secrets-hygiene, and resource-registry (record the resulting env + how to activate it)."
---

# Dependency Install Strategy

> **Skill marker**: When applying this skill, begin your reply with `[skill: dependency-install-strategy]` on its own line. If multiple skills fire on the same reply, emit each marker on its own line at the top.

## Overview

There are two good ways to install a dependency and one bad one. The good ways: the **system/local
package manager** (apt, dnf, brew, the OS's own), or a **project-local isolated environment** (venv,
uv) that is pinned and reproducible. The bad way: forcing packages into a modern, externally-managed
system interpreter (`pip install --break-system-packages`), which silently fights the OS package
manager and rots the base environment for every other tool on the host.

**Core principle:** use the package manager for what it carries at an acceptable version; isolate in a
venv/uv when you need a pin or the manager does not have it. Choose deliberately, per dependency, not by
habit.

## When this fires

- You are about to install any package, library, runtime, or CLI tool on any host.
- You hit a missing dependency (`ModuleNotFoundError`, `command not found`) or a PEP-668
  `externally-managed-environment` error.
- You are standing up or changing a project's language environment (Python/Node/Ruby/…).

## The decision (in order)

1. **Gate: ask + refresh.** Surface the missing dependency and get the go-ahead before installing
   (do not hand the user a paste-and-fix loop). Refresh the package index first on that host
   (`sudo apt-get update`, `brew update`, `winget source update`, … see the per-OS table below). These are the `ask-before-install` and
   the refresh-the-package-index-first rule; this skill picks up after it.

2. **Manager-first for version-flexible deps.** If the dependency needs **no specific version** AND the
   host's package manager carries it **at an acceptable version**, install it with the manager (global,
   managed, patched by the OS, no per-project overhead). For a *library*, "in the manager" means an OS
   package exists (e.g. `python3-numpy`, `python3-scipy`), not just that PyPI has it.

3. **Isolate when you need a pin or the manager lacks it.** If a **specific version is required**, OR
   the package is **not in the manager** (or only at a too-old version), create a **project-local venv
   or uv environment**, install there (pinned via `requirements.txt`/`uv.lock`/`pyproject.toml`), and
   **wire auto-activation on entering the folder** where the host supports it: direnv `.envrc` with
   `layout python <version>` or `layout uv`, or uv's native project env, or at least a documented
   `.venv/bin/python` invocation. Prefer uv when available (fast, reproducible, self-managing); else a
   stdlib `venv`.

4. **Never default to `--break-system-packages`.** On a PEP-668 system interpreter that is the
   anti-pattern this skill exists to avoid. If step 2 does not apply, go to step 3. Use
   `--break-system-packages` only as a consciously-justified last resort on a throwaway/base image you
   own, never on a shared operational host.

## Per-OS package managers (step 2 on each host)

Name the host first (`uname -s`: `Darwin`, `Linux`, or `MINGW64_NT-*` / `MSYS_NT-*` for Git Bash on
Windows), then use that host's manager. Never present one host's command as the only form.

| Host | First choice | Then | Index refresh | Elevation |
|---|---|---|---|---|
| macOS | Homebrew: `brew install <pkg>` | none | `brew update` | not needed |
| Windows | `winget install --id <Publisher.Package> -e --silent --accept-package-agreements --accept-source-agreements` | `scoop install <pkg>` | `winget source update` | user-scope packages need none; `choco` usually wants an elevated shell, so do not choose it for anything unattended |
| Debian, Ubuntu | `apt-get install -y <pkg>` | none | `apt-get update` | root or `sudo` |
| RHEL family | `dnf install -y <pkg>` | `yum install -y <pkg>` | `dnf makecache` | root or `sudo` |
| SUSE | `zypper --non-interactive install <pkg>` | none | `zypper --non-interactive refresh` | root or `sudo` |
| Alpine | `apk add <pkg>` | none | `apk update` | root or `sudo` |
| Arch | `pacman -S --noconfirm <pkg>` | none | the install syncs; never run `pacman -Sy` alone (a partial upgrade) | root or `sudo` |

Look the package up read-only before trusting a name (`winget show --id <id> -e`, `brew info <pkg>`,
`apt-cache policy <pkg>`): a package id that resolves is a cheap check that the command will do what you
think. On Windows, a Git Bash script that passes a flag starting with `/` to a native tool has it rewritten
into a path; write `//flag` or set `MSYS2_ARG_CONV_EXCL='*'`.

## Automating an install (a hook or a script installing its own prerequisite)

Only when the dependency is a hard prerequisite of something that must not run without it (a safety
check, a guard) and the owner has asked for it: that request is the go-ahead step 1 requires, so record it.
Then keep every one of these:

1. **The platform's own manager only.** Never download and run a script or binary, and never bootstrap the
   manager itself (no `curl | sh` to install Homebrew). If the manager is absent, say what to run and stop.
2. **Never ask for a password.** Linux needs root or `sudo -n`; with neither, report and stop.
3. **Never block the caller.** Start it detached (`nohup <cmd> >> log 2>&1 < /dev/null &`, then `disown`).
4. **One attempt at a time, and not in a loop.** A lock directory (`mkdir` is atomic) with a stale-lock
   timeout, and a stamp file that limits retries (for example one per 30 minutes).
5. **Leave evidence.** A log file, and the failure message the caller shows says what was started or why
   nothing was.
6. **An off switch** the owner can set without editing code (a marker file).
7. **Find the result without a restart.** A running process does not see a `PATH` entry added after it
   started, so also look in the manager's own folder (for example winget's `Links` folder, `/opt/homebrew/bin`).
8. **Test it with seams, never the real thing.** Read the platform and the tools present from environment
   variables a test can set, stub the installer, and prove the tests fail against the old code.

Worked example: a security hook that blocks credential-writing commands needs `jq` to read its input. A
hook that allowed everything when `jq` was missing only looked armed, so it now fails closed, says why, and
starts one background install by the rules above. Details of that failure mode: a blocking hook must fail
closed when it cannot read its input, while an advisory hook may fail open.

## Record the outcome (resource-registry)

Whatever you land on, record it in the project's durable home (AGENTS.md / project memory) so the next
session runs it right: the interpreter path, whether it is system or venv/uv, how to activate
(`direnv allow`, `uv run`, `.venv/bin/python`), and which deps came from the manager vs the env. An
env nobody documents is an env the next session re-derives the hard way.

## Notes

- **Consistency within a project.** If a project already runs on one model (e.g. all scripts on system
  python), do not split one script into a venv; migrate the whole project or stay put. Mixed models
  confuse the run story.
- **Reproducibility vs low-maintenance.** The manager path optimises for low-maintenance (OS patches
  it); the venv/uv path optimises for reproducibility (a lockfile pins it). When cross-host
  reproducibility matters (CI, many hosts), lean venv/uv + lockfile even for deps the manager carries.
- **CLI tools vs libraries.** A standalone CLI the manager carries (jq, ripgrep) is almost always a
  manager install. A library imported by project code is the case the venv/uv branch is really about.
- **Isolated mode hides user-site installs.** `python3 -I` (the safe way to run a script that reads
  untrusted data) ignores user-site packages and `PYTHON*` variables, so a library installed with
  `pip install --user` imports fine in a normal run and raises `ModuleNotFoundError` under `-I`. Seen
  2026-11-02 with numpy. Run your own code without `-I`, or give it a venv; keep `-I` for the one script
  that parses untrusted input, and record in the repo which interpreter and flags each script needs.

## Worked example

A geofeed generator on an internal host needs `reverse_geocoder`. Check: it is
**not in apt** (only unrelated geocoders), and no specific version is required. Its heavy deps
(`numpy`, `scipy`) *are* apt-packaged, but the leaf package is PyPI-only. NUC runs a PEP-668 system
python 3.13. Decision path: step 2 fails (not in the manager) -> step 3: a **project-local venv/uv** for
the project, install `reverse_geocoder` (+ the project's other deps) there, auto-activate via direnv
or uv. This matches a sibling project (already `.venv` + `pyproject.toml`) and
avoids `--break-system-packages` on the shared NUC. Record the env + activation in the repo AGENTS.md.

## Red flags

- Reaching for `pip install --break-system-packages` (or `sudo pip`) on a shared/operational host
  without having checked the manager or considered a venv.
- Installing a version-flexible, manager-carried dependency into a bespoke venv for no reason (overhead
  with no pin to justify it).
- Spinning up a venv for one script in a project whose other scripts run on system python (split run
  story).
- A venv/uv env created but never documented, so the next session cannot find or activate it.
- Skipping the index refresh, or installing before surfacing the gap and getting the go-ahead.

## Bottom Line

Manager-first for version-flexible deps it carries at an acceptable version; project-local venv/uv
(pinned, auto-activating) when you need a version or the manager lacks it; never
`--break-system-packages` a system interpreter by default. Refresh the index and get the go-ahead
first; record the resulting environment where the next session will look.
