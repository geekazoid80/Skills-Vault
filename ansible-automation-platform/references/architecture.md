# Ansible architecture

## Control node / managed node model

Ansible runs from a **control node**: any machine with Python and ansible-core installed. There is no daemon on managed nodes. For each task, Ansible generates a Python script (the module + arguments), transfers it to the managed node via the connection plugin, executes it, and parses the JSON result. The temp file is removed after execution.

```
ansible-playbook site.yml -i inventory/
        |
        v
Parse YAML (playbooks, roles, vars, inventory)
        |
        v
Build play context (resolve variables, evaluate conditionals)
        |
        v
For each host in the play's host pattern
        |
        v
Generate module code + arguments -> Python script
        |
        v
Transfer + execute via connection plugin (SSH/WinRM/local)
        |
        v
Parse JSON result -> changed / ok / failed / skipped
```

Key characteristics:
- **Agentless**: no daemon on managed nodes; SSH (Linux) or WinRM (Windows) is the only requirement.
- **Push-based**: the control node initiates tasks. Pull mode (`ansible-pull`) inverts this but is the exception.
- **Ordered**: tasks execute sequentially within a play; parallelism across hosts is controlled by `forks`.
- **Idempotent by design**: well-written modules return `changed: false` when no action is required.

---

## Inventory

Inventory is the source of host and group data. It can be static (INI or YAML files) or dynamic (a plugin or script that queries an external source at runtime).

### Static inventory

```ini
# INI format
[webservers]
web1.example.com ansible_host=10.0.1.10
web2.example.com ansible_host=10.0.1.11

[dbservers]
db1.example.com ansible_host=10.0.2.10

[production:children]
webservers
dbservers

[production:vars]
ansible_user=deploy
ansible_become=true
```

```yaml
# YAML format
all:
  children:
    production:
      children:
        webservers:
          hosts:
            web1.example.com:
              ansible_host: 10.0.1.10
            web2.example.com:
              ansible_host: 10.0.1.11
        dbservers:
          hosts:
            db1.example.com:
              ansible_host: 10.0.2.10
      vars:
        ansible_user: deploy
        ansible_become: true
```

### Dynamic inventory

Dynamic inventory plugins query external sources at runtime:

| Plugin | Source |
|---|---|
| `amazon.aws.aws_ec2` | AWS EC2 instances |
| `azure.azcollection.azure_rm` | Azure VMs |
| `google.cloud.gcp_compute` | GCP Compute instances |
| `community.vmware.vmware_vm_inventory` | VMware vCenter |
| `theforeman.foreman.foreman` | Red Hat Satellite / Foreman |
| `constructed` | Combine and filter multiple inventories with Jinja2 logic |

### Group variables and host variables

Variable files are loaded from two directory trees: alongside the inventory file, and alongside the playbook file. Within each tree, precedence runs: `group_vars/all` < `group_vars/<group>` < `host_vars/<host>`.

```
inventory/
  production/
    hosts.yml
    group_vars/
      all.yml          # Applies to all hosts
      webservers.yml   # Applies to [webservers] group
      vault.yml        # Encrypted secrets
    host_vars/
      db1.example.com.yml   # Host-specific overrides
```

---

## Connection plugins

Connection plugins define the transport between the control node and managed nodes.

| Plugin | Transport | Target | Notes |
|---|---|---|---|
| `ssh` (default) | OpenSSH | Linux / Unix | Standard for server automation |
| `paramiko` | Python SSH | Linux / Unix | Fallback when OpenSSH is unavailable |
| `winrm` | WinRM (HTTPS) | Windows | Port 5986; requires `pywinrm` |
| `psrp` | PowerShell Remoting | Windows | Faster than winrm; requires `pypsrp` |
| `local` | None (local exec) | Control node | For tasks that run on the Ansible controller itself |
| `docker` | Docker API | Containers | Managing Docker containers directly |

**Network device connection plugins** (`network_cli`, `httpapi`, `netconf`, `libssh`) are the domain of `ansible-network-modules`; they are not covered here to avoid duplication.

### Windows automation

