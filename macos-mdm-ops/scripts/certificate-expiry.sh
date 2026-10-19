#!/bin/sh
# macOS system keychain certificate expiry.
#
# READ ONLY: this script only reads state and changes nothing. Reads the certificates in the system keychain and reports those that have expired or expire within a window. It never exports a private key.
# POSIX sh; runs under the stock /bin/sh (bash 3.2) on macOS. Environment: CERT_WARN_DAYS, KEYCHAIN, CERT_FILTER (an extended regular expression on the subject).
# Exit codes: 0 no findings, 1 warnings only (this includes any check that could not run), 2 critical findings.
# A command that is missing, fails or returns nothing is reported as a warning, never as a pass.
#
# Not run against a live Mac in this vault: it is checked with shellcheck and exercised against stub
# commands only, so the output formats it parses are taken from documentation and local man pages. Try it
# on a non-critical Mac first.
#
# Example: CERT_WARN_DAYS=60 CERT_FILTER="Example Corp" sh certificate-expiry.sh
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

WARN_DAYS=${CERT_WARN_DAYS:-30}
KEYCHAIN=${KEYCHAIN:-/Library/Keychains/System.keychain}
FILTER=${CERT_FILTER:-}      # optional extended regex matched against the certificate subject
work=''
trap 'rm -f "$FINDINGS"; if [ -n "$work" ]; then rm -rf "$work"; fi' EXIT
is_uint "$WARN_DAYS" || { echo "CERT_WARN_DAYS must be a whole number of days (got '$WARN_DAYS')" >&2; exit 2; }
if [ -n "$FILTER" ]; then
    printf '' | grep -Eq "$FILTER"
    if [ $? -eq 2 ]; then echo "CERT_FILTER is not a valid extended regular expression ('$FILTER')" >&2; exit 2; fi
fi

echo 'macOS system keychain certificate expiry (read only)'
printf 'Generated: %s (UTC); warning window %s day(s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$WARN_DAYS"

check_certs() {
    need security || return 0
    need openssl || return 0
    work=$(mktemp -d "${TMPDIR:-/tmp}/cert-expiry.XXXXXX") || { add_finding Warning 'could not create a temporary directory'; return 0; }
    capture pem security find-certificate -a -p "$KEYCHAIN"
    if [ $? -ne 0 ]; then add_finding Warning "security find-certificate failed for $KEYCHAIN: $pem"; rm -rf "$work"; return 0; fi
    printf '%s\n' "$pem" | awk -v d="$work" '/-----BEGIN CERTIFICATE-----/ { n++; f = sprintf("%s/c%04d.pem", d, n) } f { print > f } /-----END CERTIFICATE-----/ { close(f); f = "" }'
    total=0; matched=0; expired=0; soon=0
    for c in "$work"/c*.pem; do
        [ -e "$c" ] || continue
        total=$((total + 1))
        subj=$(openssl x509 -in "$c" -noout -subject 2>/dev/null | sed 's/^subject= *//')
        if [ -z "$subj" ]; then add_finding Warning "certificate $(basename "$c") could not be parsed by openssl"; continue; fi
        if [ -n "$FILTER" ] && ! printf '%s' "$subj" | grep -Eq "$FILTER"; then continue; fi
        matched=$((matched + 1))
        end=$(openssl x509 -in "$c" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
        if ! openssl x509 -in "$c" -noout -checkend 0 >/dev/null 2>&1; then
            expired=$((expired + 1)); note "EXPIRED  $end  $subj"
        elif ! openssl x509 -in "$c" -noout -checkend $((WARN_DAYS * 86400)) >/dev/null 2>&1; then
            soon=$((soon + 1)); note "EXPIRING $end  $subj"
        fi
    done
    rm -rf "$work"; work=''
    note "$total certificate(s) read from $KEYCHAIN; $matched checked$([ -n "$FILTER" ] && echo " (subject matches '$FILTER')"); $expired expired, $soon expiring within $WARN_DAYS day(s)"
    if [ "$total" -eq 0 ]; then add_finding Warning "No certificates were read from $KEYCHAIN"; return 0; fi
    if [ "$matched" -eq 0 ]; then add_finding Warning "CERT_FILTER '$FILTER' matched none of the $total certificate(s); nothing was checked"; return 0; fi
    if [ "$soon" -gt 0 ]; then add_finding Warning "$soon certificate(s) in $KEYCHAIN expire within $WARN_DAYS days"; fi
    if [ "$expired" -gt 0 ]; then add_finding Warning "$expired expired certificate(s) in $KEYCHAIN (review any MDM, SCEP or identity certificates; use CERT_FILTER to narrow)"; fi
    return 0
}

section '1. SYSTEM KEYCHAIN CERTIFICATES'; run_check Certificates check_certs

complete_report
exit "$EXIT_CODE"
