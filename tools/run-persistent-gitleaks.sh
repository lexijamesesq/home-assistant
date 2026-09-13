#!/usr/bin/env bash
# Persistent-runtime launcher. The native adapter supplies its validated root;
# keeping launch policy here makes the environment and protocol seam testable.

set -euo pipefail

REPO_ROOT="${1:?repository root required}"
shift
DOTTY_HOOKS_COMMIT="4fb7b2cdd8390be9bd7ad58ca3bfdf4653e24c41"
HOOK="$REPO_ROOT/.tools/dotty-hooks/$DOTTY_HOOKS_COMMIT/gitleaks-pre-push.sh"

# These modes belong to trusted CI lanes. An inherited shell environment must
# never weaken or redirect the native Pi scan.
unset GL_NO_OVERLAY GL_OVERLAY_ONLY GL_CONFIG_PATH GL_IGNORE_PATH GL_BASE_REF GL_DECLARED_JSON
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
unset PRE_COMMIT_FROM_REF PRE_COMMIT_TO_REF PRE_COMMIT_REMOTE_NAME PRE_COMMIT_REMOTE_BRANCH

export PATH="$REPO_ROOT/.tools:$PATH"
export XDG_CONFIG_HOME="$REPO_ROOT/.tools/operator-config"

if [[ ! -x "$HOOK" ]]; then
    echo "pre-push: shared scanner missing at $HOOK — run tools/install-hooks.sh. Refusing to push unscanned." >&2
    exit 1
fi

exec "$HOOK" "$@"