Windows managed nodes use WinRM (or PSRP). Inventory group\_vars for Windows hosts:

```yaml
# group_vars/windows.yml
ansible_connection: winrm
ansible_winrm_transport: ntlm        # or kerberos, credssp
ansible_winrm_server_cert_validation: ignore   # Only for lab; use proper certs in production
ansible_port: 5986
ansible_user: Administrator
ansible_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...
```

Windows modules use the `ansible.windows` collection: `win_copy`, `win_service`, `win_regedit`, `win_package`, `win_feature`, `win_user`, and many others. DSC (Desired State Configuration) resources are callable via `community.windows.win_dsc`.

---

## Playbook / play / task structure

A **playbook** is a YAML list of **plays**. A play maps a host pattern to a list of **tasks**. Tasks call modules.

```yaml
---
- name: Configure web servers
  hosts: webservers
  gather_facts: true
  become: true
  vars:
    app_version: "2.1.0"

  pre_tasks:
    - name: Ensure apt cache is current
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

  roles:
    - common
    - webserver

  tasks:
    - name: Deploy application config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/myapp/app.conf
        owner: root
        group: root
        mode: '0644'
      notify: Restart myapp

  post_tasks:
    - name: Verify service is running
      ansible.builtin.service_facts:

  handlers:
    - name: Restart myapp
      ansible.builtin.systemd:
        name: myapp
        state: restarted
```

### Blocks and error handling

```yaml
- name: Deploy application
  block:
    - name: Pull latest code
      ansible.builtin.git:
        repo: "{{ app_repo }}"
        dest: /opt/app
        version: "{{ app_version }}"

    - name: Restart service
      ansible.builtin.systemd:
        name: myapp
        state: restarted

  rescue:
    - name: Rollback to previous version
      ansible.builtin.git:
        repo: "{{ app_repo }}"
        dest: /opt/app
        version: "{{ previous_version }}"

    - name: Notify on failure
      ansible.builtin.debug:
        msg: "Deployment failed, rolled back to {{ previous_version }}"

  always:
    - name: Ensure service is running
      ansible.builtin.systemd:
        name: myapp
        state: started
```

`rescue:` runs only if the `block:` fails. `always:` runs regardless.

---

## Modules and collections

### Fully Qualified Collection Name (FQCN)

All module references must use the FQCN format: `namespace.collection.module_name`.

```yaml
# Modern (FQCN) - always use this
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present

# Legacy short name - deprecated in 2.18, error in 2.20
- name: Install nginx
  apt:
    name: nginx
    state: present
```

### Key built-in modules

| Module | Purpose |
|---|---|
| `ansible.builtin.apt` / `yum` / `dnf` | Package management |
| `ansible.builtin.service` / `systemd` | Service management |
| `ansible.builtin.copy` | Static file transfer |
| `ansible.builtin.template` | Jinja2 template rendering |
| `ansible.builtin.file` | File / directory permissions, symlinks |
| `ansible.builtin.user` / `group` | User and group management |
| `ansible.builtin.lineinfile` | Edit specific lines in files |
| `ansible.builtin.uri` | HTTP requests and API calls |
| `ansible.builtin.command` / `shell` | Run commands (last resort; not idempotent) |
| `ansible.builtin.debug` | Print variables and messages |
| `ansible.builtin.assert` | Validation with custom pass/fail messages |
| `ansible.builtin.set_fact` | Set host-scoped variables at runtime |
| `ansible.builtin.include_tasks` / `import_tasks` | Task composition |
| `ansible.builtin.include_role` / `import_role` | Role composition |
| `ansible.builtin.async_status` | Check status of async tasks |
| `ansible.builtin.wait_for` / `wait_for_connection` | Wait for conditions |

### Collection structure

```
namespace/
  collection_name/
    galaxy.yml           # Metadata (version, description, dependencies)
    plugins/
      modules/           # Module plugins
      inventory/         # Inventory plugins
      lookup/            # Lookup plugins
      filter/            # Filter plugins
      connection/        # Connection plugins
      callback/          # Callback plugins
    roles/               # Bundled roles
    playbooks/           # Bundled playbooks
    docs/                # Documentation
    tests/               # Integration tests
```

