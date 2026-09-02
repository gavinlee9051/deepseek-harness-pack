#!/usr/bin/env bash
# patch-archive.sh - Apply the merged "archive session" feature (归档会话) onto
# the installed dsh core, so the web UI gains archive / restore / delete.
#
# This is the runtime half of the feature merged from gavinlee9051/dsh-modern-skin
# (patches/archive-core-rc2.mjs). It is version-pinned: the patch rewrites
# compiled dsh core files whose exact anchors change with every dsh release, so
# it only runs against the dsh version it was validated on (see below). On any
# other version it prints a note and exits 0 so the harness still starts.
#
# Idempotent: re-running after an upgrade or a partial failure re-applies; a
# file that already carries the archive marker is left untouched.
#
# WARNING: modifies installed dsh core files under the global node_modules
# (@deepseek-ai/*). An `npm install -g @deepseek-ai/dsh` restores the originals;
# every start re-applies automatically (see run.sh).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

ARCHIVE_SUPPORTED="0.1.1-rc.2"
PATCH="$SCRIPT_DIR/patches/archive-core-rc2.mjs"
ARCHIVE_MARKER="Permanently delete one session"

# Global install root where @deepseek-ai/dsh (and its bundled @deepseek-ai/*)
# live. The patch edits those bundled packages, NOT ~/.dsh profiles.
ARCHIVE_ROOT="$(npm root -g 2>/dev/null)/@deepseek-ai/dsh/node_modules/@deepseek-ai"
WS="$ARCHIVE_ROOT/dsh-workspace/lib/index.js"

[ -f "$PATCH" ] || { echo "[archive] patch file not found: $PATCH"; exit 1; }
[ -f "$WS" ] || { echo "[archive] dsh workspace not found: $WS"; echo "[archive] run the installer first (install.sh)"; exit 1; }

VER="$(dsh --version 2>/dev/null | tr -d '[:space:]')"
if [ "$VER" != "$ARCHIVE_SUPPORTED" ]; then
  echo "[archive] skipped: dsh '$VER' does not match supported '$ARCHIVE_SUPPORTED'"
  exit 0
fi

if grep -qF "$ARCHIVE_MARKER" "$WS"; then
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
