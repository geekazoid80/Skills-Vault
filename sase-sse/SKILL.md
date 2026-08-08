---
name: sase-sse
description: Use for vendor-neutral SASE (Secure Access Service Edge) and SSE (Security Service Edge) DESIGN, zero-trust and ZTNA architecture and maturity assessment, and platform selection. Covers the Gartner SASE model (SD-WAN plus SSE) and the SSE subset (SWG, CASB, ZTNA, FWaaS, DNS security, RBI, DLP, UEBA), NIST SP 800-207 zero-trust architecture (the seven tenets, the Policy Engine / Policy Administrator / Policy Enforcement Point model), Forrester ZTX, ZTNA versus VPN, ZTNA 1.0 versus 2.0, the Software-Defined Perimeter (SDP) and Single Packet Authorization (SPA), micro-segmentation, SSL/TLS inspection design, PoP and traffic-steering choices (agent, GRE/IPsec, PAC, DNS), single-pass architecture, a five-pillar by five-level zero-trust maturity model (Identity, Device, Network, Application, Data across Traditional to Adaptive) with a scoring method and assessment methodology, compliance mapping (NIST 800-207, CIS v8, ISO 27001, OMB M-22-09, CISA Zero Trust Maturity Model), and which platform to choose (Zscaler versus Prisma Access versus FortiSASE versus Netskope, Cloudflare, Cato). The organising idea is design-and-assess-then-select. References concepts.md, zero-trust-and-ztna.md, platform-selection.md. Triggers include "SASE", "SSE", "secure access service edge", "security service edge", "zero trust", "ZTNA", "zero trust network access", "SWG", "secure web gateway", "CASB", "FWaaS", "firewall as a service", "RBI", "remote browser isolation", "NIST 800-207", "zero trust maturity", "zero trust assessment", "replace VPN", "VPN to ZTNA migration", "SDP", "single packet authorization", "micro-segmentation", "SSL inspection", "single-pass", "SASE PoP", "SASE vs SSE", "which SASE", "Zscaler vs Prisma Access", "SASE platform comparison". For per-vendor configuration and operations see zscaler, prisma-access, and fortisase. For zero-trust IDENTITY governance (IdP, MFA, conditional access, PAM, IGA) see identity-access-management; for VPN tunnel troubleshooting see vpn-tunnel-troubleshooting; for endpoint posture signals see endpoint-detection-response; for network detection, NAC, and micro-segmentation enforcement/forensics see network-detection-response; for email security (which SASE DLP routes out) see proofpoint-essentials. Netskope, Cloudflare Zero Trust, and Cato are named here as routing context; deep per-vendor depth for those is not yet in this vault.
license: MIT
metadata:
  version: 1.0.0
---

# SASE / SSE

