# Cacti templates, data queries, and graphing

The template model that makes Cacti repeatable, the data queries that make it dynamic, and the CDEF/GPRINT layer that shapes the output.

## The template hierarchy

Cacti is template-driven so that one definition applies to many devices. Four template types build on each other:

| Template | Defines | Example |
|---|---|---|
| Data input method | How a value is gathered | SNMP get, script, SNMP data query |
| Data template | What to collect and store (the RRD shape) | "Interface traffic": in/out octets as COUNTER data sources |
| Graph template | How to render it | "Interface traffic": area for inbound, line for outbound, legend |
| Host (device) template | A bundle of graph + data-query templates for a device type | "Cisco router": traffic, CPU, memory queries |

Apply a host template to a new device and Cacti knows which graphs and data queries to run, with no per-device hand-building.

## Data input methods

A data input method is how Cacti obtains a value:

- **SNMP**: a direct OID get (for a single scalar value).
- **Script / Script Server**: run an external script (Perl, PHP, shell, Python) that returns one or more values. The Script Server keeps a PHP script resident for speed.
- **SNMP data query**: walk a table and discover multiple entities (see below).

## Data queries

A data query turns a table walk into many graphs automatically. The canonical example is the SNMP interface query:

```
1. The query walks ifTable / ifXTable on the device
2. It discovers every interface (index, name, speed, alias)
3. It presents the interfaces for selection
4. For each chosen interface it creates a data source + graph from the associated templates
```

This is why Cacti scales operationally: add a switch with fifty interfaces, run the interface data query, and get fifty interface-traffic graphs without defining any of them by hand. Script-based data queries do the same for non-SNMP sources (a script returns an indexed list, Cacti creates a graph per index).

## CDEF: calculated definitions

A CDEF transforms a data source using an RPN (reverse-Polish notation) expression, without changing what is stored. Common uses:

- Convert bits to bytes (or the reverse): `value,8,*`.
- Sum inbound and outbound for a total-traffic line.
- Clamp negatives or apply a multiplier.
- Compute percentage utilisation against interface speed.

CDEFs operate at render time, so the same stored data can be shown raw on one graph and transformed on another.

## GPRINT: legend formatting

GPRINT (and its presets) format the numeric legend under a graph: print the LAST, AVERAGE, MAX, or MIN of a data source with a chosen format and unit. GPRINT presets keep the legend formatting consistent across graph templates.

## Graph trees and aggregates

- **Graph trees**: organise graphs hierarchically (by site, by device, by role) for navigation; a device can appear in multiple trees.
- **Aggregate graphs**: combine the same data source across many devices or interfaces into one graph (for example, total WAN traffic across all edge routers) using an aggregate template.
- **Colour templates and GPRINT presets**: keep visual styling consistent across the install.
