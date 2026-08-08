# Ansible best practices

## Repository structure

A well-organised Ansible repository separates inventory, roles, playbooks, and collections.

```
ansible/
  ansible.cfg                    # Project-level configuration
  inventory/
    production/
      hosts.yml                  # Static inventory
      group_vars/
        all.yml                  # Variables for all hosts
        webservers.yml           # Group-specific variables
        vault.yml                # Encrypted secrets (ansible-vault)
      host_vars/
        db1.example.com.yml      # Host-specific overrides
    staging/
      hosts.yml
      group_vars/
  roles/
    common/                      # Base configuration applied to all hosts
    webserver/                   # Application roles
    database/
  playbooks/
    site.yml                     # Master playbook (composes roles)
    webservers.yml               # Subset playbook
    database.yml
  collections/
    requirements.yml             # Pinned collection versions
  molecule/                      # Role testing (at root level or per-role)
  .ansible-lint                  # Lint configuration
```

`ansible.cfg` at the repository root overrides global settings. Commit it to version control so every team member and CI runner uses the same configuration.

---

## Role design

### Naming conventions

- **Roles**: lowercase, with underscores if multi-word (`nginx_proxy`, `postgresql_server`). Match the project's existing convention before introducing a new style.
- **Variables**: `snake_case`, prefixed with the role name (`nginx_listen_port`, `postgres_max_connections`). Prefixing prevents collisions when multiple roles are composed.
- **Tasks**: start with a verb, be descriptive (`Install nginx package`, `Create application user`, `Deploy nginx configuration`).
- **Playbooks**: `noun.yml` or `verb-noun.yml` (`webservers.yml`, `deploy-app.yml`).

### Defaults vs vars

Use `defaults/main.yml` for values that callers should be able to override:

```yaml
# roles/webserver/defaults/main.yml
webserver_listen_port: 80
webserver_worker_processes: "auto"
webserver_document_root: /var/www/html
```

Use `vars/main.yml` only for values the role controls internally and callers should not override. Remember: `vars/main.yml` has higher precedence than `group_vars`, so overriding group\_vars with role vars is a common surprise.

### Role dependencies

Declare dependencies in `meta/main.yml`. Ansible installs them when installing the role from Galaxy, and applies them before the dependent role runs:

```yaml
# meta/main.yml
galaxy_info:
  author: myorg
  description: Web server role
  license: MIT
  min_ansible_version: "2.18"
  platforms:
    - name: Ubuntu
      versions: ["22.04", "24.04"]
    - name: EL
      versions: ["9"]

dependencies:
  - role: common
```

---

## Idempotency discipline

### Prefer modules over commands

```yaml
# GOOD: idempotent module
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present

# BAD: not idempotent; runs on every execution
- name: Install nginx
  ansible.builtin.shell: apt-get install -y nginx
```

### Guard command / shell tasks

```yaml
# creates: makes the task idempotent
- name: Initialise database schema
  ansible.builtin.command: /opt/app/init-schema.sh
  args:
    creates: /opt/app/.schema-initialised

# changed_when: false for read-only checks
- name: Read application version
  ansible.builtin.command: /opt/app/version
  register: app_version
  changed_when: false

# failed_when for custom failure conditions
- name: Assert health endpoint responds
  ansible.builtin.uri:
    url: "http://localhost:8080/health"
  register: health_response
  failed_when: health_response.status != 200
  changed_when: false
```

### Template idempotency

Templates are idempotent: the `template` module checks whether the rendered content differs from the existing file before writing. Pair `validate:` with templates for config files that have a validator:

```yaml
- name: Deploy nginx configuration
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    validate: nginx -t -c %s    # Validates before writing
  notify: Restart nginx
```

### check_mode support

Tasks that use `command` or `shell` do not automatically support check mode. Add `check_mode: false` only for tasks that must run in check mode (e.g. reading state), and add a comment explaining why. For tasks that make changes, use `when: not ansible_check_mode` to skip them in check mode.

---

## Variable hygiene

- Keep secrets separate from non-secret variables: create a `vault.yml` alongside `vars.yml` in `group_vars/<env>/`.
- Reference encrypted values with a naming prefix so it is obvious which variables are vaulted:

```yaml
# group_vars/production/vars.yml (committed unencrypted)
db_username: app_user
db_password: "{{ vault_db_password }}"
app_api_key: "{{ vault_app_api_key }}"

# group_vars/production/vault.yml (committed encrypted)
vault_db_password: !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  ...encrypted data...
vault_app_api_key: !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  ...encrypted data...
```

