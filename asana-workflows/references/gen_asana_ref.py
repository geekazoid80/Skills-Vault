#!/usr/bin/env python3
"""Generate a navigable Markdown reference from the Asana OpenAPI spec: full endpoint index (every
operation) + expanded schemas for the high-value resources. Estate-specific empirical findings are prepended by the
caller. Pure read of asana_oas.yaml; writes asana-api-reference.generated.md."""
import yaml

d = yaml.safe_load(open("asana_oas.yaml"))
paths = d["paths"]
schemas = d["components"]["schemas"]
info = d.get("info", {})
servers = d.get("servers", [])

METHODS = ("get", "post", "put", "delete", "patch")
out = []
w = out.append

w(f"_Generated from the Asana OpenAPI spec (openapi {d.get('openapi')}, info.version {info.get('version')}). "
  f"Source: https://raw.githubusercontent.com/Asana/openapi/master/defs/asana_oas.yaml_\n")
if servers:
    w(f"**Base URL:** `{servers[0].get('url')}`  ")
w("**Auth:** `Authorization: Bearer <PAT>` (personal access token) or OAuth2. "
  "**Pagination:** `limit` + `offset` (offset is an opaque token from `next_page`). "
  "**Sparse fields:** `opt_fields=a,b.c`. **Rate limits:** HTTP 429 with `Retry-After`.\n")

# --- endpoint index grouped by tag ---
w("\n## Endpoint index (all operations)\n")
by_tag = {}
for path, item in paths.items():
    for m in METHODS:
        op = item.get(m)
        if not op:
            continue
        tag = (op.get("tags") or ["(untagged)"])[0]
        by_tag.setdefault(tag, []).append((m.upper(), path, op.get("summary", ""), op.get("operationId", "")))
for tag in sorted(by_tag):
    w(f"\n### {tag}\n")
    w("| Method | Path | Summary |")
    w("|---|---|---|")
    for meth, path, summ, opid in sorted(by_tag[tag], key=lambda r: (r[1], r[0])):
        w(f"| `{meth}` | `{path}` | {summ} |")

# --- expanded schemas for the resources the estate actually uses ---
KEY = ["MembershipResponse", "MembershipCompact", "ProjectMembershipResponse", "ProjectMembershipCompact",
       "PortfolioMembershipResponse", "PortfolioMembershipCompact", "MembershipRequest",
       "MembershipUpdateRequest", "GoalMembershipBase",
       "ProjectResponse", "ProjectRequest", "ProjectCompact", "ProjectBase",
       "PortfolioResponse", "PortfolioRequest", "PortfolioBase",
       "TaskResponse", "TaskRequest", "TaskBase",
       "CustomFieldResponse", "CustomFieldRequest", "CustomFieldBase", "EnumOption",
       "UserResponse", "UserCompact", "TeamResponse", "TeamCompact",
       "WorkspaceResponse", "SectionResponse", "StoryResponse", "TagResponse"]


def prop_line(name, spec):
    spec = spec or {}
    t = spec.get("type", "")
    if "$ref" in spec:
        t = "→ " + spec["$ref"].split("/")[-1]
    if spec.get("enum"):
        t = f"enum {spec['enum']}"
    if t == "array":
        it = spec.get("items", {})
        t = "array of " + (it.get("$ref", "").split("/")[-1] or it.get("type", "?"))
    desc = (spec.get("description", "") or "").strip().replace("\n", " ")
    if len(desc) > 140:
        desc = desc[:137] + "..."
    ro = " _(read-only)_" if spec.get("readOnly") else ""
    return f"| `{name}` | {t} | {desc}{ro} |"


w("\n## Key resource schemas\n")
for sname in KEY:
    s = schemas.get(sname)
    if not s:
        continue
    props = s.get("properties")
    # some schemas compose via allOf; pull nested properties
    if not props and "allOf" in s:
        props = {}
        for part in s["allOf"]:
            if "$ref" in part:
                props.update((schemas.get(part["$ref"].split("/")[-1], {}) or {}).get("properties", {}) or {})
            else:
                props.update(part.get("properties", {}) or {})
    if not props:
        continue
    w(f"\n### {sname}\n")
    if s.get("description"):
        w((s["description"].strip().split("\n")[0])[:200] + "\n")
    w("| Field | Type | Description |")
    w("|---|---|---|")
    for pn, pv in props.items():
        w(prop_line(pn, pv))

open("asana-api-reference.generated.md", "w").write("\n".join(out) + "\n")
print("wrote asana-api-reference.generated.md")
print("lines:", len(out), "| operations indexed:", sum(len(v) for v in by_tag.values()),
      "| tags:", len(by_tag), "| key schemas expanded:", sum(1 for k in KEY if schemas.get(k)))
