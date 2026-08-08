---
name: mikrotik-routeros
description: "Use for any MikroTik RouterOS v7.x operation, audit, change review, or design pass on hardware (RouterBOARD, CCR, CRS) or virtual (CHR, x86 or aarch64). Triggers include \"routeros\", \"mikrotik\", \"/ip/\", \"/interface/\", \"/firewall filter\", \"/firewall nat\", \"/firewall mangle\", \"/ip address-list\", \"/ip dhcp-server\", \"/ip hotspot\", \"/container\", \"/app\", \"winbox\", \"MNDP\", \"MikroTik neighbour discovery\", \"TZSP\", \"tool sniffer\", \"routeros REST API\", \"/console/inspect\", \"OpenAPI from /console/inspect\", \"wg-genkey on RouterOS\", \"RouterOS as WireGuard endpoint\", \"PPPoE concentrator\", \"RouterOS BGP / OSPF config\", \"MikroTik firewall rule comment idempotency\", \"etherboot\", \"netinstall-cli\", \"configure script vs mode script\", \"RouterOS package upgrade\", \"apply-changes vs reboot\", \"CHR boot order\", \"CHR aarch64 / arm64\", \"MikroTik API client\", \"mikrotik_api Python\", \"RouterOS REST schema\", \"MikroTik Capsman\", \"VLAN bridging on RouterOS\", \"RouterOS scripting\", \"scheduler\", \"RouterOS backup vs export\", \"device-mode reset\", \"device-mode rose\", \"REST PUT vs POST on RouterOS\", \"DANGEROUS_PATHS RouterOS inspect\", \"MAC-Telnet\", \"mac-telnet\", \":parse IL\", \"print as-value\", \"RouterOS scripting traps\", \"quickchr\". Covers RouterOS v7.x only (not v6 except where called out), v7.21+ for /app YAML, v7.22+ for custom YAML apps, v7.23+ for the RouterOS-native port format and devices/expose/secrets/attach, v7.4+ for the WireGuard interface, v7.18+ for `/system/package/apply-changes`, kernel containers via /container (device-mode required). Eight sections: scope; fundamentals; firewall + idempotent scripting; state queries + REST + API; container + /app; specialised services (hotspot, sniffer, MNDP, netinstall); CHR / lab; patterns + troubleshooting. Diagnose-first; read-only `print` / `print where` queries before any state-changing command. Maps onto multi-vendor-network-ops' nine-element response contract for production-impacting changes. Consolidated fold of tikoci/routeros-skills (14 SKILL.md files: routeros-app-yaml, routeros-command-tree, routeros-container, routeros-firewall, routeros-fundamentals, routeros-hotspot, routeros-mndp, routeros-netinstall, routeros-qemu-chr, routeros-sniffer, plus routeros-syntax-inspection, routeros-scripting, routeros-mac-telnet, routeros-quickchr folded in the 2026-07-30 monthly-audit pass; Apache-2.0) plus drodecker/openclaw-mikrotik-routeros-skill/mikrotik-api (MIT)."
license: Apache-2.0
metadata:
  version: 1.2.0
---

# MikroTik RouterOS (v7.x) operations

RouterOS is MikroTik's operating system. It is not Linux; do not assume Linux semantics. v7 introduced significant architectural changes (kernel 5.x, container subsystem, REST API, WireGuard interface). v6.x is end-of-cycle for new features and OUT OF SCOPE for this skill.

This skill consolidates the tikoci routeros-skills collection (10 specialised topics) and the drodecker mikrotik-api Python client patterns into one operational surface. For deep dives on any single topic, the upstream skills remain the source; the Reference table at the end lists pointers.

> **Skill marker**: When applying this skill, begin your reply with `[skill: mikrotik-routeros]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the MikroTik estate (device roles, RouterOS version, automation conventions, firewall posture, out-of-band recovery path) before generating any config or script. Only ask the user for information not already covered or specific to this device.

Before generating any config, understand:

1. **Device and role**
   - Hardware model (CCR, CHR, CRS, hAP, others)?
   - RouterOS major / minor version (v6 vs v7 has significant divergence)?
   - Role in topology (CPE, distribution, core, MPLS PE, hotspot, on-prem firewall)?

2. **Change context**
   - Greenfield commission, production change, or post-incident remediation?
   - Maintenance window, rollback plan, out-of-band access in case of lockout?

3. **Existing conventions**
   - Firewall rule structure (address-lists, jump chains, custom comments)?
   - Backup / config-export cadence and storage location?
   - Automation surface (Netmiko, NAPALM, REST, custom scripts)?

---

## Scope and when to use

- Designing or reviewing a RouterOS v7.x firewall rulebase (filter, NAT, mangle, address-lists, interface-lists).
- Idempotent CLI / scripting work (the comment-as-tag pattern is the iron rule for repeatable scripts).
- REST API integration; mapping CLI commands to REST verbs via `/console/inspect`.
- Container deployment on RouterOS (`/container` for OCI, `/app` for declarative YAML on v7.21+).
- Hotspot / captive portal design (chains, profiles, DHCP Option 114, RADIUS, walled garden).
- Packet capture and TZSP streaming to Wireshark.
- Device discovery via MNDP and WinBox.
- Device flashing via netinstall-cli.
- CHR (Cloud Hosted Router) in QEMU / KVM for dev / test / scaling.
- Multi-device operations using the mikrotik-api Python client (status queries, firewall view, custom commands).
- Pre-upgrade baseline before RouterOS major version changes.

When the work is broader than RouterOS (mixed estate with Cisco / Juniper / Arista) use `multi-vendor-network-ops` for the umbrella response contract; this skill handles the MikroTik-specific deep-dive. For the protocol-level work over RouterOS interfaces (BGP / OSPF) see `bgp-analysis` / `igp-routing-analysis`. For VPN configuration on RouterOS (IPsec / WireGuard) see `vpn-tunnel-troubleshooting`.

## Prerequisites

- SSH or Winbox access to the device (read-only privilege sufficient for diagnosis; full admin for changes).
- Knowledge of the RouterOS version (`/system resource print`); features and CLI shape vary across v7 minor releases.
- For container or /app work: device must support and have device-mode set (`/system device-mode print`); enabling container mode requires a physical reset on hardware (LED-press).
- For REST work: HTTPS service enabled, REST users configured, certificate trust handled.
- For CHR: KVM / HVF / TCG capable host; bridge or NAT-bridge networking configured; correct image variant for the use case.

## 1. Fundamentals

RouterOS organises configuration in a path tree. Most CLI verbs are `add`, `set`, `remove`, `print`, `find`, `enable`, `disable`. Examples:

```
/ip address print
/ip address add address=192.0.2.1/24 interface=ether1
/interface bridge add name=bridge1
/interface bridge port add bridge=bridge1 interface=ether2
```

Per-version differences matter: `/interface bridge port` exists in v7 but `/interface bridge port settings` is v7.6+; check `/system resource print` for `version`.

### What RouterOS is NOT

It is NOT Linux. The agent must internalise this:

- No FHS layout, no `/bin`, `/etc`, `/var`, no shell, no coreutils, no `glibc`, no `systemctl`, no `/proc`, no `docker` CLI.
- Do NOT try `ssh admin@host 'ls /'`, `cat /etc/passwd`, `ps aux`, `journalctl`, or any Linux-rooted introspection. They will not work.
- What DOES exist: the path-tree CLI (`/ip`, `/interface`, `/system`, ...), the REST API, the legacy API protocol (TCP/8728 and TCP/8729-TLS), Winbox, WebFig (HTTPS browser UI), MNDP discovery, the RouterOS scripting language (`:if`, `:do`, `:execute`, `:parse`, `:serialize`).

WebFig health-check from a script (without any authentication): `GET https://router/` returns HTTP 200 with the login form. For authenticated REST with empty password (default factory), basic auth is literally `admin:` (the colon is REQUIRED; HTTP Basic encodes `admin:` as `YWRtaW46`).

### REST API mapping

REST parallels the CLI tree. The HTTP-verb mapping is RouterOS-specific and a common LLM mistake:

| CLI verb | HTTP verb | Notes |
|---|---|---|
| `add` | `PUT /rest/<path>` | Creates a new item; body carries the properties. **NOT POST.** |
| `set` | `PATCH /rest/<path>/<id>` | Modifies an existing item. |
| `remove` | `DELETE /rest/<path>/<id>` | Deletes by ID. |
| Action verbs (`start`, `stop`, `reboot`, others) | `POST /rest/<path>/<action>` | RouterOS uses POST for actions, not for create. |

```
GET    https://router/rest/ip/address
PUT    https://router/rest/ip/address      body: {"address":"192.0.2.1/24","interface":"ether1"}
PATCH  https://router/rest/ip/address/<id> body: {"disabled":"yes"}
DELETE https://router/rest/ip/address/<id>
```

`<id>` is the RouterOS internal item ID (looks like `*A`); discover via the GET response. `PUT /rest/user/add` returns `{"ret":"*ID"}`; `PUT /rest/<path>` (without `/add`) returns the full object.

Schema introspection: `/console/inspect path=/ip/address` returns the per-attribute type, default, and read-only flags. Use it to discover unfamiliar paths before guessing. Section 3 covers the inspect surface in depth, including which paths CRASH the REST server if introspected.

### Architecture names

RouterOS ships per-CPU-architecture packages with these labels:

| Arch label | CPU class | Examples | CHR support |
|---|---|---|---|
| `x86` | Intel / AMD 64-bit | CCR2004-1G, CHR x86_64 | Yes |
| `arm64` | ARMv8 64-bit | CCR2116, CCR2216, hAP ax3 / ax2, CHR aarch64 (`chr-<ver>-arm64.img`) | Yes |
| `arm` | ARMv7 32-bit | RB5009, hAP ac3, older CCRs | No |
| `mipsbe` | MIPS big-endian | RB750Gr3, hEX, older hAP | No |
| `mmips` | MIPS micro | RB951Ui, RB962, low-end hAP | No |
| `smips` | MIPS small | hAP mini, mAP | No |
| `ppc` | PowerPC | older CCR1009, CRS125 | No |
| `tile` | Tilera | original CCR1036 | No |

CHR is x86 and arm64 only; do NOT try CHR on arm / mips / ppc / tile. The all-packages zip uses `x86` in the filename; individual `.npk` files for x86 do NOT carry the arch suffix (every other arch does: `routeros-7.18-arm64.npk`).

### Inspecting hardware from RouterOS

The agent's debugging surface:

```
/system resource print              # CPU, memory, RouterOS version, board name
/system resource hardware print     # board details, CPU model, factory firmware
/system resource irq print          # IRQ distribution per CPU core
/disk print                          # storage devices
/system package print                # installed packages and versions
/ip service print                    # which services are exposed and to whom
/interface print                     # all interfaces, running state, types
```

### Package management and the apply-changes / reboot gotcha (v7.18+)

Packages live under `/system/package`. Installation flows:

- Upload `.npk` files (via REST `PUT /rest/file/<name>` or WinBox file panel), then `/system/package/apply-changes` (added 7.18) to commit the install.
- Online update: `/system/package/update/check-for-updates` then `/system/package/update/install`.

**Critical gotcha on 7.18+:** plain `/system/reboot` DISCARDS uploaded packages that have not been applied. The agent must run `/system/package/apply-changes` BEFORE rebooting if a package was just uploaded. The reverse (apply without reboot) works in some cases (extra packages enable / disable) and not others (system package upgrade requires reboot after apply).

Extras available to install (architecture-dependent): `container`, `iot`, `zerotier`, `wifi-qcom`, `rose-storage`, `ups`, `gps`, `calea`, `tr069-client`, `user-manager`. See upstream `routeros-fundamentals/references/extra-packages.md` for the full per-package CLI surface.

### Device-mode

Device-mode gates dangerous features (container, USB peripheral access, some serial console paths). On 7.17+ there are four named modes (per device class):

| Mode | When applied | Container? | USB peripherals? | Notes |
|---|---|---|---|---|
| `home` | Consumer hAP / SOHO | No | No | Default factory mode on home gear. |
| `basic` | Default factory mode on most CCR / CRS | No | No | |
| `advanced` | Required for `/container` and similar | Yes | Yes | Hardware: physical reset (LED-press during boot, 12+ attempts typical via REST despite docs claim of 3). |
| `rose` | Storage-oriented profile (RouterOS Storage extras) | No | Storage USB | For NAS-style RB5009 + USB-SSD deployments. |

`/system/device-mode/update mode=<mode>` initiates the change; an `activation-timeout` window (10s to 1d) follows during which the operator must perform the physical confirmation. On REST the endpoint blocks ALL other REST requests until the window closes; lab-verified the physical-confirmation `attempt-count` is typically 12+ via REST despite the docs stating 3. In QEMU, `system_reset` from the QEMU monitor counts as the physical confirmation.

### Version-format and upgrade endpoint

RouterOS version strings follow `MAJOR.MINOR[.PATCH][betaN|rcN]`, e.g. `7.18`, `7.18.1`, `7.19beta3`, `7.20rc1`. Four release channels:

| Channel | Use for |
|---|---|
| `long-term` | Production where stability dominates; bug fixes only. |
| `stable` | Default production; gets new features. |
| `testing` | Beta; for lab and pre-prod soak. |
| `development` | Early access; expect breakage. |

Latest-version probe: `GET https://upgrade.mikrotik.com/routeros/NEWESTa7.<channel>` returns plain text `version_string<space>build_epoch`. Useful for "are we behind?" automation. See upstream `routeros-fundamentals/references/version-parsing.md` for the full grammar and the x86-naming exception.

### Do NOT assume

- That a v6 syntax still works in v7 (many paths got renamed; `interface ovpn-server` -> `interface ovpn-server server`; etc.).
- That the firewall has Linux iptables semantics (it shares the kernel netfilter primitive but the exposed model is RouterOS-specific).
- That a script that worked yesterday will work after an upgrade (test `/system upgrade` in CHR first).
- That device-mode is on (containers / certain protocols are gated; hardware reset required to enable).
- That POST creates a resource over REST (it does NOT; PUT does; the local body used to get this wrong and it has been corrected in this revision).
- That `/system/reboot` after a package upload preserves the upload on 7.18+ (it does NOT; `apply-changes` first).

## 2. Firewall and idempotent scripting

The firewall has four tables (filter, NAT, mangle, raw) plus address-lists and interface-lists. Rules are evaluated top-down per chain; FIRST MATCH wins. There is no priority field; ORDER is the priority. **IPv6 lives in a SEPARATE tree `/ipv6/firewall`; rules do NOT apply cross-protocol.** If you need both, you write each side.

**Iron rule for scripts: tag every rule with a unique `comment=`.** RouterOS has no native upsert; the only safe pattern for idempotent automation is:

```
:if ([/ip firewall filter find comment="auto:allow-mgmt-ssh"] = "") do={
  /ip firewall filter add chain=input action=accept protocol=tcp dst-port=22 src-address-list=mgmt comment="auto:allow-mgmt-ssh"
}
```

The comment pattern guarantees a script that re-runs will not duplicate rules (the `find` returns the existing one).

### Non-terminal actions stop nothing

A common LLM-mistake: assuming every `action=` is terminal. Several actions are NON-TERMINAL and rule evaluation continues to the next rule:

- `action=add-src-to-address-list`
- `action=add-dst-to-address-list`
- `action=log`
- Any rule with `passthrough=yes` (default for `mangle` action=mark-*).

If a rule has a non-terminal action AND needs to also stop matching, follow it with an explicit terminal rule (`action=accept` / `drop` / `reject`) on the same match set, or use `place-before=0` to push a terminal rule before the non-terminal one. Wrong:

```
# This logs and KEEPS GOING; later rules can still drop the packet.
/ip firewall filter add chain=input action=log src-address=192.0.2.10 comment="auto:log-mgmt"
```

Correct (log then accept):

```
/ip firewall filter add chain=input action=log src-address=192.0.2.10 log-prefix="mgmt" comment="auto:log-mgmt"
/ip firewall filter add chain=input action=accept src-address=192.0.2.10 comment="auto:accept-mgmt" place-before=0
```

### Address-list timeouts as primary DoS-blacklist pattern

```
/ip firewall address-list add list=blacklist address=198.51.100.0/24 timeout=1d comment="auto:24h-blacklist"
```

`timeout=` makes the entry auto-expire; the address-list garbage-collects on its own. Used in the detect -> blacklist -> drop pipeline so an attacker IP self-clears after a window.

### Connection state

Explicit enum: `new`, `established`, `related`, `invalid`, `untracked`.

- `untracked` requires that the connection be excluded from conntrack first via `/ip/firewall/raw action=notrack`. Untracked packets do NOT match FastTrack flows.
- **Never combine `fasttrack-connection` with mangle routing marks.** FastTrack bypasses subsequent rule processing (mangle / NAT / forward chain filter) for the connection's fast-path; mark-routing requires evaluation of those tables. If both are present, mark-routing intermittently does not apply.

### Common rule patterns

```
# Address-lists for dynamic groups
/ip firewall address-list add list=blacklist address=198.51.100.0/24
/ip firewall filter add chain=input action=drop src-address-list=blacklist comment="auto:drop-blacklist"

# Interface-lists for trust grouping
/interface list add name=WAN
/interface list member add list=WAN interface=ether1
/ip firewall filter add chain=input action=drop in-interface-list=WAN comment="auto:drop-from-wan"

# NAT (masquerade outbound)
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN comment="auto:masq-wan"

# Hairpin / DST-NAT for published service
/ip firewall nat add chain=dstnat action=dst-nat protocol=tcp dst-port=443 in-interface-list=WAN to-addresses=192.0.2.10 comment="auto:dnat-https"

# Force DNS through the router (redirect 53 to local DNS)
/ip firewall nat add chain=dstnat action=redirect to-ports=53 protocol=udp dst-port=53 in-interface-list=LAN comment="auto:dns-redirect-udp"
/ip firewall nat add chain=dstnat action=redirect to-ports=53 protocol=tcp dst-port=53 in-interface-list=LAN comment="auto:dns-redirect-tcp"
```

### Layer 7 protocol matcher

Layer7 regexes use POSIX-ERE semantics. The biggest gotcha: precedence. `(a|b|c)` matches `a` or `b` or `c`; `(a)|(b)|(c)` matches `a` OR matches the regex `(b)|(c)` (alternation operator binds loosely). Always group alternatives inside ONE parenthesis pair.

### Management-tool safety

