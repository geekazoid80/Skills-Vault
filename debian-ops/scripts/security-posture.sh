#!/bin/sh
# Debian security posture summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports host firewall state (ufw or nftables), AppArmor profile counts, effective sshd settings and the sudo implementation. It reports; it does not harden.
# POSIX sh (the Debian /bin/sh is dash). Run as root (sudo sh security-posture.sh); without root the firewall, AppArmor and sshd checks warn that they were not performed.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings
# or an invalid setting (the message is on standard error).
# A required command that is missing, fails or returns nothing is a warning, never a pass; an optional
# component that is not installed (for example snapd, sshd, cloud-init) is reported as information.
#
# Not run on a live host in this vault: it is checked with shellcheck and exercised against stub commands
# only, so the output formats it parses are taken from manual pages and vendor documentation. Try it on a
# non-critical host first.
#
# Example: sudo sh security-posture.sh
#
# shellcheck disable=SC2016,SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops;
#  SC2016: where used, dpkg-query format strings contain a literal ${Status}.)

set -u
LC_ALL=C
export LC_ALL
# sbin directories hold ufw, sshd, aa-status and similar, and are often missing from a normal user's PATH.
# SBIN_PATH exists so a test can set it empty; leave it unset in normal use.
PATH="$PATH${SBIN_PATH-:/usr/local/sbin:/usr/sbin:/sbin}"
export PATH
EXIT_CODE=2   # any path that does not reach a verdict exits 2
FINDINGS=$(mktemp "${TMPDIR:-/tmp}/linux-skill.XXXXXX") || { echo "cannot create a temporary file" >&2; exit 2; }
trap 'rm -f "$FINDINGS"' EXIT
trap 'exit 2' HUP INT TERM

