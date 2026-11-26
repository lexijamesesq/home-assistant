#!/usr/bin/env bash
# pi-sync.sh — bring the Pi's live checkout level with the default branch.
#
# The working tree is the running /config, and pull requests are squash-merged,
# so a fast-forward never applies. This moves HEAD and the index to the
# default branch, then brings in only the files the default branch changed. It
# never overwrites or deletes a file changed on the Pi, or one only the Pi has,
# ignored ones included: if the default branch changed or added one of those,
# it stops before changing anything. A file the
# default branch stopped tracking stays on disk if it has local changes or is
# now ignored, and is removed otherwise. Files Home Assistant reads are listed afterwards, because
# applying them needs a reload or restart.
#
# Usage: tools/pi-sync.sh [checkout]   (default /config)

set -euo pipefail

cd "${1:-/config}"
branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
branch="${branch#origin/}"
branch="${branch:-master}"

git fetch --quiet origin "$branch"
old="$(git rev-parse HEAD)"
new="$(git rev-parse "origin/$branch")"
if [[ "$old" == "$new" ]]; then
	echo "pi-sync: already level with $branch at ${new:0:12}"
	exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git diff --name-only --no-renames "$old" "$new" >"$work/changed"
{
	git diff --name-only --no-renames "$old"
	git ls-files --others --exclude-standard
} >"$work/local"

is_local() { grep -qxF -- "$1" "$work/local"; }
in_new() { git cat-file -e "$new:$1" 2>/dev/null; }
in_old() { git cat-file -e "$old:$1" 2>/dev/null; }
# A file on disk that was not tracked, ignored ones included, exists only on the Pi.
pi_only() { [[ -e "$1" || -L "$1" ]] && ! in_old "$1"; }

conflicts=0
while IFS= read -r path; do
	if in_new "$path" && { is_local "$path" || pi_only "$path"; }; then
		[[ "$conflicts" -eq 1 ]] || echo "pi-sync: stopped, nothing changed. $branch and the Pi both changed:" >&2
		echo "  $path" >&2
		conflicts=1
	fi
done <"$work/changed"
[[ "$conflicts" -eq 0 ]] || exit 1

git reset --quiet --mixed "$new"
echo "pi-sync: ${old:0:12} -> ${new:0:12} on $branch"
: >"$work/applied"
# Bring in everything the default branch has first, .gitignore included, so a
# file it stopped tracking is judged against its own ignore rules.
while IFS= read -r path; do
	if in_new "$path"; then
		git checkout --quiet -- "$path"
		echo "  updated  $path"
		echo "$path" >>"$work/applied"
	fi
done <"$work/changed"
while IFS= read -r path; do
	in_new "$path" && continue
	if is_local "$path"; then
		echo "  kept, no longer tracked  $path"
	elif git check-ignore --quiet --no-index -- "$path"; then
		[[ ! -e "$path" ]] || echo "  kept, now ignored  $path"
	elif [[ -e "$path" ]]; then
		rm -f -- "$path"
		echo "  removed  $path"
		echo "$path" >>"$work/applied"
	fi
done <"$work/changed"

# What Home Assistant reads: its YAML and .storage, and the code and assets it loads.
reload=""
while IFS= read -r path; do
	case "$path" in
	.github/* | tools/* | tests/* | .*.yaml) ;;
	.storage/* | *.yaml | pyscript/* | python/* | themes/* | blueprints/* | lovelace/* | template/* | custom_components/* | www/*)
		reload="$reload  $path"$'\n'
		;;
	esac
done <"$work/applied"
if [[ -n "$reload" ]]; then
	echo "pi-sync: Home Assistant reads these; reload or restart to apply them:"
	printf '%s' "$reload"
fi
