# Ansible diagnostics

## SSH connection failures

### Connection refused

```
fatal: [web1.example.com]: UNREACHABLE! => {
    "msg": "Failed to connect to the host via ssh: ssh: connect to host 10.0.1.10 port 22: Connection refused"
}
```

Diagnosis:
1. Is SSH running on the managed node? `ssh web1.example.com` from the control node.
2. Firewall blocking? `nc -zv 10.0.1.10 22`
3. Correct user? Check `ansible_user` in inventory or `remote_user` in `ansible.cfg`.
4. SSH key present? Check `ansible_ssh_private_key_file` or confirm SSH agent has the key.

Resolution:
- Debug the SSH session directly: `ssh -vvv user@10.0.1.10`
- For bastion / jump host access: `ansible_ssh_common_args: '-o ProxyJump=bastion.example.com'`
- Verify `ansible.cfg` for `remote_user` and `private_key_file` settings.

### Authentication failed

```
fatal: [web1]: UNREACHABLE! => {
    "msg": "Failed to connect to the host via ssh: Permission denied (publickey,gssapi-keyex,gssapi-with-mic)"
}
```

Resolution:
- Confirm the SSH key is loaded (`ssh-add -l`).
- Check `ansible_ssh_private_key_file` in group\_vars or host\_vars.
- Verify `authorized_keys` on the managed node.
- If using password auth (not recommended): `ansible_password` must be set (vault-encrypted).

### Timeout

```
fatal: [web1]: UNREACHABLE! => {"msg": "timed out"}
```

Increase the default connection timeout in `ansible.cfg`:

```ini
[defaults]
timeout = 30    # Default is 10 seconds
```

Or per task: `timeout:` parameter on `ansible.builtin.wait_for_connection`.

---

## WinRM connection failures

```
fatal: [win1.example.com]: UNREACHABLE! => {
    "msg": "winrm or psrp connection error"
}
```

Diagnosis:
1. WinRM enabled on the target? On the Windows host: `winrm quickconfig`
2. HTTPS listener configured? `winrm get winrm/config/Listener`
3. Correct credentials? `ansible_user`, `ansible_password`
4. Firewall open? Port 5986 (HTTPS) or 5985 (HTTP).

```yaml
# group_vars/windows.yml
ansible_connection: winrm
ansible_winrm_transport: ntlm      # or kerberos, credssp
ansible_winrm_server_cert_validation: ignore   # Only for lab; use proper certs
ansible_port: 5986
```

---

## Privilege escalation (become) failures

```
fatal: [web1]: FAILED! => {
    "msg": "Missing sudo password"
}
```

Resolution:
- Add `ansible_become_password: !vault |` (encrypted) to inventory.
- Configure passwordless sudo: add `<user> ALL=(ALL) NOPASSWD:ALL` to sudoers.
- For pipelining: ensure `!requiretty` or `Defaults !requiretty` in sudoers.
- Scope `become: true` to tasks that actually need it rather than setting it play-wide.

---

## Module errors

### Module not found

```
ERROR! couldn't resolve module/action 'community.general.ufw'.
```

Resolution:
1. Install the collection: `ansible-galaxy collection install community.general`
2. Verify `collections/requirements.yml` includes it.
3. Check the FQCN spelling: `ansible-doc -l | grep ufw`
4. In an Execution Environment: rebuild the EE to include the collection.

### Unknown module parameter (typo)

```
fatal: [web1]: FAILED! => {
    "msg": "Unsupported parameters for (ansible.builtin.apt) module: update_cashe.
            Supported parameters include: update_cache ..."
}
```

Resolution:
- Check the spelling (`update_cashe` vs `update_cache`).
- Check module documentation: `ansible-doc ansible.builtin.apt`
- Check ansible-core version -- some parameters were added in later versions.

### Module argument type error (2.19+)

From ansible-core 2.19, stricter argspec validation rejects incorrect parameter types.

```
fatal: [web1]: FAILED! => {
    "msg": "value of state must be one of: present, absent, latest, build-dep, fixed, got: install"
}
```

Resolution:
- Read the module documentation to confirm the valid values.
- Run `--check` mode first when migrating from an older ansible-core version to surface type errors without making changes.

---

## Variable resolution issues

### Undefined variable

```
fatal: [web1]: FAILED! => {
    "msg": "AnsibleUndefinedVariable: 'app_port' is undefined"
}
```

