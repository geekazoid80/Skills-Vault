# Architecture and agent

## SaaS model

Action1 is a cloud-native SaaS platform: there is no on-premises management server, distribution point, or database to run. All console, policy, reporting, and patch-catalogue functions are hosted by Action1; the only thing in the customer environment is the agent. This removes the infrastructure and patching-the-patcher burden of legacy on-prem tools and lets the platform reach remote and roaming endpoints directly.

## The agent

A single lightweight, cloud-managed agent installs in under ten minutes and connects outbound:

- **Primary port:** 443 (HTTPS), so it works through standard outbound firewall policy.
- **Fallback port:** 22543.
- **No VPN required:** the agent reaches the cloud directly, so endpoints off the corporate network (laptops, home workers, cloud instances) are managed the same as on-net ones.

### Enrolment

Deploy the agent at scale through:

- **Active Directory integration** for domain-joined estates.
- **Group Policy (GPO)** to push the installer.
- **Third-party endpoint management tools** (existing RMM or deployment pipelines).

Treat any enrolment credential or token as a secret-store item (see `secrets-hygiene`).

## Platform support

Unified cross-platform patching from one console:

- **Windows** and **macOS** (long-standing).
- **Linux** native agent from the December 2025 release, covering Debian and Ubuntu (latest LTS versions) plus Red Hat-based distributions, with more versions planned.

This is the verified state as of the source date in the `.sources` provenance; Linux distro coverage is expanding, so confirm current support against the public documentation before committing to a specific distro.

## Peer-to-peer distribution

To avoid every endpoint pulling the same patch payload from the cloud over the WAN, Action1 supports peer-to-peer patch distribution: endpoints on a local segment share the payload among themselves. This cuts WAN bandwidth on patch days and is the main scale lever for sites with many endpoints behind a constrained link.

## Multi-organisation and access control

- **Multi-organisation:** an "Entire Enterprise" selector aggregates data across all organisations the user can access, for MSPs and multi-tenant enterprises.
- **Role-based access control (RBAC):** scope what each operator can see and do, per organisation.

## Licensing

The platform is free for the first 200 endpoints with full functionality (no feature gating on the free tier); paid tiers scale beyond that. The free tier makes it a common choice for small estates and for the test-and-evaluate stage of a larger rollout.
