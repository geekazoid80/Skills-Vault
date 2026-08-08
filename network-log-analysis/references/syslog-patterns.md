# Syslog Patterns Reference: Network Log Analysis

Vendor-specific syslog message format tables, RFC 5424 facility / severity matrix, and common network event pattern catalogues for raw log analysis. Vendor coverage: classic Cisco IOS, Cisco IOS-XE, Cisco NX-OS, Cisco IOS-XR, Juniper JunOS, Arista EOS. The four Cisco platforms get separate sections because syslog formats diverge meaningfully: NX-OS uses module-name-based mnemonics, IOS-XR prefixes every message with `RP/<rack>/<slot>/CPU<n>:`, and classic IOS lacks some modern facilities.

## RFC 5424 facility codes

| Code | Facility | Typical network use |
|------|----------|-------------------|
| 0 | kern | Not used by network devices |
| 1 | user | General device messages |
| 2 | mail | Not used by network devices |
| 3 | daemon | SNMP, NTP, routing daemons |
| 4 | auth | Login, AAA, TACACS+ / RADIUS |
| 5 | syslog | Syslog infrastructure messages |
| 6 | lpr | Not used by network devices |
| 7 | news | Not used by network devices |
| 8 | uucp | Not used by network devices |
| 9 | cron | Scheduled tasks on Linux-based devices |
| 10 | authpriv | Privileged authentication events |
| 11 | ftp | Not used by network devices |
| 16 | local0 | Commonly assigned: routers |
| 17 | local1 | Commonly assigned: switches |
| 18 | local2 | Commonly assigned: firewalls |
| 19 | local3 | Commonly assigned: wireless controllers |
| 20 | local4 | Commonly assigned: load balancers |
| 21 | local5 | Available for custom assignment |
| 22 | local6 | Available for custom assignment |
| 23 | local7 | Commonly assigned: network management (vendor defaults: IOS / IOS-XE / NX-OS / IOS-XR / EOS) |

## RFC 5424 severity levels

| Value | Severity | Keyword | Description |
|-------|----------|---------|-------------|
| 0 | Emergency | emerg | System is unusable |
| 1 | Alert | alert | Immediate action required |
| 2 | Critical | crit | Critical conditions |
| 3 | Error | err | Error conditions |
| 4 | Warning | warning | Warning conditions |
| 5 | Notice | notice | Normal but significant |
| 6 | Informational | info | Informational messages |
| 7 | Debug | debug | Debug-level messages |

**Priority (PRI) calculation:** `PRI = (Facility * 8) + Severity`

Example: local0.warning = (16 * 8) + 4 = 132. In raw syslog: `<132>`.

## Classic Cisco IOS message format

**Format:** `*timestamp: %FACILITY-SEVERITY-MNEMONIC: description`

Largely identical to IOS-XE for the common mnemonics. Key differences from IOS-XE:

- No `IOSXE_INFRA-*` facility (IOS-XE introduced for infrastructure events)
- No `APP_HOSTING-*` or `IOX-*` facilities (IOS-XE container hosting)
- Older trains (12.x) lack some newer mnemonics; check device's IOS train documentation
- `monitor capture` not available; use `debug ip packet detail acl <name>` or legacy `ip traffic-export` for packet evidence

The common-mnemonic catalogue below for IOS-XE applies to classic IOS unchanged for the listed events. Where a mnemonic is IOS-XE-only it is noted.

## Cisco IOS-XE message format

**Format:** `*timestamp: %FACILITY-SEVERITY-MNEMONIC: description`. Timestamp prefix `*` for non-synced clock, `.` for synced.

### Common IOS-XE facility codes

