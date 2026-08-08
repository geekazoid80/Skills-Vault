---
name: ansible-network-modules
description: "Use for any Ansible-based network device automation work using the Ansible network collections. Triggers include \"ansible network\", \"cisco.ios.*\", \"cisco.iosxr.*\", \"cisco.nxos.*\", \"junipernetworks.junos.*\", \"arista.eos.*\", \"paloaltonetworks.panos.*\", \"fortinet.fortios.*\", \"fortinet.fortimanager.*\", \"checkpoint.mgmt.*\", \"ansible_network_os\", \"ansible_connection: network_cli\", \"ansible_connection: httpapi\", \"ansible_connection: netconf\", \"ios_config\", \"ios_command\", \"ios_facts\", \"junos_config\", \"junos_command\", \"ios_l3_interfaces resource module\", \"state: replaced merged deleted rendered parsed gathered overridden\", \"ansible-vault encrypt_string\", \"playbook for network change\", \"declarative network automation\", \"network playbook\", \"ansible-galaxy collection install network\". Covers the network connection plugins (network_cli / httpapi / netconf / libssh; when to use each), collection and module catalogue per vendor, the resource-module pattern (state: replaced / merged / deleted / rendered / parsed / gathered / overridden), inventory shape (group_vars per platform with ansible_network_os and ansible_connection), vault discipline (ansible-vault encrypt_string; CI reads vault password from secret store; never commit decrypted YAML), playbook patterns (--check --diff two-phase loop; serial: knob for safe rollouts; block / rescue for transactional change), and the idempotent-by-default, check-mode-first, diff-narrated discipline. Self-authored from public Ansible Network documentation; no upstream third-party Claude skill exists. Apache-2.0."
license: Apache-2.0
metadata:
  version: 1.0.0
---

# ansible-network-modules

Declarative network device automation using the Ansible network collections. The paradigm is YAML-first: inventory describes the fleet, playbooks describe the desired state, modules reconcile actual against desired. Compared to NAPALM / Netmiko / Nornir (Python-first), Ansible-network is better suited to organisations where change-management workflow is built around playbook review, not Python code review.

