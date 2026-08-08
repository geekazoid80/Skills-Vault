# OpsMill Infrahub

Infrahub is a schema-driven source of truth for infrastructure. It centralises devices, circuits, IP addresses, services, cloud resources, and any other infrastructure object you choose to model, with Git-like versioned branches and a GraphQL-native API. This reference covers how to reach it through the Infrahub MCP server, the tools that server exposes, the common workflows, and how it compares with NetBox and Nautobot.

## MCP server

- Repository: opsmill/infrahub-mcp (https://github.com/opsmill/infrahub-mcp)
- Transport: stdio via FastMCP (also supports HTTP on a configurable port)
- Requires: INFRAHUB_ADDRESS, INFRAHUB_API_TOKEN
- Python: 3.13+
- Dependencies: fastmcp, infrahub_sdk

All tool calls below run via the Infrahub MCP server.

## How Infrahub differs

Infrahub is not just another IPAM / DCIM tool. The key differentiators:

- Schema-driven: define your own infrastructure models rather than only the built-in IPAM / DCIM shapes. Devices, circuits, IP addresses, services, cloud resources, any infrastructure object can be modelled.
- Versioned branches: Git-like branching for infrastructure data. Make changes on a branch, review the diff, merge once approved.
- GraphQL-native: a full GraphQL API for flexible queries, not just REST. Query exactly the fields you need and traverse relationships in a single request.
- Relationship-first: a rich relationship model between objects, with relationship-level filters and traversal.

## MCP tools (10 tools)

### Node operations (3 tools)

- get_nodes (kind, branch?, filters?, partial_match?): retrieve all objects of a specific kind with optional filtering and partial matching.
- get_node_filters (kind, branch?): list available filters for a kind; attribute filters (attr__value) and relationship filters (rel__attr__value).
- get_related_nodes (kind, relation, filters?, branch?): traverse a relationship from a node kind to get connected objects (peers, members, interfaces).

### Schema operations (3 tools)

- get_schema_mapping (branch?): list all schema node kinds and generics available in Infrahub.
- get_schema (kind, branch?): full schema for a specific kind, covering attributes, relationships, and their types.
- get_schemas (branch?, exclude_profiles?, exclude_templates?): retrieve all schemas, optionally excluding profiles and templates.

### GraphQL operations (2 tools)

- get_graphql_schema (none): retrieve the full GraphQL schema from Infrahub in SDL format.
- query_graphql (query, branch?): execute an arbitrary GraphQL query against Infrahub.

### Branch operations (2 tools)

- get_branches (none): list all branches in Infrahub with their details.
- branch_create (name, sync_with_git?): create a new branch for isolated infrastructure changes.

## Workflow: discover available data

1. List kinds: get_schema_mapping. What infrastructure types are modelled?
2. Inspect schema: get_schema(kind="InfraDevice"). What attributes and relationships does a device have?
3. List filters: get_node_filters(kind="InfraDevice"). How can devices be queried?
4. Get nodes: get_nodes(kind="InfraDevice"). List all devices.
5. Report: an infrastructure data-model overview with node counts per kind.

## Workflow: infrastructure audit

1. Schema overview: get_schema_mapping. Discover all kinds.
2. Device inventory: get_nodes(kind="InfraDevice"). All devices.
3. IP addresses: get_nodes(kind="InfraIPAddress"). All IPs (if IPAM is modelled).
4. Prefixes: get_nodes(kind="InfraPrefix"). All subnets.
5. Relationships: get_related_nodes(kind="InfraDevice", relation="interfaces"). Device interfaces.
6. Report: an infrastructure inventory from Infrahub with relationship context.

## Workflow: branch-based change

1. List branches: get_branches.
2. Create branch: branch_create(name="change-123-add-vlan").
3. Query current state: get_nodes(kind="InfraVLAN", branch="change-123-add-vlan").
4. Make changes via GraphQL: query_graphql(query="mutation { ... }", branch="change-123-add-vlan").
5. Verify: get_nodes on the branch.
6. Merge: via the Infrahub UI / API, merge the branch to main.
7. Report: a change summary with a before / after branch comparison.

## Workflow: GraphQL exploration

1. Schema: get_graphql_schema. Full SDL schema.
2. Test query: query_graphql(query="{ InfraDevice { edges { node { name { value } } } } }").
3. Filtered query: query_graphql(query="{ InfraDevice(name__value: \"core-rtr\") { ... } }").
4. Nested relationships: traverse in a single query via GraphQL nesting.
5. Report: a custom data extraction with exactly the fields needed.

## Infrahub vs NetBox vs Nautobot

| Feature | NetBox | Nautobot | Infrahub |
| --- | --- | --- | --- |
| Origin | DigitalOcean / NetBox Labs | Network to Code | OpsMill |
| Data model | Fixed DCIM / IPAM + custom fields | Fixed DCIM / IPAM + Jobs + custom fields | Fully schema-driven (define any model) |
| Versioning | No branching | No branching | Git-like branches for data |
| API | REST + GraphQL | REST + GraphQL | GraphQL-native |
| MCP tools | Read-write via FastMCP | Read-only IPAM (5 tools) | Read + GraphQL mutations + branches (10 tools) |
| Use when | Standard IPAM / DCIM | Standard IPAM / DCIM (NTC ecosystem) | Custom infrastructure models, versioned changes |

## Important rules

- Discover before querying: always call get_schema_mapping first to learn what kinds exist. Do not guess kind names.
- Use filters: call get_node_filters to learn valid filter syntax before using get_nodes with filters.
- Branch for changes: create a branch before making mutations via query_graphql. Never mutate main directly.
- GraphQL mutations require authorisation: ensure the API token has write permissions for mutation queries.
- Partial matching: use partial_match=True in get_nodes for fuzzy matching on filter values.
- Relationship traversal: use get_related_nodes to follow relationships; use get_schema to discover relationship names first.

## Environment variables

- INFRAHUB_ADDRESS: Infrahub instance URL (e.g. http://infrahub.example.com:8000).
- INFRAHUB_API_TOKEN: Infrahub API authentication token.
- MCP_HOST: server bind address when running in HTTP mode (default 0.0.0.0, optional).
- MCP_PORT: server port when running in HTTP mode (default 8001, optional).

## Working with the rest of this skill and the vault

| Need | Where to go |
| --- | --- |
| NetBox as the source of truth, plus reconciling discovered state against intended state | the netbox.md reference / reconciliation.md |
| Nautobot as the source of truth (Network to Code ecosystem) | the nautobot.md reference |
| Driving devices from data pulled out of Infrahub (test / config jobs) | the pyats-network-automation vault skill |
| Validating live state against Infrahub-modelled intent | the pyats-network-automation vault skill |