| Facility | Subsystem | Example mnemonic |
|----------|-----------|-----------------|
| LINK | Layer 1 / 2 interface | LINK-3-UPDOWN |
| LINEPROTO | Line protocol | LINEPROTO-5-UPDOWN |
| OSPF | OSPF routing | OSPF-5-ADJCHG |
| BGP | BGP routing | BGP-5-ADJCHANGE, BGP-3-NOTIFICATION |
| SYS | System events | SYS-5-CONFIG_I, SYS-5-RESTART |
| SEC | Security | SEC-6-IPACCESSLOGP |
| SEC_LOGIN | Login security | SEC_LOGIN-4-LOGIN_FAILED |
| AUTHMGR | Auth manager | AUTHMGR-5-START, AUTHMGR-5-SUCCESS |
| SNMP | SNMP subsystem | SNMP-3-AUTHFAIL |
| HSRP | First-hop redundancy | HSRP-5-STATECHANGE |
| VLAN | VLAN manager | VLAN-3-NATIVE_VLAN_MISMATCH |
| SPANNING | Spanning tree | SPANTREE-2-BLOCK_PVID_LOCAL |
| CRYPTO | IPsec / IKE | CRYPTO-4-IKMP_NO_SA |
| DHCP | DHCP snooping | DHCP_SNOOPING-5-DHCP_SNOOPING_MATCH |
| IOSXE_INFRA | Infrastructure (IOS-XE only) | IOSXE_INFRA-6-PROCPATH_CLIENT_HOG |
| APP_HOSTING | App-hosting (IOS-XE only) | APP_HOSTING-6-APP_ACTIVATED_SUCCESS |

### Critical IOS-XE mnemonics to monitor

| Mnemonic | Severity | Meaning | Action |
|----------|----------|---------|--------|
| LINK-3-UPDOWN | Error | Physical interface state change | Correlate with LINEPROTO, check cabling |
| LINEPROTO-5-UPDOWN | Notice | Line protocol state change | Correlate with LINK, check L2 negotiation |
| OSPF-5-ADJCHG | Notice | OSPF neighbour adjacency change | Check both neighbours, verify network stability |
| BGP-5-ADJCHANGE | Notice | BGP neighbour state change | Check peering config, route impact |
| BGP-3-NOTIFICATION | Error | BGP notification received / sent | Decode notification code for root cause |
| SYS-5-CONFIG_I | Notice | Configuration changed | Verify authorised change, identify user |
| SYS-5-RESTART | Notice | System restart | Check for crash, power event, or planned reload |
| SEC_LOGIN-4-LOGIN_FAILED | Warning | Authentication failure | Track source IP, count frequency |
| SNMP-3-AUTHFAIL | Error | SNMP auth failure | Verify community string, check source |
| HSRP-5-STATECHANGE | Notice | HSRP role change | Check for active / standby flip, verify primary |

## Cisco NX-OS message format

**Format:** `YYYY MMM DD HH:MM:SS.ms hostname %module-severity-MNEMONIC: description`

NX-OS uses module-name-based mnemonics rather than the IOS-XE facility-name style. Module names identify the subsystem.

### Common NX-OS modules

| Module | Subsystem | Example mnemonic |
|--------|-----------|-----------------|
| ETHPORT | Physical Ethernet ports | ETHPORT-5-IF_DOWN_LINK_FAILURE, ETHPORT-5-IF_UP |
| ETH_PORT_CHANNEL | LACP / port-channels | ETH_PORT_CHANNEL-5-PORT_DOWN, ETH_PORT_CHANNEL-5-PORT_UP |
| BGP | BGP routing | BGP-5-ADJCHANGE, BGP-3-NOTIFICATION |
| OSPF | OSPF routing | OSPF-5-ADJCHG |
| EIGRP | EIGRP routing | EIGRP-5-NBRCHANGE |
| ISIS | IS-IS routing | ISIS-6-ADJ_STATE |
| VPC | vPC (virtual port-channel) | VPC-2-PEER_KEEPALIVE_RECV_FAIL, VPC-2-PEER_LINK_DOWN |
| FEX | Fabric extender (Nexus 7K) | FEX-2-FEX_OFFLINE |
| FCOE | Fibre Channel over Ethernet | FCOE_MGR-2-FCOE_MGR_LICENSE_DENIED |
| POAP | Zero-touch provisioning | POAP-2-POAP_DHCP_DISCOVER_START |
| VSHD | Configuration shell | VSHD-5-VSHD_SYSLOG_CONFIG_I |
| AUTHPRIV | Privileged authentication | AUTHPRIV-3-SYSTEM_MSG (authentication failure) |
| AAA | Authentication / authorisation / accounting | AAA-5-AAA_ACCOUNTING_MESSAGE |
| SNMPD | SNMP daemon | SNMPD-3-AUTHFAIL |
| MONITOR | SPAN / monitor sessions | MONITOR-6-SESSION_UP |