> **Skill marker**: When applying this skill, begin your reply with `[skill: ansible-network-modules]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the Ansible inventory, vault, collection versions, and execution-environment conventions before generating or editing playbooks. Only ask the user for information not already covered or specific to this playbook.

Before drafting any module call, understand:

1. **Target estate**
   - Vendor(s) and OS version(s) in the play (Cisco IOS / NX-OS / IOS-XR, JunOS, EOS, others)?
   - Connection plugin appropriate per platform (network_cli, netconf, httpapi)?
   - Collection version pinned in `requirements.yml`?

2. **Change posture**
   - Read-only fact-gather, idempotent push, or destructive operation?
   - Maintenance window, change ticket, rollback plan?
   - Pre / post evidence expected by reviewers?

3. **Inventory and credentials**
   - Inventory source (static YAML, dynamic plugin, NetBox)?
   - Secrets path (Ansible Vault, env, Hashi Vault)?

---

## Iron rules

1. **`gather_facts: false` for network plays.** The default `gather_facts: true` runs `setup` against the host; `setup` does not work on network devices and either hangs to timeout or fails noisily. Set `gather_facts: false` at the play level; gather facts via the vendor-specific `*_facts` module instead (e.g. `cisco.ios.ios_facts`).
2. **`connection:` MUST be `network_cli`, `httpapi`, or `netconf`, never `ssh`.** Ansible's default `ssh` connection assumes a Linux-style POSIX host. Network device CLI requires the network-aware connection plugin; pick per platform (`network_cli` for IOS / NX-OS / JunOS / EOS / FortiOS; `httpapi` for PAN-OS / EOS-eAPI / NX-API; `netconf` for JunOS NETCONF / IOS-XE NETCONF / cisco.iosxr.iosxr_netconf).
3. **Idempotent module first; check_mode before apply.** Run with `--check --diff` first (no changes; shows what would change); narrate the diff via AskUserQuestion; then run without `--check` to apply. The two-phase loop is non-negotiable for production change.
4. **`ansible-vault encrypt_string` for credentials; never plaintext in inventory.** Vault each per-platform credential individually with a memorable name (`ansible_password`, `ansible_become_password`, `panos_api_key`). The CI / CD vault password file comes from the secret store (HashiCorp Vault, AWS Secrets Manager, the platform's secret store), never committed.
5. **One vendor collection per platform; pin versions in `requirements.yml`.** Use `cisco.ios` for IOS, `cisco.iosxr` for IOS-XR, `cisco.nxos` for NX-OS, `junipernetworks.junos` for JunOS, `arista.eos` for EOS, `paloaltonetworks.panos` for PAN-OS, `fortinet.fortios` for FortiOS, `fortinet.fortimanager` for FortiManager, `checkpoint.mgmt` for Check Point. The legacy `community.network` is deprecated for these platforms; do NOT mix.
6. **Resource modules over `*_config` modules where available.** For supported scopes, `cisco.ios.ios_l3_interfaces` (state: replaced / merged / deleted / rendered / parsed / gathered / overridden) is dramatically more idempotent than `cisco.ios.ios_config` (line-based diff). Use the resource-module name; reach for `_config` only when the scope is unsupported.
7. **`serial:` knob on production rollouts.** Default is `serial: 0` (all hosts in parallel). For change runs on shared infrastructure, set `serial: 1` (one host at a time) or a small percentage (`serial: "10%"`) so a partial-fail does not nuke the entire fleet.

## Network connection plugins

| Plugin | Use case | Notes |
|---|---|---|
| `network_cli` | Cisco IOS / NX-OS / JunOS / EOS / FortiOS / others with a vendor CLI shell | Default for most platforms; uses libssh or paramiko under the hood. |
| `httpapi` | PAN-OS, EOS via eAPI, NX-OS via NX-API, F5, FortiManager API | HTTPS + JSON; faster than network_cli; needs the platform's API enabled. |
| `netconf` | JunOS NETCONF, IOS-XE NETCONF, cisco.iosxr_netconf, NSO | Structured XML over SSH (port 830); strongly typed; supports candidate / commit semantics natively. |
| `libssh` | Performance variant of network_cli for high-fanout fleets | Set via `ansible_network_cli_ssh_type: libssh` in group_vars; faster than paramiko. |
| `paramiko` | Fallback when libssh is unavailable | The historical default; works everywhere paramiko works. |

`ansible_network_os` group_var maps the platform: `ios`, `iosxr`, `nxos`, `junos`, `eos`, `panos`, `fortios`, `checkpoint`, etc. Required for `network_cli` and most `httpapi` collections.

## Collection / module catalogue

| Vendor | Collection | Key modules | Connection |
|---|---|---|---|
| Cisco IOS / IOS-XE | `cisco.ios` | `ios_facts`, `ios_command`, `ios_config`, `ios_l3_interfaces`, `ios_l2_interfaces`, `ios_vlans`, `ios_acls`, `ios_bgp_global`, `ios_ospfv2`, `ios_user`, `ios_logging_global` | `network_cli` |
| Cisco IOS-XR | `cisco.iosxr` | `iosxr_facts`, `iosxr_command`, `iosxr_config`, `iosxr_interfaces`, `iosxr_bgp_global`, `iosxr_ospfv2`, `iosxr_acls` | `network_cli` or `netconf` |
| Cisco NX-OS | `cisco.nxos` | `nxos_facts`, `nxos_command`, `nxos_config`, `nxos_l3_interfaces`, `nxos_vlans`, `nxos_acls`, `nxos_bgp_global` | `network_cli` or `httpapi` (NX-API) |
| Juniper JunOS | `junipernetworks.junos` | `junos_facts`, `junos_command`, `junos_config`, `junos_interfaces`, `junos_l3_interfaces`, `junos_bgp_global`, `junos_ospfv2`, `junos_acls`, `junos_user` | `netconf` (preferred) or `network_cli` |
| Arista EOS | `arista.eos` | `eos_facts`, `eos_command`, `eos_config`, `eos_l3_interfaces`, `eos_vlans`, `eos_acls`, `eos_bgp_global`, `eos_ospfv2` | `httpapi` (eAPI) or `network_cli` |
| Palo Alto PAN-OS | `paloaltonetworks.panos` | `panos_facts`, `panos_op`, `panos_config_element`, `panos_address_object`, `panos_security_rule`, `panos_nat_rule`, `panos_commit_push` | `local` (uses `panxapi` Python lib) |
| Fortinet FortiOS | `fortinet.fortios` | `fortios_system_global`, `fortios_firewall_policy`, `fortios_firewall_address`, `fortios_router_static`, `fortios_router_bgp`, `fortios_log_setting` | `httpapi` |
| Fortinet FortiManager | `fortinet.fortimanager` | `fmgr_pkg_firewall_policy`, `fmgr_dvm_cmd_add_device`, `fmgr_securityconsole_install_package` | `httpapi` |
| Check Point | `checkpoint.mgmt` | `cp_mgmt_access_rule`, `cp_mgmt_host`, `cp_mgmt_network`, `cp_mgmt_publish`, `cp_mgmt_install_policy` | `httpapi` (Check Point API) |

The Ansible Galaxy index is the source of truth for new collections and modules; check `galaxy.ansible.com/ui/repo/published/<namespace>/<collection>/` for the latest version and module list before pinning in `requirements.yml`.

## Resource modules vs config modules (the modern pattern)

```yaml
# Resource module: declarative; idempotent; state-driven
- name: Set L3 interface IP and description
  cisco.ios.ios_l3_interfaces:
    config:
      - name: GigabitEthernet0/1
        ipv4:
          - address: 192.0.2.1/30
        description: LINK_TO_R2
    state: replaced