**Never use `remove [find dynamic=no]`** in automation. This wipes EVERY non-dynamic rule, including ones a sibling orchestrator added. The safer pattern: filter by your comment-as-tag prefix (`/ip firewall filter remove [find comment~"^auto:"]`). Even safer: list, diff, and remove only the specific tags you own.

### DoS-protection load-bearing rules (lifted from `routeros-firewall/references/dos-protection.md`)

- `psd=weight,delay,low-port-weight,high-port-weight`: matches port-scan candidates. The last two values are **weight scores, NOT port ranges** (a frequent misreading; e.g. `psd=21,3s,3,1` is "weight 21 within 3 seconds, low-port weight 3, high-port weight 1").
- `connection-limit=X,Y`: matches when source has more than X connections; **Y is the netmask prefix bits to group by** (e.g. `connection-limit=20,32` per /32; `connection-limit=200,24` per /24).
- `action=tarpit`: replies with zero TCP window so the attacker's connection stalls in ESTABLISHED state; ties up their state table without sending data. Pair with `connection-state=new`.
- Three-stage pipeline: detect with `psd` or `connection-limit` -> blacklist with `action=add-src-to-address-list address-list=ddos timeout=1d` -> drop or tarpit with `src-address-list=ddos`.

### Mangle-routing load-bearing rules (lifted from `routeros-firewall/references/mangle-routing.md`)

- v7 requires the routing table to be created BEFORE mark-routing can target it: `/routing/table/add name=via-isp2 fib`. The `fib` keyword is mandatory in v7; v6 created tables on-the-fly.
- The DNS-exempt rule MUST be placed BEFORE the mark-routing rule, else DNS lookups follow the alternative path and clients see resolver mismatches.
- `hotspot=auth` is a valid match value alongside `from-client`, `local-dst`, `http`.
- MSS-clamping pattern for VPN MTU: `chain=forward action=change-mss tcp-flags=syn protocol=tcp new-mss=clamp-to-pmtu`.
- **FastTrack bypasses mangle.** See the rule above in Connection state.

### Rule ordering caveats

- `add` appends to the END of the chain; if you need a rule earlier, use `add place-before=<id>`.
- Re-ordering existing rules: `move` (`/ip firewall filter move <id> destination=<n>`).
- Always run `/ip firewall filter print` BEFORE and AFTER a change; diff the output.

### Common LLM mistakes (consolidated checklist)

| Mistake | Reality |
|---|---|
| Assuming `action=log` stops rule evaluation. | Non-terminal; follow with explicit accept / drop. |
| Assuming `action=add-src-to-address-list` stops rule evaluation. | Non-terminal. |
| Mixing `fasttrack-connection` with mangle marks. | FastTrack bypasses mangle; marks unreliable. |
| Using `[find dynamic=no]` for cleanup in scripts. | Wipes sibling tools' rules; filter by your tag prefix. |
| Forgetting `connection-state=new` on `tarpit`. | Tarpits existing flows; matches your own legitimate traffic. |
| Layer7 regex `(a)|(b)|(c)` for alternation. | Use `(a|b|c)`; precedence binds loosely otherwise. |
| Treating IPv4 firewall rules as covering IPv6. | `/ipv6/firewall` is a separate tree; write both. |
| `action=accept` on a `prerouting` mangle rule. | mangle has no accept; use `passthrough=yes` or just omit. |
| Forgetting `comment=` on automation-driven rules. | Second run duplicates rules. |
| `/routing/table/add` without `fib` keyword (v7). | Table never registers; mark-routing silently routes via main. |

### RouterOS scripting traps (correctness gotchas)

RouterOS scripting is not shell, Lua, or Python; the traps LLMs most often get wrong (folded from upstream `routeros-scripting`):

