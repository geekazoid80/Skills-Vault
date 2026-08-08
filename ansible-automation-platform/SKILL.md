---
name: ansible-automation-platform
description: "Use for general Ansible automation AND Red Hat Ansible Automation Platform (AAP) OPERATIONS: authoring and running playbooks, designing roles, managing inventory, working with collections and Ansible Galaxy, variable precedence, Jinja2 templating, ansible-vault secret handling, Execution Environments, Automation Controller / AWX job templates and workflow templates, Event-Driven Ansible rulebooks, ansible-lint, Molecule testing, and ansible-core version changes. References: architecture.md, best-practices.md, aap-platform.md, diagnostics.md. Triggers include \"ansible\", \"ansible playbook\", \"ansible role\", \"ansible inventory\", \"ansible collection\", \"ansible-galaxy\", \"jinja2 template\", \"ansible vault\", \"ansible-vault\", \"variable precedence\", \"handlers\", \"ansible facts\", \"idempotency\", \"AWX\", \"Automation Controller\", \"Ansible Automation Platform\", \"AAP\", \"execution environment\", \"job template\", \"workflow template\", \"ansible-navigator\", \"ansible-runner\", \"event-driven ansible\", \"EDA\", \"rulebook\", \"ansible-lint\", \"molecule\", \"ansible-core\", \"ansible windows\", \"win_ modules\", \"ad-hoc command\", \"ansible roles structure\", \"galaxy collection install\", \"requirements.yml\", \"ansible.cfg\", \"gather_facts\", \"become\", \"no_log\", \"changed_when\", \"failed_when\", \"check mode\", \"ansible --check\", \"ansible-builder\", \"decision environment\", \"ansible collections\", \"ansible forks\", \"pipelining\", \"fact caching\", \"ansible async\", \"ansible serial\", \"block rescue\". For Ansible NETWORK device automation (cisco.ios, junipernetworks.junos, arista.eos, resource modules, network_cli / netconf connection plugins) use ansible-network-modules; for Terraform IaC see terraform-iac-ops; for secret handling discipline see secrets-hygiene."
license: MIT
metadata:
  version: 1.0.0
---

# Ansible automation platform

> **Skill marker**: When applying this skill, begin your reply with `[skill: ansible-automation-platform]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

Ansible is an agentless, push-based automation engine: the control node pushes module code to managed nodes over SSH (Linux) or WinRM (Windows), executes it, and receives a JSON result. No daemon runs on managed nodes. This skill owns the full general Ansible loop from authoring to execution, and the Red Hat Ansible Automation Platform (AAP) / AWX management layer on top.

## When to use

- Writing or reviewing playbooks, roles, tasks, handlers, and templates.
- Designing or troubleshooting inventory (static, dynamic, group\_vars, host\_vars).
- Working with collections: installing, pinning versions, FQCN usage, publishing to Automation Hub.
- Managing secrets with ansible-vault (file encryption, variable encryption, multi-vault IDs).
- Operating Automation Controller / AWX: job templates, workflow templates, credentials, schedules, RBAC.
- Building or troubleshooting Execution Environments with ansible-builder and ansible-navigator.
- Configuring Event-Driven Ansible: rulebooks, event sources, decision environments, activations.
- Validating playbooks and roles with ansible-lint or Molecule.
- Investigating ansible-core version compatibility (2.18, 2.19, 2.20) and migration requirements.

## When not to use

- **Network device automation** (Cisco IOS / NX-OS, Juniper JunOS, Arista EOS, network\_cli / httpapi / netconf connection plugins, resource modules): use `ansible-network-modules`. That skill owns the network-device specialisation; this skill does not duplicate it.
- **Terraform / OpenTofu IaC**: see `terraform-iac-ops`.
- **Secret handling discipline** (vault password storage, CI secret injection, token rotation): see `secrets-hygiene`. This skill uses ansible-vault; hygiene discipline lives there.

## Core model

The execution model is: control node parses YAML (playbooks, roles, inventory, vars); resolves variables according to the 22-level precedence ladder; evaluates conditionals; generates a Python module bundle; transfers it to the managed node via the connection plugin; runs it; and parses the JSON result. Connection plugins decide the transport: `ssh` (default for Linux), `winrm` / `psrp` (Windows), `local` (control node), `docker` (containers). Network-device plugins (`network_cli`, `httpapi`, `netconf`) are the domain of `ansible-network-modules`.

Idempotency is the design contract: a well-written task produces the same outcome whether it runs once or ten times. The module is responsible for detecting current state and returning `changed: false` when no action is required. Tasks using `command` or `shell` break this contract unless guarded with `creates:`, `changed_when: false`, or `failed_when`.

Variable precedence runs from lowest to highest: role defaults, inventory group\_vars (all, group, host), playbook group\_vars (all, group, host), host facts, play vars / vars\_files, role vars, block vars, task vars, set\_fact / register, extra vars (`-e`). Extra vars always win. See `references/architecture.md` for the full 22-level ladder.

## Reference router

Load the reference that matches the request. Each is a standalone deep-dive.

| Topic | Covers | Reference |
|---|---|---|
| Architecture | Control/managed node model, inventory types, connection plugins, playbook/play/task structure, collections (FQCN, Galaxy, requirements.yml), role layout, variable precedence (22-level), Jinja2 templating, handlers, facts, idempotency, ansible-core 2.18/2.19/2.20 version deltas | `references/architecture.md` |
| Best practices | Repo and role structure, naming conventions, idempotency discipline (changed\_when / failed\_when / check\_mode), variable hygiene, ansible-vault discipline, tags, rollout strategy (--limit, serial), testing (Molecule, ansible-lint, --syntax-check), collection version pinning, performance (fact caching, pipelining, free strategy), CI integration | `references/best-practices.md` |
| AAP platform | Red Hat Ansible Automation Platform / AWX: Automation Controller (organisations, inventories, credentials, projects, job templates, workflow templates, RBAC, schedules, surveys, API), Execution Environments (ansible-builder, ansible-navigator, ansible-runner), Private Automation Hub, Event-Driven Ansible (rulebooks, sources, conditions, actions, decision environments), ansible-lint in CI, REST API, awx CLI | `references/aap-platform.md` |
| Diagnostics | Failed tasks, unreachable hosts, SSH / WinRM connection and auth errors, variable precedence surprises, Jinja2 templating errors, idempotency drift (perpetually-changed tasks), fact-gathering issues, privilege escalation (become) failures, vault decrypt errors, verbosity (-vvv) and ANSIBLE\_DEBUG, callback plugins, Controller job-status and log retrieval | `references/diagnostics.md` |

## The check-mode-first loop in one screen

Safe change discipline for every environment:

```bash
# 1. Syntax check
ansible-playbook site.yml --syntax-check

