#!/usr/bin/env bash
# recon_chain.sh - orchestrate a passive-first external recon sweep.
#
# Chains whichever recon CLIs are present on PATH (subfinder/amass for
# subdomain enumeration, httpx for live-host validation) into one normalised
# asset list. Deliberately stops short of content discovery and screenshotting
# (ffuf/gowitness); run those separately, by hand, once the live-host list has
# been reviewed, per the manual-review-point discipline in
# references/tooling-landscape.md.
#
# HARD SAFETY GATE: refuses to run against any target unless called with
# --i-have-authorization pointing at a scope file that names this exact
# engagement. This operationalises the authorisation discipline this skill
# inherits from penetration-testing (or, for Kacific assets,
# kacific-security-assessment-scope) in the tooling itself, not just prose.
#
# Usage:
#   recon_chain.sh --domain example.com --i-have-authorization scope.txt [--outdir ./recon-out]
#
# scope.txt is a plain-text file you create yourself, naming: the authorised
# scope, the engagement/RoE reference, and the authorising contact. Its mere
# existence is not authorisation; it is a local record that you confirmed
# authorisation exists before running this script. If you have not confirmed
# written authorisation, do not create this file and do not run this script.

set -euo pipefail

DOMAIN=""
SCOPE_FILE=""
OUTDIR="./recon-out"

usage() {
  cat <<'EOF'
Usage: recon_chain.sh --domain <domain> --i-have-authorization <scope-file> [--outdir <dir>]

Required:
  --domain <domain>                 seed domain to enumerate (e.g. example.com)
  --i-have-authorization <file>     path to a local scope file confirming written
                                     authorisation for this exact engagement.
                                     The script refuses to run without this.

Optional:
  --outdir <dir>                    output directory (default: ./recon-out)
  -h, --help                        show this help and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --i-have-authorization) SCOPE_FILE="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" || -z "$SCOPE_FILE" ]]; then
  echo "error: --domain and --i-have-authorization are both required." >&2
  echo "This script will not run an external recon sweep without an explicit," >&2
  echo "on-disk record that you confirmed written authorisation first." >&2
  echo >&2
  usage
  exit 2
fi

if [[ ! -s "$SCOPE_FILE" ]]; then
  echo "error: scope file '$SCOPE_FILE' does not exist or is empty." >&2
  echo "Create it with the authorised scope, RoE/engagement reference, and" >&2
  echo "authorising contact before running this script. See penetration-testing's" >&2
  echo "examples/rules_of_engagement_template.md for the fields to capture." >&2
  exit 2
fi

echo "Scope file confirmed: $SCOPE_FILE"
echo "----"
cat "$SCOPE_FILE"
echo "----"
read -r -p "Does the above correctly describe THIS run against '$DOMAIN'? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted: confirmation not given." >&2
  exit 3
fi

mkdir -p "$OUTDIR"
SUBS_FILE="$OUTDIR/subdomains.txt"
LIVE_FILE="$OUTDIR/live-hosts.json"
ASSETS_FILE="$OUTDIR/assets.csv"

: > "$SUBS_FILE"

echo "[1/3] Passive subdomain enumeration for $DOMAIN"
if command -v subfinder >/dev/null 2>&1; then
  subfinder -silent -d "$DOMAIN" >> "$SUBS_FILE" || true
elif command -v amass >/dev/null 2>&1; then
  amass enum -passive -silent -d "$DOMAIN" >> "$SUBS_FILE" || true
else
  echo "  warning: neither subfinder nor amass found on PATH; skipping passive enumeration." >&2
  echo "  install one of them, or supply a pre-built subdomain list at $SUBS_FILE and re-run." >&2
fi
sort -u -o "$SUBS_FILE" "$SUBS_FILE"
echo "  $(wc -l < "$SUBS_FILE" | tr -d ' ') candidate subdomain(s) written to $SUBS_FILE"

echo "[2/3] Live-host validation"
if command -v httpx >/dev/null 2>&1; then
  httpx -silent -json -status-code -title -tech-detect -l "$SUBS_FILE" > "$LIVE_FILE" || true
  echo "  live-host results written to $LIVE_FILE"
else
  echo "  warning: httpx not found on PATH; skipping live-host validation." >&2
  echo "  install httpx (github.com/projectdiscovery/httpx) to complete this stage." >&2
  : > "$LIVE_FILE"
fi

echo "[3/3] Normalising into $ASSETS_FILE"
echo "hostname,resolved_ip,live,status_code,redirect_to,technology,screenshot_ref,source_technique" > "$ASSETS_FILE"
if [[ -s "$LIVE_FILE" ]] && command -v python3 >/dev/null 2>&1; then
  python3 - "$LIVE_FILE" "$ASSETS_FILE" <<'PYEOF'
import json, sys, csv

live_file, assets_file = sys.argv[1], sys.argv[2]
rows = []
with open(live_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        rows.append([
            rec.get("input") or rec.get("url", ""),
            ",".join(rec.get("a", []) or []),
            "yes",
            rec.get("status_code", ""),
            rec.get("location", ""),
            ";".join(rec.get("tech", []) or []),
            "",
            "httpx",
        ])

with open(assets_file, "a", newline="", encoding="utf-8") as fh:
    writer = csv.writer(fh)
    writer.writerows(rows)

print(f"  appended {len(rows)} live-host record(s)")
PYEOF
else
  echo "  no live-host JSON to normalise (httpx unavailable or produced no output)."
fi

echo
echo "Done. Review $ASSETS_FILE by hand before running any content discovery or"
echo "screenshot pass (deliberately not automated by this script), and before"
echo "handing the list to attack-surface-management or penetration-testing."
