# Service and vulnerability detection

Once ports are known, detection answers what is running and whether it looks vulnerable. All scanning stays authorised and scope-enforced.

## Service version detection

`nmap -sV --version-intensity 7 -p common <host>` probes each open port and returns the service name, product, version, and a CPE identifier. Intensity 0-9 trades speed for thoroughness (7 is a sensible default). The CPE it produces is exactly what `nvd-cve` needs to look up known vulnerabilities for that version.

## OS fingerprinting

`nmap -O <host>` fingerprints the operating system from TCP/IP stack behaviour, returning a match name, accuracy, and device type. It works best when the target has at least one open and one closed port; ranges fingerprint poorly, so target a single host.

## NSE scripts

The Nmap Scripting Engine runs focused checks. Common scripts:

| Script | Purpose |
|---|---|
| `ssl-cert` | display SSL certificate details |
| `ssl-enum-ciphers` | list supported SSL/TLS ciphers (weak-cipher detection) |
| `http-title`, `http-headers`, `http-methods` | web service inspection |
| `banner` | grab service banners |
| `smb-enum-shares`, `smb-os-discovery` | SMB share and OS enumeration |
| `ssh-hostkey` | show SSH host keys |
| `ftp-anon` | check for anonymous FTP |

Examples:

```bash
# SSL inspection on 443
nmap --script ssl-cert,ssl-enum-ciphers -p 443 <host>
# HTTP inspection
nmap --script http-title,http-headers -p 80,443,8080 <host>
# SMB enumeration
nmap --script smb-enum-shares,smb-os-discovery -p 445 <host>
```

## The vuln NSE category

`nmap --script vuln -p common <host>` runs the "vuln" script category, which checks for known CVEs and common misconfigurations. It is **slow**, so aim it at specific hosts, never a wide range. It is a lightweight complement to, not a replacement for, a credentialed vulnerability scanner.

## Full reconnaissance sweep

`nmap -A <host>` (or a combined SYN + `-sV` + `-O` + default scripts) is the all-in-one audit sweep: port scan plus service detection plus OS fingerprinting plus default NSE scripts. It takes longer but gives a comprehensive picture; keep it to a single host or a small range (/28 or smaller).

## Handing off

Service detection produces versions and CPEs; pass those to `nvd-cve` to enumerate the known CVEs, then to `vulnerability-management` to prioritise and remediate. nmap finds and fingerprints; it does not own the vulnerability decision.
