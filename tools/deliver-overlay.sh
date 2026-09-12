#!/usr/bin/env bash
#
# deliver-overlay.sh — deliver the operator's gitleaks overlay from this
# Mini to the Home Assistant Pi's persistent /config path, for pre-push-gitleaks.sh to
# read. Runs on the Mini, over the Terminal & SSH add-on. Same pattern
# susuwatari-config's deploy-to-pi.sh Step 0 already uses: streamed over
# stdin, written atomically (temp + mv), sha256-verified, content never
# echoed anywhere.
#
# Usage:
#   ./tools/deliver-overlay.sh
#   PI_HOST=ha.example.invalid ./tools/deliver-overlay.sh

set -euo pipefail

PI_HOST="${PI_HOST:?Set PI_HOST to the Home Assistant host name or address}"
PI_USER="${PI_USER:-root}"
OVERLAY_SRC="${XDG_CONFIG_HOME:-$HOME/.config}/gitleaks/operator-rules.toml"

if [[ ! -r "$OVERLAY_SRC" ]]; then
    echo "FATAL: operator gitleaks ruleset is not installed on this Mini ($OVERLAY_SRC) — run the blueprint's gitleaks-rules apply first." >&2
    exit 1
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "${PI_USER}@${PI_HOST}" true 2>/dev/null; then
    echo "FATAL: cannot reach the Home Assistant Pi at ${PI_USER}@${PI_HOST}." >&2
    exit 1
fi

LOCAL_SHA="$(shasum -a 256 "$OVERLAY_SRC" | cut -c1-64)"
REMOTE_SHA="$(ssh -o BatchMode=yes "${PI_USER}@${PI_HOST}" \
    'umask 077; dest=/config/.tools/operator-config/gitleaks; mkdir -p "$dest" && chmod 0700 "$dest" \
     && tmp="$dest/.operator-rules.toml.tmp.$$" \
     && trap '\''rm -f "$tmp"'\'' EXIT HUP INT TERM \
     && cat > "$tmp" && chmod 0600 "$tmp" \
     && mv -f "$tmp" "$dest/operator-rules.toml" \
     && trap - EXIT HUP INT TERM \
     && sha256sum "$dest/operator-rules.toml" | cut -c1-64' \
    < "$OVERLAY_SRC")"

if [[ "$REMOTE_SHA" != "$LOCAL_SHA" ]]; then
    echo "FATAL: overlay on the Pi does not match the Mini's (sha256 mismatch)." >&2
    exit 1
fi
echo "deliver-overlay: installed on the Pi (sha256 ${LOCAL_SHA:0:12}...)."
