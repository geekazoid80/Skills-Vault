#!/bin/sh
# macOS security posture summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports System Integrity Protection, the authenticated root volume, Gatekeeper, FileVault, the application firewall, Remote Login, update settings, XProtect and local administrators. It reports; it does not harden.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Run as the logged-in administrator; no sudo is needed. Environment: SOCKETFILTERFW, MAX_ADMINS. Its only probe is a TCP connection to localhost port 22 (no login).
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sh security-posture.sh
#
# shellcheck disable=SC2043,SC2154,SC2181,SC2329
# (SC2154: capture() assigns the named variable through eval; SC2181: the status tested is capture's;
#  SC2329: check functions are called through run_check; SC2043: single-name validation loops.)

set -u
LC_ALL=C
export LC_ALL
EXIT_CODE=2   # any path that does not reach a verdict exits 2
FINDINGS=$(mktemp "${TMPDIR:-/tmp}/macos-skill.XXXXXX") || { echo "cannot create a temporary file" >&2; exit 2; }
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
    _crit=${_crit:-0}; _warn=${_warn:-0}
    if [ "$_crit" -eq 0 ] && [ "$_warn" -eq 0 ]; then
        echo 'No warnings or critical findings.'
        EXIT_CODE=0
        return 0
    fi
    grep '^Critical|' "$FINDINGS" | sed 's/^Critical|/  CRITICAL: /'
    grep '^Warning|' "$FINDINGS" | sed 's/^Warning|/  WARNING:  /'
    if [ "$_crit" -gt 0 ]; then EXIT_CODE=2; else EXIT_CODE=1; fi
}

SOCKETFILTERFW=${SOCKETFILTERFW:-/usr/libexec/ApplicationFirewall/socketfilterfw}
MAX_ADMINS=${MAX_ADMINS:-3}      # local administrators other than root
for _v in MAX_ADMINS; do
    eval "_val=\$$_v"
    is_uint "$_val" || { echo "$_v must be a whole number (got '$_val')" >&2; exit 2; }
done

echo 'macOS security posture'
printf 'Generated: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

check_sip() {
    need csrutil || return 0
    capture out csrutil status || { add_finding Warning "csrutil status failed: $out"; return 0; }
    note "$out"
    case "$out" in
        *"Custom Configuration"*) add_finding Critical 'System Integrity Protection is in a custom configuration (parts of it were disabled from Recovery)' ;;
        *enabled*) : ;;
        *disabled*) add_finding Critical 'System Integrity Protection is disabled' ;;
        *) add_finding Warning "could not read the SIP state from: $out" ;;
    esac
    capture ar csrutil authenticated-root status
    case "$ar" in
        *enabled*) note "$ar" ;;
        *disabled*) note "$ar"; add_finding Warning 'Authenticated root volume (signed system volume seal) is disabled' ;;
        *) add_finding Warning "could not read the authenticated root state from: $ar" ;;
    esac
    return 0
}
check_gatekeeper() {
    need spctl || return 0
    capture out spctl --status || true
    note "$out"
    case "$out" in
        *"assessments enabled"*) : ;;
        *"assessments disabled"*) add_finding Critical 'Gatekeeper assessments are disabled' ;;
        *) add_finding Warning "could not read the Gatekeeper state from: $out" ;;
    esac
    return 0
}
check_filevault() {
    need fdesetup || return 0
    capture out fdesetup status || true
    note "$out"
    case "$out" in
        *"Encryption in progress"*|*"Decryption in progress"*) add_finding Warning "FileVault is mid-operation: $out" ;;
        *"FileVault is On"*) : ;;
        *"FileVault is Off"*) add_finding Critical 'FileVault is off' ;;
        *) add_finding Warning "could not read the FileVault state from: $out" ;;
    esac
    return 0
}
check_firewall() {
    if [ ! -x "$SOCKETFILTERFW" ]; then add_finding Warning "socketfilterfw not found at $SOCKETFILTERFW"; return 0; fi
    capture out "$SOCKETFILTERFW" --getglobalstate || true
    note "$out"
    case "$out" in
        *"is enabled"*|*"State = 1"*|*"State = 2"*) : ;;
        *"is disabled"*|*"State = 0"*) add_finding Warning 'The application firewall is disabled (acceptable only if another host firewall is managed)' ;;
        *) add_finding Warning "could not read the firewall state from: $out" ;;
    esac
    capture st "$SOCKETFILTERFW" --getstealthmode || true
    note "$st"
    return 0
}
check_remote_login() {
    if ! have nc; then add_finding Warning 'nc not found; Remote Login was not checked'; return 0; fi
    capture probe nc -z -w 2 127.0.0.1 22
    prc=$?
    if [ "$prc" -eq 0 ]; then
        note 'Port 22 is listening on localhost (Remote Login appears enabled)'
        add_finding Warning 'Remote Login (SSH) appears enabled; confirm it is intended and limited to the right users'
    else
        case "$probe" in
            *efused*) note 'Nothing listening on port 22 (Remote Login appears off)' ;;
            *) add_finding Warning "The port 22 probe failed without a clear refusal, so Remote Login was not evaluated: $probe" ;;
        esac
    fi
    return 0
}
check_updates() {
    need defaults || return 0
    for key in AutomaticCheckEnabled AutomaticDownload CriticalUpdateInstall ConfigDataInstall; do
        capture v defaults read /Library/Preferences/com.apple.SoftwareUpdate "$key"
        if [ $? -ne 0 ]; then note "$key: not set (system default applies)"; continue; fi
        note "$key = $v"
        if [ "$v" = "0" ]; then add_finding Warning "Software Update setting $key is 0"; fi
    done
    note 'These keys describe the local setting. On managed Macs updates are enforced with declarative software update management; legacy MDM update management stopped working in macOS 27.'
    capture xp defaults read /Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist CFBundleShortVersionString
    if [ $? -eq 0 ]; then note "XProtect version: $xp"; else add_finding Warning 'XProtect version could not be read'; fi
    return 0
}
check_accounts() {
    need dscl || return 0
    capture admins dscl . -read /Groups/admin GroupMembership || { add_finding Warning 'could not read the admin group'; return 0; }
    members=$(printf '%s\n' "$admins" | sed 's/^GroupMembership: *//')
    others=$(printf '%s\n' "$members" | tr ' ' '\n' | grep -v '^root$' | grep -v '^$' | tr '\n' ' ')
    count=$(printf '%s\n' "$others" | wc -w | tr -d ' ')
    note "Administrators other than root ($count): $others"
    if [ "$count" -gt "$MAX_ADMINS" ]; then add_finding Warning "$count local administrators besides root (more than $MAX_ADMINS, a rule of thumb)"; fi
    capture guest defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled
    if [ $? -eq 0 ] && [ "$guest" = "1" ]; then add_finding Warning 'The guest account is enabled'; fi
    return 0
}

section '1. SYSTEM INTEGRITY PROTECTION'; run_check SIP check_sip
section '2. GATEKEEPER';                  run_check Gatekeeper check_gatekeeper
section '3. FILEVAULT';                   run_check FileVault check_filevault
section '4. APPLICATION FIREWALL';        run_check Firewall check_firewall
section '5. REMOTE LOGIN';                run_check 'Remote Login' check_remote_login
section '6. UPDATE SETTINGS AND XPROTECT'; run_check Updates check_updates
section '7. ACCOUNTS';                    run_check Accounts check_accounts

complete_report
exit "$EXIT_CODE"
