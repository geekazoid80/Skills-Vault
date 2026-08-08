# Host and port scanning

All scanning is authorised, scope-enforced, and audit-logged (see `scope-and-management.md`). Start with host discovery, then scan ports on the live hosts.

## Host discovery

Find the live hosts before port-scanning so you do not waste time on dead addresses.

- **Ping sweep (ICMP plus TCP):** `nmap -sn 192.168.1.0/24`. Works across routed segments; identifies which addresses respond.
- **ARP discovery (LAN only):** on a directly connected segment, ARP is more reliable than ICMP (hosts that drop ping still answer ARP): `nmap -PR -sn 192.168.1.0/24`. Needs raw-socket capability (`cap_net_raw`).

## Port scanning

| Technique | Command | Privilege | Use |
|---|---|---|---|
| Top-N common ports | `nmap --top-ports 100 192.168.1.1` | none | quick first pass |
| SYN half-open | `nmap -sS -p 1-65535 192.168.1.1` | cap_net_raw | fast, the default for breadth |
| TCP connect | `nmap -sT -p 22,80,443,8080 192.168.1.1` | none | works without privileges |
| UDP | `nmap -sU -p 53,123,161 192.168.1.1` | cap_net_raw | DNS/SNMP/NTP/TFTP/syslog; slow, keep targeted |

Notes:

- **SYN scan** never completes the TCP handshake (sends SYN, reads SYN/ACK or RST), so it is fast and light, but needs raw-socket capability on the nmap binary.
- **TCP connect** completes the handshake via the OS, so it needs no special privilege but is heavier and more visible.
- **UDP** is inherently slow because closed UDP ports are inferred from ICMP unreachables (rate-limited): always give it a targeted port list (common UDP service ports: 53, 67/68, 69, 123, 161/162, 500, 514, 1900), never a full range.
- **Top-ports** is the pragmatic opening move: scan the top 100 or top 1000 to see the shape of a host before a deeper scan.

## A typical subnet sweep

1. Discover hosts: `nmap -sn 192.168.1.0/24` (or ARP on a LAN).
2. Quick port pass on live hosts: `nmap --top-ports 100 <host>`.
3. Deeper scan where warranted: `nmap -sS -p 1-65535 <host>` (SYN) or `nmap -sT -p <list> <host>` (connect).
4. UDP services where relevant: `nmap -sU -p 53,123,161 <host>`.

## Output

Scans return structured results with a scan id (for later retrieval), the target, the hosts found and their open ports, and summary counts. The scan id is the key to the before/after comparison workflow in `scope-and-management.md`.
