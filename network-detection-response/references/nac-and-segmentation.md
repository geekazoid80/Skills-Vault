# Network access control and micro-segmentation

Controlling who connects (NAC) and limiting what a connected workload can reach (micro-segmentation). Both directly constrain lateral movement.

## Why NAC

Network Access Control enforces who is allowed to connect before they connect. Traditional network security assumes internal devices are trusted; NAC removes that assumption and addresses:

- Rogue device access (unauthorised devices, visitors).
- Unmanaged device risk (BYOD, IoT, OT).
- Non-compliant device access (out-of-patch, no EDR agent).
- Guest network segmentation.

## 802.1X authentication

Port-based access control with three components:

1. **Supplicant:** the device requesting access (runs an 802.1X client).
2. **Authenticator:** the switch or wireless AP enforcing access.
3. **Authentication server:** the RADIUS server (ISE, ClearPass, NPS) making the decision.

EAP methods:

- **EAP-TLS:** certificate-based, most secure, requires PKI.
- **PEAP:** password inside a TLS tunnel, common for user authentication.
- **EAP-FAST:** Cisco proprietary, faster re-authentication.
- **MAB (MAC Authentication Bypass):** fallback for non-802.1X devices, authenticates by MAC address (spoofable, treat as weak).

NAC binds device access to identity, which is why `identity-access-management` is a sibling: the RADIUS server, the EAP-TLS certificates, and the posture decision all sit on the identity surface.

## NAC deployment phases

Roll NAC out in stages or it causes outages:

1. **Visibility only:** monitor mode, build the device inventory, no enforcement.
2. **Profiling:** classify devices by type (workstation, phone, printer, IoT, OT).
3. **Policy development:** define access policy per device category.
4. **Pilot enforcement:** enable enforcement on low-risk segments first.
5. **Full enforcement:** roll out everywhere with an exception process in place.

The recurring failure is jumping to enforcement with no monitor-only baseline: legitimate devices get blocked and the rollback is an outage.

## Traditional vs micro-segmentation

**Traditional segmentation:** VLAN/firewall-based perimeters between zones. Coarse-grained (whole VLANs talk freely inside a zone), static (changes mean firewall rule edits).

**Micro-segmentation:** policy at the workload level, independent of network topology. Fine-grained (specific workload-to-workload allow/deny), dynamic (policy follows the workload through VM migration or cloud bursting), enforcing least privilege between workloads even when they share a subnet.

## Application-dependency mapping

Map what talks to what before writing any policy:

1. **Discovery:** deploy agents/sensors in monitor mode; capture all flow data.
2. **Application grouping:** group workloads by tier (web, app, DB).
3. **Dependency visualisation:** identify every inter-workload path.
4. **Policy draft:** translate observed and required connections into allow rules.
5. **Ring-fencing:** start with a coarse ring-fence (block everything else), then refine inward.

## Enforcement boundaries

Rather than authoring every allow rule first, define an enforcement boundary that isolates a group of workloads, then open only the required paths. This:

- Limits the blast radius of a compromised workload.
- Simplifies policy: deny-by-default inside the boundary, explicit allows only.
- Aligns with the zero-trust "assume breach" principle.

## East-west segmentation value

Micro-segmentation directly limits lateral movement:

- Ransomware cannot spread between segmented workloads over SMB.
- A compromised workload cannot reach unrelated application tiers.
- Every attempted (and blocked) east-west connection becomes visible.
- It maps to ATT&CK mitigations for T1021 (Remote Services), T1570 (Lateral Tool Transfer), and T1210 (Exploitation of Remote Services).

Visibility must precede enforcement. Writing deny rules before dependency mapping breaks legitimate application paths and erodes trust in the programme.
