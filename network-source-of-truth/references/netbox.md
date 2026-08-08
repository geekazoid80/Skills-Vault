# NetBox source of truth

NetBox is a data-centre infrastructure resource model (DCIM) and IP address management (IPAM) platform. In this skill it serves as the network source of truth (SoT): the intended state of devices, interfaces, addressing, VLANs, and cabling. Reconciliation compares this intended state against live device state and reports where reality and intent diverge.

## Golden rule

NetBox is READ-WRITE. The MCP server has full API access to create and update devices, IPs, interfaces, VLANs, prefixes, and cables. During reconciliation, however, discrepancies are reported and ticketed first; they are NEVER auto-corrected without explicit human approval.

NetBox is the intended state. If reality differs from NetBox, either the network is wrong (the device drifted) or NetBox needs updating (the model is stale). Deciding which is a human judgement, so the workflow stops at "reported and ticketed" until a person signs off the correction.

## NetBox MCP tools

Each tool below is called via the NetBox MCP server. Parameters are passed as a JSON object.

| Tool | Parameters | Purpose |
|---|---|---|
| `netbox_get_objects` | `object_type`, `filters` (dict), `limit`, `brief` | Bulk query objects by type, optionally filtered. |
| `netbox_get_object_by_id` | `object_type`, `object_id` | Fetch a single object by its ID. |
| `netbox_search_objects` | `query`, `object_types` | Global text search across one or more object types. |
| `netbox_get_changelogs` | `filters` (dict) | Read the audit trail of NetBox changes. |

## Object model

The object types most relevant to reconciliation, and the fields each carries:

| Object type | Key fields |
|---|---|
| `dcim.devices` | name, role, platform, site, status |
| `dcim.interfaces` | name, type, enabled, MAC, MTU, mode (access / tagged), untagged_vlan, tagged_vlans |
| `ipam.ip-addresses` | address (CIDR), assigned_object, status, role |
| `dcim.cables` | A-side termination, B-side termination, type, length |
| `ipam.vlans` | vid, name, site, tenant, status |
| `ipam.prefixes` | prefix (CIDR), VRF, site, status |
| `dcim.sites` | name, region, physical_address |

## Changelog audit

After a reconciliation pass, check the NetBox changelogs to understand when the source of truth was last updated. Call `netbox_get_changelogs` with filters such as `object_type=dcim.interface` and `limit=20`.

The changelog answers a question the bare diff cannot: is a discrepancy due to a recent device change (the device drifted away from a correct model) or stale NetBox data (NetBox was never updated to match a deliberate network change)? A recent changelog entry on the affected object points toward NetBox being current and the device having drifted; a long-untouched object with a mismatch points toward stale NetBox data. This steers the correction toward fixing the device or updating the model.

## When to use NetBox as source of truth

- Scheduled: weekly or monthly source-of-truth validation.
- Post-change: after every configuration change, verify NetBox still matches reality.
- Incident response: when investigating an outage, check whether NetBox data is accurate for the affected devices before trusting it.
- New device onboarding: verify NetBox was populated correctly after adding a new device.
- Audit and compliance: demonstrate that infrastructure documentation matches reality.

## Reconciliation methodology

The full intent-vs-live-state reconciliation methodology (discrepancy taxonomy, diff engine, severity model, ticketing, fleet-wide reporting) is in reconciliation.md.

## Working with the rest of this skill

- `reconciliation.md`: the drift methodology that consumes the tools and object model described here.
- `nautobot.md` and `infrahub.md`: alternative source-of-truth platforms with their own MCP surfaces and object models; choose the one your environment runs.
- Live device state for reconciliation (what the network actually reports) comes from the vault skill `pyats-network-automation`. NetBox supplies the intended state; pyATS supplies the observed state; reconciliation.md compares the two.