### Installing collections

```bash
# Install a single collection
ansible-galaxy collection install amazon.aws

# Install from requirements.yml (preferred; pin versions)
ansible-galaxy collection install -r collections/requirements.yml

# requirements.yml
collections:
  - name: amazon.aws
    version: ">=7.0.0,<8.0.0"
  - name: community.general
    version: "9.0.0"
  - name: ansible.windows
    version: "2.5.0"
```

---

## Roles

A role is a reusable, self-contained unit of automation with a standard directory layout.

```
roles/
  webserver/
    tasks/
      main.yml       # Required: task entry point
    handlers/
      main.yml       # Handlers triggered by notify
    templates/       # Jinja2 templates (.j2)
    files/           # Static files for copy / script
    vars/
      main.yml       # High-priority role variables (override group_vars)
    defaults/
      main.yml       # Low-priority defaults (intended to be overridden)
    meta/
      main.yml       # Role metadata, dependencies, Galaxy info
    molecule/        # Molecule test scenarios
```

`defaults/main.yml` is for values that callers should override. `vars/main.yml` is for values that the role controls and callers should not need to override. A common mistake is putting user-overridable values in `vars/main.yml`, which silently overrides `group_vars`.

### Role dependencies

```yaml
# meta/main.yml
dependencies:
  - role: common
    vars:
      common_packages:
        - htop
        - curl
  - role: geerlingguy.docker
    version: ">=6.0,<7.0"   # ansible-core 2.20+ supports version constraints
```

### Installing roles from Galaxy

```bash
ansible-galaxy role install geerlingguy.nginx
ansible-galaxy role install -r roles/requirements.yml
```

---

## Variable precedence (22-level ladder)

From lowest (easily overridden) to highest (always wins):

1. Role defaults (`roles/x/defaults/main.yml`)
2. Inventory `group_vars/all`
3. Playbook `group_vars/all`
4. Inventory `group_vars/<group>`
5. Playbook `group_vars/<group>`
6. Inventory `host_vars/<host>`
7. Playbook `host_vars/<host>`
8. Host facts (gathered by `setup`)
9. Play `vars:`
10. Play `vars_prompt:`
11. Play `vars_files:`
12. Role vars (`roles/x/vars/main.yml`)
13. Block `vars:`
14. Task `vars:` (includes `include_vars`)
15. `set_fact` / `register`
16. Extra vars (`-e` / `--extra-vars`) -- **always wins**

Practical rule: put defaults in `roles/x/defaults/main.yml`, environment-specific values in `group_vars`, and emergency overrides in `--extra-vars`. Avoid `vars/main.yml` in roles for values the caller needs to tune.

---

## Jinja2 templating

Ansible uses Jinja2 for templating in task arguments, `template:` files, and `when:` conditionals.

```yaml
# Variable substitution
- name: Deploy config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf

# When conditionals
- name: Install on Debian only
  ansible.builtin.apt:
    name: nginx
    state: present
  when: ansible_os_family == "Debian"

# Filters
- name: Show list as comma-separated
  ansible.builtin.debug:
    msg: "{{ my_list | join(', ') }}"

# Lookups
- name: Read a local file
  ansible.builtin.debug:
    msg: "{{ lookup('file', '/etc/hostname') }}"
```

Common Jinja2 filters: `default`, `join`, `split`, `regex_replace`, `regex_search`, `to_json`, `to_yaml`, `from_json`, `from_yaml`, `json_query` (requires `jmespath`), `combine`, `dict2items`, `items2dict`, `selectattr`, `map`, `unique`, `flatten`, `zip`.

**ansible-core 2.19+**: Jinja2 3.2 is required; native types are default (`{{ 42 }}` is an integer, not a string). Review templates that relied on string coercion.

---

## Handlers

Handlers are tasks that run once at the end of a play when notified by at least one task.

```yaml
tasks:
  - name: Configure nginx
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Restart nginx    # Queues the handler if this task changed

  - name: Enable nginx
    ansible.builtin.systemd:
      name: nginx
      enabled: true
    notify: Restart nginx    # Same handler name; only runs once regardless

handlers:
  - name: Restart nginx
    ansible.builtin.systemd:
      name: nginx
      state: restarted
```