# vs the legacy config module: imperative; line-based diff; brittle
- name: Same intent via ios_config (avoid where resource module exists)
  cisco.ios.ios_config:
    parents: interface GigabitEthernet0/1
    lines:
      - description LINK_TO_R2
      - ip address 192.0.2.1 255.255.255.252
```

**Resource module `state` semantics:**

- `merged` (default): additive; existing fields preserved; new fields added.
- `replaced`: replaces the matching resource (e.g. one interface) with the supplied config; other resources untouched.
- `overridden`: replaces ALL resources of this type with the supplied config; resources not in the play config are removed.
- `deleted`: removes the matching resources.
- `rendered`: returns the CLI commands without applying (offline render; useful for review).
- `parsed`: converts CLI text into structured data (offline parse; useful for ingest).
- `gathered`: reads current state into structured data (read-only; alternative to `*_facts`).

**The `overridden` state is the source of most operational surprises.** It removes resources NOT mentioned in the play. Use deliberately; never combine with a partial play that filters for one host group.

## Inventory shape

```ini
# inventory/hosts.ini
[cisco_ios]
r1.nyc.example.net
r2.nyc.example.net

[juniper_junos]
mx1.lax.example.net

[arista_eos]
sw1.dfw.example.net

[network:children]
cisco_ios
juniper_junos
arista_eos
```

```yaml
# inventory/group_vars/cisco_ios.yml
ansible_network_os: ios
ansible_connection: network_cli
ansible_user: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          (encrypted)
ansible_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          (encrypted)
ansible_become: true
ansible_become_method: enable
ansible_become_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          (encrypted)
```

```yaml
# inventory/group_vars/juniper_junos.yml
ansible_network_os: junos
ansible_connection: netconf
ansible_user: !vault |
          (encrypted)
ansible_ssh_private_key_file: ~/.ssh/junos_id_ed25519
```

```yaml
# inventory/group_vars/arista_eos.yml
ansible_network_os: eos
ansible_connection: httpapi
ansible_httpapi_use_ssl: true
ansible_httpapi_validate_certs: true
ansible_user: !vault |
          (encrypted)
ansible_password: !vault |
          (encrypted)
```

`group_vars/all.yml` holds the cross-platform baseline (`ansible_python_interpreter: /usr/bin/python3` if needed, retry counts, log paths). Per-platform group_vars set the connection plugin and platform-specific variables. Per-host overrides go in `host_vars/<hostname>.yml`.

## Vault discipline

```bash
# Encrypt one credential at a time with a memorable name; commit the encrypted block to inventory
ansible-vault encrypt_string --name 'ansible_password' 'real-password-here'

# Edit a vaulted inventory file
ansible-vault edit inventory/group_vars/cisco_ios.yml

