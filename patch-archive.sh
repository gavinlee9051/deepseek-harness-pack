#!/usr/bin/env bash
# patch-archive.sh - Apply the merged "archive session" feature (归档会话) onto
# the installed dsh core: the web UI gains archive / restore / delete.
#
# The feature is version-specific: the patch rewrites compiled dsh core files
# whose exact anchors change with every dsh release, so it only runs against a
# dsh version it was validated on (see the table below). On any other version it
# prints a note and exits 0 so the harness still starts.
#
#   dsh version    patch                       what it adds
#   0.1.1-rc.2     archive-core-rc2.mjs        archive + restore + delete
#   0.1.5-rc.1     archive-core-0.1.5.mjs      restore + delete (archive is upstream)
#
# Idempotent: a file already carrying the version's marker is left untouched.
# Sourced from gavinlee9051/dsh-modern-skin (core feature only, no skin).
#
# WARNING: modifies installed dsh core files under the global node_modules
# (@deepseek-ai/*). An `npm install -g @deepseek-ai/dsh` restores the originals;
# every start re-applies automatically (see run.sh).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

# Global install root where @deepseek-ai/dsh (and its bundled @deepseek-ai/*)
# live. The patch edits those bundled packages, NOT ~/.dsh profiles.
ARCHIVE_ROOT="$(npm root -g 2>/dev/null)/@deepseek-ai/dsh/node_modules/@deepseek-ai"
WS="$ARCHIVE_ROOT/dsh-workspace/lib/index.js"

[ -f "$WS" ] || { echo "[archive] dsh workspace not found: $WS"; echo "[archive] run the installer first (install.sh)"; exit 1; }

VER="$(dsh --version 2>/dev/null | tr -d '[:space:]')"
case "$VER" in
  0.1.1-rc.2)
    PATCH="$SCRIPT_DIR/patches/archive-core-rc2.mjs"
    MARKER="Permanently delete one session"
    ;;
  0.1.5-rc.1)
    PATCH="$SCRIPT_DIR/patches/archive-core-0.1.5.mjs"
    MARKER="deleteSession(sessionId) {"
    ;;
  *)
    echo "[archive] skipped: dsh '$VER' has no validated archive patch"
    exit 0
    ;;
esac

[ -f "$PATCH" ] || { echo "[archive] patch file not found: $PATCH"; exit 1; }

if grep -qF "$MARKER" "$WS"; then
  echo "[archive] already applied"
  exit 0
fi

echo "[archive] applying archive session feature to dsh $VER ..."
if node "$PATCH" --root "$ARCHIVE_ROOT"; then
  echo "[archive] applied"
else
  echo "[archive] WARNING: apply reported a failure (dsh layout changed?)"
  echo "[archive]          reinstall dsh, then start again to retry"
  exit 1
fi
