#!/usr/bin/env bash
#
# pre-push-gitleaks.sh — the actual pre-push hook body, installed by
# install-hooks.sh (a symlink, not a copy, so an update takes effect on the
# next push with no re-install step). Runs on the Home Assistant Pi, inside
# the Terminal & SSH add-on, against this checkout's own .tools/gitleaks.
#
# Two layers, same shape as every other repo's hook chain in this estate:
#   1. gitleaks' own default rules over the outgoing commit range (provider-
#      shaped credentials — this repo currently has no tracked .gitleaks.toml
#      of its own, matching secret-scan.yml's CI layer).
#   2. the operator overlay, read from its fixed path on this device
#      (~/.config/gitleaks/operator-rules.toml) — delivered here from the
#      Mini by tools/deliver-overlay.sh, same atomic/sha256-verified pattern
#      susuwatari-config's deploy-to-pi.sh already uses. If the overlay is
#      absent, this layer is SKIPPED with a warning, never treated as a
#      pass — the base layer alone still blocks a push.
#
# Standard git pre-push hook protocol: reads "<local ref> <local sha>
# <remote ref> <remote sha>" lines on stdin, one per ref being pushed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLEAKS="$REPO_ROOT/.tools/gitleaks"
OVERLAY_PATH="${HOME}/.config/gitleaks/operator-rules.toml"

if [[ ! -x "$GITLEAKS" ]]; then
    echo "pre-push: gitleaks binary missing at $GITLEAKS — run tools/install-hooks.sh first. Refusing to push unscanned." >&2
    exit 1
fi

fail=0
# shellcheck disable=SC2034  # local_ref/remote_ref are part of the pre-push
# hook protocol's fixed four-field line shape; only the two shas are used.
while read -r local_ref local_sha remote_ref remote_sha; do
    [[ "$local_sha" == "0000000000000000000000000000000000000000" ]] && continue  # branch deletion
    if [[ "$remote_sha" == "0000000000000000000000000000000000000000" ]]; then
        # New remote ref: scanning the whole history being introduced is too
        # broad; scan against the merge-base with the default branch instead.
        base="$(git -C "$REPO_ROOT" merge-base "$local_sha" origin/main 2>/dev/null || echo "$local_sha")"
        range="${base}..${local_sha}"
    else
        range="${remote_sha}..${local_sha}"
    fi

    echo "pre-push: scanning $range (base rules)..."
    if ! "$GITLEAKS" git "$REPO_ROOT" --log-opts="$range" --redact --no-banner; then
        echo "pre-push: BLOCKED — base gitleaks rules found a match in $range." >&2
        fail=1
    fi

    if [[ -r "$OVERLAY_PATH" ]]; then
        echo "pre-push: scanning $range (operator overlay)..."
        if ! "$GITLEAKS" git "$REPO_ROOT" --log-opts="$range" --config "$OVERLAY_PATH" --redact --no-banner; then
            echo "pre-push: BLOCKED — operator overlay found a match in $range." >&2
            fail=1
        fi
    else
        echo "pre-push: WARNING — operator overlay not present at $OVERLAY_PATH; base rules only for this push. Run tools/deliver-overlay.sh from the Mini." >&2
    fi
done

exit "$fail"