add_finding() { printf '%s|%s\n' "$1" "$2" >> "$FINDINGS"; }
section() { printf '\n%s\n%s\n' "$1" '------------------------------------------------------------------------'; }
note() { printf '  %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
is_root() { [ "$(id -u)" = "0" ]; }
# need CMD: a missing command is a warning, never a pass.
need() { if have "$1"; then return 0; fi; add_finding Warning "$1 not found; the related checks were skipped"; return 1; }
# capture VAR CMD ARGS...: store combined output in VAR and return the command's exit status.
capture() { _cap_var=$1; shift; _cap_out=$("$@" 2>&1); _cap_rc=$?; eval "$_cap_var=\$_cap_out"; return "$_cap_rc"; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
# run_check NAME FUNCTION: a check that returns non-zero is reported as a warning, never as a clean pass.
run_check() { _rc_name=$1; _rc_fn=$2; "$_rc_fn"; _rc_status=$?; if [ "$_rc_status" -ne 0 ]; then add_finding Warning "$_rc_name could not be completed (status $_rc_status)"; fi; }
complete_report() {
    section SUMMARY
    _crit=$(grep -c '^Critical|' "$FINDINGS" 2>/dev/null); _warn=$(grep -c '^Warning|' "$FINDINGS" 2>/dev/null)
    if ! is_uint "$_crit" || ! is_uint "$_warn"; then echo 'internal error: the findings could not be counted' >&2; EXIT_CODE=2; return 0; fi
    if [ "$_crit" -eq 0 ] && [ "$_warn" -eq 0 ]; then
        echo 'No warnings or critical findings.'
        EXIT_CODE=0
        return 0
    fi
    grep '^Critical|' "$FINDINGS" | sed 's/^Critical|/  CRITICAL: /'
    grep '^Warning|' "$FINDINGS" | sed 's/^Warning|/  WARNING:  /'
    if [ "$_crit" -gt 0 ]; then EXIT_CODE=2; else EXIT_CODE=1; fi
}
# validate_uint NAME...: exit 2 with a message when a numeric setting is not a whole number.
validate_uint() { for _v in "$@"; do eval "_val=\$$_v"; if ! is_uint "$_val" || [ "${#_val}" -gt 9 ]; then echo "$_v must be a whole number of at most 9 digits (got '$_val')" >&2; exit 2; fi; done; }
# validate_pct NAME...: a whole number from 1 to 100.
validate_pct() { validate_uint "$@"; for _v in "$@"; do eval "_val=\$$_v"; if [ "$_val" -lt 1 ] || [ "$_val" -gt 100 ]; then echo "$_v must be between 1 and 100 (got '$_val')" >&2; exit 2; fi; done; }
# validate_flag NAME...: exactly 0 or 1.
validate_flag() { for _v in "$@"; do eval "_val=\$$_v"; case "$_val" in 0|1) : ;; *) echo "$_v must be 0 or 1 (got '$_val')" >&2; exit 2 ;; esac; done; }
# validate_decimal NAME...: a non-negative number such as 1 or 0.5.
validate_decimal() { for _v in "$@"; do eval "_val=\$$_v"; case "$_val" in ''|.|*[!0-9.]*|*.*.*) echo "$_v must be a non-negative number (got '$_val')" >&2; exit 2 ;; esac; done; }
# in_list WORD LIST: is WORD one of the newline-separated entries of LIST?
in_list() { printf '%s\n' "$2" | grep -Fqx -- "$1"; }
# osr KEY: value of KEY in the os-release file named by $OS_RELEASE, without quotes.
osr() { sed -n "s/^$1=//p" "$OS_RELEASE" | head -1 | tr -d '"'; }
# first_lines N TEXT: the first N lines of TEXT, indented, for a finding's detail.
first_lines() { printf '%s\n' "$2" | head -n "$1" | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
# in_words WORD WORDS: is WORD one of the space-separated entries of WORDS?
in_words() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

OS_RELEASE=${OS_RELEASE:-/etc/os-release}
SSHD_BIN=${SSHD_BIN:-sshd}

echo 'Debian security posture (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

check_firewall() {
    is_root || { add_finding Warning 'firewall state needs root (ufw status, nft list ruleset); it was not checked'; return 0; }
    found=0
    if have ufw; then
        capture u ufw status
        if [ $? -ne 0 ]; then add_finding Warning "ufw status failed: $(first_lines 2 "$u")"; return 0; fi
        case "$u" in
            *'Status: active'*) note 'UFW is active'; found=1 ;;
            *'Status: inactive'*) note 'UFW is installed but inactive' ;;
            *) add_finding Warning "could not read the UFW status from: $(first_lines 2 "$u")" ;;
        esac
    fi
    if [ "$found" -eq 0 ] && have nft; then
        capture rs nft list ruleset
        if [ $? -ne 0 ]; then add_finding Warning "nft list ruleset failed: $(first_lines 2 "$rs")"; return 0; fi
        hooks=$(printf '%s\n' "$rs" | grep -c 'hook input')
        if [ "$hooks" -gt 0 ]; then note "nftables has $hooks base chain(s) on the input hook (check the policy and rules yourself: a chain with policy accept filters nothing)"; found=1; fi
    fi
    if [ "$found" -eq 0 ]; then
        if have ufw || have nft; then add_finding Warning 'No active host firewall rules were found (UFW inactive and no nftables input chain); Debian installs no firewall by default, so confirm another layer protects this host'
        else add_finding Warning 'Neither ufw nor nft is installed, so no host firewall state could be read'; fi
    fi
    return 0
}
check_apparmor() {
    is_root || { add_finding Warning 'aa-status needs root; AppArmor state was not checked'; return 0; }
    need aa-status || return 0
    aa-status --enabled >/dev/null 2>&1
    aa_rc=$?
    case "$aa_rc" in
        0) : ;;
        1) add_finding Warning 'AppArmor is not enabled or loaded (aa-status --enabled exit 1); Debian does not require it, so confirm that is intended'; return 0 ;;
        2) add_finding Warning 'AppArmor is enabled but no policy is loaded (aa-status --enabled exit 2)'; return 0 ;;
        *) add_finding Warning "aa-status --enabled returned $aa_rc (3 means the control files under /sys/kernel/security are not available)"; return 0 ;;
    esac
    capture pr aa-status --profiled || pr=''
    capture en aa-status --enforced || en=''
    capture cp aa-status --complaining || cp=''
    if ! is_uint "$pr" || ! is_uint "$en" || ! is_uint "$cp"; then add_finding Warning "could not read the AppArmor profile counts (loaded '$pr', enforcing '$en', complaining '$cp')"; return 0; fi
    note "AppArmor: $pr profile(s) loaded, $en enforcing, $cp complaining"
    if [ "$cp" -gt 0 ]; then add_finding Warning "$cp AppArmor profile(s) are in complain mode, which logs but does not block"; fi
    return 0
}
check_ssh() {
    is_root || { add_finding Warning 'sshd -T needs root; the effective SSH settings were not checked'; return 0; }
    if ! have "$SSHD_BIN"; then note 'sshd is not installed; SSH settings were not checked'; return 0; fi
    capture cfg "$SSHD_BIN" -T
    if [ $? -ne 0 ]; then add_finding Warning "sshd -T failed: $(first_lines 2 "$cfg")"; return 0; fi
    prl=$(printf '%s\n' "$cfg" | awk '$1 == "permitrootlogin" { print $2 }')
    pa=$(printf '%s\n' "$cfg" | awk '$1 == "passwordauthentication" { print $2 }')
    pe=$(printf '%s\n' "$cfg" | awk '$1 == "permitemptypasswords" { print $2 }')
    note "sshd: permitrootlogin=${prl:-?} passwordauthentication=${pa:-?} permitemptypasswords=${pe:-?}"
    if [ -z "$prl" ] || [ -z "$pa" ] || [ -z "$pe" ]; then add_finding Warning 'sshd -T did not report permitrootlogin, passwordauthentication and permitemptypasswords (Match blocks are not evaluated)'; return 0; fi
    if [ "$pe" = yes ]; then add_finding Critical 'sshd permits empty passwords'; fi
    if [ "$prl" = yes ]; then add_finding Warning 'sshd permits root login with a password (PermitRootLogin yes)'; fi
    if [ "$pa" = yes ]; then add_finding Warning 'sshd allows password authentication; prefer keys where you can'; fi
    return 0
}
check_sudo() {
    if ! have sudo; then note 'sudo is not installed'; return 0; fi
    capture sv sudo --version || { add_finding Warning 'sudo --version failed'; return 0; }
    note "sudo: $(printf '%s\n' "$sv" | head -1)"
    if have dpkg-query; then
        capture ldap dpkg-query -W -f '${Status}' sudo-ldap
        case "$ldap" in
            *' ok installed') add_finding Warning 'sudo-ldap is installed; the Debian 13 release notes say it will be removed in forky, so move to libsss-sudo' ;;
        esac
    fi
    return 0
}

section '1. HOST FIREWALL';         run_check Firewall check_firewall
section '2. APPARMOR';              run_check AppArmor check_apparmor
section '3. SSH';                   run_check SSH check_ssh
section '4. SUDO';                  run_check sudo check_sudo

complete_report
exit "$EXIT_CODE"