# 2. Dry run with diff: shows what would change; no changes made
ansible-playbook site.yml -i inventory/production --check --diff

# 3. Limit to a small set first
ansible-playbook site.yml -i inventory/production --check --diff --limit web1.example.com

# 4. Staged rollout: apply one host at a time
ansible-playbook site.yml -i inventory/production --diff --limit webservers
# (play-level serial: 1 or serial: "10%" in the playbook controls staged rollout)

# 5. Full apply after review
ansible-playbook site.yml -i inventory/production --diff
```

Key constraints:
- Run `--check --diff` before any production apply. The diff is the review artefact.
- Use `--limit` to scope the apply to a subset before fleet-wide rollout.
- Set `serial:` in the play (not globally) for rolling updates: `serial: 1` for one host at a time; `serial: "10%"` for a batch percentage.
- Wrap multi-task changes in `block: / rescue:` for transactional rollback.
- Prefer modules over `command` / `shell`; idempotency is the module's responsibility.
- Never commit decrypted vault YAML; use `ansible-vault encrypt_string` for individual values.

## Cross-references

- `ansible-network-modules`: the network-device sub-specialist (Cisco IOS / NX-OS, JunOS, Arista EOS, PAN-OS; network\_cli / httpapi / netconf connection plugins; resource modules). Use that skill for anything network-device-facing; this skill does not duplicate it.
- `terraform-iac-ops`: Terraform handles infrastructure provisioning; Ansible handles OS-level configuration management. The two complement each other.
- `secrets-hygiene`: ansible-vault discipline (vault password storage, CI injection, secret stores, never-commit rules) and integration with external secret stores (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault). This skill invokes vault commands; hygiene lives there.
- `linux-host-ops`: OS-level tasks that Ansible typically automates (package management, service control, user management, file permissions).
- `systematic-debugging`: when a failed task or unreachable host is the symptom of a deeper infrastructure problem, diagnose root cause before re-running.

## Red flags

- Running a playbook against production without `--check --diff` first.
- Committing a decrypted vault file (any `!vault` block expanded to plaintext in the diff).
- Using `shell:` or `command:` where a module exists; breaks idempotency and introduces injection risk.
- Not pinning collection versions in `requirements.yml`; CI drifts on the next galaxy sync.
- Ignoring `changed_when` on `command` / `shell` tasks; every run reports changed and triggers downstream handlers.
- Using non-FQCN module references (e.g. `apt:` instead of `ansible.builtin.apt:`); deprecated in 2.18, errors in 2.20.
- Setting role vars in `vars/main.yml` for values the user should be able to override; those belong in `defaults/main.yml`.
- Running `serial: 0` (all hosts in parallel) on production infrastructure changes without explicit review.
- Storing vault passwords in the repository or as plaintext CI environment variables.

## Bottom line

Ansible is the YAML-first, agentless configuration management and orchestration tool. Load the reference that matches the request: `architecture.md` for execution model and variable precedence; `best-practices.md` for repo structure, idempotency discipline, and testing; `aap-platform.md` for Automation Controller, Execution Environments, and Event-Driven Ansible; `diagnostics.md` for connection errors, module failures, and vault issues. For Ansible network-device automation, delegate to `ansible-network-modules`.
