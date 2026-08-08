---
name: linux-host-bringup
description: Use when bringing up a Linux server / VM / LXC / NUC for hosting (web service, reverse-proxied app, static site, monitoring agent), hardening an existing host, or reviewing one. Triggers include "set up a new VM for X", "bring up an LXC for Y", "harden this host", "add a domain to this server", "reverse-proxy this app", "issue an HTTPS cert", "open the firewall for Z", "switch this host to key-only SSH", "this NUC is a fresh install". Walks the phased workflow (intake, secure access, firewall, web server, hosting branch, HTTPS, validation, optional tuning) with hard safety gates between phases (do not change SSH auth in the only active session; do not issue certs before DNS resolves; do not force HTTP-to-HTTPS redirect before HTTPS works). Customised localised version of obra/superpowers/skills/secure-linux-web-hosting (originally xixu-me/skills); cross-references systematic-debugging for failures, plan-time-tooling for the deploy-checklist trigger, secrets-hygiene for SSH keys and ACME credentials.
metadata:
  version: 1.1.0
---

# Linux Host Bringup

> **Skill marker**: When applying this skill, begin your reply with `[skill: linux-host-bringup]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Turn a fresh Linux host into a safely reachable web host (or backend service host) without leaning on stale distro-specific memory or out-of-date tutorials. Phases are linear with explicit safety gates between them; skipping a gate is how operators lock themselves out or land a half-configured host that fails the first real request.

**Core principle:** verify current docs before commands, keep the phases in order, and treat the safety gates as hard stops. Do not collapse the static-site branch and the reverse-proxy branch into one default answer.

## Initial Assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the host's role (static site, reverse proxy, backend service), DNS posture, and the user's current SSH access state before commanding the host. Only ask the user for information not already covered or specific to this bringup.

Before commanding the host, understand:

1. **Host and distro**
   - Distro family (Debian / Ubuntu / RHEL / Alma / Rocky / Arch / others) and image name?
   - Cloud provider, on-prem hardware, or LXC / VM tenant?
   - Disk and memory layout sufficient for the workload?

2. **Access posture**
   - Root, admin user, or single live SSH session only?
   - Out-of-band recovery path if SSH is lost (console, cloud rescue, IPMI)?
   - Existing keys versus password auth?

3. **Service intent**
   - Static site, reverse-proxied app, or backend-only (no public HTTP)?
   - DNS already pointed at the host, or to-be-cut-over?
   - TLS plan (Let's Encrypt ACME, manual cert, mTLS)?

---

## When to use

- A cloud server, VM, droplet, or fresh LXC that the user wants to use for hosting.
- A NUC or other on-prem Linux host being commissioned for a service.
- Connecting a domain or DNS A / AAAA record to a host.
- SSH login, SSH hardening, root login, key rollout, port change, firewall setup.
- Installing or configuring nginx / Caddy for a website or as a reverse proxy.
- Putting a small app behind a reverse proxy.
- HTTPS issuance via Let's Encrypt or another ACME client; cert renewal; HTTP-to-HTTPS redirect.
- Optional post-launch tuning (BBR, sysctl, etc.).

Do NOT use this skill for:

- Kubernetes, container orchestrators, or PaaS deployment design.
- Application-specific build / CI / CD questions where the Linux side is incidental.
- Windows or macOS host administration.
- Public multi-tenant production architecture reviews (those need a wider SRE / platform-design treatment).

## The phased workflow

Phases run in this order unless the user is explicitly asking for review or remediation of an existing setup. Each phase has a safety gate; do not advance past it without satisfying the gate.

### 1. Intake and classify the current state

Identify before doing anything:

- Distro family (Debian / Ubuntu / RHEL / Alma / Rocky / Arch / etc.) and image name. If unknown, have the user inspect `/etc/os-release` or run `cat /etc/os-release` themselves.
- Whether the user has root access, an admin user, or only one live SSH session.
- Whether DNS already points at the host.
- Whether the goal is a static site, a reverse-proxied app, or a backend-only service (no public HTTP).
- Whether ports are already exposed.
- Whether HTTPS is already partially configured.

**Safety gate:** if the distro is unknown, do NOT issue distro-specific commands. Ask for it.

### 2. Verify current docs before actionable commands

Use bundled or remembered references to ROUTE the work. Verify the current commands against live official documentation before issuing them.

Always re-verify:

- Package manager commands and package names (`apt`, `dnf`, `yum`, `pacman`, `apk`).
- Firewall tooling and service names (`ufw`, `firewalld`, `nftables`).
- SSH service unit names and config include paths.
- Web server package and config layout (nginx vs Caddy vs Apache).
- The chosen ACME client's current instructions (Certbot, `acme.sh`, `lego`).

Distro family drives all three of those, so establish the family before the first command:

| Family | Package manager | Firewall | SSH unit | Watch out for |
|---|---|---|---|---|
| Debian / Ubuntu | `apt` | `ufw` (or `nftables`) | commonly `ssh` | `systemctl restart sshd` fails on a stock install |
| Fedora / RHEL / Rocky / Alma | `dnf` | `firewalld` | commonly `sshd` | SELinux contexts on web roots |
| Arch | `pacman` | user-chosen, often absent by default | commonly `sshd` | services are not auto-enabled after install |
| Unknown | stop and verify | stop and verify | stop and verify | do not guess from a tutorial |

The `ssh` versus `sshd` unit-name split is the one that bites most often: the same command is correct on one family and a no-op error on another.

If you cannot verify a detail, say so and give high-level guidance instead of repeating an old Debian-10 tutorial path as universal.

### 3. Secure access (the critical safety gate)

Before any SSH hardening change, ALWAYS:

1. Confirm key-based login works in a SECOND, FRESH SSH session.
2. Keep the original session open until the second session has been validated.
3. Only then disable password auth, change SSH port, or disable root login.

**Safety gate:** never recommend SSH hardening (port change, password disable, root disable) until key-based login is proven from a separate session. Locking yourself out of a fresh box is the most common preventable failure in this workflow.

**Validate before you reload.** Never reload or restart sshd on an unvalidated config. Run the config test first (`sshd -t`, or `sshd -T` to dump the effective config), reload only if the test passed, then prove the result in a fresh session before closing the original one. A reload on a config with a typo is exactly the lockout the safety gate above exists to prevent, and the test costs nothing.

Cross-reference: SSH key handling and ACME client credentials follow `secrets-hygiene` (real key material lives in gitignored files and the secret store; tracked sample templates only).

### 4. Firewall and exposure

Default deny inbound. Open only what is needed:

- Port 22 (or the chosen SSH port) from a sane source set.
- Port 80 (HTTP) for ACME challenge plus the HTTP-to-HTTPS redirect.
- Port 443 (HTTPS) for the live site.
- Internal app ports stay on loopback / a private interface; the reverse proxy fronts them.

Do NOT open the application's internal port (e.g. `:3000`, `:8080`) directly to the internet. The reverse proxy handles that mapping.

**Safety gate:** the application listener should bind to `127.0.0.1` (or the private interface), never `0.0.0.0`, before the firewall is loosened. If the listener is on `0.0.0.0`, change it first. Check what is actually listening with `ss -tulpn` rather than assuming the app honoured its config.

**Two firewall layers, not one.** A cloud VM or LXC tenant usually sits behind a provider-edge filter (AWS security group, DigitalOcean or Hetzner cloud firewall, the LXC host's bridge rules) as well as its own host firewall. Both have to allow the traffic. Opening 443 on the host and finding the port still unreachable from outside almost always means the edge was never opened. State which layer you changed, and confirm the other one separately.

### 5. Web server setup

Install the chosen web server (nginx / Caddy / Apache). Confirm the service is enabled and starts cleanly. Verify the default page loads via `curl` from the host AND from a remote machine.

Same validate-before-reload discipline as sshd, and in this fixed order: syntax check, reload only on a pass, check locally on the host, then check remotely. For nginx that is `nginx -t` before `systemctl reload nginx`; Caddy and Apache have their own equivalents (`caddy validate`, `apachectl configtest`). Reloading a web server on a broken config drops the running site, and the syntax check would have caught it.

### 6. Hosting branch

Pick ONE branch. Do not collapse them.

#### Static site

- Files served from a single document root.
- Owned by an unprivileged user; readable by the web server's user.
- SELinux / AppArmor: ensure the web server can read the document root (different defaults across distros).
- No application stack involved.

#### Reverse-proxied app

- App listens on loopback or a private interface.
- Reverse proxy maps a public URL to the app's port.
- WebSocket support if the app uses it (`proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";`).
- Forwarded headers configured so the app sees the real client IP and protocol.