- Never put secrets in plain text in inventory files, task arguments, or playbook `vars:` blocks.
- Use `no_log: true` on tasks that log sensitive values:

```yaml
- name: Set database password
  ansible.builtin.mysql_user:
    name: "{{ db_username }}"
    password: "{{ db_password }}"
  no_log: true
```

---

## ansible-vault discipline

```bash
# Encrypt a single variable value (preferred over file-level encryption)
ansible-vault encrypt_string 'SuperSecret123' --name 'vault_db_password'

# Encrypt an entire file
ansible-vault encrypt group_vars/production/vault.yml

# Edit an encrypted file
ansible-vault edit group_vars/production/vault.yml

# Run playbook with vault password from a file (preferred for CI)
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Multiple vault IDs (different passwords for dev/prod secrets)
ansible-playbook site.yml \
  --vault-id dev@~/.vault_pass_dev \
  --vault-id prod@~/.vault_pass_prod
```

Rules:
- Never commit vault password files. Add them to `.gitignore`.
- In CI, inject the vault password via the secret store (HashiCorp Vault, AWS Secrets Manager, CI native secrets); read it in a wrapper script. See `secrets-hygiene` for the injection patterns.
- Do not `git rm` a decrypted vault file and assume it is gone; it remains in history. Rotate the secrets instead.
- Prefer `encrypt_string` for individual values over whole-file encryption; it preserves readability of the surrounding file.

---

## Tags

Tags allow selective task execution. Apply them consistently:

```yaml
- name: Install packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop: "{{ required_packages }}"
  tags:
    - packages
    - install

- name: Deploy configuration
  ansible.builtin.template:
    src: app.conf.j2
    dest: /etc/app/app.conf
  tags:
    - config
    - deploy
```

```bash
# Run only tasks tagged 'deploy'
ansible-playbook site.yml --tags deploy

# Skip tasks tagged 'packages'
ansible-playbook site.yml --skip-tags packages
```

Avoid over-tagging. Aim for tags that correspond to meaningful change categories (packages, config, service, deploy, security), not individual tasks.

---

## Rollout strategy

```bash
# Limit to specific hosts or groups
ansible-playbook site.yml --limit webservers
ansible-playbook site.yml --limit "web1.example.com,web2.example.com"

# Start from a specific task (for recovery)
ansible-playbook site.yml --start-at-task "Deploy application"
```

```yaml
# Serial execution in the play (rolling update)
- name: Rolling update of web servers
  hosts: webservers
  serial: 1               # One host at a time
  max_fail_percentage: 0  # Abort on first failure

# Or as a percentage
  serial: "10%"           # 10% of hosts per batch

# Or as a list (ramp up)
  serial: [1, 5, 20]      # 1 host, then 5, then 20
```

---

## Testing

### ansible-lint

ansible-lint validates playbooks and roles against a set of rules.

```bash
# Lint playbooks and roles
ansible-lint playbooks/ roles/

# Use a specific profile
ansible-lint --profile production

# List available rules
ansible-lint --list-rules
```

Key rule categories:
- `fqcn`: all module calls must use FQCN (mandatory in 2.20).
- `no-changed-when`: `command` / `shell` tasks must have `changed_when`.
- `yaml[truthy]`: use `true` / `false`, not `yes` / `no`.
- `name[missing]`: every task must have a `name:`.
- `no-free-form`: avoid free-form module arguments; use the YAML dict form.

Configure via `.ansible-lint`:

```yaml
# .ansible-lint
profile: production
exclude_paths:
  - .git/
  - molecule/
warn_list:
  - experimental
```

### Molecule

Molecule provides a testing framework for Ansible roles.

```yaml
# molecule/default/molecule.yml
dependency:
  name: galaxy
driver:
  name: docker
platforms:
  - name: ubuntu-24
    image: ubuntu:24.04
    pre_build_image: true
  - name: el9
    image: rockylinux:9
    pre_build_image: true
provisioner:
  name: ansible
verifier:
  name: ansible   # or testinfra
```

```bash
# Full test lifecycle
molecule test

# Or step by step
molecule create        # Spin up test instances
molecule converge      # Apply the role
molecule idempotence   # Re-apply; assert no changes (changed: 0)
molecule verify        # Run verification tests
molecule destroy       # Tear down instances
```

The idempotence step catches tasks that are not idempotent: if any task reports `changed` on the second run, the step fails.

### Syntax check

```bash
ansible-playbook site.yml --syntax-check
```

Run this in CI on every PR as a pre-check gate before running molecule or deploying.

---

## Collection version pinning

Always pin collection versions in `collections/requirements.yml`. Floating versions cause CI to break silently when a collection releases a breaking change.

