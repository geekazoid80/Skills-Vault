#!/bin/sh
# SLES security posture summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports SELinux (SLES 16) or AppArmor (SLES 15), firewalld state and effective sshd settings (as root). It reports; it does not harden.
# POSIX sh (/bin/sh is bash on SLES). Run as root (sudo sh security-posture.sh); without root several checks warn that they were not performed.
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
# shellcheck disable=SC2016,SC2034,SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops;
#  SC2016: where used, single-quoted format strings contain a literal ${...};
#  SC2034: release-phase table values are read through eval.)

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
first_lines() { printf '%s\n' "$2" | head -n "$1" | sed 's#://[^/@ ]*@#://[redacted]@#g' | tr '\n' ';' | sed 's/;$//; s/;/; /g'; }
# in_words WORD WORDS: is WORD one of the space-separated entries of WORDS?
in_words() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }

OS_RELEASE=${OS_RELEASE:-/etc/os-release}
SELINUX_CONFIG=${SELINUX_CONFIG:-/etc/selinux/config}
SSHD_BIN=${SSHD_BIN:-sshd}

echo 'SLES security posture (read only)'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

MAJOR=''
resolve_release() {
    [ -r "$OS_RELEASE" ] || return 0
    vid=$(osr VERSION_ID); MAJOR=${vid%%.*}
    return 0
}
check_selinux() {
    case "$MAJOR" in
        16) : ;;
        15) if ! have getenforce || [ "$(getenforce 2>/dev/null)" = Disabled ]; then note 'SLES 15 defaults to AppArmor; SELinux is not in use here (SUSE supports SELinux on 15 SP7 as an option, and it is the default from 16)'; return 0; fi ;;
        *) add_finding Warning "VERSION_ID major '${MAJOR:-unknown}' is not 15 or 16, so the expected security framework is unknown" ;;
    esac
    need getenforce || return 0
    capture mode getenforce
    if [ $? -ne 0 ]; then add_finding Warning "getenforce failed: $mode"; return 0; fi
    cfg=''
    if [ -r "$SELINUX_CONFIG" ]; then cfg=$(sed -n 's/^SELINUX=//p' "$SELINUX_CONFIG" | head -1); fi
    note "SELinux runtime mode: $mode; configured mode: ${cfg:-unreadable}"
    case "$mode" in
        Enforcing) : ;;
        Permissive) add_finding Warning 'SELinux is permissive: it logs but does not block' ;;
        Disabled) add_finding Critical 'SELinux is disabled' ;;
        *) add_finding Warning "unexpected getenforce output '$mode'" ;;
    esac
    is_root || { add_finding Warning 'ausearch needs root; SELinux denials were not checked'; return 0; }
    if have ausearch; then
        if have systemctl && ! systemctl is-active --quiet auditd 2>/dev/null; then add_finding Warning 'auditd is not active, so denials go to the journal and the ausearch result below is not reliable'; fi
        capture av ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts today
        av_rc=$?
        if [ "$av_rc" -eq 1 ]; then
            case "$av" in
                *'<no matches>'*) note 'No SELinux denials today (ausearch -ts today found no matches)' ;;
                *) add_finding Warning "ausearch exited 1 without reporting no matches, so denials could not be checked: $(first_lines 2 "$av")" ;;
            esac
        elif [ "$av_rc" -eq 0 ]; then n=$(printf '%s\n' "$av" | grep -c '^type='); add_finding Warning "ausearch found $n SELinux denial or error record(s) today; read them before changing policy"
        else add_finding Warning "ausearch returned $av_rc: $(first_lines 2 "$av")"; fi
    else
        note 'ausearch is not installed (package audit); denials were not checked'
    fi
    return 0
}
check_apparmor() {
    case "$MAJOR" in
        15) : ;;
        16) note 'SLES 16 replaced AppArmor with SELinux'; return 0 ;;
        *) return 0 ;;
    esac
    is_root || { add_finding Warning 'aa-status needs root; AppArmor state was not checked'; return 0; }
    if ! have aa-status; then note 'aa-status is not installed; AppArmor was not checked (SELinux may be in use on this 15 host)'; return 0; fi
    aa-status --enabled >/dev/null 2>&1
    aa_rc=$?
    case "$aa_rc" in
        0) : ;;
        1) add_finding Warning 'AppArmor is not enabled or loaded (aa-status --enabled exit 1)'; return 0 ;;
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
check_firewall() {
    need firewall-cmd || return 0
    capture st firewall-cmd --state
    if [ $? -ne 0 ]; then add_finding Warning "firewalld is not running or firewall-cmd failed: $(first_lines 2 "$st")"; return 0; fi
    case "$st" in
        running) note 'firewalld is running' ;;
        *) add_finding Warning "unexpected firewall-cmd --state output '$st'" ;;
    esac
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
    if [ "$prl" = yes ]; then add_finding Warning 'sshd permits root login with a password (PermitRootLogin yes); new SLES 16 installations turn this off by default'; fi
    if [ "$pa" = yes ]; then add_finding Warning 'sshd allows password authentication; prefer keys where you can'; fi
    return 0
}

run_check Release resolve_release
section '1. SELINUX (SLES 16)';   run_check SELinux check_selinux
section '2. APPARMOR (SLES 15)';  run_check AppArmor check_apparmor
section '3. FIREWALL';            run_check Firewall check_firewall
section '4. SSH';                 run_check SSH check_ssh

complete_report
exit "$EXIT_CODE"
