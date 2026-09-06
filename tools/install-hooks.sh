#!/usr/bin/env bash
#
# install-hooks.sh — idempotently provision the pre-push secret-scan hook on
# this checkout, and the gitleaks binary it needs. Run from the Terminal &
# SSH add-on's shell, or from its init_commands so a container rebuild
# re-applies both.
#
# WHY THIS EXISTS
# ---------------
# This repo's working copy lives in an ephemeral add-on container rebuilt on
# every add-on update — an installed git hook does not survive that, and
# neither does a binary dropped outside the persistent volume. Both live
# under this repo's own checkout (on /config, the persistent volume), and
# this script is the thing that re-applies them, rather than a one-time
# manual step that quietly stops being true after the next rebuild.
#
# WHAT THIS DOES NOT DO
# ----------------------
# It does not scan anything itself — see pre-push-gitleaks.sh for the actual
# hook logic. It never edits a Home Assistant configuration file. Nothing
# under /config changes except .git/hooks/pre-push and .tools/ (both
# gitignored, neither is HA config).
#
#     tools/install-hooks.sh [--check]
#
# --check reports whether the hook and binary are correctly in place and
# exits non-zero if not, without installing or downloading anything.

set -euo pipefail

MODE=install
[[ "${1:-}" == "--check" ]] && MODE=check

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLEAKS_VERSION="8.30.1"
TOOLS_DIR="$REPO_ROOT/.tools"
GITLEAKS_BIN="$TOOLS_DIR/gitleaks"
GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --git-dir)"
HOOK_PATH="$GIT_DIR/hooks/pre-push"
HOOK_SOURCE="$REPO_ROOT/tools/pre-push-gitleaks.sh"

note()  { printf '%s\n' "$1"; }
drift() { printf 'DRIFT %s\n' "$1"; DRIFT=1; }
DRIFT=0

# --- gitleaks binary: checksum-verified, arm64 (Raspberry Pi 5 / HAOS) -----
if [[ -x "$GITLEAKS_BIN" ]] && "$GITLEAKS_BIN" version 2>/dev/null | grep -q "$GITLEAKS_VERSION"; then
    note "OK    gitleaks $GITLEAKS_VERSION present at $GITLEAKS_BIN"
elif [[ "$MODE" == check ]]; then
    drift "gitleaks $GITLEAKS_VERSION not present at $GITLEAKS_BIN"
else
    mkdir -p "$TOOLS_DIR"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    base="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}"
    tarball="gitleaks_${GITLEAKS_VERSION}_linux_arm64.tar.gz"
    curl -sSfL -o "$tmp/$tarball" "$base/$tarball"
    curl -sSfL -o "$tmp/checksums.txt" "$base/gitleaks_${GITLEAKS_VERSION}_checksums.txt"
    line="$(grep -E "[[:space:]]${tarball}\$" "$tmp/checksums.txt")"
    [[ "$(printf '%s\n' "$line" | wc -l)" -eq 1 ]]
    (cd "$tmp" && printf '%s\n' "$line" | sha256sum -c -)
    tar -xzf "$tmp/$tarball" -C "$tmp" gitleaks
    install -m 0755 "$tmp/gitleaks" "$GITLEAKS_BIN"
    note "FIXED gitleaks $GITLEAKS_VERSION installed at $GITLEAKS_BIN"
fi

# --- pre-push hook: a thin symlink to the tracked hook script --------------
# A symlink (not a copy) means a `git pull` that updates pre-push-gitleaks.sh
# takes effect on the next push with no re-install step.
if [[ -L "$HOOK_PATH" ]] && [[ "$(readlink "$HOOK_PATH")" == "$HOOK_SOURCE" ]]; then
    note "OK    pre-push hook symlinked to $HOOK_SOURCE"
elif [[ "$MODE" == check ]]; then
    drift "pre-push hook not symlinked to $HOOK_SOURCE"
else
    mkdir -p "$GIT_DIR/hooks"
    ln -sf "$HOOK_SOURCE" "$HOOK_PATH"
    chmod +x "$HOOK_SOURCE"
    note "FIXED pre-push hook symlinked to $HOOK_SOURCE"
fi

# --- core.hooksPath must be unset/default — never redirected elsewhere ----
hooks_path_cfg="$(git -C "$REPO_ROOT" config --get core.hooksPath || true)"
if [[ -z "$hooks_path_cfg" ]]; then
    note "OK    core.hooksPath unset (default .git/hooks in effect)"
else
    drift "core.hooksPath is set to '$hooks_path_cfg' — the installed hook above would not run; this script never changes core.hooksPath itself"
fi

if [[ "$MODE" == check ]]; then
    if [[ "$DRIFT" -eq 0 ]]; then
        echo "install-hooks: no drift — fully wired."
        exit 0
    fi
    echo "install-hooks: drift present. Run without --check to install."
    exit 1
fi
echo "install-hooks: converged."