> **Skill marker**: When applying this skill, begin your reply with `[skill: sase-sse]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

This is the vendor-neutral entry point for Secure Access Service Edge (SASE), Security Service Edge (SSE), and the zero-trust architecture that underpins them. It owns the reasoning that survives any one product: what zero trust actually requires (NIST SP 800-207), how the SSE components fit together (SWG, CASB, ZTNA, FWaaS, and their siblings), how to assess a zero-trust posture and build a roadmap, and which platform earns the deployment. Platform-specific configuration lives in the per-vendor skills; the depth here is the design and the assessment that outlast a platform change.

## Initial assessment

If a `CLAUDE.md` or `AGENTS.md` exists in the working directory, read it first to understand the estate (existing SD-WAN, IdP, EDR, current remote-access model, cloud footprint, compliance drivers) before advising. Only ask the user for information not already covered.

Before designing or selecting, understand:

1. **The problem being solved.** Internet-access security (SWG, DNS, cloud firewall), private-application access (ZTNA, replacing VPN), SaaS security (CASB, inline versus API), data protection (DLP), or a full network-and-security transformation (SASE with SD-WAN). SASE is a convergence story; most estates adopt one pillar first.
2. **The starting posture.** Perimeter firewall plus VPN, or partial cloud-proxy adoption already. The zero-trust maturity model in `references/zero-trust-and-ztna.md` gives a five-pillar baseline.
3. **The identity and device substrate.** Zero trust depends entirely on a strong IdP and a device-posture signal. If those are weak, they are the first pillar to fix, not the network.
4. **The operating model.** Single-vendor SASE (one console, one agent) versus best-of-breed SSE plus a separate SD-WAN. This is the load-bearing selection decision.

## When to use

- Designing a SASE or SSE architecture, or choosing between SASE and SSE-only adoption.
- Assessing a zero-trust posture and building a prioritised remediation roadmap.
- Planning a VPN-to-ZTNA migration.
- Comparing SASE/SSE platforms for a selection decision.
- Reasoning about an SSE component (SWG, CASB, ZTNA, FWaaS, DNS security, RBI) at the design level.

## When not to use

- **Configuring a specific platform** (the exact Zscaler ZIA/ZPA policy, Prisma Access template, or FortiSASE profile): use `zscaler`, `prisma-access`, or `fortisase`. This umbrella decides whether the platform fits and how the architecture should look; those own the configuration and operations.
- **Zero-trust IDENTITY governance** (IdP selection, MFA rollout, conditional access, privileged access management, identity governance): use `identity-access-management`. The Identity pillar of the maturity model here routes there for depth; this skill owns the network-access side of zero trust, not the identity platform.
- **Troubleshooting an existing VPN tunnel** (IPsec phase-1/phase-2, SSL-VPN client faults): use `vpn-tunnel-troubleshooting`. This skill owns the ZTNA-as-VPN-replacement architecture, not tunnel debugging.
- **Endpoint posture and EDR** (the device-health signal a ZTNA policy consumes): use `endpoint-detection-response`.
- **Network detection, NAC (802.1X), and micro-segmentation enforcement or forensics**: use `network-detection-response`. This skill owns the ZTNA/SASE design; NDR owns the detection and the on-network enforcement.
- **Email security and email DLP**: use `proofpoint-essentials` (and the enterprise and Microsoft-native email skills). SASE DLP here covers web and SaaS egress; email is a separate control point.
- **Deep Netskope, Cloudflare Zero Trust, or Cato configuration**: named here as routing context only; deep per-vendor depth for those is not yet in this vault.

## The model in brief

**Zero trust (NIST SP 800-207)** grants no implicit trust based on network location. Every request is verified against dynamic policy using identity, device posture, and context; access is per-session and per-resource; the enterprise monitors posture continuously. The logical model is a Policy Engine that decides, a Policy Administrator that issues and revokes session credentials, and a Policy Enforcement Point that sits inline and enforces.

**SASE (Gartner)** is the convergence of WAN edge (SD-WAN) and cloud-delivered security (SSE) as a single service. **SSE** is the security-only subset, for estates not ready to consolidate SD-WAN:

```
SASE = SSE + SD-WAN
SSE  = SWG + CASB + ZTNA + FWaaS + DNS security + RBI + DLP + UEBA
```

**The SSE components**, at a glance (design depth in `references/concepts.md`):

| Component | Owns | Primary use case |
|---|---|---|
| SWG | Internet-bound web traffic: URL filtering, TLS inspection, malware scan, app control | Safe internet access |
| CASB | SaaS visibility and control, inline and API | SaaS governance, shadow-IT discovery |
| ZTNA | Identity-aware, app-level access to private resources | Replace VPN for private apps |
| FWaaS | Cloud-delivered L7 firewall, IPS, threat prevention | Consistent firewall without appliances |
| DNS security | Blocking at the DNS layer | Lightweight first line, IoT coverage |
| RBI | Rendering risky sites in an isolated remote browser | High-risk browsing, uncategorised sites |

**ZTNA versus VPN** is the pivotal shift: a VPN extends the trusted network (lateral movement follows a breach); ZTNA grants access to a named application only, verifies every request, and never exposes the network. Full comparison and the ZTNA 1.0 versus 2.0 distinction are in `references/zero-trust-and-ztna.md`.

## Assessing zero-trust maturity

Score five pillars (Identity, Device, Network, Application, Data) across five levels (Traditional, Initial, Advanced, Optimal, Adaptive). The **overall posture is the lowest pillar**, not the average: a Level 4 network with Level 1 identity is only as strong as the identity. Report both the lowest-pillar score (true posture) and a weighted average (progress trajectory). Remediate the lowest pillar first, and sequence foundational pillars (Identity, Network) ahead of dependent ones (Application, Data). The full scoring matrix, both calculation methods, and the four-phase assessment methodology are in `references/zero-trust-and-ztna.md`.

## Choosing a platform

The load-bearing decision is single-vendor SASE versus best-of-breed SSE plus separate SD-WAN. Then match the traffic profile and the estate to the platform. Summary guidance and a side-by-side (Zscaler, Prisma Access, FortiSASE, Netskope, Cloudflare, Cato) are in `references/platform-selection.md`; per-vendor configuration is in `zscaler`, `prisma-access`, and `fortisase`.

## Cross-references

- `zscaler`: Zscaler Zero Trust Exchange operations (ZIA internet access, ZPA private access, ZDX digital experience). This umbrella decides whether Zscaler fits; that skill builds it.
- `prisma-access`: Palo Alto Prisma Access / SASE operations (ZTNA 2.0, FWaaS, ADEM).
- `fortisase`: Fortinet FortiSASE operations (FortiClient, secure private access, SD-WAN convergence).
- `identity-access-management`: the identity substrate zero trust depends on (IdP, MFA, conditional access, PAM, IGA). The Identity pillar routes here.
- `vpn-tunnel-troubleshooting`: IPsec and SSL-VPN tunnel diagnosis. This skill owns the migration away from VPN; that owns the tunnel while it exists.
- `endpoint-detection-response`: the device-posture and EDR signal a ZTNA policy consumes (Device pillar).
- `network-detection-response`: NAC (802.1X), on-network micro-segmentation enforcement, and network forensics (Network pillar).
- `proofpoint-essentials`: email security, the control point SASE DLP routes email out to.
- `secrets-hygiene`: SASE and IdP integration uses API tokens and certificates; treat them as schema, never store a live value.

## Red flags

- Buying SASE to "do zero trust" while identity stays single-factor and there is no device-posture signal. Zero trust is identity-first; the network layer cannot compensate.
- Deploying ZTNA but leaving the old VPN as a full-network fallback for everyone. That preserves the lateral-movement path the migration was meant to remove.
- Enabling SSL/TLS inspection without a plan for the inspection CA, the bypass list (banking, medical, government, certificate-pinned apps), or the privacy implications.
- Calling a product "ZTNA" and assuming continuous verification: many are ZTNA 1.0 (connect-then-trust). Verify whether trust is re-evaluated within the session.
- Scoring maturity by averaging pillars and reporting a comfortable number while the lowest pillar is Level 1.
- Choosing best-of-breed SSE plus a separate SD-WAN without budgeting for the dual management plane and the integration work.
- Backhauling cloud-bound traffic through a data-centre firewall after adopting a cloud security stack, negating the latency and scale benefits.

## Reference files

- `references/concepts.md`: NIST 800-207 logical model and product mapping, SASE/SSE architecture, the SSE components in depth (SWG, CASB inline and API, ZTNA, FWaaS), SDP and Single Packet Authorization, PoPs and traffic steering, single-pass architecture, SSL/TLS inspection, DLP in a SASE context, UEBA, SD-WAN as the on-ramp, and identity integration.
- `references/zero-trust-and-ztna.md`: the seven NIST tenets, ZTNA versus VPN and ZTNA 1.0 versus 2.0, the VPN-to-ZTNA migration framework, the five-pillar by five-level maturity model with the scoring matrix and both calculation methods, the four-phase assessment methodology, and compliance mapping (NIST, CIS v8, ISO 27001, OMB M-22-09, CISA).
- `references/platform-selection.md`: single-vendor versus best-of-breed, the selection criteria, a side-by-side of the major platforms (Zscaler, Prisma Access, FortiSASE, Netskope, Cloudflare, Cato), and the decision guidance.

## Bottom line

Start from the problem, not the product: internet access, private-app access, SaaS control, or data protection. Fix identity and device posture before the network, because zero trust is identity-first and the maturity posture is the lowest pillar. Prefer ZTNA over VPN for private apps, and verify the product does continuous, per-request verification rather than connect-then-trust. Choose single-vendor SASE or best-of-breed SSE from the traffic profile and operating model, not from familiarity, and route all per-vendor configuration to `zscaler`, `prisma-access`, and `fortisase`.