```yaml
# collections/requirements.yml
collections:
  - name: amazon.aws
    version: "7.6.0"
  - name: community.general
    version: "9.1.0"
  - name: ansible.windows
    version: "2.5.0"
  - name: community.vmware
    version: "4.8.0"
```

```bash
# Install pinned collections
ansible-galaxy collection install -r collections/requirements.yml

# Update all collections to latest (then review changelog and re-pin)
ansible-galaxy collection install -r collections/requirements.yml --upgrade
```

Commit `collections/requirements.yml` to version control. Do not commit the installed collection files themselves (they live in `~/.ansible/collections/` or `./collections/ansible_collections/`).

---

## Performance

### SSH overhead

```ini
# ansible.cfg
[ssh_connection]
pipelining = True           # Reduces SSH round-trips (requires !requiretty in sudoers)
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o PreferredAuthentications=publickey
```

Pipelining sends the module code directly over the existing SSH connection rather than using a second SCP/SFTP connection. It typically halves the time per task.

### Fact caching

```ini
# ansible.cfg
[defaults]
gathering = smart             # Only gather if facts are not cached or expired
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600   # Seconds; 1 hour
```

Use `redis` or `memcached` for large fleets where JSON files become slow.

### Forks

```ini
# ansible.cfg
[defaults]
forks = 50    # Default is 5; increase for larger fleets
```

Each fork is a parallel host execution. Balance against control node resources.

### Free strategy

```yaml
# In a play where host ordering does not matter
- hosts: webservers
  strategy: free   # Each host runs all tasks independently; no synchronisation between hosts
  tasks:
    ...
```

The default `linear` strategy synchronises all hosts at each task boundary. `free` lets faster hosts race ahead.

### Mitogen (third-party)

Mitogen (`mitogen_linear` strategy plugin) dramatically reduces playbook execution time for large fleets by replacing Ansible's SSH invocation model with a persistent Python interpreter on each host. It is not part of ansible-core; install and enable separately. Review compatibility with your ansible-core version before adopting.

### Async tasks

For long-running tasks, use async to avoid blocking the SSH connection:

```yaml
- name: Run long database backup
  ansible.builtin.command: /opt/backup/full-backup.sh
  async: 3600     # Maximum runtime (seconds)
  poll: 0         # Fire and forget (0 = no polling)
  register: backup_job

# Later: check status
- name: Wait for backup to complete
  ansible.builtin.async_status:
    jid: "{{ backup_job.ansible_job_id }}"
  register: backup_result
  until: backup_result.finished
  retries: 60
  delay: 60
```

---

## CI integration

A typical CI pipeline for an Ansible repository:

1. `ansible-lint` on changed playbooks and roles.
2. `--syntax-check` on the master playbook.
3. `molecule test` for each changed role (matrix: Ubuntu, RHEL/Rocky).
4. On merge to main: apply to staging with `--check --diff`; promote to production after approval.

```yaml
# .github/workflows/ansible-lint.yml (GitHub Actions pattern)
on: [pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install ansible-core ansible-lint
      - run: ansible-lint
```

For production applies, use Automation Controller / AWX job templates rather than running `ansible-playbook` directly from CI. CI triggers the Controller job via the REST API; Controller handles credentials, audit trails, and notifications. See `references/aap-platform.md`.

---

## Common mistakes

1. **Not using FQCN**: `apt:` is ambiguous; always use `ansible.builtin.apt:`. Required as of 2.20.
2. **`shell:` when `command:` suffices**: `shell:` spawns a full shell (risk of injection). Use `command:` unless you need pipes or redirects; use a module if one exists.
3. **Ignoring variable precedence**: role `vars/main.yml` overrides `group_vars`. Use `defaults/main.yml` for values callers need to tune.
4. **Not validating templates**: use `validate:` on template tasks for files with validators (nginx, sshd, sudoers, etc.).
5. **Giant monolithic playbooks**: break into roles. A playbook should compose roles; raw tasks belong in roles.
6. **Missing `changed_when` on `command` / `shell`**: every run reports `changed`, triggering handlers unnecessarily and making idempotence checks fail.
7. **Floating collection versions**: pin in `requirements.yml` and upgrade deliberately with changelog review.
8. **`serial: 0` (default) on production changes**: runs all hosts in parallel. Set `serial: 1` or a small percentage for rolling changes.
9. **Secrets in plain text**: any secret in inventory or a task argument that is not a `!vault` block is a finding.
10. **Skipping `--check --diff` before production**: the diff is both the safety check and the review artefact.