### Critical NX-OS mnemonics to monitor

| Mnemonic | Severity | Meaning | Action |
|----------|----------|---------|--------|
| ETHPORT-5-IF_DOWN_LINK_FAILURE | Notice | Interface link failure | Check optic, cabling, peer interface |
| ETHPORT-5-IF_UP | Notice | Interface up | Confirm intended state, verify peer |
| ETH_PORT_CHANNEL-5-PORT_DOWN | Notice | Port-channel member down | Check LACP negotiation, peer config |
| VPC-2-PEER_KEEPALIVE_RECV_FAIL | Critical | vPC peer keepalive failure | Check peer-link, mgmt0 connectivity, vPC consistency |
| VPC-2-PEER_LINK_DOWN | Critical | vPC peer-link down | Loss of vPC redundancy; check L2 path |
| FEX-2-FEX_OFFLINE | Critical | Fabric extender offline | Check FEX uplinks, FEX power |
| VSHD-5-VSHD_SYSLOG_CONFIG_I | Notice | Configuration committed | Verify authorised user and change |
| AUTHPRIV-3-SYSTEM_MSG | Error | Authentication failure (varies by AAA backend) | Track source IP, count frequency |
| BGP-5-ADJCHANGE | Notice | BGP state change | Check peering, route impact |
| OSPF-5-ADJCHG | Notice | OSPF adjacency change | Check both neighbours |

## Cisco IOS-XR message format

**Format:** `RP/<rack>/<slot>/CPU<n>:<timestamp> <hostname> <process>[<pid>]: %FACILITY-SEVERITY-MNEMONIC : description`

The `RP/0/RP0/CPU0:` prefix identifies the route processor and node. Other prefixes: `RP/0/RSP0/CPU0:` (ASR9k RSP), `LC/0/0/CPU0:` (line cards). Process-name prefix matters: routing protocols log via `bgp`, `ospf`, `isis`, `pim` daemons each with its own PID.

### Common IOS-XR facility prefixes

| Facility prefix | Subsystem | Example mnemonic |
|----------------|-----------|-----------------|
| PKT_INFRA-LINK | Physical interface | PKT_INFRA-LINK-3-UPDOWN |
| PKT_INFRA-LINEPROTO | Line protocol | PKT_INFRA-LINEPROTO-5-UPDOWN |
| ROUTING-BGP | BGP routing | ROUTING-BGP-5-ADJCHANGE, ROUTING-BGP-3-NOTIFICATION |
| ROUTING-OSPF | OSPF routing | ROUTING-OSPF-5-ADJCHG |
| ISIS | IS-IS routing | ISIS-6-ADJCHG |
| CONFIG | Configuration | CONFIG-6-DB_COMMIT |
| SECURITY-MGD_AUTH | Auth manager | SECURITY-MGD_AUTH-3-LOGIN_FAILED |
| SNMP | SNMP subsystem | SNMP-3-AUTHFAIL |
| MGBL | Manageability (NetConf, REST, gRPC) | MGBL-CONFIG-6-DB_COMMIT |
| OS-SYSMGR | Process / system manager | OS-SYSMGR-3-PROC_NOT_STARTED |

### Critical IOS-XR mnemonics to monitor

| Mnemonic | Severity | Meaning | Action |
|----------|----------|---------|--------|
| PKT_INFRA-LINK-3-UPDOWN | Error | Physical interface state change | Correlate with LINEPROTO, check optic |
| PKT_INFRA-LINEPROTO-5-UPDOWN | Notice | Line protocol state change | Correlate with LINK |
| ROUTING-OSPF-5-ADJCHG | Notice | OSPF adjacency change | Check both neighbours |
| ROUTING-BGP-5-ADJCHANGE | Notice | BGP neighbour state change | Check peering, route impact |
| ROUTING-BGP-3-NOTIFICATION | Error | BGP notification | Decode notification code |
| ISIS-6-ADJCHG | Informational | IS-IS adjacency change (SP-core dominant) | Check link, peer config |
| CONFIG-6-DB_COMMIT | Informational | Configuration committed | Verify authorised user |
| SECURITY-MGD_AUTH-3-LOGIN_FAILED | Error | Authentication failure | Track source IP, count frequency |
| OS-SYSMGR-3-PROC_NOT_STARTED | Error | Process failed to start | Check process restart count, system health |
| MGBL-CONFIG-6-DB_COMMIT | Informational | Config commit via NetConf / gRPC | Verify automation source |

