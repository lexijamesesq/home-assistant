#!/usr/bin/env bash
# Home Assistant adapter for Dotty's canonical fail-closed pre-push scanner.
# Runtime files and private rules live below /config's persistent volume.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "$REPO_ROOT" != "/homeassistant" ]]; then
    echo "pre-push: refusing — expected the /config checkout at /homeassistant (got '${REPO_ROOT:-<none>}')." >&2
    exit 1
fi

exec "$REPO_ROOT/tools/run-persistent-gitleaks.sh" "$REPO_ROOT" "$@"