# Run a playbook reading the vault password from a script (preferred for CI)
ansible-playbook -i inventory/hosts.ini --vault-password-file scripts/get-vault-pw.sh playbook.yml
```

`scripts/get-vault-pw.sh` reads from the secret store (`vault read -field=password secret/ansible/prod`, `aws secretsmanager get-secret-value --secret-id ansible-vault-prod --query SecretString --output text`); it must NEVER hard-code the password.

CI patterns:
- GitHub Actions: store the vault password as an encrypted secret; expose via `env: ANSIBLE_VAULT_PASSWORD`; have `get-vault-pw.sh` echo it.
- AWX / AAP: use the built-in Vault credential type; the controller injects at runtime.
- Jenkins: use the Credentials plugin with the SSH-Username-with-Password pattern; bind to ANSIBLE_VAULT_PASSWORD env.

NEVER:
- Commit a decrypted vault file (even temporarily; `git rm` does not erase it from history).
- Use `--ask-vault-pass` in CI (interactive prompt fails non-interactively).
- Vault the entire inventory file (you lose grep-ability for non-secret variables); only vault the secret values.

## Playbook patterns

### Two-phase check / apply (mandatory for production)

```bash
# Phase 1: check + diff; no changes; surface diff to user via AskUserQuestion
ansible-playbook -i inventory/hosts.ini playbooks/ntp-config.yml --check --diff

# Phase 2: apply (only after diff approval)
ansible-playbook -i inventory/hosts.ini playbooks/ntp-config.yml --diff
```

### Safe rollout with `serial:` and `max_fail_percentage:`

```yaml
- name: Roll out NTP config across spines
  hosts: spines
  gather_facts: false
  serial: 1
  max_fail_percentage: 0
  tasks:
    - name: Configure NTP servers
      cisco.ios.ios_ntp_global:
        config:
          servers:
            - server: 169.254.169.123
              prefer: true
            - server: time.cloudflare.com
        state: replaced
```

`serial: 1` runs one host at a time. `max_fail_percentage: 0` aborts the whole rollout on the first failure; raise to e.g. 25 if you want best-effort. For ring topologies, `serial: 1` plus `order: shuffle` distributes risk.

### Transactional change with `block: / rescue:`

```yaml
- hosts: edge_routers
  gather_facts: false
  tasks:
    - block:
        - name: Save pre-change config
          cisco.ios.ios_command:
            commands:
              - show running-config
          register: pre_config

        - name: Push new BGP config
          cisco.ios.ios_bgp_global:
            config:
              as_number: 65001
              router_id: 198.51.100.1
            state: replaced

        - name: Verify BGP neighbours up
          cisco.ios.ios_command:
            commands:
              - show ip bgp summary
            wait_for:
              - result[0] contains "Established"
            retries: 5
            delay: 10
      rescue:
        - name: Roll back to pre-change config
          cisco.ios.ios_config:
            src: "{{ pre_config.stdout[0] }}"
            replace: config
          when: pre_config is defined
        - name: Surface failure
          ansible.builtin.fail:
            msg: "BGP push failed; rolled back. See logs for diagnosis."
```

`block: / rescue:` is Ansible's transactional pattern: rescue runs only if the block fails. Pair with explicit pre-change capture for rollback.

### Junos commit-confirm

```yaml
- name: Push Junos config with commit-confirm
  hosts: juniper_junos
  gather_facts: false
  tasks:
    - name: Apply config with 5-minute confirm timeout
      junipernetworks.junos.junos_config:
        src: "{{ inventory_hostname }}.conf"
        confirm: 5

    - name: Verify reachability post-push
      ansible.builtin.wait_for:
        host: "{{ ansible_host }}"
        port: 830
        timeout: 60

    - name: Confirm the commit (cancels rollback)
      junipernetworks.junos.junos_config:
        confirm_commit: true