### 7. HTTPS

Only after the HTTP site or proxy path works AND DNS resolves to this host:

1. Issue the certificate via the ACME client.
2. Verify the cert chain and date validity.
3. Configure the web server to serve HTTPS with the new cert.
4. Verify HTTPS loads cleanly from a remote browser.
5. Only THEN add the HTTP-to-HTTPS redirect.

**Safety gate:** never force the HTTP-to-HTTPS redirect until HTTPS itself loads cleanly. A broken redirect plus a broken HTTPS leaves the site dark.

### 8. Validation

End-to-end verification before declaring the host done:

- DNS resolves correctly from a third-party resolver (`dig +trace` or `dig @1.1.1.1`).
- TLS chain validates (`openssl s_client -connect host:443 -servername host </dev/null`).
- HTTP redirects to HTTPS without loops.
- Service is reachable from off-host (a phone on cellular, a remote `curl`).
- The web server's access log records the validation requests.
- Service-specific health endpoint (if any) returns a 200.

Use `completion-gate` Layer 3 for the verification claim. No "done" without a fresh validation result in this turn.

### 9. Optional advanced tuning

After the host is working, NOT before:

- BBR or other TCP congestion-control changes.
- HTTP/3 / QUIC.
- Tighter sysctl tuning (file descriptor limits, somaxconn, etc.).
- Kernel security hardening (sysctl `net.ipv4.conf.all.rp_filter`, etc.).

