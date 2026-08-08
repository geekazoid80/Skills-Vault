---
name: dependency-install-strategy
description: "Use when about to install a package, library, runtime, or CLI tool, or set up a project's language environment, on any host (workstation, NUC, CI box, container). Triggers include \"pip install\", \"apt install\", \"brew install\", \"npm/pnpm install\", \"missing dependency\", \"ModuleNotFoundError\", \"externally-managed-environment / PEP 668\", \"set up a venv\", \"should I use uv\", \"requirements.txt / pyproject\", \"which python\", \"install X on the NUC\". Decides HOW to install: prefer the system/local package manager for version-flexible deps it carries at an acceptable version; drop to a project-local venv/uv (pinned, auto-activating) only when a specific version is required or the manager does not carry it. Never --break-system-packages a PEP-668 system interpreter as the default. Composes with apt-update-before-install (refresh the index first), the ask-before-install rule (get the go-ahead), secrets-hygiene, and resource-registry (record the resulting env + how to activate it)."
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
   (`sudo apt-get update`, `brew update`, …). These are the `ask-before-install` and
   `apt-update-before-install` rules; this skill picks up after them.

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
