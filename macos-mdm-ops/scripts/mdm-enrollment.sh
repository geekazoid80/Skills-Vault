#!/bin/sh
# macOS MDM enrollment summary.
#
# READ ONLY: this script only reads state and changes nothing. Reports the enrollment state, Automated Device Enrollment, user approval, the bootstrap token state and FileVault recovery keys. With CHECK_NETWORK=1 it tests TCP 443 to the device-side Apple enrollment hosts.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Run as root for the complete picture (sudo sh mdm-enrollment.sh). Environment: CHECK_NETWORK.
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: sudo sh mdm-enrollment.sh
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

CHECK_NETWORK=${CHECK_NETWORK:-0}

echo 'macOS MDM enrollment (read only)'
printf 'Generated: %s (UTC); network reachability checks %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$( [ "$CHECK_NETWORK" = 1 ] && echo ON || echo off)"

check_version() {
    need sw_vers || return 0
    capture ver sw_vers -productVersion || { add_finding Warning 'sw_vers failed'; return 0; }
    note "macOS $ver"
    return 0
}
check_enrollment() {
    need profiles || return 0
    capture out profiles status -type enrollment
    if [ $? -ne 0 ]; then add_finding Warning "profiles status -type enrollment failed: $out"; return 0; fi
    printf '%s\n' "$out" | sed 's/^/  /'
    case "$out" in
        *"MDM enrollment: Yes"*) :
            case "$out" in
                *"User Approved"*) : ;;
                *"Enrolled via DEP: Yes"*) : ;;
                *) add_finding Warning 'The MDM enrollment is neither user approved nor made through Automated Device Enrollment, so many controls are unavailable' ;;
            esac ;;
        *"MDM enrollment: No"*) add_finding Warning 'This Mac is not enrolled in MDM' ;;
        *) add_finding Warning "could not read the enrollment state from: $out" ;;
    esac
    case "$out" in
        *"Enrolled via DEP: Yes"*|*"Enrolled via DEP: No"*) : ;;
        *) add_finding Warning 'The Automated Device Enrollment line was not found in the output' ;;
    esac
    return 0
}
check_bootstrap() {
    need profiles || return 0
    capture out profiles status -type bootstraptoken
    if [ $? -ne 0 ]; then add_finding Warning "profiles status -type bootstraptoken failed (run as root): $out"; return 0; fi
    printf '%s\n' "$out" | sed 's/^/  /'
    sup=$(printf '%s\n' "$out" | sed -n 's/.*supported on server: *\([A-Za-z]*\).*/\1/p' | head -1)
    esc=$(printf '%s\n' "$out" | sed -n 's/.*escrowed to server: *\([A-Za-z]*\).*/\1/p' | head -1)
    if [ -z "$sup" ] || [ -z "$esc" ]; then add_finding Warning "could not read the bootstrap token state from: $out"; return 0; fi
    if [ "$sup" = YES ] && [ "$esc" != YES ]; then add_finding Warning 'The MDM service supports the bootstrap token but this Mac has not escrowed one (FileVault key rotation and on-demand Platform SSO accounts depend on it)'; fi
    if [ "$sup" != YES ]; then note 'The MDM service does not report bootstrap token support'; fi
    return 0
}
check_filevault_keys() {
    need fdesetup || return 0
    capture p fdesetup haspersonalrecoverykey
    capture i fdesetup hasinstitutionalrecoverykey
    note "FileVault personal recovery key present: $p; institutional recovery key present: $i"
    case "$p$i" in *true*) : ;; *) add_finding Warning 'No FileVault recovery key is reported (or FileVault is off)' ;; esac
    return 0
}
check_network() {
    if [ "$CHECK_NETWORK" != 1 ]; then note 'skipped: set CHECK_NETWORK=1 to test the device-side hosts Apple documents for enrollment'; return 0; fi
    need nc || return 0
    for h in albert.apple.com iprofiles.apple.com deviceenrollment.apple.com; do
        if nc -z -G 5 "$h" 443 >/dev/null 2>&1; then note "$h:443 reachable"; else add_finding Warning "$h:443 is not reachable from this Mac"; fi
    done
    note 'Only the device-side hosts are tested, and only as a TCP connection; a proxy that breaks TLS would still pass. The service-side hosts (mdmenrollment, identity, gdmf, vpp) are the management service'"'"'s to reach, and APNs (*.push.apple.com on 443, 80, 5223 and 2197) is a wildcard Apple does not list as hosts, so neither is tested.'
    return 0
}

if ! is_root; then add_finding Warning 'Not running as root; some profiles subcommands return only the current user view or fail'; fi
section '1. PLATFORM';             run_check Platform check_version
section '2. ENROLLMENT';           run_check Enrollment check_enrollment
section '3. BOOTSTRAP TOKEN';      run_check 'Bootstrap token' check_bootstrap
section '4. FILEVAULT RECOVERY KEYS'; run_check 'FileVault recovery keys' check_filevault_keys
section '5. APPLE SERVICE REACHABILITY (active)'; run_check Reachability check_network

complete_report
exit "$EXIT_CODE"
