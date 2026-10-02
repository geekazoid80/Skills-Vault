# Build tool root walk escaping a worktree: the detail

Companion to the "A build that fails only inside the worktree" section of `SKILL.md`. Read it when the quick checks there (outer checkout missing `node_modules`, scratch-clone discriminator) are not the whole story, or when you want the fix that avoids keeping a second install.

**Version stamp.** Learnt 2026-09-19 against Vite 8.0.x to 8.3.0 (rolldown tsconfig resolution), Astro 7.3.2, `astro-pagefind` up to 2.0.1, Yarn 4 (Berry) and Node's native ESM type stripping. Re-check the specifics against your versions; the mechanism is the durable part.

## The mechanism

A worktree's `.git` is a file, so a root-detection walk that only stops at a `.git` directory can pass straight through it into the outer checkout. When a dependency ships a nested `tsconfig.json`, Vite's tsconfig resolution walks up, lands on the outer checkout's `tsconfig.json` (often byte-identical to the worktree's own), and fails to resolve an `extends` such as `astro/tsconfigs/strict` because the outer checkout has no `node_modules/astro`.

Upstream treated the walk-and-load-everything behaviour as by-design (vitejs/vite#23459, closed). The same maintainer comment points at the escape hatch below.

## Fix A: pin the tsconfig so nothing is auto-discovered

Vite 8.3.0 added a top-level `tsconfig` option (vitejs/vite#23310) that skips auto-discovery in favour of a pinned path.

1. Make sure `vite` resolves to 8.3.0 or later. When it is not a direct dependency, use the package manager's override (`resolutions` in Yarn).
2. Set the option in the framework's Vite block, for example `vite: { tsconfig: "./tsconfig.json" }` in `astro.config.mjs`.

Confirmed 8.3.0 alone, without the option, still fails identically; the option does the work and the version bump makes it available.

**Test each half per repo before writing "both are required".** In one sibling repo the framework's and the Tailwind plugin's `vite` ranges (`vite@npm:^8.0.13`) already floated to 8.3.0 on a clean install with no override, and the option alone fixed the build. The framework's own `vite` peer range also allows 8.3.0, so the bump needs no peer-range change. The override was then added defensively, so a later range change could not silently regress below 8.3.0, but it was not load-bearing there. Do not carry a blanket claim from the repo where the fix was first found.

## Fix B: when the config file itself imports a package that ships raw TypeScript

Fix A is necessary but **not sufficient** when `astro.config.mjs` (or the equivalent) imports, at top level, a package (for example one that is called as `pagefind()` inside `integrations: []`) whose `main` or `exports` points at an uncompiled `.ts` file with no compiled JavaScript published.

Why it escapes Fix A:

- Node's native ESM loader refuses to type-strip `.ts` files under `node_modules` (`ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING`). No CLI flag lifts that restriction for `node_modules` specifically; `--experimental-strip-types` only toggles stripping in general (checked with `node --help` and `process.allowedNodeEnvironmentFlags`).
- Astro's config loader (`astro/dist/core/config/vite-load.js`, function `loadConfigWithVite`) tries a native `import()` first for speed, swallows any failure (`debug("Failed to load config with Node", e)`, invisible without debug logging), and falls back to an internal minimal Vite dev server (`createMinimalViteDevServer.js`, which calls Vite's `createServer()`).
- That fallback server does the escaping tsconfig walk **before** the user's config has been parsed, so the `vite.tsconfig` option from Fix A cannot reach it.

A repo whose config has no such top-level import always loads through the native fast path and never meets this fallback, which is why the same Fix A can work in one repo and not in its sibling.

**The fix: patch the framework's fallback server to pin the tsconfig too.** With Yarn's patch protocol:

1. `yarn patch astro`, edit `createMinimalViteDevServer.js`, then `yarn patch-commit -s <dir>`. That produces `.yarn/patches/astro-npm-<version>-<hash>.patch`, referenced from `package.json` as `patch:astro@npm%3A<version>#~/.yarn/patches/...`.
2. In the `createServer({...})` call add `...(fs.existsSync(rootTsconfig) ? { tsconfig: rootTsconfig } : {})`, where `rootTsconfig = path.join(root, "tsconfig.json")`.
3. Keep the `vite >= 8.3.0` resolution from Fix A; the patch passes the `tsconfig` option that version introduced.

Confirmed by direct experiment that both halves are independently required in this case: removing only the `astro.config.mjs` option (keeping the patch) fails at the main-build stage; removing only the patch (keeping the option) fails at the config-load stage.

**Telling which failure point you are at.** The framework's wrapper error message is identical for both. Run the config in isolation to see the real underlying error: `node -e "import('./astro.config.mjs?t='+Date.now())"`. Then check every package imported at the top of the config for a `.ts`-only `main` or `exports`.

## Yarn Berry trap: the patch file may not be committed

A blanket `.yarn/` entry in `.gitignore` (common, with a comment such as "no Zero-Installs or PnP") also swallows `.yarn/patches/`. The patch then exists only on the machine that made it, and the build breaks for everyone else. Use `.yarn/*` plus `!.yarn/patches`, and run `git check-ignore -v <patch path>` after `patch-commit`; a path that is still ignored prints a match.

## Verify the fix without the masking effect

Build with the outer checkout's `node_modules` **absent**, and again in a genuinely fresh `git clone` of the fixed branch (not a worktree; `file .git` should show a directory). A build that only passes while the outer checkout is installed has not exercised the fix.

## When to leave it at the cheap fallback

Installing dependencies in the outer checkout works for either failure point and costs nothing. When the build-tooling detour is not the point of the session, reach for that rather than a from-scratch investigation, and note the cause so the next person does not re-diagnose it.