**Regex caveat:** patterns anchored at start-of-line MUST account for the `RP/0/RP0/CPU0:` prefix. Strip with `sed 's/^RP\/[0-9]\+\/[A-Z]\+[0-9]\+\/CPU[0-9]\+://'` before applying IOS-XE-style patterns, or write IOS-XR-specific patterns that include the prefix.

## Juniper JunOS message format

**Standard format:** `timestamp hostname process[pid]: EVENT_ID: message`

**Structured format (when `structured-data` enabled):** `timestamp hostname process[pid]: [junos@2636 tag="value" ...] message`

### Common JunOS event categories

| Process | Event prefix | Subsystem |
|---------|-------------|-----------|
| rpd | RPD_OSPF_*, RPD_BGP_*, RPD_ISIS_* | Routing protocol daemon |
| mgd | UI_*, MGMT_* | Management daemon |
| chassisd | CHASSISD_* | Chassis / hardware management |
| dcd | DCD_* | Device configuration daemon |
| snmpd | SNMPD_*, SNMP_TRAP_* | SNMP agent |
| sshd | SSHD_* | SSH daemon |
| eventd | EVENTD_* | Event processing |
| pfed | PFE_* | Packet forwarding engine |
| alarmd | ALARM_* | Alarm management |

### Critical JunOS events to monitor

| Event ID | Meaning | Action |
|----------|---------|--------|
| RPD_OSPF_NBRDOWN | OSPF neighbour went down | Check link state, peer config |
| RPD_OSPF_NBRUP | OSPF neighbour came up | Verify adjacency health |
| RPD_BGP_NEIGHBOR_STATE_CHANGED | BGP peer state transition | Check peering session, route impact |
| RPD_ISIS_ADJDOWN | IS-IS adjacency down | Check level, hello / hold timers, MTU |
| UI_COMMIT | Configuration committed | Verify authorised user and change |
| UI_COMMIT_COMPLETED | Commit finished successfully | Correlate with UI_COMMIT for timing |
| CHASSISD_FPC_OFFLINE | Line card offline | Hardware failure investigation |
| SNMPD_AUTH_FAILURE | SNMP authentication failure | Check community / credentials, source |
| SSHD_LOGIN_FAILED | SSH login failure | Track source, count frequency |
| ALARM_MANAGEMENT_ALARM_SET | Alarm raised | Check alarm type and severity |
| PFE_FW_SYSLOG_ETH | Firewall filter match | Evaluate filter hit, check policy |

## Arista EOS message format

**Format:** `timestamp hostname AgentName: %FACILITY-SEVERITY-message`

### Common EOS agent names

| Agent | Subsystem |
|-------|-----------|
| Ebra | Ethernet interface management |
| Stp | Spanning tree protocol |
| Bgp | BGP routing |
| Ospf | OSPF routing |
| Isis | IS-IS routing |
| Acl | Access control lists |
| Aaa | Authentication / authorisation |
| ConfigAgent | Configuration management |
| Lldp | Link layer discovery |
| Mlag | Multi-chassis link aggregation |
| PimBidir | PIM multicast routing |

### Critical EOS events to monitor

| Pattern | Meaning | Action |
|---------|---------|--------|
| %LINEPROTO-5-UPDOWN | Interface protocol state change | Check physical link, peer device |
| %BGP-5-ADJCHANGE | BGP adjacency change | Verify peering, assess route impact |
| %OSPF-5-ADJCHG | OSPF adjacency change | Check link and neighbour health |
| %SYS-5-CONFIG_I | Configuration change | Identify user, verify authorisation |
| %SYS-5-RELOAD | System reload | Check reason code (crash vs planned) |
| %MLAG-4-INTF_INACTIVE | MLAG interface down | Check MLAG peer link, domain health |
| %SECURITY-4-LOGIN_FAILED | Authentication failure | Track source, evaluate threat |
| %STP-6-INTERFACE_STATE | STP port state change | Verify topology convergence |

