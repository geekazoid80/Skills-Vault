---
name: action1-patch-management
description: Use for Action1 cloud-native patch management and autonomous endpoint management configuration and operations. Covers the SaaS architecture and the lightweight cloud-managed agent (port 443 with 22543 fallback, no VPN or on-premises server, install in under ten minutes), agent enrolment (Active Directory integration, GPO, third-party deployment tools), cross-platform OS patching (Windows, macOS, and Linux native agent from the December 2025 release covering Debian and Ubuntu LTS plus Red Hat-based distributions), third-party application patching from the software repository of pre-configured packages, peer-to-peer patch distribution, policy-based automation (approval workflows, scheduling, maintenance windows, reboot control), time-based update rings for staged rollout, built-in vulnerability intelligence (missing patches correlated to CVEs with CVSS scores, CISA KEV flags, and active-ransomware-campaign indicators), compliance reporting (predefined templates plus custom reports from any PowerShell-scriptable source), multi-organisation Entire Enterprise aggregation, role-based access control, remote script execution with optional PowerShell signing enforcement, and the always-free 200-endpoint tier with full functionality. References architecture-and-agent.md, patching-and-automation.md, vulnerability-and-reporting.md. Triggers include "Action1", "Action1 patch management", "Action1 agent", "cloud patch management", "autonomous endpoint management", "third-party patching", "patch automation policy", "update rings", "peer-to-peer patch distribution", "200 free endpoints", "patch deployment", "missing patches", "patch compliance reporting". For the vendor-neutral VM programme that decides what to patch and the SLA see vulnerability-management; for the CVE behind a missing patch see nvd-cve; for endpoint threat detection see endpoint-detection-response; for the compliance frameworks patch management evidences see compliance-benchmark-audit; for agent-enrolment credential and PowerShell-signing handling see secrets-hygiene.
license: MIT
metadata:
  version: 1.0.0
---

# Action1 patch management