Diagnosis:
1. Is the variable defined in any of the expected locations (defaults, vars, group\_vars, host\_vars, extra vars)?
2. Scope issue? Variables set with `set_fact` or `register` are host-scoped and not available to other hosts.
3. Typo? Variable names are case-sensitive.

Resolution:
- Use the `default` filter: `{{ app_port | default(8080) }}`
- Debug a variable across all variable sources:

```bash
ansible -i inventory/production -m debug -a "var=app_port" webservers
ansible -i inventory/production -m debug -a "var=hostvars[inventory_hostname]" web1
```

- Verbose mode shows variable sources: `ansible-playbook site.yml -vvv`

### Variable has unexpected value (precedence surprise)

```yaml
# Debug task to inspect resolution
- name: Debug variable sources
  ansible.builtin.debug:
    msg: |
      nginx_port resolved to: {{ nginx_port }}
```

Common traps:
- `vars/main.yml` in a role overrides `group_vars`. Use `defaults/main.yml` for user-overridable values.
- `include_vars` is loaded at task execution time, not play parse time.
- `set_fact` persists for the rest of the play for that host but does not carry to other hosts.
- Extra vars (`-e`) always win; they override everything including role vars.

---

## Jinja2 templating errors

### Syntax errors in templates

```
fatal: [web1]: FAILED! => {
    "msg": "AnsibleError: template error while templating string: ..."
}
```

Resolution:
- Test a template fragment in isolation: `ansible -m debug -a "msg={{ 'hello' | upper }}" localhost`
- Use `--syntax-check` to catch YAML syntax errors before running the play.
- ansible-core 2.19+: `{{ 42 }}` produces an integer, not a string. If you need a string, use `{{ 42 | string }}`.

---

## Idempotency drift (perpetually-changed tasks)

A task reports `changed` on every run when it should report `ok` on subsequent runs.

Causes:
- **Missing `changed_when`** on a `command` / `shell` task: the module always reports changed.
- **Non-deterministic template**: the template renders differently each time (e.g. a timestamp or random value in the template).
- **Module that does not support check mode**: re-writes the file even when content is identical.
- **Ordering-sensitive config**: list ordering in the template differs from the live file.

Diagnosis:
1. Run the playbook twice in succession with `-vvv`. Compare the second run's output.
2. For template tasks: check the rendered output manually with `ansible-playbook --check --diff`.
3. Add `changed_when: false` to purely read-only tasks.
4. For `command` / `shell` that modifies state: implement a guard with `creates:` / `removes:` or check current state first.

---

## Fact-gathering issues

### Gather facts timeout or failure

```
FAILED - RETRYING: [web1]: Gathering Facts (1 retries left)
```

Resolution:
- Verify SSH connectivity works: `ansible web1 -m ping`
- Disable fact gathering for plays that do not need facts: `gather_facts: false`
- Gather only required subsets: `gather_subset: ['network']`

### Stale cached facts

If fact caching is enabled and a host's configuration has changed, the cached facts may be stale.

```bash
# Clear the fact cache for all hosts
rm -rf /tmp/ansible_facts/*

# Or disable smart gathering temporarily
ANSIBLE_GATHERING=explicit ansible-playbook site.yml
```

---

## Vault decrypt errors

```
ERROR! Decryption failed (no vault secrets would decrypt the data)
```

Resolution:
- Verify you are passing the correct vault password: `--ask-vault-pass` or `--vault-password-file`.
- For multi-vault ID configurations: ensure the vault ID in the encrypted block matches a supplied `--vault-id`.
- Check vault ID syntax: `$ANSIBLE_VAULT;1.2;AES256;prod` (the label after `AES256;` is the vault ID).

```bash
# Test vault decryption directly
ansible-vault view group_vars/production/vault.yml --vault-password-file ~/.vault_pass
```

---

## Performance debugging

### Identify slow tasks

```bash
ANSIBLE_CALLBACKS_ENABLED=timer,profile_tasks ansible-playbook site.yml
```

Common causes of slow playbooks:
1. **Too few forks**: default is 5; increase to 50 in `ansible.cfg`.
2. **Fact gathering on every run**: use `gathering = smart` and fact caching.
3. **No SSH pipelining**: enable in `ansible.cfg`; requires `!requiretty` in sudoers.
4. **No SSH multiplexing**: set `ControlMaster=auto ControlPersist=60s` in `ssh_args`.
5. **`serial: 1`** when not needed for production safety.
6. **Large file transfers**: use `ansible.builtin.synchronize` (rsync) instead of `copy` for large directories.

