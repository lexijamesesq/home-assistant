#!/usr/bin/env bash
# Retired. The Pi's checkout once linked its pre-push hook here; until
# tools/install-hooks.sh replaces that hook with the native pre-commit one, a
# push must fail closed rather than go out unscanned.
echo "pre-push: the Pi's hooks are not set up. Run tools/install-hooks.sh, then push again." >&2
exit 1