Handlers run after all tasks in the play complete (or are flushed with `ansible.builtin.meta: flush_handlers`). If the play fails before the handler runs, the handler is skipped -- use `--force-handlers` to override.

---

## Facts and fact gathering

Facts are host variables gathered by the `setup` module at the start of a play (`gather_facts: true` is the default).

```yaml
# Gather only specific fact subsets (faster)
- hosts: webservers
  gather_facts: true
  gather_subset:
    - network
    - hardware
    - min           # Only minimal facts (much faster)

# Disable fact gathering if not needed
- hosts: webservers
  gather_facts: false
```

Useful built-in facts: `ansible_distribution`, `ansible_os_family`, `ansible_architecture`, `ansible_hostname`, `ansible_default_ipv4.address`, `ansible_memtotal_mb`, `ansible_processor_vcpus`.

Fact caching (persistent across runs):

```ini
# ansible.cfg
[defaults]
gathering = smart             # Only gather if facts are not cached
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600
```

---

## Idempotency model

An idempotent task returns `changed: false` on the second run if the first run already achieved the desired state.

Modules in `ansible.builtin` and most collection modules are idempotent by design. When you must use `command` or `shell`, add guards:

```yaml
# Guard with creates: (skip if the file already exists)
- name: Initialise database
  ansible.builtin.command: /opt/app/init-db.sh
  args:
    creates: /opt/app/.db-initialized

# Guard with changed_when (read-only operation; never report changed)
- name: Check application version
  ansible.builtin.command: /opt/app/version
  register: app_version
  changed_when: false

# Guard with failed_when (custom failure condition)
- name: Check service health
  ansible.builtin.uri:
    url: "http://localhost:8080/health"
  register: health
  failed_when: health.status != 200
  changed_when: false
```

---

## ansible-core version deltas

### 2.18 (Ansible community package 11)

- **Python 3.11+ required** on the control node (managed nodes: 3.8+).
- Improved collection dependency resolution with clearer conflict detection.
- Module defaults groups (`module_defaults: group/ansible.builtin.apt: ...`) work reliably.
- `hash_behaviour = merge` removed; use the `combine` filter instead.
- Non-FQCN module references generate deprecation warnings (will be errors in 2.20).
- `include:` (ambiguous static directive) deprecated; use `include_tasks:` or `import_tasks:`.

### 2.19

- **Jinja2 3.2+ required**; native types are default (`{{ 42 }}` is an integer, not a string in templates). Review templates relying on string coercion.
- Stricter argspec validation: unknown parameters are rejected (previously warned). Run `--check` mode first when migrating.
- Improved async task handling and `async_status` structured progress data.
- `constructed` inventory plugin `strict` mode improvements.
- AWS `aws_ec2` inventory plugin defaults to IMDSv2; `azure_rm` supports managed identity natively.

### 2.20 (current as of 2026)

- **Non-FQCN module references are now errors** (were warnings in 2.18--2.19). Run `ansible-lint` with the `fqcn` rule to catch remaining short names.
- `include:` directive removed; use `include_tasks:` or `import_tasks:`.
- `with_*` loop syntax removed; use `loop:` with appropriate filters.
- Python 3.9+ required on **managed nodes** (raised from 3.8 in 2.19).
- Role `meta/main.yml` dependency declarations support version constraints.
- `ansible.builtin.assert` gains `quiet: true` parameter.
- EE image signing and verification for supply-chain security.
- Faster playbook parsing, improved connection pool management, better `ansible-galaxy collection list` caching.

**Migration checklist (any version bump):**

1. Run `ansible-lint` with the latest ruleset; fix `fqcn`, `no-changed-when`, `yaml[truthy]` violations.
2. Replace `include:` with `include_tasks:` or `import_tasks:`.
3. Replace `with_items` / `with_dict` / `with_*` with `loop:` + filters.
4. Verify managed nodes meet the Python version requirement.
5. Test with `--check --diff` against staging before applying to production.