Each of these is a separate small change with its own validation step. Do not bundle.

## Local-machine vs server actions

Always distinguish:

- **Local machine:** SSH session, DNS lookup, browser test, certificate inspection.
- **Server:** package install, config edit, service reload, firewall rule.

When giving instructions to the user, split them into two parallel columns or label each command with where it runs. The class of bug "I ran `systemctl restart nginx` on my laptop" is preventable.

## Output expectations

For a fresh setup, provide:

- A brief diagnosis of the current state.
- The current phase and why it comes next.
- Local-machine steps separate from server steps.
- Concrete commands or config snippets only AFTER doc verification.
- A verification step after each risky change.
- A short "if this fails, check X" branch for the likely mistake at that phase.

For a hardening or troubleshooting review, provide:

- The most likely risk or breakage first (use `systematic-debugging` Phase 1 evidence-gathering).
- A prioritised remediation sequence.
- The first safe verification step before the next config change.

## Cross-references

- `systematic-debugging`: when the host won't boot, the cron didn't fire, the service crashes, or the firewall is dropping packets. Phase 1 evidence-gathering at every component boundary maps onto this skill's phases (DNS, TLS, web server, app, system).
- `plan-time-tooling`: an LXC bring-up or first deploy of a new module is a mandatory `engineering:deploy-checklist` trigger. Run it BEFORE the implementation sub-agent is briefed; output goes to `docs/runbooks/<host>.md`.
- `secrets-hygiene`: SSH keys, ACME account material, and any per-deployment credentials live in gitignored files plus the secret store. Real key material never lands in tracked artefacts.
- `completion-gate` Layer 3: the validation in Phase 8 IS the completion-gate evidence. Do not claim the host is up without running it in this turn.

## Common mistakes

- Treating Debian-specific commands from an old article as Linux-universal.
- Hardening SSH in the ONLY active session and locking yourself out.
- Opening application ports directly to the internet instead of keeping the app on loopback.
- Mixing static-file hosting guidance and reverse-proxy guidance in one nginx config.
- Attempting ACME issuance before DNS or HTTP is actually correct.
- Forcing the HTTP-to-HTTPS redirect before HTTPS is proven.
- Treating BBR or sysctl tuning as part of the core setup instead of an optional later step.
- Ignoring SELinux or AppArmor differences when nginx can read files on Debian but not on RHEL.
- Issuing the cert before DNS propagates (HTTP-01 challenge fails; rate-limit consequences from the CA).
- Reloading sshd or the web server without running the config syntax check first.
- Opening a port on the host firewall and forgetting the provider-edge filter in front of it, then debugging the wrong layer.
- Using `systemctl restart sshd` on Debian or Ubuntu, where the unit is `ssh`.

## Red flags

- About to recommend an SSH hardening change without confirming a second session works.
- About to issue a cert without DNS verification.
- About to add a forced HTTPS redirect before HTTPS is loading cleanly.
- App listener on `0.0.0.0` and firewall about to be loosened.
- About to reload sshd or the web server without a passing config syntax check.
- "The port is open but it is still unreachable" without having checked the provider-edge filter as a separate layer.
- "BBR will fix the latency" before basic hosting is proven.
- "Just disable SELinux" as a workaround for a denied read.
- Recommending Debian commands when the host is actually RHEL.

## Bottom line

Phases run in order. Safety gates are hard stops, not suggestions. Verify docs before commands. Validate end-to-end before declaring done. Optional tuning waits until the basics work.
