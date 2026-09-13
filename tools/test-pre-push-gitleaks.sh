#!/usr/bin/env bash
# Synthetic integration checks for the installed canonical scanner. This never
# reads the operator's real ruleset or any estate configuration.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTTY_HOOKS_COMMIT="4fb7b2cdd8390be9bd7ad58ca3bfdf4653e24c41"
SCANNER="$REPO_ROOT/.tools/dotty-hooks/$DOTTY_HOOKS_COMMIT/gitleaks-pre-push.sh"
GITLEAKS="$REPO_ROOT/.tools/gitleaks"
LAUNCHER="$REPO_ROOT/tools/run-persistent-gitleaks.sh"

[[ -x "$SCANNER" ]] || { echo "SKIP: run tools/install-hooks.sh first" >&2; exit 77; }
[[ -x "$GITLEAKS" ]] || { echo "SKIP: run tools/install-hooks.sh first" >&2; exit 77; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# Exercise the actual persistent launcher with a recording scanner: inherited
# trusted-lane overrides are absent, while native args and stdin are unchanged.
launch_root="$scratch/launch-root"
launch_hook="$launch_root/.tools/dotty-hooks/$DOTTY_HOOKS_COMMIT/gitleaks-pre-push.sh"
mkdir -p "$(dirname "$launch_hook")"
cat > "$launch_hook" <<'EOF'
#!/usr/bin/env bash
set -eu
for name in GL_NO_OVERLAY GL_OVERLAY_ONLY GL_CONFIG_PATH GL_IGNORE_PATH GL_BASE_REF GL_DECLARED_JSON GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML PRE_COMMIT_FROM_REF PRE_COMMIT_TO_REF PRE_COMMIT_REMOTE_NAME PRE_COMMIT_REMOTE_BRANCH; do
    eval "value=\${$name-}"
    [[ -z "$value" ]] || { echo "override survived: $name" >&2; exit 1; }
done
printf 'args=%s|%s\n' "$1" "$2"
printf 'xdg=%s\n' "$XDG_CONFIG_HOME"
cat
EOF
chmod 0755 "$launch_hook"
protocol='refs/heads/topic aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/topic 0000000000000000000000000000000000000000'
launch_out="$(printf '%s\n' "$protocol" | env GL_NO_OVERLAY=1 GL_OVERLAY_ONLY=1 GL_CONFIG_PATH=/tmp/wrong GL_IGNORE_PATH=/tmp/wrong GL_BASE_REF=wrong GL_DECLARED_JSON=/tmp/wrong GITLEAKS_CONFIG=/tmp/wrong GITLEAKS_CONFIG_TOML=wrong PRE_COMMIT_FROM_REF=wrong PRE_COMMIT_TO_REF=wrong PRE_COMMIT_REMOTE_NAME=wrong PRE_COMMIT_REMOTE_BRANCH=wrong "$LAUNCHER" "$launch_root" alternate "$scratch/alternate.git")"
grep -q "^args=alternate|$scratch/alternate.git$" <<< "$launch_out"
grep -q "^xdg=$launch_root/.tools/operator-config$" <<< "$launch_out"
grep -q "^$protocol$" <<< "$launch_out"

remote="$scratch/remote.git"
alternate="$scratch/alternate.git"
repo="$scratch/repo"
git init --bare -q "$remote"
git init --bare -q "$alternate"
git init -q -b master "$repo"
mkdir -p "$repo/.tools/operator-config/gitleaks"
ln -s "$REPO_ROOT/.tools/gitleaks" "$repo/.tools/gitleaks"
ln -s "$REPO_ROOT/.tools/dotty-hooks" "$repo/.tools/dotty-hooks"
xdg="$repo/.tools/operator-config"
git -C "$repo" config user.name "Synthetic Test"
git -C "$repo" config user.email "12345+synthetic@users.noreply.github.com"
git -C "$repo" config commit.gpgsign false
git -C "$repo" remote add origin "$remote"
git -C "$repo" remote add alternate "$alternate"
printf '[extend]\nuseDefault = true\n' > "$repo/.gitleaks.toml"
printf 'clean fixture\n' > "$repo/fixture.txt"
git -C "$repo" add .
git -C "$repo" commit -qm base
git -C "$repo" push -q -u origin master
git -C "$remote" symbolic-ref HEAD refs/heads/master
git -C "$repo" push -q -u alternate master
git -C "$alternate" symbolic-ref HEAD refs/heads/master

run_hook() {
    local old="$1" new="$2"
    printf 'refs/heads/master %s refs/heads/master %s\n' "$new" "$old" |
        (cd "$repo" && PATH="$REPO_ROOT/.tools:$PATH" XDG_CONFIG_HOME="$xdg" "$SCANNER" origin "$remote")
}

printf 'next clean fixture\n' >> "$repo/fixture.txt"
git -C "$repo" add fixture.txt
git -C "$repo" commit -qm clean
base="$(git -C "$repo" rev-parse HEAD^)"
tip="$(git -C "$repo" rev-parse HEAD)"

if run_hook "$base" "$tip" >"$scratch/missing.out" 2>&1; then
    echo "FAIL: missing overlay did not block" >&2
    exit 1
fi
grep -q 'operator overlay is missing' "$scratch/missing.out"

printf 'this is not valid toml = =\n' > "$xdg/gitleaks/operator-rules.toml"
if run_hook "$base" "$tip" >"$scratch/malformed.out" 2>&1; then
    echo "FAIL: malformed overlay did not block" >&2
    exit 1
fi
grep -q 'operator overlay failed to load' "$scratch/malformed.out"

cat > "$xdg/gitleaks/operator-rules.toml" <<'EOF'
[extend]
useDefault = true

[[rules]]
id = "synthetic-operator-marker"
description = "synthetic integration marker"
regex = '''SYNTHETIC_OPERATOR_MARKER_[A-Z0-9]{12}'''
keywords = ["SYNTHETIC_OPERATOR_MARKER_"]
EOF
chmod 0600 "$xdg/gitleaks/operator-rules.toml"
run_hook "$base" "$tip" >"$scratch/clean.out" 2>&1
printf 'refs/heads/master %s refs/heads/master %s\n' "$tip" "$base" |
    (cd "$repo" && PATH="$REPO_ROOT/.tools:$PATH" XDG_CONFIG_HOME="$xdg" "$SCANNER" alternate "$alternate") >"$scratch/non-origin.out" 2>&1

# Real git-push acceptance path: a fixture-native hook calls the production
# launcher with this disposable root. The clean ref advances on the bare
# remote; the planted marker push is rejected and leaves that ref unchanged.
cat > "$repo/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
exec "$LAUNCHER" "$repo" "\$@"
EOF
chmod 0755 "$repo/.git/hooks/pre-push"
git -C "$repo" push -q origin master
[[ "$(git -C "$remote" rev-parse refs/heads/master)" == "$tip" ]]

printf 'SYNTHETIC_OPERATOR_MARKER_ABCDEF123456\n' >> "$repo/fixture.txt"
git -C "$repo" add fixture.txt
git -C "$repo" commit -qm leak
if git -C "$repo" push origin master >"$scratch/leak.out" 2>&1; then
    echo "FAIL: synthetic operator-rule finding did not block an actual push" >&2
    exit 1
fi
[[ "$(git -C "$remote" rev-parse refs/heads/master)" == "$tip" ]]
grep -q 'sensitive content' "$scratch/leak.out"
if grep -q 'SYNTHETIC_OPERATOR_MARKER_ABCDEF123456' "$scratch/leak.out"; then
    echo "FAIL: hook output exposed the matched value" >&2
    exit 1
fi

# A new branch whose tip removed the marker still blocks because the scanner
# examines every outgoing commit tree, including the historical leak commit.
git -C "$repo" checkout -qb historical "$base"
printf 'SYNTHETIC_OPERATOR_MARKER_ZYXWVU987654\n' > "$repo/history.txt"
git -C "$repo" add history.txt
git -C "$repo" commit -qm 'historical marker'
rm "$repo/history.txt"
git -C "$repo" add -u
git -C "$repo" commit -qm 'remove historical marker'
historical_tip="$(git -C "$repo" rev-parse HEAD)"
zero=0000000000000000000000000000000000000000
if printf 'refs/heads/historical %s refs/heads/historical %s\n' "$historical_tip" "$zero" |
    (cd "$repo" && PATH="$REPO_ROOT/.tools:$PATH" XDG_CONFIG_HOME="$xdg" "$SCANNER" alternate "$alternate") >"$scratch/historical.out" 2>&1; then
    echo "FAIL: removed marker in new-branch history did not block" >&2
    exit 1
fi
grep -q 'sensitive content' "$scratch/historical.out"

# Deleting a ref has no outgoing content and succeeds, including on a remote
# whose name is not origin.
printf 'refs/heads/historical %s refs/heads/historical %s\n' "$zero" "$historical_tip" |
    (cd "$repo" && PATH="$REPO_ROOT/.tools:$PATH" XDG_CONFIG_HOME="$xdg" "$SCANNER" alternate "$alternate") >"$scratch/deletion.out" 2>&1

echo "PASS: launcher seam, overlay failures, actual clean/leak pushes, non-origin range, redaction, historical new-branch leak, and deletion"