- **Interactive row numbers are not stable IDs.** `print` row numbers (`0`, `1`, ...) are print-buffer positions, unusable in scripts. Resolve at runtime with `[find ...]` and a stable selector (`comment=`, `name=`, a unique address). Internal IDs show as `.id=*HEX` in `print as-value`.
- **`[find]` returns an ID array** (zero, one, or many). `set` / `remove` / `disable` take the array directly; code needing exactly one object must check `[:len $ids]` before `get`. Use your own `comment=` tag prefix for idempotent cleanup, never a broad `[find dynamic=no]` (wipes sibling tools' rules).
- **Quote IP-prefix literals in `find` / `where`.** `/ip/address` stores `address` as a string with prefix length, so `address=111.111.1.1/24` (unquoted) can match nothing; use `address="111.111.1.1/24"` or `[:tostr $var]`.
- **`print as-value` is an array of maps**, even for one row: `[:pick [... as-value where ...] 0]->"prop"`, not `[...]->"prop"`.
- **`monitor` commands need `once do={}`** to capture values in a script; hyphenated fields use `$"rx-bits-per-second"`. Prefer `:log` over `:put` in scheduler / hook scripts with no attached terminal.
- **Globals must be re-declared where read.** `:global name;` before reading or calling a global variable or function inside another script or function body; avoid names colliding with RouterOS properties (`dst-address`), or quote them (`$"dst-address"`).
- **Arrays are not JavaScript arrays.** `{}` is a syntax error (use `[:toarray ""]`); the `.` concatenation operator distributes over an array unless you `[:tostr]` it first.
- **Script policies gate correctness.** Scheduler, Netwatch, and `on-up` hooks run with limited policy; if the script needs `files` / `write` / `sensitive` / reboot rights the caller must carry them. `dont-require-permissions=yes` runs the script with its own policy for less-privileged callers; use only for deliberately bounded scripts.

## 3. State queries, REST, and the mikrotik-api client

`/console/inspect` is the canonical way to introspect any path. Two surfaces matter: the CLI-form (`path=/ip/address`) for interactive use, and the REST-form (POST body with `path` as a COMMA-SEPARATED string) for automation.

### `/console/inspect` at the CLI

```
/console/inspect path=/ip/address
/console/inspect path=/ip/firewall/filter request=detail
```

Four request types: `child` (subpaths), `syntax` (per-attribute types, defaults, read-only flags), `highlight` (terminal-rendering metadata), `completion` (tab-complete candidates).

### `/console/inspect` over REST: comma-separated path

The REST body uses a comma-separated string, NOT a slash-separated path:

```
POST /rest/console/inspect
Content-Type: application/json
{ "path": "ip,address,add", "request": "syntax" }
```

A frequent LLM mistake is to send `"path": "/ip/address/add"` (slash) or `"path": "ip.address.add"` (dot). Both are wrong; the REST form is comma-only.

### DANGEROUS_PATHS that crash the REST server (version-specific; fixed 7.21.4)

Calling `request=syntax` or `completion` on the scripting-keyword paths `where`, `do`, `else`, `rule`, `command`, `on-error` deadlocks the RouterOS REST server on RouterOS <= 7.20.8 (measured; a bare `do` hangs `syntax` / `completion` at both 128 MB and 512 MB RAM). The crash is silent (the REST listener stops responding, and a hung server also makes subsequent unrelated probes look broken); recovery needs `/system/script/run` on the device or a reboot. **FIXED in 7.21.4** (all six paths return instantly). So treat the hard-skip as a conservative policy for old or unknown versions, not a timeless six-path rule; on 7.21.4+ feature-detect with a short per-request timeout. Separate limit on all versions: `input` beyond 32,767 bytes is rejected, and highlight has a latency cliff near 28 KB (observed 7.23.x), so route oversized scripts to `:parse` (no cap) rather than highlighting a truncated copy and calling it validated.

### Inspect validity is necessary, not sufficient

`/console/inspect` reports what its parser accepts, which is not what the runtime accepts. There is a measured inspect-vs-runtime gap: inspect passes `blackhole=yes` on a route where the runtime wants the bare `blackhole` flag. Only executing on an appropriate target proves runtime acceptance; read a clean inspect as "structurally plausible", not "will apply". Two reader rules that stop wrong conclusions: (1) highlight and `:parse` stop at the FIRST hard error (one `error` byte, or a line / column message with no partial IL), so neither gives multi-error diagnostics in one call, and an unclassified `none` token means "not classified", not "valid literal". (2) Offsets and tokens are byte-based: highlight emits one token per input byte and completion `offset` counts wire bytes, so ASCII-normalise input (replace each byte > 127 with `?`) before mapping editor character positions onto RouterOS byte positions.

### `.proplist` and `.query` special parameters

Cross-cutting REST parameters (treat like SQL `SELECT` and `WHERE`):

```
GET /rest/ip/address?.proplist=address,interface,disabled
GET /rest/ip/address?.query=interface=ether1
```

`.proplist` projects columns; `.query` filters rows. Both reduce payload and parse load.

### Output formats

Inspect data exists in three shapes:

| Format | Where | Use |
|---|---|---|
| `inspect.json` | Per-RouterOS-version raw data model | Canonical machine-readable form; offline tooling can point at this via `INSPECTFILE` env var. |
| RAML 1.0 | Generated from inspect | Older RouterOS REST contracts. |
| OpenAPI 3.0 | Generated from inspect (RouterOS 7.21.1+) | Use this for new tooling; supported by openapi-generator and most LSP integrations. |

### Performance

Full inspect-tree traversal is many thousands of sequential POSTs (no batch API; one HTTP request per node). Expect minutes, not seconds. Cache `inspect.json` per-version rather than re-walking the tree.

### REST API at the resource level

```
curl -k -u admin:<password> https://router/rest/ip/address
curl -k -u admin:<password> -X PUT https://router/rest/ip/address \
  -H 'Content-Type: application/json' \
  -d '{"address":"192.0.2.1/24","interface":"ether1"}'
```

Use PUT (not POST) for create; see the verb-mapping table in Section 1.

### REST gotchas per resource

**Firewall (`/ip/firewall/filter`, `/ip/firewall/nat`, `/ip/firewall/mangle`)**

- PUT APPENDS to the end of the chain; for placement, use `place-before=*ID`.
- There is NO `move` action via REST; to re-order, DELETE and re-add with a different `place-before`.
- All booleans are strings (`"yes"` / `"no"`, not `true` / `false`).
- Rules with `dynamic=true` cannot be modified via REST; PATCH returns silently with no effect.
- `reject-with` accepts an enum (`icmp-net-unreachable`, `icmp-host-unreachable`, `icmp-port-unreachable`, `icmp-proto-unreachable`, `icmp-net-prohibited`, `icmp-host-prohibited`, `icmp-admin-prohibited`, `tcp-reset`).
- `/ip/firewall/connection` is READ-ONLY (the conntrack view); PATCH / DELETE not supported.

**Networking (`/ip/dns`, `/ip/dhcp-client`, `/ip/dhcp-server`)**

- `/ip/dns` returns an OBJECT (not an array); it is a singleton. Use `POST /rest/ip/dns/set` (not PATCH on an ID).
- `/ip/dhcp-client` defaults to `disabled=yes`; you must explicitly set `"disabled":"no"` when adding via REST.
- `add-default-route=special-classless` triggers RFC 3442 Classless Static Route option processing.
- `/ip/dhcp-server` `address-pool` defaults to `static-only` (no dynamic leases unless overridden).
- Three-step DHCP-server setup: pool first (`/ip/pool`), then network (`/ip/dhcp-server/network`), then server (`/ip/dhcp-server`).

**Users (`/user`, `/user/group`)**

- A user disabling themselves via REST silently no-ops; use a different `full`-group user.
- `expired:true` on the admin DOES NOT affect REST API access (only blocks CLI / WinBox / SSH).
- The `rest-api` policy controls REST access; default `read` group does NOT include it.
- `/rest/user/add` returns `{"ret":"*ID"}` (just the ID); `PUT /rest/user` returns the full object.
- Password auth is disabled BY DEFAULT when an SSH key is configured for the user.
- `/export` does NOT include SSH keys or user passwords (intentional; they live in protected storage).

### Async commands over REST

Three monitor-endpoint modes (`/interface/monitor-traffic`, `/system/health/monitor`, others):

| Body parameter | Behaviour |
|---|---|
| `duration="Xs"` | Returns a `.section` ARRAY of samples; each section numbered as a string `"0"`, `"1"`, ... |
| `once=""` (empty string) | Returns one sample immediately. |
| Neither set | Blocks INDEFINITELY (no timeout); will hang the HTTP client. |

`.section` is numbered as STRING, not integer. ERROR-prefix detection on the last section: if the final entry starts with `"ERROR:"`, the run aborted. Use an `AbortSignal` / client-side timeout as a safety net for the no-param case.

### `/system/device-mode/update` is a blocking REST endpoint

When `/system/device-mode/update` is in its `activation-timeout` window, it STALLS ALL OTHER REST endpoints. Other requests queue until the window closes (timeout: `10s..1d`). Plan automation around this: schedule device-mode changes during quiet windows; do not pipeline other REST calls behind it. In QEMU, send `system_reset` from the QEMU monitor as the physical-confirmation equivalent.

### mikrotik-api Python client

For multi-device operations, the drodecker `mikrotik_api` Python client wraps either REST or the legacy API protocol:

```python
from mikrotik_api import RouterOSApi

with RouterOSApi(host="router1.example.com", username="admin",
                password=os.environ["ROUTER_PASSWORD"]) as api:
    interfaces = api.command("/interface/print")
    for iface in interfaces:
        print(iface["name"], iface["running"])
```

Common operational queries handled by `mikrotik_api`: status, firewall list, interfaces, DHCP leases, ARP table, WireGuard peers, users, logs, backup creation, storage, services, traffic stats. Use it for VIEWING; for state-changing fleet ops, prefer Ansible (community.routeros) or pyATS-style harnesses with proper rollback. See `secrets-hygiene` for how to keep router passwords out of source.

## 4. Container subsystem and declarative apps

Two layers:

- **`/container`** -- low-level OCI subsystem. Requires `device-mode container=yes` (use `/system/device-mode/update container=yes` then perform physical confirmation; see Section 1 device-mode table). Uses VETH pairs into RouterOS bridges; image management via `/container mounts`.
- **`/app`** -- declarative YAML app management (v7.21+ builtin apps; v7.22+ supports custom YAML; v7.23+ added `devices`, `expose`, `secrets`, `attach`). Higher abstraction; intended replacement of raw `/container` for most use cases.

### Device-mode prerequisite

```
/system/device-mode/update container=yes
# physical confirmation within activation-timeout window (10s..1d)
# attempt-count is typically 12+ via REST despite docs claim of 3
```

After confirmation: install the container package via `/system/package/apply-changes` (v7.18+) -- do NOT just `/system/reboot`, that discards the upload. See Section 1 for the apply-changes gotcha.

### Container quick start

```
/container config set registry-url=https://registry-1.docker.io/v2
/interface veth add name=veth1 address=172.17.0.2/24 gateway=172.17.0.1
/interface bridge port add bridge=container-bridge interface=veth1
/container add remote-image=alpine:latest interface=veth1 root-dir=disk1/alpine
/container start <number>
```

### Env / mount property-name history (version-sensitive)

The container env / mount surface changed twice; the property names differ per RouterOS version:

| Version | Env property | Mount property | Inline alternative |
|---|---|---|---|
| Pre-7.20 | `envlist=<name>` (singular) | `mounts=<name>` (singular) | None |
| 7.20 | `envlists=<name>` (plural) | `mounts=<name>` | None |
| 7.21+ | `envlists=<name>` | `mounts=<name>` | `env=KEY=VAL` and `mount=src=dst` inline on `/container/add` |

Using `envlist=` (singular) on 7.20+ silently no-ops; using `envlists=` (plural) on pre-7.20 errors. Check `/system resource print` version before generating the property name.

### OCI image local-import constraints

Images imported locally (not pulled from a registry) must:

- Be a **single layer** (squash or flatten first; multi-layer images fail to start).
- Be **uncompressed** (no `.tar.gz`; plain `.tar`).
- Use the **Docker v1 manifest** (not OCI v2); the bundle is `manifest.json` + `config.json` + `layer.tar`.

`docker save <image> | tar -O > image.tar` does NOT produce a single-layer image; use `docker export` from a running container instead (collapses layers into the container's flat filesystem).

### REST API gotchas for `/container`

- `.running` is a STRING (`"true"` / `"false"`), NOT a boolean. Parsing as bool fails or yields the wrong type in strict TypeScript / Pydantic.
- There is NO `.stopped` field. To detect stopped state: `.status == "stopped"` (also a string).
- `DELETE /rest/container/<id>` while the container is stopping returns HTTP 400. Must poll `.status == "stopped"` first, then DELETE.

### Architecture mapping (RouterOS arch -> OCI platform)

| RouterOS arch | OCI platform string | docker buildx tag |
|---|---|---|
| `arm` | `linux/arm/v7` | `--platform linux/arm/v7` |
| `arm64` | `linux/arm64` | `--platform linux/arm64` |
| `x86` | `linux/amd64` | `--platform linux/amd64` |

Mismatched platform images fail at startup with `exec format error`; always tag-pull or build for the target arch.

### `/container` vs `/app`

| Aspect | `/container` | `/app` |
|---|---|---|
| Abstraction level | OCI direct | Declarative YAML wrapper around `/container` |
| Network | Manual VETH + bridge | Auto-bridges; can be re-bridged post-creation via `/app/set network=` |
| Config / secrets | Manual env / mount | YAML schema + placeholders |
| Auto-update | None | Yes (auto-update from declared URL) |
| Netinstall L2 carve-out | Bridge directly to physical | `/app` cannot do L2 directly; re-bridge post-creation |
| Recommended for | Quick lab / one-off | Persistent service with config + auto-update |

### `/app` YAML schema and version history

- v7.22: initial custom-YAML support; subset of docker-compose.
- v7.23beta2: new RouterOS-native port format `host:container:label:proto`.
- v7.23: added `devices`, `expose`, `secrets`, `attach` top-level keys.

Port format has TWO styles (both still accepted on 7.23+):

```yaml
# Old OCI-style (pre-7.23; still works): host:container/proto:label
ports:
  - "8080:80/tcp:webfig"
  - "8443:443/tcp:webfig-ssl"

# New RouterOS-native (7.23+ preferred): host:container:label:proto
ports:
  - "8080:80:webfig:tcp"
  - "8443:443:webfig-ssl:tcp"

# Long-form object syntax (either era):
ports:
  - host: 8080
    container: 80
    proto: tcp
    label: webfig
```

The local-body claim "no `host:container` shorthand" was wrong; OLD style DID support it.

### Placeholders

Five built-in placeholders, used in `ports`, `env`, and `volumes` values:

| Placeholder | Resolves to |
|---|---|
| `[accessIP]` | The IP a client uses to reach the router (typically the router's LAN IP). |
| `[accessPort]` | First port mapped (for single-port apps). |
| `[accessPort2]` | Second port mapped (for apps with two faces, e.g. web + admin). |
| `[containerIP]` | The container's internal VETH IP. |
| `[routerIP]` | The router's bridge IP on the container network. |

Distinct from the `${VAR}` form from `/app config` (which substitutes per-instance vars).

### `/app` REST API

- `PUT /rest/app` body `{"yaml-url": "https://example.com/myapp.yaml"}` -- creates the app from a remote YAML.
- `GET /rest/app/<id>` returns the YAML string plus metadata (version, last-update, status).

### Common `/app` mistakes (consolidated)

| Mistake | Reality |
|---|---|
| Mixing port styles on different entries within one app. | Pick one style per app; do not mix. |
| Lowercase env-var keys in `.latest.json` strict schema. | Strict schema requires uppercase; relaxed schema (`.editor.json`) accepts lowercase. |
| Using `deploy:` or `resources:` keys. | Not supported; silently ignored. |
| Using `version:` top-level key (docker-compose habit). | Ignored; not part of /app schema. |
| Treating Docker `configs:` and `secrets:` as supported. | Configs use inline `content:` only (no external mount); secrets are 7.23+. |

For the full top-level and service-property catalogues, defer to upstream `routeros-app-yaml/SKILL.md` and `routeros-app-yaml/references/examples.md`.

## 5. Specialised services

### Hotspot (captive portal)

Hotspot is opinionated: a hotspot chain in firewall, hotspot profile, hotspot instance per interface, optional RADIUS, walled garden. **IPv4 only**; there is no IPv6 hotspot.

```
/ip hotspot setup    # interactive wizard; produces a working baseline
/ip hotspot profile print
/ip hotspot user add name=guest password=...
/ip hotspot walled-garden add dst-host=*.example.com
/ip hotspot walled-garden ip add dst-address=192.0.2.0/24
```

#### Chain interaction with firewall

The hotspot subsystem dynamically injects `hs-unauth` and `hs-auth` chains into the firewall. Hotspot chain processing happens BEFORE `input` and `forward` chain matching. A common LLM-mistake: writing `/ip firewall filter add chain=input action=drop dst-port=443` thinking it secures the captive portal. It silently breaks login (the splash page redirect is dropped).

#### Profile properties worth knowing

- `ssl-certificate=<name>_0`: RouterOS appends `_0` to the certificate name when importing into the hotspot profile. If you import `myportal.crt`, the profile references it as `myportal.crt_0`. Predict the suffix when scripting.
- `use-radius=yes` BYPASSES local users entirely; if the RADIUS server is unreachable, all logins fail (no local fallback).
- `login-by` controls auth method (`http-pap`, `http-chap`, `https`, `mac`, `mac-cookie`, `cookie`); pick deliberately, defaults to `http-pap,http-chap`.

#### Instance properties

- `keepalive-timeout=none` to DISABLE keepalive (NOT `0`; `0` is silently ignored).

#### DHCP Option 114 (RFC 8910 captive portal API)

For modern captive-portal API discovery, set Option 114 on the DHCP server. iOS and Android REQUIRE `force=yes` on the option (they skip the probe without it). The quote syntax for the URL value is **outer-double-inner-single mandatory**:

```
/ip dhcp-server option add code=114 name=capport-api value="'https://router.lan/api.json'" force=yes
/ip dhcp-server network set <id> dhcp-option=capport-api
```

The `api.json` endpoint is auto-served by RouterOS but only created after the FIRST CAPPORT probe arrives; reproduce by triggering a client connect.

#### Walled garden: L3 vs L7

Two surfaces:

- `/ip/hotspot/walled-garden/ip` -- **L3 IP / CIDR matcher; works for HTTPS** (TCP-level allow before HTTP inspection).
- `/ip/hotspot/walled-garden` -- L7 HTTP matcher with `dst-host` wildcards; **does NOT work for HTTPS** (no TLS termination on RouterOS).

For modern destinations (Google, Apple, CRL responders) you MUST use the L3 form; the L7 form is pre-TLS-everywhere legacy.

#### Common hotspot LLM mistakes (consolidated)

| Mistake | Reality |
|---|---|
| Dropping TCP/443 to "secure" the portal. | Breaks the captive-portal flow silently. |
| Setting `keepalive-timeout=0` to disable. | Silently ignored; use `keepalive-timeout=none`. |
| L7 walled-garden for HTTPS destinations. | L7 cannot see TLS SNI; use the L3 `/ip` form. |
| RADIUS without a local fallback path. | RADIUS-only auth dies if the server is unreachable. |
| Mixing hotspot with PCC mark-routing in mangle. | Hotspot chain processing competes with mangle mark-routing; PCC paths bypass hotspot rewrite. |
| Forgetting `force=yes` on Option 114. | iOS / Android skip the probe; portal never appears. |
| Treating `ssl-certificate=myportal.crt` literally. | Profile references `myportal.crt_0` (RouterOS appends `_0`). |
| Building external captive-portal HTML without `$(...esc)` URL-escape on user-controlled fields. | XSS / inject risk via `$(http-header-X)` interpolation. |
| Expecting hotspot to work on IPv6. | IPv4 only. |
| Editing servlet HTML in place without backing up `flash/hotspot/`. | RouterOS resets servlet files on package upgrade. |

For the external captive-portal HTML template-variable subsystem (`$(name)` server-side substitution, servlet-page list, conditional `$(if ... )$(endif)`, RADIUS pass-through `$(radius<id>)`, header injection `$(http-header-X)`, the `-esc` URL-escape suffix), defer to upstream `routeros-hotspot/references/template-variables.md`. For multi-RADIUS-server fallback and the "disable at deploy then enable after files land" pattern, see `routeros-hotspot/references/radius-client.md`.

### Sniffer and TZSP streaming

Three modes, **combinable simultaneously**:

1. Memory buffer: packets held for ~10 minutes; queryable via `/tool/sniffer/packet print`.
2. File capture: written to flash via `file-name=capture.pcap`.
3. TZSP streaming: live UDP stream to a remote dissector.

PCAPNG (with metadata) is the **default capture format since RouterOS 7.20**; the local-body claim "pcap" was incomplete.

```
/tool sniffer set interface=ether1 file-name=capture.pcap file-limit=10MB
/tool sniffer start
# ... wait ...
/tool sniffer stop
/file print
```

Interactive one-shot (does NOT write to file; prints to terminal):

```
/tool sniffer quick ip-protocol=icmp interface=ether1
```

Useful filter properties (subset; see upstream `routeros-sniffer/SKILL.md` for the full 16-field table):

- `filter-stream=yes` (default): EXCLUDES the TZSP stream itself from capture; if you turn this off you create a feedback loop and DoS the sniffer.
- `filter-direction=any|rx|tx`
- `only-headers=yes`: skip payload, useful for high-throughput captures.
- `memory-limit=<bytes>` / `file-limit=<bytes>`.

For live streaming to Wireshark via TZSP:

```
/tool sniffer set streaming-enabled=yes streaming-server=192.0.2.50:37008
/tool sniffer start
```

In Wireshark: open UDP/37008 listener with TZSP dissector enabled.

For firewall-mangle-driven sampling (capture only matching flows):

```
/ip firewall mangle add chain=prerouting action=sniff-tzsp \
  sniff-target=192.0.2.50 sniff-target-port=37008 \
  src-address=192.0.2.10 protocol=tcp dst-port=443
```

`action=sniff-tzsp` is a `passthrough`-equivalent action; it does NOT modify or drop the original packet, only copies it to the TZSP target.

#### Mangle-driven vs sniffer

| Use mangle | Use /tool sniffer |
|---|---|
| Capture only specific flows | Capture everything on an interface |
| Conditional capture (turn on under load) | One-off ad-hoc capture |
| Long-running baseline streaming to a SOC | Quick troubleshooting session |
| Multiple capture criteria in one config | Single set of filters |

#### Sniffer gotchas

- Hardware-offloaded bridge traffic is NOT visible to `/tool/sniffer` (offload bypasses the CPU). Disable hw-offload on the bridge OR capture upstream on the wire.
- Wireless client-to-client unicast inside the same SSID is NOT visible (handled by the radio firmware below CPU visibility).
- Cleanup ritual after a streaming session: `set streaming-enabled=no streaming-server=0.0.0.0` and `/ip/firewall/mangle remove [find comment~"TZSP"]`. Leaving the stream active leaks traffic to a possibly-stale collector IP.

For the host-side dissection recipes (Wireshark / tshark / tcpdump on TZSP, port-conflict workarounds, host firewall rules for the listener), see upstream `routeros-sniffer/references/tzsp-receivers.md`.

### MNDP (MikroTik Neighbour Discovery)

MNDP is the LLDP-equivalent for RouterOS-to-RouterOS discovery and the basis for the WinBox "Neighbours" tab.

#### Protocol basics

| Property | Value |
|---|---|
| Transport | UDP, port 5678 (bidirectional, same port) |
| IPv4 scope | Broadcast `255.255.255.255` |
| IPv6 scope | Multicast `ff02::1` |
| Authentication | None |
| Discovery scope | L2 broadcast domain only (no L3 forwarding) |

Treat MNDP like an open SNMP community: anyone on the L2 segment can read identity, software version, board, IPs, MACs, uptime, capabilities.

#### Multi-interface behaviour

A device with N interfaces emits N announcements, each with a DIFFERENT interface name, MAC, and IP, but the SAME identity. Group by identity when building a topology view; do not assume one announcement = one device.

#### Timing (never interpret missing-as-offline)

| Medium | Refresh window |
|---|---|
| Wired LAN | 1 to 3 seconds |
| WiFi | 3 to 10 seconds |
| ZeroTier / overlay | 5 to 20 seconds |
| Satellite | 10 to 30 seconds |

A missed refresh is normal under load; require multiple consecutive misses before flagging the neighbour offline. WinBox uses a 5-second cadence; match it for parity.

#### Discovery configuration

```
/ip neighbor print
/ip neighbor discovery-settings set discover-interface-list=LAN
/ip neighbor discovery-settings set protocol=cdp,lldp,mndp
```

The `protocol=` set lets RouterOS announce / receive multiple protocols simultaneously. To exclude specific interfaces from a per-list discovery: prefix with `!` in the interface-list, e.g. `discover-interface-list=LAN,!no-mndp`.

REST: `/rest/ip/neighbor` returns the neighbour table.

#### Security

- No auth; assume any reader on the L2 segment captures the announcement.
- Information leak surface: identity, RouterOS version (helps target known CVEs), board model, IP / MAC of every interface, uptime, capabilities.
- **Always disable on WAN-facing interfaces** (`/ip neighbor discovery-settings set discover-interface-list=LAN` excludes WAN if WAN is not in the LAN interface-list).

For the 9-byte refresh-packet wire format and full TLV-type table, defer to upstream `routeros-mndp/SKILL.md` (deep TLV format was deliberately retained as upstream pointer in the original fold). For socket-implementation snippets, TypeScript MNDP-parser reference, and other-language reference implementations (Go, Elixir, C, Swift), the upstream is the place.

### MAC-Telnet (Layer 2 terminal access)

MAC-Telnet reaches a RouterOS device by MAC address over Layer 2 (UDP 20561, no IP configuration needed) and is how WinBox and `/tool/mac-telnet` recover a device with no reachable IP. Auth is MD5 challenge-response on older RouterOS and EC-SRP (MTWEI) on modern releases; treat it like console access and restrict the MAC-server interface list accordingly. For the full wire format (22-byte header, session lifecycle, MD5-vs-MTWEI negotiation), defer to upstream `routeros-mac-telnet/SKILL.md`.

### Netinstall (device flashing)

`netinstall-cli` (Linux) flashes RouterOS images to RouterBOARD devices via etherboot / BOOTP / TFTP. Safety facts the agent often misses:

- **Does NOT erase the licence key**; the level is recovered after flash.
- **Does NOT reset RouterBOOT settings** (boot device, baud rate, fail-safe boot); only RouterOS itself is reinstalled.

#### Workflow

1. Connect a Linux host to the same L2 segment as the device (or via direct cable).
2. Trigger etherboot entry; three options:
   - **Reset button**: hold while powering on; release when LED pattern changes.
   - **Serial console Ctrl+E**: catches RouterBOOT prompt; lets you select etherboot interactively.
   - **In-OS pre-stage**: `/system routerboard settings set boot-device=try-ethernet-once-then-nand` (then reboot; falls back to NAND if etherboot does not complete).
3. Run `netinstall-cli -a <client-ip> -r <router-mac> routeros-x.y.z.npk` (system package; see naming below).
4. Optional `-c <configure-script>` applies post-install config (persists across upgrades; survives `/system reset-configuration`).
5. Optional `-m <modescript>` configures device-mode pre-install (one-shot; mode-change reboots the device).

The `-sm` flag (split mode script) requires RouterOS 7.22+.

#### Default-mode behaviour (no `-r`, no `-e`)

If you omit both `-r` (reset config) and `-e` (erase), netinstall KEEPS the old configuration, downloads the new image, reformats, and re-uploads the config DB. It does NOT touch files outside the config DB (no `flash/dude`, no `flash/user-manager`). For a true wipe, pass `-r -e`.

#### Configure script vs mode script

| Property | Configure script (`-c`) | Mode script (`-m`) |
|---|---|---|
| Persists across upgrades | Yes | No (one-shot) |
| Survives `/system reset-configuration` | Yes (re-runs until you re-netinstall without it) | No |
| Run order | After first boot | Before first boot (reboots after mode change) |
| RouterOS 7.22+ for `-sm` (split mode script) | Not applicable | Yes |
| Timeout | 120 seconds | 120 seconds |

A configure script that errors keeps re-running on every `/system reset-configuration` until the device is re-netinstalled WITHOUT the `-c` flag. Predictable trap if the script depends on transient infrastructure.

#### Variables in configure script

`$defconfPassword` and `$defconfWifiPassword` are auto-injected (RouterOS 7.10beta8+); use them to set credentials in the same script without hardcoding.

#### First-boot script order

Mode script runs first; if device-mode actually changes, the device REBOOTS, and then the configure script runs. Plan the two halves accordingly; a configure script that assumes mode-script side effects must tolerate the reboot.

#### Package URL patterns

- Primary: `https://download.mikrotik.com/routeros/<version>/routeros-<version>-<arch>.npk`
- Fallback CDN: `https://cdn.mikrotik.com/routeros/<version>/routeros-<version>-<arch>.npk`

For arch values, see the Section 1 architecture-name table. The system package MUST be listed first when flashing multiple packages in one run; netinstall processes them in order and gets confused if extras precede the base.

#### Etherboot / DHCP-snooping failure modes

- USB-ethernet adapters that auto-flap during link negotiation can cause netinstall to drop midway. Use a stable wired NIC on the Linux host.
- DHCP snooping on the upstream switch can intercept the BOOTP exchange; either disable snooping on the relevant VLAN or use a direct cable.

For non-x86 hosts (running netinstall under qemu-i386-static on ARM, or under a macOS Linux VM), see upstream `routeros-netinstall/SKILL.md`.

## 6. CHR (Cloud Hosted Router) in QEMU

CHR is the virtual-machine RouterOS image, **available for both x86_64 (`chr-<ver>.img`, SeaBIOS boot) and aarch64 (`chr-<ver>-arm64.img`, UEFI boot)**. The local body previously treated CHR as x86-only; aarch64 has been a first-class CHR target since RouterOS 7.15+.

To ground a RouterOS command or script against a real disposable instance before publishing, the upstream `routeros-quickchr` skill wraps `@tikoci/quickchr` (a TS / CLI helper) to boot a throwaway CHR and run `quickchr exec <name> '<command>'`; this is tooling, not required for operations, but useful when you want runtime proof rather than an inspect-only check (see "Inspect validity is necessary, not sufficient" in Section 3).

### Image variants

- `chr-<ver>.img` (raw, x86_64, SeaBIOS).
- `chr-<ver>-arm64.img` (raw, aarch64, UEFI).
- `.vdi` (VirtualBox), `.vmdk` (VMware), `.qcow2` (QEMU). Use the matching variant.
- Third-party `fat-chr` (UEFI-bootable x86 repack for Apple Virtualization.framework) exists outside the official MikroTik tree; see upstream `routeros-qemu-chr/SKILL.md` for the variant table.

### Acceleration and CPU model

- **KVM** on Linux x86 / arm64; **HVF** on macOS x86 / Apple Silicon; **TCG** fallback elsewhere (unusable for production).
- **KVM and HVF both require host-guest arch match.** You cannot run an aarch64 CHR on an x86 host with KVM / HVF; only TCG cross-arch works and is multi-second-per-instruction slow.
- HVF + `-cpu cortex-a710` (an ARMv8.5 CPU with SVE2) **CRASHES on Apple Silicon** (which is ARMv8.5 but does not advertise SVE2 to the guest). Use `-cpu host` with HVF on Apple Silicon, not a specific model name.
- TCG performance hint: `-accel tcg,tb-size=256` (raises translation-block cache; reduces re-JIT churn).

### Boot tracks

#### x86_64 (SeaBIOS)

```
qemu-system-x86_64 \
  -enable-kvm -cpu host -smp 2 -m 256 \
  -drive file=chr-7.18.img,if=virtio \
  -netdev bridge,id=n1,br=br0 \
  -device virtio-net-pci,netdev=n1 \
  -nographic
```

#### aarch64 (UEFI)

```
qemu-system-aarch64 \
  -accel hvf -cpu host -smp 2 -m 256 -machine virt \
  -drive if=pflash,format=raw,readonly=on,file=$(brew --prefix qemu)/share/qemu/edk2-aarch64-code.fd \
  -drive file=chr-7.18-arm64.img,if=none,id=hd0,format=raw \
  -device virtio-blk-pci,drive=hd0 \
  -netdev user,id=n1 -device virtio-net-pci,netdev=n1 \
  -nographic
```

### VirtIO: critical details

VirtIO PCI works on both x86 and aarch64; **VirtIO MMIO does not** (RouterOS lacks the `virtio_mmio` driver).

The `if=virtio` shorthand on aarch64 is a TRAP: QEMU resolves `if=virtio` to virtio-MMIO on the `virt` machine, which RouterOS cannot bind. The disk attaches but never appears; the kernel stalls silently. **On aarch64, always use the long form: `-drive if=none,id=hd0` + `-device virtio-blk-pci,drive=hd0`** (PCI form).

The `if=virtio` shorthand IS safe on x86 (resolves to virtio-blk-pci).

### Port-forward table for `-netdev user`

Host-only access to the guest's services without bridging:

| Guest port | Service | Host-port convention |
|---|---|---|
| 80 | WebFig (HTTP) | 8080 (one instance) / 8081, 8082, ... (multi) |
| 443 | WebFig (HTTPS) | 8443 / 8444, 8445, ... |
| 22 | SSH | 2222 / 2223, ... |
| 8728 | Legacy API (TCP) | 18728 / 18729, ... |
| 8729 | Legacy API (TLS) | 18829 / 18830, ... |
| 8291 | WinBox | 8291 / 8292, ... |

```
-netdev user,id=n1,hostfwd=tcp::8080-:80,hostfwd=tcp::8443-:443,hostfwd=tcp::2222-:22,hostfwd=tcp::18728-:8728,hostfwd=tcp::8291-:8291
```

### Health-check and the 5-stage startup race

After QEMU starts, REST does NOT become available immediately. Expect this sequence (each stage transiently visible):

| Stage | Symptom | Meaning |
|---|---|---|
| 1 | `connection refused` | QEMU launched; RouterOS not booted yet. |
| 2 | `ECONNRESET` on TCP handshake | RouterOS kernel up; network stack initialising. |
| 3 | HTTP 401 on `/rest` | nginx-equivalent listening; REST not authorised yet (user db loading). |
| 4 | HTTP 200 but response body is the login form HTML | REST handler not yet routing `/rest` paths. |
| 5 | HTTP 200 with correct JSON | Ready. |

Build health-checks that expect stages 1 through 4 transiently; only stage 5 is "ready". A naive "first 200" check fires at stage 4 and gets wrong data.

### Known limitations

- **QEMU Guest Agent (QGA) requires KVM**: the `cpuid` instruction (used by QGA discovery) is not faithfully emulated under TCG. QGA-driven shutdowns / network info are KVM-only.
- **`check-installation` is unfixable on aarch64**: the upstream script is 32-bit ELF; the DTB capability files do not enumerate `acpi-on`/`acpi-off` on `virt` machine; the check always reports "unsupported board". Ignore it on aarch64; rely on `/system resource print` instead.
- **`-kernel <vmlinuz>` direct boot does NOT work for CHR.** The CHR image has a proprietary boot wrapper; you must boot the disk image, not extract and direct-boot the kernel.
- **Cross-arch x86-on-aarch64 is unviable**: TCG full-system emulation of x86 on aarch64 spends 16+ host instructions per guest instruction; lab measurements show seconds-per-shell-command. Use an x86 host for x86 CHR.
- **No `virtio_mmio`**; always use `virtio-pci` form (see VirtIO note above).

### Licensing

CHR tiers: P1 (free, 1 Mbps per interface), P10 (10 Mbps), P-Unlimited (real-world). **60-day P-Unlimited trial** available via mikrotik.com account binding; after expiry the CHR continues running but drops to 1 Mbps and cannot upgrade RouterOS version while expired.

**System-id per VM**: the CHR licence binds to the `system-id` (RouterOS-generated UUID); cloning a VM clones the `system-id`, which DOUBLE-BINDS the licence and silently invalidates both. Always run `/system license generate-key` on a freshly cloned CHR before binding.

For full QEMU pattern catalogues (Inline / Wrapper / Bun-TS / `--readconfig`), the kernel-driver matrix, the deep `known-issues.md` (cross-arch evidence, UEFI pflash size-match gotchas, background-mode `exec` PID-capture, socat retry, mktemp race), and the full GitHub Actions CI recipe (KVM-enabled `ubuntu-latest`, VDI-to-QCOW2 conversion, sshpass-based `.npk` upload, concurrent-build rebase pattern), defer to upstream `routeros-qemu-chr/SKILL.md` and its references (`chr-licensing.md`, `github-actions-ci.md`, `known-issues.md`, `virtio-drivers.md`).

## 7. Patterns and troubleshooting

### Backup vs export (the both-and rule)

- `/system backup save name=daily` -> binary backup; restorable via `/system backup load`. Includes everything (passwords, certs, CHR licence).
- `/export show-sensitive file=daily` -> human-readable script. Replayable on a similar device. Easier to diff in git.

ALWAYS take both before any change. Binary backup for fast restore; export for forensic comparison and source-of-truth in git.

### Pre-change capture

```
:do { /export show-sensitive } on-error={ }
:do { /system backup save name=("pre-change-".[/system clock get time]) } on-error={ }
```

Schedule daily exports to a remote SCP target via `/system scheduler`.

### Change diagnosis decision tree

```
RouterOS change misbehaving
├── Did the rule add succeed?
│   ├── No -> read the CLI error; common causes: typo in path, item exists, missing required field
│   └── Yes -> continue
│
├── Is the rule active?
│   ├── /ip firewall filter print shows it disabled? -> /ip firewall filter enable <id>
│   └── Active -> continue
│
├── Is it being matched?
│   ├── /ip firewall filter print stats -> hit count zero? -> rule ordering issue (something earlier matched first)
│   └── Hit count growing -> continue
│
├── Is it doing the expected action?
│   ├── /ip firewall connection print and packet capture confirm
│   └── If not -> action / target wrong; revisit the rule
│
└── Is it surviving reboot?
    ├── /system backup load on the same device after reboot test
    └── If not -> change was made but NOT saved (rare, but possible if scripts use temporary structures)
```

### Common pitfalls

- Forgetting `comment=` on automation-driven rules; second run duplicates them.
- Using `add` repeatedly when `set` is the right verb (creates fresh items each time).
- Editing a config that lives in `/system scheduler` script body without versioning the script (loss on reboot if not exported).
- Adding a rule into a chain that does not exist; RouterOS does not error helpfully if the chain name has a typo.
- Enabling a service (`/ip service`) without restricting source addresses; routinely abused by scanners.
- Treating `/container` and `/app` as interchangeable; they are not; pick one per service.
- Running CHR on TCG without realising performance is unusable; switch to KVM / HVF.

## Severity table (operational findings)

| Finding | Severity | Rationale |
|---|---|---|
| Password / API key in `/system scheduler` script body | Critical | Visible to any read-only admin; rotate immediately. |
| `/ip service` enabled with no `address` restriction | High | Internet-exposed services are scanned within minutes. |
| Firewall input chain with no default drop | High | Anything not matched is permitted. |
| MNDP enabled on WAN interface | Medium | Information disclosure to internet scanners. |
| Container / app on default disk1 with no quota | Medium | Container can fill the device flash and brick it. |
| `/system backup` last >7 days ago | Medium | No restore point for a change. |
| Script without comment-as-tag pattern | Medium | Re-running duplicates rules; dangerous in CI. |
| CHR running on TCG (no KVM / HVF) | Low to Medium | Performance unusable; symptom looks like RouterOS bug. |
| Hotspot walled-garden missing CRL / OCSP / NTP destinations | Low | Captive portal can break for clients with strict cert validation. |
| RouterOS v6 in production (any) | Medium | EOL for new features; security patches limited; plan v7 migration. |

## Cross-references

- `multi-vendor-network-ops` -- umbrella; this skill is the MikroTik-specific specialist. Apply the nine-element response contract to every state-changing change.
- `bgp-analysis`, `igp-routing-analysis` -- when running BGP / OSPF on RouterOS; commands differ from Cisco / Junos but the protocol semantics are identical.
- `vpn-tunnel-troubleshooting` -- when configuring IPsec or WireGuard on RouterOS; the WireGuard interface in v7.4+ is straightforward; IPsec proposals match the multi-vendor patterns covered in that skill.
- `acl-rule-analysis` -- vendor-agnostic ACL methodology; RouterOS firewall is a first-class target.
- `linux-host-ops` -- when CHR sits on a KVM host you also operate, the host falls under linux-host-ops; the guest is RouterOS.
- `bash-defensive` -- RouterOS scripting is a quasi-shell; the same defensive idioms apply (quote variables, exit on error via `:do { } on-error={ }`).
- `secrets-hygiene` -- API tokens, RouterOS passwords, RADIUS shared secrets, CHR licences all fall under the patterns there. Never paste a `/export` containing `secret=` strings into a chat.
- `pyats-network-automation` -- pyATS does not have first-class RouterOS support (no Genie parser); use `mikrotik_api` Python client or community.routeros Ansible collection instead.
- `completion-gate` Layer 3 -- every state-changing change requires fresh post-check evidence (rule active, hit count growing, backup saved) before claiming "done".
- `plan-time-tooling` -- every state-changing recommendation fires `engineering:deploy-checklist` at plan time. Add the export-and-backup-first rule to that checklist for RouterOS work.
- `systematic-debugging` -- Phase 1 boundary evidence (which interface, which chain, which rule comment, which connection-tracking entry) before any change.
- `oncall-runbooks` -- incident classification when a RouterOS change escalates to a customer-impacting outage.

## Red flags (about-to-act warnings)

- About to push firewall changes without `/system backup save` and `/export show-sensitive` first.
- About to use `add` in a script without checking for an existing comment-tagged rule.
- About to enable `/container` device-mode on hardware in a maintenance-impacting way (physical reset required).
- About to upgrade RouterOS major version without testing the same upgrade on a CHR clone first.
- About to enable `/ip service` on www-ssl / api-ssl with no `address` restriction.
- About to delete a `/system scheduler` job without exporting its script first (script body is in the job; deleting the job loses it).
- About to push to a fleet via `mikrotik_api` without per-device error handling and a rollback path.
- About to flash a device with `netinstall-cli` over a flaky link (interrupted flash can brick the device).
- About to configure WireGuard on RouterOS by hand for a full mesh (use orchestration; see `vpn-tunnel-troubleshooting`).

## Reference (upstream skills folded into this body)

| Topic | Upstream | Use when |
|---|---|---|
| Fundamentals (CLI / REST / version model) | `tikoci/routeros-skills/routeros-fundamentals` | Onboarding to RouterOS; v7-vs-v6 reminders. |
| Async REST monitor endpoints | `tikoci/routeros-skills/routeros-fundamentals/references/async-commands-rest.md` | Three-mode duration / once / no-param semantics; `.section` string-indexing. |
| Device-mode (CLI side) | `tikoci/routeros-skills/routeros-fundamentals/references/device-mode.md` | Factory-default-per-device-type matrix; ROSE mode; full feature gating. |
| Device-mode (REST side) | `tikoci/routeros-skills/routeros-fundamentals/references/device-mode-rest.md` | Blocking-endpoint behaviour; activation-timeout range; HTTP 400 shapes; QEMU `system_reset`. |
| Extra packages | `tikoci/routeros-skills/routeros-fundamentals/references/extra-packages.md` | Per-package CLI surface for container, iot, zerotier, wifi-qcom, rose-storage, ups, gps, calea, tr069-client, user-manager. |
| CHR licensing (REST flow) | `tikoci/routeros-skills/routeros-fundamentals/references/licensing-rest.md` | `/system/license/renew` request / response shapes; ERROR prefix detection. |
| Packages (REST shape) | `tikoci/routeros-skills/routeros-fundamentals/references/packages-rest.md` | Package-object schema; `scheduled` enum; `numbers` POST pattern. |
| REST patterns (generic) | `tikoci/routeros-skills/routeros-fundamentals/references/rest-api-patterns.md` | Verb mapping; ID handling; auth shapes; common headers. |
| Firewall REST surface | `tikoci/routeros-skills/routeros-fundamentals/references/routeros-firewall-rest.md` | PUT-appends + place-before; no-move; boolean-as-string; `reject-with` enum; conntrack read-only. |
| Networking REST surface | `tikoci/routeros-skills/routeros-fundamentals/references/routeros-networking-rest.md` | Singleton vs list (`/ip/dns` object); DHCP defaults; classless-route option. |
| Users REST surface | `tikoci/routeros-skills/routeros-fundamentals/references/routeros-users-rest.md` | Self-disable no-op; expired flag scope; `rest-api` policy; password-with-SSH-key default. |
| RouterOS scripting language | `tikoci/routeros-skills/routeros-fundamentals/references/scripting.md` | `:if`, `:do`, `:execute`, `:parse`, `:serialize`; array `->` indexing; permissions table. |
| Version format / channels / upgrade endpoint | `tikoci/routeros-skills/routeros-fundamentals/references/version-parsing.md` | Full grammar; x86 naming exception; per-channel probe URL. |
| Firewall (filter, NAT, mangle, address-lists, idempotency) | `tikoci/routeros-skills/routeros-firewall` | Designing the rulebase. |
| DoS protection | `tikoci/routeros-skills/routeros-firewall/references/dos-protection.md` | Full `psd` decomposition; `connection-limit` netmask; tarpit mechanism; three-stage pipeline. |
| Mangle / policy-based routing | `tikoci/routeros-skills/routeros-firewall/references/mangle-routing.md` | `/routing/table/add fib`; DNS-exempt ordering; MSS-clamp; FastTrack interaction. |
| Schema introspection / REST mapping | `tikoci/routeros-skills/routeros-command-tree` | Mapping CLI to REST; node-type model; DANGEROUS_PATHS; `.proplist` / `.query`. |
| Container subsystem | `tikoci/routeros-skills/routeros-container` | Low-level OCI on RouterOS; device-mode setup; full `/container/add` property catalogue. |
| Declarative `/app` YAML | `tikoci/routeros-skills/routeros-app-yaml` | Building custom apps in v7.22+ YAML format; full top-level and service-property schemas. |
| `/app` YAML examples | `tikoci/routeros-skills/routeros-app-yaml/references/examples.md` | Minimal app; full-featured all-properties; store-file; port-format and placeholder examples. |
| Hotspot / captive portal | `tikoci/routeros-skills/routeros-hotspot` | Wizard plus deep RADIUS / Walled Garden / Option 114. |
| Hotspot RADIUS client | `tikoci/routeros-skills/routeros-hotspot/references/radius-client.md` | Multi-server fallback; disable-then-enable-after-files pattern; `[:resolve]` first-A-record trap. |
| Hotspot template variables | `tikoci/routeros-skills/routeros-hotspot/references/template-variables.md` | Full external-captive-portal HTML subsystem; `$(name)`, `$(if)`, `$(radius<id>)`, `$(http-header-X)`, `-esc` URL-escape. |
| Sniffer + TZSP | `tikoci/routeros-skills/routeros-sniffer` | Packet capture, live Wireshark streaming, full filter-property table. |
| TZSP receiver recipes | `tikoci/routeros-skills/routeros-sniffer/references/tzsp-receivers.md` | Wireshark / tshark / tcpdump on TZSP; port-conflict workaround; host firewall (ufw / iptables) rules. |
| MNDP wire format and discovery | `tikoci/routeros-skills/routeros-mndp` | Deep MNDP TLV format; protocol-level work; reference implementations. |
| Netinstall (device flashing) | `tikoci/routeros-skills/routeros-netinstall` | Bricked device recovery; bulk imaging; full 15-flag table; non-x86 host options. |
| CHR in QEMU | `tikoci/routeros-skills/routeros-qemu-chr` | Lab CHR builds; QEMU pattern catalogues; UEFI firmware sourcing. |
| CHR licensing (CLI side) | `tikoci/routeros-skills/routeros-qemu-chr/references/chr-licensing.md` | Trial flow; system-id-per-VM cloning issue; tier table. |
| CHR known issues | `tikoci/routeros-skills/routeros-qemu-chr/references/known-issues.md` | check-installation aarch64; cross-arch TCG evidence; pflash size-match; mktemp + trap race. |
| CHR VirtIO driver matrix | `tikoci/routeros-skills/routeros-qemu-chr/references/virtio-drivers.md` | Full per-arch driver presence; 9p, NVMe, E1000, Hyper-V, Xen, KVM_GUEST. |
| CHR on GitHub Actions | `tikoci/routeros-skills/routeros-qemu-chr/references/github-actions-ci.md` | KVM-enabled `ubuntu-latest`; VDI-to-QCOW2; sshpass `.npk` upload; concurrent-build rebase. |
| Multi-device API client | `drodecker/openclaw-mikrotik-routeros-skill/mikrotik-api` | Python client for status queries and viewing. |
| Syntax inspection / validation | `tikoci/routeros-skills/routeros-syntax-inspection` | `/console/inspect` probe selection (highlight / completion / syntax / child) and `:parse` IL; highlight token vocabulary; per-version crash and cap detail; the 913-script corpus evidence. |
| Scripting language traps | `tikoci/routeros-skills/routeros-scripting` | Full `.rsc` idioms and the trap catalogue distilled into Section 2; `[find]` selectors; `print as-value`; array semantics; script policies. |
| MAC-Telnet (L2 terminal) | `tikoci/routeros-skills/routeros-mac-telnet` | UDP 20561 wire format (22-byte header), session lifecycle, MD5 vs EC-SRP / MTWEI auth negotiation. |
| Disposable-CHR grounding | `tikoci/routeros-skills/routeros-quickchr` | `@tikoci/quickchr` TS / CLI wrapper to boot a throwaway CHR and run a command for runtime proof. |

## Bottom line

RouterOS is its own thing; do not assume Linux (no `/etc`, no shell, no `docker` CLI; do not `ssh admin@host 'ls /'`). Tag every script-driven rule with a unique `comment=` (the only safe path to idempotency). Always `/export` AND `/system backup save` before changes. Use `/console/inspect` to discover paths; on RouterOS <= 7.20.8 skip the DANGEROUS_PATHS list (`where`, `do`, `else`, `rule`, `command`, `on-error` deadlock the REST server via `syntax` / `completion`; fixed in 7.21.4), and remember inspect validity is necessary not sufficient (it accepts forms the runtime rejects, e.g. `blackhole=yes`). Over REST, **PUT creates, PATCH modifies, DELETE removes, POST is for actions**; the inspect-body path is COMMA-separated, not slash. Non-terminal firewall actions (`log`, `add-src-to-address-list`, `passthrough=yes`) keep evaluating; pair with a terminal rule. Pick `/container` (low-level) or `/app` (declarative) per service, never both; on 7.18+ run `/system/package/apply-changes` before any reboot or the upload is discarded. CHR runs on x86_64 AND aarch64 (UEFI; `if=virtio` is a trap on aarch64, use `virtio-blk-pci` long form); verify KVM / HVF acceleration is on AND host-guest arch match before blaming RouterOS. WireGuard on RouterOS v7.4+ is solid; for IPsec interop with non-MikroTik peers use `vpn-tunnel-troubleshooting` for the multi-vendor proposal-matching playbook.
