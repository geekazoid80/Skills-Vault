---
name: ios-xe-mpls-l2vpn
description: "Use for Cisco IOS-XE MPLS L2VPN service provisioning and troubleshooting on carrier/PE-role platforms (ASR1000 family and similar), covering VPWS, VPLS, EVPN-VPWS and EVPN-VPLS. Triggers include \"bridge-domain\", \"service instance\", \"member evpn-instance\", \"xconnect\", \"pseudowire\", \"EVPN-VPWS\", \"EVPN-VPLS\", \"Legacy configuration model is being used\", \"Bridge domain is configured with legacy model\", \"ASR1000 L2VPN\", \"IOS-XE bridge-domain binding\". NOT for EVPN-VXLAN data-centre fabric (leaf/spine, VTEPs; see evpn-vxlan-fabric) and NOT for IOS-XR L2VPN (different OS, different config model). Covers the inline-vs-top-level bridge-domain binding model conflict, its two confusing IOS-XE error messages, and the misleading advice one of them gives."
metadata:
  version: 1.0.0
---

# Cisco IOS-XE MPLS L2VPN service provisioning

Cisco IOS-XE MPLS L2VPN (VPWS, VPLS, and their EVPN-signalled successors EVPN-VPWS and EVPN-VPLS) runs on
carrier/PE-role platforms such as the ASR1000 family. This is distinct from EVPN-VXLAN data-centre fabric:
the data plane is MPLS, not VXLAN, and the device role is a WAN/service-provider edge router, not a DC
leaf or spine. Use `evpn-vxlan-fabric` for that surface; use this skill for MPLS L2VPN service
provisioning on IOS-XE.

> **Skill marker**: When applying this skill, begin your reply with `[skill: ios-xe-mpls-l2vpn]` on its
> own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each
> marker on its own line at the top: transparency over neatness.

## Scope

- Provisioning or troubleshooting a `bridge-domain` that carries an EVPN instance, VPWS xconnect, or a
  plain Layer-2-only attachment circuit on IOS-XE.
- Diagnosing the `% Legacy configuration model is being used` / `% Bridge domain is configured with
  legacy model` error pair.
- Any question about which binding model (inline vs top-level) a given bridge-domain should use.

Not in scope: EVPN-VXLAN fabric troubleshooting (`evpn-vxlan-fabric`), general BGP/MPLS underlay work
(`bgp-analysis`), or IOS-XR `l2vpn` / `xconnect` configuration (a different OS and a different config
model; do not assume parity).

## Confirmed finding: two bridge-domain binding models, and they cannot mix per service-instance

Confirmed live 2026-09-19 on an ASR1000-family router (exact IOS-XE release not yet catalogued; record it
here the next time this is confirmed against a specific version) while provisioning an EVPN L2VPN service.

**The two models.** IOS-XE has two mutually exclusive ways to bind an attachment circuit
(`interface ... / service instance <m> ethernet`) to a `bridge-domain <n>`:

1. **Inline model.** `bridge-domain <n>` is configured directly under the service instance:
   ```
   interface GigabitEthernet0/0/1
    service instance 100 ethernet
     encapsulation dot1q 100
     bridge-domain 100
   ```
   Used by a plain Layer-2-only bridge-domain that carries no EVPN instance.

2. **Top-level list model.** The bridge-domain instead declares its members from the top level:
   ```
   bridge-domain 200
    member GigabitEthernet0/0/2 service-instance 200
    member evpn-instance 200
   ```
   Required for a bridge-domain that carries an EVPN instance member (`member evpn-instance <n>`). ALL of
   that bridge-domain's attachment circuits must be bound this way, not just the EVPN member line.

Both models can coexist on the same box for **different** bridge-domains: on the box this was confirmed
against, an entire family of ~6 EVPN-backed bridge-domains used the top-level model exclusively (zero
inline `bridge-domain` lines under any of their service instances), while a separate family of ~6 plain-L2
bridge-domains used the inline model exclusively (zero top-level `member` stanzas). The conflict only
arises when the **same** service-instance/bridge-domain pair is bound both ways at once.

## The trap: two error messages, and the first one's advice is wrong for an EVPN-backed domain

Mixing the two models for the same pair produces this error:

```
% Legacy configuration model is being used,
Please use bridge-domain command under this service instance.
```

Its literal advice, add `bridge-domain <n>` under the service instance, is exactly right for a plain-L2
domain and exactly wrong for an EVPN-backed one: it re-adds the inline line and the conflict just moves.
Following it on an EVPN-backed domain, then trying to add the EVI member at the top level, produces the
second error:

```
% Bridge domain is configured with legacy model.
Please remove bridge domain configuration from any Ethernet service instances
and add them as members within the bridge domain.
```

Read this second message as generic guidance ("this bridge-domain has a leftover inline line; if it needs
the top-level model, remove the inline line"), not as a statement that EVPN caused the conflict.

## Root cause and fix

The observed root cause was a **leftover inline `bridge-domain <n>` line** already present under the
service-instance, left over from an earlier, abandoned config attempt, fighting a **new top-level
`member`** line trying to bind the same service-instance the other way. It was never about the EVPN
instance itself, only about the duplicate/conflicting circuit binding underneath it.

Fix: remove the inline `bridge-domain <n>` line from under the service-instance, keep only the top-level
`member ... service-instance <m>` binding, then add `member evpn-instance <n>` at the top level. It goes
through cleanly once the duplicate binding is gone.

```
interface GigabitEthernet0/0/1
 service instance 100 ethernet
  encapsulation dot1q 100
! remove any inline "bridge-domain 100" line here

bridge-domain 100
 member GigabitEthernet0/0/1 service-instance 100
 member evpn-instance 100
```

Before touching a bridge-domain that already has attachment circuits, run `show bridge-domain <n>` and
`show running-config | section bridge-domain <n>` (plus each candidate service-instance's own
running-config) to confirm which model it currently uses, rather than assuming from the error text alone.

## Open question: not yet confirmed against Cisco documentation

Whether "the bridge-domain carries an EVI member" is genuinely the deciding factor for which binding model
IOS-XE requires, versus some other internal state, is **not confirmed against an official Cisco source**.
The evidence for it is a consistent live pattern across ~12 bridge-domains on one box (6 EVPN-backed, all
top-level, zero inline; 6 plain-L2, all inline, zero top-level), not a release note or config guide. Treat
"EVI member present -> top-level model required" as the working hypothesis, not settled fact, until it is
verified against Cisco's own L2VPN / EVPN configuration guide for the release in question. When that
verification happens, record the confirming (or disconfirming) source and the exact IOS-XE release here.

## Red flags

- About to follow the FIRST error message's literal advice ("use bridge-domain command under this service
  instance") on a bridge-domain that carries or will carry `member evpn-instance`.
- Adding a top-level `member ... service-instance` line to a bridge-domain without first checking for a
  leftover inline `bridge-domain` line under that same service-instance.
- Assuming a bridge-domain's binding model from the error text alone rather than from `show bridge-domain`
  / `show running-config`.
- Stating "EVI member present forces the top-level model" as a documented Cisco rule; it is currently an
  observed pattern only (see Open question above).
- Assuming IOS-XR `l2vpn`/`xconnect` syntax or behaviour carries over; it does not share this config model.

## Cross-references

- `evpn-vxlan-fabric` -- the sibling EVPN skill, scoped to BGP-EVPN-over-VXLAN data-centre fabric
  (leaf/spine, VTEPs, anycast gateway). Different data plane and device role from this skill; do not
  conflate the two just because both involve EVPN.
- `multi-vendor-network-ops` -- umbrella skill; lists MPLS L2VPN/VPLS in its general topic surface and
  supplies the diagnose-first workflow and nine-element response contract for any state-changing change
  on top of the device-level detail here.
- `bgp-analysis` -- for the underlying MP-BGP EVPN control-plane session carrying the L2VPN EVPN routes,
  when the symptom is control-plane rather than the bridge-domain binding model itself.
- `documented-limits-are-starting-points` -- applies directly to the Open question above: an IOS-XE error
  message's own suggested fix is not proof of the underlying rule: verify against Cisco documentation
  before treating either the trap or the fix as settled behaviour rather than an observed pattern.
- `verify-before-asserting` -- do not state the open question as confirmed Cisco behaviour in a report or
  change record; state it as observed-and-unconfirmed until a primary source lands.

## Bottom line

On Cisco IOS-XE, a bridge-domain carrying an EVPN instance member must bind every attachment circuit via
the top-level `bridge-domain <n> / member <interface> service-instance <m>` list model; a plain
Layer-2-only bridge-domain instead uses the inline `bridge-domain <n>` line under the service instance.
The two models coexist fine across different bridge-domains but cannot mix for the same
service-instance/bridge-domain pair. When they do, the first error message's own advice is wrong for an
EVPN-backed domain: the fix is to remove the leftover inline line and keep only the top-level binding, not
to add the inline line back. Whether the EVI member is truly the deciding factor, versus some other
internal state, remains unconfirmed against Cisco's own documentation.