```

If the second task (reachability check) fails, the device auto-rolls back at the 5-minute mark. The `confirm_commit: true` task is what makes the change permanent.

## Common pitfalls

1. `connection: ssh` instead of `connection: network_cli`. Default ssh connection assumes POSIX shell; the play hangs or returns garbage.
2. `gather_facts: true` on a network device. `setup` is a Linux fact-gathering module; it does not work; play hangs to timeout.
3. Ad-hoc `ansible -m shell` against a network OS. Modules `*_command` (e.g. `cisco.ios.ios_command`) are the equivalent; `shell` does not work.
4. Missing `ansible_network_os` group_var. Connection plugins fall back to ambiguous handling and fail with cryptic errors.
5. Hard-coded credentials in inventory. Always vault. Even in dev.
6. `state: present` ambiguity in config modules. Some modules infer "present" loosely; use the resource-module `state:` taxonomy where available.
7. Pinned-old-collection drift. `requirements.yml` must pin a known-good version; allow upgrade in a controlled bump PR. Floating versions break the next CI run.
8. `serial: all` (default) on production change. Lockstep failure across the fleet. Set `serial: 1` or a small percentage.
9. No `block: / rescue:` on partial-failure rollback. Half-applied change leaves the fleet in inconsistent state.
10. Mixing playbook and ad-hoc against the same fleet during a change window. The change window is a critical section; only one tool drives at a time.

## Cross-references

- `napalm-netmiko`: Python alternative; better fit when network engineers are Python-first and change management is built around code review (PRs against playbooks vs PRs against scripts).
- `nornir-automation`: Python orchestration alternative with structured per-host results; better fit when you need fine-grained processor hooks (ServiceNow / Slack mid-run) that Ansible's callback plugin model handles less ergonomically.
- `pyats-network-automation`: Cisco-fleet alternative for fleet automation with structured Genie parsing; better fit when test-then-deploy AEtest workflows are the contract.
- `multi-vendor-network-ops`: umbrella; this skill is the declarative paradigm specialist underneath the diagnose-first methodology; the 9-element response contract applies on production-impacting playbook runs.
- `bgp-analysis` / `igp-routing-analysis`: protocol-depth specialists; resource modules `*_bgp_global`, `*_ospfv2` feed their decision trees.
- `acl-rule-analysis`: when the change is an ACL push (`*_acls` resource modules), the audit discipline lives there.
- `secrets-hygiene`: vault discipline; CI vault password from secret store; never commit decrypted YAML.
- `systematic-debugging`: Phase 1 boundary evidence often comes from a `*_facts` module run.
- `completion-gate` Layer 3: post-deploy verification gate; re-run `*_command` show against expected output.
- `plan-time-tooling`: production playbook runs fire `engineering:deploy-checklist`; new collection adoption fires `engineering:architecture`.
- `bash-defensive`: wrapper scripts that invoke `ansible-playbook` follow defensive-bash discipline.
- `consumer-rollout`: when introducing a shared playbook consumed by other teams, drop a Required hooks section into each consumer's AGENTS.md.

## Red flags (stop and ASK before)

1. About to commit a decrypted vault file (any `!vault` block expanded to plaintext anywhere in the diff).
2. About to push with `serial: all` (the default) on production change.
3. About to use `state: present` against a config module without reading current state first.
4. About to skip `--check --diff` for a production change.
5. About to rely on `ignore_errors: yes` for a fleet push (suppresses the per-host failure surface; chains broken changes silently).
6. About to set `ansible_connection: ssh` against a network device.
7. About to embed a PAN-OS API key, SNMP community, or any other secret in inventory plaintext.
8. About to use a `community.network` deprecated module instead of the vendor collection (e.g. `community.network.ios_config` instead of `cisco.ios.ios_config`).
9. About to skip a collection version pin in `requirements.yml`; CI will drift.
10. About to run `ansible -m raw` against an unknown OS (raw bypasses module sanity checks; expect garbage on network devices).

## Bottom line

Ansible-network is the declarative, YAML-first paradigm for multi-vendor network automation. The Ansible network connection plugins (`network_cli`, `httpapi`, `netconf`) plus per-vendor collections (`cisco.ios`, `cisco.iosxr`, `cisco.nxos`, `junipernetworks.junos`, `arista.eos`, `paloaltonetworks.panos`, `fortinet.fortios`, `fortinet.fortimanager`, `checkpoint.mgmt`) cover the multi-vendor estate. Resource modules (state: replaced / merged / deleted / rendered / parsed / gathered / overridden) replace the legacy line-based `*_config` pattern wherever supported. Vault every credential individually; CI reads the vault password from the secret store. Two-phase check / diff / apply is non-negotiable for production. `serial:` and `block: / rescue:` give you safe rollouts with rollback. For Python-first teams, `napalm-netmiko` and `nornir-automation` are the alternatives; for Cisco-only fleets with structured-test workflows, `pyats-network-automation` is the alternative.