---

## Check mode and step mode

```bash
# Dry run: shows what would change without making changes
ansible-playbook site.yml --check --diff

# Limit to specific hosts
ansible-playbook site.yml --check --diff --limit web1.example.com

# Step through tasks interactively (confirm each task)
ansible-playbook site.yml --step

# Start from a specific task (for recovery)
ansible-playbook site.yml --start-at-task "Deploy application"
```

---

## Debugging commands

```bash
# Test connectivity (ping module)
ansible all -m ping -i inventory/production

# Gather and display facts
ansible web1 -m setup -i inventory/production
ansible web1 -m setup -a "filter=ansible_distribution*" -i inventory/production

# Run an ad-hoc command
ansible webservers -m command -a "uptime" -i inventory/production

# List hosts in a group
ansible webservers -i inventory/production --list-hosts

# Syntax check
ansible-playbook site.yml --syntax-check

# List all tasks without executing
ansible-playbook site.yml --list-tasks

# List all tags
ansible-playbook site.yml --list-tags

# Verbose output (up to -vvvv)
ansible-playbook site.yml -vvv

# Enable debug-level logging
ANSIBLE_DEBUG=True ansible-playbook site.yml
```

---

## Callback plugins for debugging

```ini
# ansible.cfg
[defaults]
callbacks_enabled = timer, profile_tasks, json
```

| Callback | Purpose |
|---|---|
| `timer` | Prints total playbook elapsed time |
| `profile_tasks` | Shows per-task execution time, sorted by slowest |
| `profile_roles` | Shows per-role execution time |
| `json` | Outputs machine-readable JSON (useful for CI log parsing) |
| `junit` | Generates JUnit XML test reports (CI integration) |
| `debug` | Enables interactive step-through debugging strategy |

---

## ansible-lint diagnostics

```bash
# Run linter; exit code 2 means violations found
ansible-lint playbooks/ roles/

# Show all violations with full context
ansible-lint -v playbooks/site.yml

# Show only specific rule violations
ansible-lint --warn-list no-changed-when roles/

# List available rules
ansible-lint --list-rules
```

Key rules that indicate real problems:
- `no-changed-when`: `command` / `shell` tasks without `changed_when`.
- `fqcn`: not using Fully Qualified Collection Names (errors in ansible-core 2.20).
- `yaml[truthy]`: `yes` / `no` instead of `true` / `false`.
- `name[missing]`: tasks without a `name:` field.
- `no-free-form`: module arguments in free-form string instead of YAML dict.

---

## Automation Controller job diagnostics

### Job stuck in Pending

1. Check `awx-manage list_instances` for node health and capacity.
2. Confirm receptor service is running on execution nodes: `systemctl status receptor`.
3. Verify no capacity limits are set on the instance group (Max Concurrent Jobs, Max Forks).
4. Check if a previous job is monopolising capacity with a high fork count.

### Retrieve job logs

Via the REST API:
```bash
# Get job details
curl -k -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/jobs/4832/

# Get stdout in plain text
curl -k -H "Authorization: Bearer $TOKEN" \
  "https://controller.example.com/api/v2/jobs/4832/stdout/?format=txt"
```

Via the AAP MCP server (if configured): `job_status` to confirm the job state, then `job_logs` to retrieve execution output.

### EE pull failures

```
denied: requested access to the resource is denied, unauthorized
```

Resolution: Attach a Container Registry credential (for your Private Automation Hub or registry) to the Execution Environment definition in the Controller UI (Execution Environments > edit > Credential).

### Project sync failure

```
ERROR! the playbook: site.yml could not be found
```

Resolution:
1. Verify the project sync succeeded: check the project's status in the Controller UI or via `/api/v2/projects/{id}/`.
2. Confirm the playbook filename exactly matches the job template's Playbook field (case-sensitive).
3. Check the SCM credential has permission to access the repository.

### Licence errors

```bash
# Check licence status
curl -k -H "Authorization: Bearer $TOKEN" \
  https://controller.example.com/api/v2/config/ | python3 -m json.tool | grep -A 10 licence_info
```

Common licence errors:
- `License has expired`: renew the subscription at `access.redhat.com`.
- `License count exceeded`: too many managed hosts; purchase additional capacity or reduce host count.
- `Subscription not found`: manifest not uploaded or corrupted; re-download from the portal.