## Common network event patterns (all vendors)

### Interface events

| Event category | [IOS] | [IOS-XE] | [NX-OS] | [IOS-XR] | [JunOS] | [EOS] |
|---------------|-------|----------|---------|----------|---------|-------|
| Link down | `LINK-3-UPDOWN.*down` | `LINK-3-UPDOWN.*down` | `ETHPORT-5-IF_DOWN_LINK_FAILURE` | `PKT_INFRA-LINK-3-UPDOWN.*Down` | `SNMP_TRAP_LINK_DOWN` | `%LINEPROTO-5-UPDOWN.*down` |
| Link up | `LINK-3-UPDOWN.*up` | `LINK-3-UPDOWN.*up` | `ETHPORT-5-IF_UP` | `PKT_INFRA-LINK-3-UPDOWN.*Up` | `SNMP_TRAP_LINK_UP` | `%LINEPROTO-5-UPDOWN.*up` |
| Duplex mismatch | `CDP-4-DUPLEX_MISMATCH` | `CDP-4-DUPLEX_MISMATCH` | `ETHPORT-3-IF_DUPLEX_MISMATCH` | `PKT_INFRA-IFMGR-3-DUPLEX_MISMATCH` | `CHASSISD_FPC_ERR` | `%ETH-4-DUPLEX_MISMATCH` |
| Error counters | `CONTROLLER-2-PARITY` | `CONTROLLER-2-PARITY` | `ETHPORT-3-IF_RX_CRC_ERROR` | `PKT_INFRA-IFMGR-3-CRC_ERROR` | `PFE_FW_SYSLOG_ETH` | `%PHY-4-CRC_ERROR` |
| Port-channel member down | `EC-5-CANNOT_BUNDLE2` | `EC-5-CANNOT_BUNDLE2` | `ETH_PORT_CHANNEL-5-PORT_DOWN` | `BUNDLEMGR-5-MBR_STATE_DOWN` | `LACPD_TIMEOUT` | `%LACP-4-INACTIVE` |

### Authentication events

| Event category | [IOS] | [IOS-XE] | [NX-OS] | [IOS-XR] | [JunOS] | [EOS] |
|---------------|-------|----------|---------|----------|---------|-------|
| Login failure | `SEC_LOGIN-4-LOGIN_FAILED` | `SEC_LOGIN-4-LOGIN_FAILED` | `AUTHPRIV-3-SYSTEM_MSG.*authentication failure` | `SECURITY-MGD_AUTH-3-LOGIN_FAILED` | `SSHD_LOGIN_FAILED` | `%SECURITY-4-LOGIN_FAILED` |
| Login success | `SEC_LOGIN-5-LOGIN_SUCCESS` | `SEC_LOGIN-5-LOGIN_SUCCESS` | `AUTHPRIV-6-SYSTEM_MSG.*session opened` | `SECURITY-MGD_AUTH-6-LOGIN_SUCCESS` | `SSHD_LOGIN_ACCEPTED` | `%SECURITY-6-LOGIN_SUCCESS` |
| SNMP auth fail | `SNMP-3-AUTHFAIL` | `SNMP-3-AUTHFAIL` | `SNMPD-3-AUTHFAIL` | `SNMP-3-AUTHFAIL` | `SNMPD_AUTH_FAILURE` | `%SNMP-4-AUTHFAIL` |
| Privilege escalation | `PRIV-5-PRIV_CHANGE` | `PRIV-5-PRIV_CHANGE` | `AAA-6-USER_PRIV_CHANGE` | `SECURITY-MGD_AUTH-5-PRIV_CHANGE` | `UI_AUTH_EVENT` | `%AAA-5-ENABLE` |

### Configuration change events

