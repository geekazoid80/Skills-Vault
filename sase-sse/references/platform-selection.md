# SASE / SSE platform selection

Vendor-neutral selection guidance. This reference decides which platform earns the deployment; per-vendor configuration lives in `zscaler`, `prisma-access`, and `fortisase`.

## The load-bearing decision: single-vendor versus best-of-breed

Every other choice follows from this one.

- **Single-vendor SASE** builds SD-WAN and SSE as one platform: one agent, one policy model, one console. It is simplest to operate and gives consistent policy end to end. The trade-off is coupling: you take that vendor's view of every component, strong or weak.
- **Best-of-breed** pairs a separate SD-WAN vendor with a separate security (SSE) vendor. It lets you pick the strongest component in each category, at the cost of integration work and a dual management plane. Budget for both explicitly; the integration cost is the part most often underestimated.

A useful default: if the estate is greenfield or mid-size and values operational simplicity, lean single-vendor. If it already has a strong incumbent SD-WAN or a security team that wants best-in-class components and can run the integration, lean best-of-breed SSE.

## Selection criteria

Weigh the platform against the estate, not against a feature checklist:

1. **The problem first.** Internet access (SWG-led), private-app access (ZTNA-led), SaaS control (CASB-led), or full transformation (SASE). Vendors have heritage: some are proxy/SWG-first, some firewall-first, some CASB-first. Match the heritage to the primary problem.
2. **PoP footprint and latency.** The user-to-PoP distance sets the experience. Check for PoPs in the metros where users actually are, and for direct peering with the cloud and SaaS the estate uses.
3. **Identity and posture integration.** How cleanly the platform consumes the existing IdP (SAML/OIDC) and device-posture source (MDM, EDR). Zero trust is identity-first; a weak IdP integration undercuts the whole deployment.
4. **ZTNA depth.** Whether the ZTNA is connect-then-trust (1.0) or continuous, per-request, all-port (2.0), and whether it supports the legacy protocols (SSH, RDP, thick-client TCP) the estate still needs.
5. **SD-WAN story.** Native (single-vendor) or integration with an incumbent. Relevant only if WAN convergence is in scope.
6. **Operating model and skills.** The console the team will live in, the policy model they must learn, and whether it fits the existing firewall or proxy skill set.
7. **Data residency and compliance.** Where inspection happens, and whether the PoP map and data handling satisfy the estate's jurisdiction and framework obligations.

## Platform side-by-side

Heritage and typical fit. Deep per-vendor coverage in this vault exists for the first three; the rest are routing context.

| Platform | Heritage / strength | Typical fit | Vault skill |
|---|---|---|---|
| Zscaler Zero Trust Exchange | Cloud proxy / SWG-first; large PoP footprint; ZIA (internet), ZPA (private), ZDX (experience) | Internet-access-led SSE, large distributed workforce | `zscaler` |
| Palo Alto Prisma Access | Firewall-first (PAN-OS); ZTNA 2.0, FWaaS, ADEM; Panorama/Strata management | Estates standardised on Palo Alto, ZTNA-2.0 requirements | `prisma-access` |
| Fortinet FortiSASE | Firewall/SD-WAN-first (FortiGate); FortiClient agent; tight SD-WAN convergence | Fortinet estates wanting single-vendor SASE with SD-WAN | `fortisase` |
| Netskope One | CASB-first; strong inline and API CASB, DLP, UEBA | SaaS-governance-led SSE | routing context |
| Cloudflare Zero Trust | Network/edge-first; Access (ZTNA), Gateway (SWG/DNS), very large edge, free tier | Fast ZTNA adoption, edge-heavy or cost-sensitive estates | routing context |
| Cato Networks | Purpose-built single-vendor SASE (SD-WAN and SSE from the ground up) | Estates wanting one converged platform and one console | routing context |

### PoP footprint (approximate, as published around 2024)

PoP counts change often; treat these as an order-of-magnitude guide and confirm against the vendor's current figures at selection time (see the cite-sources discipline).

- Cloudflare: 300+ cities.
- Zscaler: 150+ data centres.
- Palo Alto Prisma Access: 110+ PoPs.
- Cato Networks: 80+ PoPs.
- Netskope: 75+ PoPs.

## Decision guidance

- **Internet access is the priority**: lean to a proxy/SWG-first platform with a large PoP footprint.
- **Replacing VPN for private apps is the priority**: lead with ZTNA depth (insist on continuous, per-request, all-port verification) and check legacy-protocol support.
- **SaaS governance is the priority**: lead with CASB depth (inline plus API, strong DLP and UEBA).
- **Full network-and-security convergence with an existing firewall/SD-WAN estate**: a single-vendor SASE that matches the incumbent lowers operational cost.
- **A strong incumbent SD-WAN plus a security team that wants best-in-class**: best-of-breed SSE, with the integration cost budgeted.

Do not choose on brand familiarity or a feature checklist. Choose on the primary problem, the PoP-to-user map, the identity and posture integration, and the operating model the team will actually run. Then route the configuration to `zscaler`, `prisma-access`, or `fortisase`.