> **Skill marker**: When applying this skill, begin your reply with `[skill: action1-patch-management]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This skill builds and operates Action1, a cloud-native patch management and autonomous endpoint management platform. It is the deployment end of vulnerability management: where `vulnerability-management` decides what to patch and by when, Action1 deploys the patch and verifies it. It is authored from Action1's public documentation (no upstream skill); see the `.sources` provenance for cited sources and the verification date.

## When to use

- Deploying and enrolling the Action1 agent (AD, GPO, third-party tools).
- Configuring patch automation: approval workflows, scheduling, maintenance windows, reboot control.
- Designing time-based update rings for staged rollout (test group to production).
- Patching third-party applications from the software repository.
- Reading Action1's built-in vulnerability intelligence (CVE/CVSS/KEV/ransomware indicators).
- Building compliance and patch-status reports; using multi-organisation aggregation.
- Running remote actions and scripts across the estate.

## When not to use

- **Deciding what to patch first and the SLA** (KEV/EPSS/CVSS prioritisation, exception process, asset criticality): use `vulnerability-management`. Action1 reports missing patches and deploys them; the prioritisation strategy is the umbrella's.
- **The standalone CVE lookup**: use `nvd-cve`.
- **Endpoint threat detection and response** (behavioural detection, EDR/XDR): use `endpoint-detection-response`. Action1 manages patches, not threat detection.
- **A different patch or VM tool**: the commercial scanners (`tenable-vulnerability-management`, `qualys-vulnerability-management`, `rapid7-vulnerability-management`) have their own patch and remediation integrations.

## Classify the request first

| Class | Examples | Where the depth lives |
|---|---|---|
| Architecture + agent | SaaS model, the cloud-managed agent and ports, enrolment methods, platform support, peer-to-peer distribution, multi-org, RBAC, the free tier | `references/architecture-and-agent.md` |
| Patching + automation | automation policies (approval, scheduling, maintenance windows, reboot), update rings, third-party app patching, the software repository, software deployment | `references/patching-and-automation.md` |
| Vulnerability + reporting | the built-in CVE/CVSS/KEV/ransomware intelligence, compliance and custom reporting, remote script execution, multi-organisation aggregation | `references/vulnerability-and-reporting.md` |

## Core model (condensed)

**Cloud-native, agent-based, no on-premises footprint.** Action1 is SaaS: a lightweight cloud-managed agent installs in under ten minutes, connects outbound on 443 (22543 fallback), and needs no VPN or on-prem server. That removes the management-server and connectivity burden of legacy patch tools and reaches remote and roaming endpoints directly.

**Automate, then stage with rings.** The point of the platform is autonomous patching: policy-based automations handle approval, scheduling, and maintenance windows so patches deploy without manual touch. Stage the risk with time-based update rings ("first successfully deployed X days ago"), so a patch proves itself on a test ring before it reaches production. Control reboots explicitly; an uncoordinated reboot is the most common patch-deployment incident.

**Patch the OS and the third-party apps together.** Cross-platform OS patching (Windows, macOS, and Linux from the December 2025 release: Debian and Ubuntu LTS plus Red Hat-based) and third-party application patching from a pre-configured software repository run from one console. Third-party apps (browsers, runtimes, productivity tools) are where much of the real exploited surface lives, so patching them matters as much as the OS.

**Patching is vulnerability-aware.** Missing patches are correlated to known CVEs with CVSS scores, CISA KEV flags, and indicators for vulnerabilities tied to active ransomware campaigns, so the deployment queue can be driven by real risk. This is deployment-side intelligence; the programme-level prioritisation and SLA reasoning lives in `vulnerability-management`, and Action1 is the "patch" remediation option that programme calls for.

**Peer-to-peer distribution and scale.** Peer-to-peer patch distribution lets endpoints share patch payloads on a local segment rather than each pulling from the cloud, cutting WAN bandwidth. Multi-organisation support (the Entire Enterprise selector) aggregates across tenants, and the platform is free for the first 200 endpoints with full functionality.

## Reference router

| Need | Load |
|---|---|
| SaaS architecture, the cloud-managed agent and ports, enrolment (AD/GPO/third-party), platform support, peer-to-peer distribution, multi-org, RBAC, the free tier | `references/architecture-and-agent.md` |
| Automation policies (approval, scheduling, maintenance windows, reboot control), time-based update rings, third-party app patching, the software repository, software deployment | `references/patching-and-automation.md` |
| Built-in vulnerability intelligence (CVE/CVSS/KEV/ransomware), compliance and custom reporting, remote script execution with PowerShell signing, multi-organisation aggregation | `references/vulnerability-and-reporting.md` |

## Cross-references

- `vulnerability-management`: the VM programme that decides what to patch and the SLA; Action1 is the "patch" remediation that fulfils it, and reports missing patches back. Reciprocal reference.
- `nvd-cve`: the CVE detail behind a missing patch Action1 flags.
- `endpoint-detection-response`: EDR detects threats and reports patch posture; Action1 owns the patch deployment.
- `compliance-benchmark-audit`: patch management and timely remediation are controls that frameworks (PCI, NIST, CIS) test; Action1's compliance reports are evidence.
- `secrets-hygiene`: agent-enrolment credentials, RBAC roles, and PowerShell script-signing keys live in the secret store, never inline.

## Red flags

- About to deploy patches estate-wide with no update-ring staging (a bad patch hits production with no test ring ahead of it).
- About to automate patching with no reboot control or maintenance window (uncoordinated reboots during business hours).
- About to treat Action1's CVE intelligence as the whole prioritisation strategy instead of routing programme decisions to `vulnerability-management`.
- About to patch the OS but leave third-party applications (browsers, runtimes) unpatched.
- About to enable remote script execution without PowerShell signing enforcement on a sensitive estate.
- About to store an agent-enrolment credential or signing key inline instead of the secret store.

## Bottom line

Action1 is cloud-native, agent-based patch management with no on-prem footprint: enrol the agent, automate approval and scheduling, and stage deployments through time-based update rings with explicit reboot control. Patch the OS and third-party apps together, and let the built-in CVE/CVSS/KEV/ransomware intelligence order the queue, while routing programme-level prioritisation and SLAs to `vulnerability-management`. Keep enrolment credentials and signing keys in the secret store.