| Event category | [IOS] | [IOS-XE] | [NX-OS] | [IOS-XR] | [JunOS] | [EOS] |
|---------------|-------|----------|---------|----------|---------|-------|
| Config saved / committed | `SYS-5-CONFIG_I` | `SYS-5-CONFIG_I` | `VSHD-5-VSHD_SYSLOG_CONFIG_I` | `CONFIG-6-DB_COMMIT` | `UI_COMMIT` | `%SYS-5-CONFIG_I` |
| Config rollback | `ROLLBACK-5-ROLLBACK` | `ROLLBACK-5-ROLLBACK` | `VSHD-5-CONFIG_REPLACE` | `CONFIG-6-DB_LOAD` | `UI_COMMIT_ROLLBACK` | `%SYS-5-CONFIG_ROLLBACK` |
| Archive created | `ARCHIVE-5-ARCHIVE` | `ARCHIVE-5-ARCHIVE` | `SYSMGR-5-CFGWRITE_STARTED` | `CONFIG-6-DB_ARCHIVE` | `MGMT_ARCHIVE` | `%CONFIG-5-ARCHIVE` |

### Routing adjacency events

| Event category | [IOS] | [IOS-XE] | [NX-OS] | [IOS-XR] | [JunOS] | [EOS] |
|---------------|-------|----------|---------|----------|---------|-------|
| OSPF neighbour down | `OSPF-5-ADJCHG.*Down` | `OSPF-5-ADJCHG.*Down` | `OSPF-5-ADJCHG.*Down` | `ROUTING-OSPF-5-ADJCHG.*Down` | `RPD_OSPF_NBRDOWN` | `%OSPF-5-ADJCHG.*Down` |
| OSPF neighbour up | `OSPF-5-ADJCHG.*FULL` | `OSPF-5-ADJCHG.*FULL` | `OSPF-5-ADJCHG.*FULL` | `ROUTING-OSPF-5-ADJCHG.*Full` | `RPD_OSPF_NBRUP` | `%OSPF-5-ADJCHG.*Full` |
| BGP peer down | `BGP-5-ADJCHANGE.*down` | `BGP-5-ADJCHANGE.*down` | `BGP-5-ADJCHANGE.*Down` | `ROUTING-BGP-5-ADJCHANGE.*Down` | `RPD_BGP_NEIGHBOR_STATE_CHANGED.*Idle` | `%BGP-5-ADJCHANGE.*down` |
| BGP peer up | `BGP-5-ADJCHANGE.*Established` | `BGP-5-ADJCHANGE.*Established` | `BGP-5-ADJCHANGE.*Up` | `ROUTING-BGP-5-ADJCHANGE.*Up` | `RPD_BGP_NEIGHBOR_STATE_CHANGED.*Established` | `%BGP-5-ADJCHANGE.*Established` |
| BGP notification | `BGP-3-NOTIFICATION` | `BGP-3-NOTIFICATION` | `BGP-3-NOTIFICATION` | `ROUTING-BGP-3-NOTIFICATION` | `RPD_BGP_NEIGHBOR_STATE_CHANGED` | `%BGP-3-NOTIFICATION` |
| IS-IS adjacency down | `ISIS-6-ADJ_STATE.*Down` | `ISIS-6-ADJ_STATE.*Down` | `ISIS-6-ADJ_STATE.*Down` | `ISIS-6-ADJCHG.*Down` | `RPD_ISIS_ADJDOWN` | `%ISIS-6-ADJ_STATE.*Down` |
| EIGRP neighbour change (Cisco-only) | `DUAL-5-NBRCHANGE` | `DUAL-5-NBRCHANGE` | `EIGRP-5-NBRCHANGE` | N/A (EIGRP not on IOS-XR) | N/A | N/A |

### NX-OS and IOS-XR specific events (no IOS-XE equivalent)

| Event category | [NX-OS] | [IOS-XR] |
|---------------|---------|----------|
| vPC peer-keepalive failure | `VPC-2-PEER_KEEPALIVE_RECV_FAIL` | N/A |
| vPC peer-link down | `VPC-2-PEER_LINK_DOWN` | N/A |
| FEX offline (Nexus 7K) | `FEX-2-FEX_OFFLINE` | N/A |
| Process restart | `SYSMGR-2-SERVICE_CRASHED` | `OS-SYSMGR-3-PROC_NOT_STARTED` |
| NetConf / gRPC config commit | (uses VSHD-5-VSHD_SYSLOG_CONFIG_I with `via netconf` tag) | `MGBL-CONFIG-6-DB_COMMIT` |
