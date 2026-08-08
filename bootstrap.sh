#!/usr/bin/env bash
# Run on a fresh machine after cloning this repo. Builds the generic skill BASE
# into ~/.claude/skills as a symlink farm. Overlay-agnostic: if you also maintain
# a private/overlay vault, run that vault's overlay builder afterwards.
#
# Brownfield guard: the base build resets the whole farm, so it must NOT run on a
# machine whose farm already carries an overlay (per-skill links pointing at a
# different vault); that would strip the overlay. If one is detected we refuse
# (exit 6) and point at the overlay builder, which is the correct entry point on
# such a machine (it resets, rebuilds the base, then re-adds its own layer).
# Override with SKILLS_FARM_RESET=1 only when you deliberately mean to drop the
# overlay and go back to a generic-only farm.
#
# Exit codes: 0/2/3 propagate from build-farm-base.sh; 6 = refused because the
# farm carries an overlay.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_BASE="${VAULT:-$here}"
FARM="${SKILLS_FARM:-$HOME/.claude/skills}"

if [ -d "$FARM" ] && [ "${SKILLS_FARM_RESET:-}" != "1" ]; then
  overlay=0
  for l in "$FARM"/*; do
    [ -L "$l" ] || continue
    case "$(readlink "$l")" in
      "$VAULT_BASE"/*) : ;;             # a base link this vault owns
      *) overlay=$((overlay + 1)) ;;    # points elsewhere: an overlay link
    esac
  done
  if [ "$overlay" -gt 0 ]; then
    echo "error: $FARM already carries $overlay overlay link(s) from another vault." >&2
    echo "Rebuilding the base here would strip them. Run this machine's overlay builder" >&2
    echo "instead (it rebuilds the base and re-adds the overlay); do not run bootstrap.sh" >&2
    echo "directly on an overlay machine. To drop the overlay on purpose, re-run with:" >&2
    echo "  SKILLS_FARM_RESET=1 bash $here/bootstrap.sh" >&2
    exit 6
  fi
fi

SKILLS_VAULT_BASE="$VAULT_BASE" exec bash "$here/build-farm-base.sh"
