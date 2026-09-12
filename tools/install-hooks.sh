#!/usr/bin/env bash
#
# install-hooks.sh — idempotently provision the pre-push secret-scan hook on
# this checkout, and the gitleaks binary it needs. Run from the Terminal &
# SSH add-on's shell, or from its init_commands so a container rebuild
# re-applies both.
#
# WHY THIS EXISTS
# ---------------
# The Terminal & SSH App is rebuilt on updates. Paths outside /config can
# disappear; the hook, public scanner bundle and private overlay all live on
# its persistent /config mount. This idempotent installer also detects drift
# after a rebuild without repeatedly downloading valid installed artifacts.
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
GITLEAKS_ARCHIVE_SHA="e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
GITLEAKS_BINARY_SHA="00e91bbe655bd7c47753e8cfe61cb76ea1a5d7e7702fe161ee40102b46b3823b"
DOTTY_HOOKS_COMMIT="4fb7b2cdd8390be9bd7ad58ca3bfdf4653e24c41"
TOOLS_DIR="$REPO_ROOT/.tools"
GITLEAKS_BIN="$TOOLS_DIR/gitleaks"
HOOKS_DIR="$TOOLS_DIR/dotty-hooks/$DOTTY_HOOKS_COMMIT"
OVERLAY_PATH="$TOOLS_DIR/operator-config/gitleaks/operator-rules.toml"
GIT_DIR="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)"
HOOK_PATH="$GIT_DIR/hooks/pre-push"
HOOK_SOURCE="$REPO_ROOT/tools/pre-push-gitleaks.sh"

note()  { printf '%s\n' "$1"; }
drift() { printf 'DRIFT %s\n' "$1"; DRIFT=1; }
DRIFT=0

hook_files=(gitleaks-pre-push.sh gitleaks-common.sh house-code-common.sh)
hook_shas=(
    7186e80ca26acdef402ae0d3906932ecda5c2626bd945d48da26fb1b35ce7252
    cbe7a9ad314d3e46c67a6fe948850c929b9c94ce7d6997537626d44c25ee1136
    b87c1fea3c6064727c75476d8f53b67158208ecc44128cab4d6ff57def70035e
)

# --- gitleaks binary: checksum-verified, arm64 (Raspberry Pi 5 / HAOS) -----
if [[ -x "$GITLEAKS_BIN" ]] \
    && [[ "$(sha256sum "$GITLEAKS_BIN" | cut -d' ' -f1)" == "$GITLEAKS_BINARY_SHA" ]] \
    && [[ "$("$GITLEAKS_BIN" version 2>/dev/null)" == "$GITLEAKS_VERSION" ]]; then
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
    (cd "$tmp" && printf '%s  %s\n' "$GITLEAKS_ARCHIVE_SHA" "$tarball" | sha256sum -c -)
    tar -xzf "$tmp/$tarball" -C "$tmp" gitleaks
    printf '%s  %s\n' "$GITLEAKS_BINARY_SHA" "$tmp/gitleaks" | sha256sum -c -
    install -m 0755 "$tmp/gitleaks" "$GITLEAKS_BIN"
    note "FIXED gitleaks $GITLEAKS_VERSION installed at $GITLEAKS_BIN"
fi

# --- canonical shared scanner: immutable commit + per-file checksums --------
hooks_ok=1
for i in "${!hook_files[@]}"; do
    file="$HOOKS_DIR/${hook_files[$i]}"
    [[ -f "$file" ]] || { hooks_ok=0; break; }
    actual="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)"
    [[ "$actual" == "${hook_shas[$i]}" ]] || { hooks_ok=0; break; }
done
if [[ "$hooks_ok" -eq 1 ]] && [[ -x "$HOOKS_DIR/gitleaks-pre-push.sh" ]]; then
    note "OK    Dotty scanner $DOTTY_HOOKS_COMMIT present at $HOOKS_DIR"
elif [[ "$MODE" == check ]]; then
    drift "Dotty scanner $DOTTY_HOOKS_COMMIT is missing or checksum-invalid at $HOOKS_DIR"
else
    mkdir -p "$TOOLS_DIR/dotty-hooks"
    hook_tmp="$(mktemp -d "$TOOLS_DIR/dotty-hooks/.install.XXXXXX")"
    trap 'rm -rf "${tmp:-}" "${hook_tmp:-}"' EXIT
    for i in "${!hook_files[@]}"; do
        name="${hook_files[$i]}"
        url="https://raw.githubusercontent.com/lexijamesesq/dotty/$DOTTY_HOOKS_COMMIT/git-hooks/$name"
        curl -sSfL -o "$hook_tmp/$name" "$url"
        printf '%s  %s\n' "${hook_shas[$i]}" "$hook_tmp/$name" | sha256sum -c -
    done
    chmod 0755 "$hook_tmp/gitleaks-pre-push.sh"
    chmod 0644 "$hook_tmp/gitleaks-common.sh" "$hook_tmp/house-code-common.sh"
    if [[ -e "$HOOKS_DIR" ]]; then
        old_hooks="$TOOLS_DIR/dotty-hooks/.replaced.$$"
        mv "$HOOKS_DIR" "$old_hooks"
    fi
    mv "$hook_tmp" "$HOOKS_DIR"
    hook_tmp=""
    [[ -n "${old_hooks:-}" ]] && rm -rf "$old_hooks"
    note "FIXED Dotty scanner $DOTTY_HOOKS_COMMIT installed at $HOOKS_DIR"
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

# Both configurations must be present and loadable before reporting readiness.
# Scanner output is suppressed so private rule contents cannot enter diagnostics.
for config in "$REPO_ROOT/.gitleaks.toml" "$OVERLAY_PATH"; do
    if [[ ! -f "$config" || ! -r "$config" ]]; then
        drift "scanner configuration missing or unreadable at $config; pushes will be blocked"
    elif [[ -x "$GITLEAKS_BIN" ]]; then
        probe="$(mktemp -d)"
        if "$GITLEAKS_BIN" dir "$probe" --config "$config" --no-banner >/dev/null 2>&1; then
            note "OK    scanner configuration loadable at $config"
        else
            drift "scanner configuration failed to load at $config; pushes will be blocked"
        fi
        rm -rf "$probe"
    fi
done

if [[ "$DRIFT" -ne 0 ]]; then
    if [[ "$MODE" == check ]]; then
        echo "install-hooks: drift present. Run without --check, deliver the overlay, and resolve reported Git configuration drift."
    else
        echo "install-hooks: incomplete — resolve reported drift before pushing."
    fi
    exit 1
fi
if [[ "$MODE" == check ]]; then
    echo "install-hooks: no drift — fully wired."
    exit 0
fi
echo "install-hooks: converged."
