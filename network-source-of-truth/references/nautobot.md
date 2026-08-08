# Nautobot IPAM and source of truth

Nautobot is a network source-of-truth and automation platform (a fork of NetBox by Network to Code). This reference covers querying its IPAM and DCIM data via the Nautobot MCP server.

## MCP server

- Repository: aiopnet/mcp-nautobot (https://github.com/aiopnet/mcp-nautobot)
- Transport: stdio (Python via the MCP SDK), also supports HTTP on a configurable port
- Requires: NAUTOBOT_URL, NAUTOBOT_TOKEN
- Python: 3.13+
- Read-only: all tools are read operations (requires an API token with read permissions)

## MCP tools (5 tools)

Invoke these via the Nautobot MCP server:

- `get_ip_addresses` (address?, prefix?, status?, role?, tenant?, vrf?, limit?, offset?): retrieve IP addresses with filtering. status (active, reserved, deprecated); role (loopback, secondary, anycast); plus VRF and tenant.
- `get_prefixes` (prefix?, status?, site?, role?, tenant?, vrf?, limit?, offset?): retrieve network prefixes filtered by site, role, status, VRF, or tenant.
- `get_ip_address_by_id` (ip_id): retrieve a specific IP address by its Nautobot UUID.
- `search_ip_addresses` (query, limit?): full-text search across all IP address data.
- `test_connection` (none): verify connectivity to the Nautobot API; returns status, URL, and timestamp.

### Tool details

`get_ip_addresses`, the primary IPAM query tool, supports rich filtering:

- address: specific IP (e.g. 10.0.1.1)
- prefix: network prefix filter (e.g. 10.0.0.0/24); returns all IPs within the prefix
- status: active, reserved, deprecated
- role: loopback, secondary, anycast, vip, hsrp, vrrp
- tenant: filter by tenant (multi-tenancy)
- vrf: filter by VRF (routing instance isolation)
- limit: max results (default 100, max 1000)
- offset: pagination offset

Returns JSON with a count and IP address objects including assignment details.

`get_prefixes`, network prefix (subnet) lookup with site awareness:

- prefix: specific prefix (e.g. 10.0.0.0/24)
- site: filter by site or location name
- role: prefix role (production, development, management)
- status: active, reserved, deprecated, container
- tenant / vrf: multi-tenancy and routing isolation

Returns JSON with prefix objects including utilisation data.

`search_ip_addresses`, free-text search across all IP address fields. Use it when you do not know exactly which field to filter on. Query by partial IP, hostname, description, or any text in the IP record. Default limit 50 (max 500).

## Workflow: IPAM audit

1. Test connection: `test_connection`.
2. List prefixes: `get_prefixes` by site.
3. IP utilisation: `get_ip_addresses` per prefix; how many IPs active versus reserved.
4. Deprecated check: `get_ip_addresses(status="deprecated")`; stale allocations.
5. Report: IPAM utilisation summary by site and prefix.

## Workflow: IP address lookup

1. Search: `search_ip_addresses(query="10.1.2.3")`.
2. Details: `get_ip_address_by_id`; full details including device assignment.
3. Prefix context: `get_prefixes(prefix="10.1.2.0/24")`; which subnet, which site.
4. Report: IP ownership, device assignment, subnet, site, VRF, and tenant.

## Workflow: VRF reconciliation

1. Get VRF IPs: `get_ip_addresses(vrf="PROD-VRF")`.
2. Get VRF prefixes: `get_prefixes(vrf="PROD-VRF")`.
3. Cross-check: verify IPs fall within expected prefix ranges.
4. Overlap detection: compare prefixes across VRFs for unintended overlap.
5. Report: VRF allocation summary with anomalies.

## Workflow: site IP summary

1. Site prefixes: `get_prefixes(site="Chicago-DC")`.
2. Per-prefix IPs: `get_ip_addresses(prefix="10.10.0.0/16")`.
3. Loopbacks: `get_ip_addresses(role="loopback", status="active")`.
4. Report: site IPAM dashboard with prefix utilisation, loopback inventory, and tenant breakdown.

## Nautobot vs NetBox

| Feature | NetBox (netbox.md) | Nautobot (this reference) |
| --- | --- | --- |
| Origin | DigitalOcean / NetBox Labs | Network to Code (fork of NetBox) |
| IPAM | Full IPAM, DCIM, circuits | Full IPAM, DCIM, circuits plus Jobs framework |
| API style | REST + GraphQL | REST + GraphQL + Jobs API |
| MCP tools | Read-write via FastMCP | Read-only via the MCP SDK |
| Use when | Org uses NetBox | Org uses Nautobot |

If the organisation runs both, use both for cross-platform reconciliation.

## Important rules

- Read-only: all tools are read operations; no writes to Nautobot.
- API token scope: ensure the token has read permissions for IPAM endpoints.
- Pagination matters: for large datasets use limit and offset (max 1000 per request).
- VRF isolation: IP addresses can be duplicated across VRFs; always filter by VRF when the network uses overlapping address space.
- Multi-tenancy: filter by tenant for shared Nautobot instances serving multiple organisations.

## Environment variables

- NAUTOBOT_URL: Nautobot instance URL (e.g. https://nautobot.example.com)
- NAUTOBOT_TOKEN: Nautobot API token with read permissions
- MCP_PORT: server port in HTTP mode (default 8000, optional)
- MCP_HOST: server bind address (default 127.0.0.1, optional)

## Working with the rest of this skill and the vault

| Need | Where to go |
| --- | --- |
| NetBox as the source of truth, or cross-platform reconciliation | the netbox.md and reconciliation.md references |
| Infrahub as the source of truth | the infrahub.md reference |
| Push IPAM-derived config to devices, or validate against intent | the `pyats-network-automation` vault skill |
| Test or validate live device state against Nautobot data | the `pyats-network-automation` vault skill |
