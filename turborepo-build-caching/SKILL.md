---
name: turborepo-build-caching
description: "Use PROACTIVELY whenever working in a Turborepo monorepo (any repo with a turbo.json), or editing turbo.json / tsconfig.json / CI actions/cache config, or setting up or reviewing a monorepo's build-test-CI pipeline. Audit the build-cache config against the rules on contact; do NOT wait for a symptom. Symptoms that mean a misconfig is ALREADY biting (triple-check every rule if any is seen): cache misses on unrelated edits, a docs/markdown edit busting the build cache, slow or hanging cache save, \"no output files found\" warnings, tsc rebuilding everything, low cache-hit rates. NOT for single-package repos or non-turbo build tools (nx, bazel, plain tsc). Covers source-scoped inputs, outputs matching outDir/declarationDir plus the tsbuildinfo, the build-vs-typecheck tsBuildInfoFile clobber, the **/.turbo CI glob trap, and globalDependencies for shared root data/schema."
---

# Turborepo build caching

> **Skill marker**: when applying this skill, begin your reply with `[skill: turborepo-build-caching]` on its own line so the transcript shows it fired.

## Fire proactively, not reactively

This is an **audit you run on contact** with a turbo monorepo's build/cache surface, not a fix you reach for only after something breaks. On load, run the full R1-R7 checklist against the current `turbo.json` + tsconfig **even if nothing looks wrong**. If any trigger symptom is already present, treat it as confirmation of a latent misconfig and **re-verify each rule twice**: run the markdown/src acid test (R7) *and* check the CI cache-save time. A masked failure (`continue-on-error`, a silently disabled cache) reads green while doing nothing, so "CI is passing" is not evidence the cache works.

## Core principle

Turborepo caches a task's declared `outputs`, keyed by a content hash of its `inputs` + `globalDependencies` + internal-dependency versions. Two failure modes dominate: **over-hashing** (inputs too broad, so unrelated edits bust the cache) and **under-declaring** (outputs missing, so the task never caches or restores inconsistently). A third, monorepo-specific trap lives in the CI layer (a deep glob in the `actions/cache` path). Get inputs tight, outputs complete, the CI cache path glob-free, and prove it with the acid test.

Crucial semantic to keep in mind: **turbo restores a task's `outputs` only on a cache HIT** (when it skips the task). On a miss it runs the task fresh and restores nothing. So declaring a file as an output preserves it *through hits*; it does not give you incremental-on-miss.

## The rules

### R1 - Scope `inputs` to source
With no `inputs` key, turbo hashes every non-gitignored file in the package. Editing `AGENTS.md`/`README.md` or a stray root file then busts that package's build/test/typecheck cache. Set explicit source-scoped inputs:

```jsonc
"build": { "inputs": ["src/**", "scripts/**", "tsconfig.json", "package.json", "!**/*.md"] }
```

`node_modules`, `dist`, `.turbo`, `coverage` are usually already gitignored, so they are already out of the default hash; the ones that bite are **markdown and per-package data files**, which are not. Explicit positive globs (`src/**`) exclude them inherently; add `!**/*.md` for clarity. Include EVERY real source root: check each package's tsconfig `include` (e.g. an app may add `scripts/**`).

### R2 - `outputs` must list every emitted artifact
Undeclared outputs are the number-one mistake: if turbo does not know what a task writes, it caches nothing and reruns every time. List the compiler `outDir` (and `declarationDir` if separate), plus the tsbuildinfo where the task emits it. Delete dead entries (a classic is `.next/**` copied into a repo with no Next.js app).

```jsonc
"build": { "outputs": ["dist/**", ".turbo/tsconfig.tsbuildinfo"] }
```

### R3 - tsbuildinfo in `outputs` only for tasks that emit it
`incremental: true` in tsconfig writes a `.tsbuildinfo`. Declare it as an output of the task that **emits** (the `tsc` build), so the cached artifact stays consistent with `dist`. Do **not** declare it for a `tsc --noEmit` typecheck: turbo restores outputs only on a hit (skipping the task), so a `--noEmit` buildinfo yields no benefit and makes turbo warn `"no output files found"` for every package that does not produce it (stubs, echo tasks). A task that produces no cacheable artifact gets `"outputs": []`. If `incremental` is on but nothing declares the buildinfo of the emitting task, either declare it or turn `incremental` off; leaving it undeclared is the worst of both.

### R4 - build and typecheck must not share a `tsBuildInfoFile`
If both `tsc` (build) and `tsc --noEmit` (typecheck) write the same `tsBuildInfoFile`, they clobber each other's incremental state, forcing needless rebuilds. Give typecheck its own file via the CLI flag:

```jsonc
"typecheck": "tsc --noEmit --tsBuildInfoFile .turbo/typecheck.tsbuildinfo"
```

This clobber fix lives at the *script* level and is independent of whether the file is a turbo output.

### R5 - Never glob `**/.turbo` (or any deep path) in a CI cache `path`
`actions/cache` expands its `path` globs with a full workspace tree walk. `**/.turbo` in a pnpm monorepo walks `node_modules` (100k+ files) on **save** to locate a handful of tiny dirs: minutes of hang for a payload that is often single-digit MB, tripping the job timeout and cancelling green runs. Cache the **root `.turbo`** (turbo's task cache lives in `.turbo/cache/`); that is all you need for cross-run task hits. Split restore/save so the save can be `continue-on-error` (a cache save must never fail a build), and never leave a save unbounded:

```yaml
- uses: actions/cache/restore@v4
  with: { path: .turbo, key: turbo-${{ runner.os }}-${{ github.sha }}, restore-keys: "turbo-${{ runner.os }}-" }
# ... build/test ...
- uses: actions/cache/save@v4
  if: always()
  continue-on-error: true
  with: { path: .turbo, key: turbo-${{ runner.os }}-${{ github.sha }} }
```

### R6 - Shared root deps go in `globalDependencies`
Files a task reads that live *outside* any package (root `data/`, `prisma/schema.prisma`, root config) are invisible to package-scoped `inputs`, so changing them does not bust the cache: a stale-cache correctness bug. List them in `globalDependencies` so any change invalidates every task.

### R7 - Verify empirically (the acid test)
Config changes are not "done" until proven. Two runs of a task in a row: the second must print `>>> FULL TURBO`. Then:
- Edit a **markdown** file and rerun: still `FULL TURBO` (docs must not bust the cache).
- Edit a **source** file and rerun: only that package and its dependents rebuild.

turbo hashes content, not mtime, so `touch` proves nothing; append real content and revert.

## Red flags

- A task in `turbo.json` with no `inputs` (hashes everything, incl. markdown).
- A task that writes an artifact but has `"outputs": []` (never caches).
- `outputs` listing a directory the task does not produce (dead config, `"no output files found"` warnings).
- `incremental: true` in tsconfig but the emitting task does not declare its tsbuildinfo in `outputs`.
- build and typecheck pointing at the same `tsBuildInfoFile`.
- `**/*`, `**/.turbo`, or any deep glob in a CI cache `path:`.
- A cache-save step with no `continue-on-error`, or an explicit `timeout-minutes` band-aid masking a real slowness (find the cause; usually R5).
- A `continue-on-error` cache save that "succeeds" in exactly `timeout-minutes` (it was timeout-killed and masked; check the step duration).
- Tests reading root `data/`/schema with nothing in `globalDependencies`.
- Declaring the config fixed without running the markdown-edit and src-edit acid test.

## Worked example: the 180s to 1s cache-save

A 59-project pnpm + turbo + TS monorepo cancelled green CI runs: the `actions/cache` save hung ~3-18 min and tripped the 25-min job timeout, always *after* `pnpm test` passed. First diagnosis (cache too big) was wrong; measurement showed the cache was **6.3 MB** (root `.turbo` 2.7 MB). Root cause was the `**/.turbo` path glob walking `node_modules` on save (R5). The audit also found: no `inputs` anywhere (markdown busted caches, R1); a dead `.next/**` output (R2); `incremental: true` with the tsbuildinfo undeclared (R3); build and typecheck sharing one `tsBuildInfoFile` (R4); root `data/`+`prisma` untracked (R6). Fixing all six and caching only root `.turbo` took the save from **180 s (timeout-killed, masked green) to 1 s**, and the acid test confirmed a markdown edit kept `FULL TURBO` while a src edit rebuilt only the touched package and its dependents.

## References

Cite these rather than duplicating them:
- Configuring turbo.json: https://turborepo.dev/docs/reference/configuration
- Caching: https://turborepo.dev/docs/crafting-your-repository/caching

## Bottom line

On contact with a turbo monorepo, audit before you trust: tight source-scoped `inputs`, complete `outputs` (outDir + tsbuildinfo where emitted), no deep glob in the CI cache path, shared root deps in `globalDependencies`, build and typecheck on separate buildinfo files. Then prove it with the markdown/src acid test and the CI save time. A cache that reads green can still be doing nothing.
