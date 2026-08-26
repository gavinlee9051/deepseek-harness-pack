#!/usr/bin/env bash
# _common.sh - Shared bootstrap sourced by every script in this package.
# Resolves the package directory and the Node.js binary dir without any
# hardcoded paths, so the package works for any user / install location.
# An env.sh written by install.sh (optional) can pin DEPLOY_DIR/NODE_BIN_DIR.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

if [ -f "$SCRIPT_DIR/env.sh" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/env.sh"
fi

DEPLOY_DIR="${DEPLOY_DIR:-$SCRIPT_DIR}"

# Locate node: explicit pin > PATH > default nvm location.
if [ -n "${NODE_BIN_DIR:-}" ] && [ -x "$NODE_BIN_DIR/node" ]; then
  export PATH="$NODE_BIN_DIR:$PATH"
elif ! command -v node >/dev/null 2>&1; then
  NVM_DEFAULT="$HOME/.nvm/versions/node"
  if [ -d "$NVM_DEFAULT" ]; then
    LATEST="$(ls -1 "$NVM_DEFAULT" 2>/dev/null | sort -V | tail -1)"
    [ -n "$LATEST" ] && export PATH="$NVM_DEFAULT/$LATEST/bin:$PATH"
  fi
fi
