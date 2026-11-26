#!/usr/bin/env bash
# pi-sync.sh — bring the Pi's live checkout level with the default branch.
#
# The working tree is the running /config, and pull requests are squash-merged,
# so a fast-forward never applies. This moves HEAD and the index to the default
# branch, then brings in the files the default branch changed. Each changed
# file is compared on disk with the commit the Pi was on and the default branch:
# - the same as the default branch: already applied, nothing to do;
# - the same as the commit the Pi was on: brought in, or removed if the default
#   branch stopped tracking it and it is not now ignored;
# - different from both: the Pi changed it, or only the Pi has it. If the default
#   branch has a version, the sync stops before changing anything; if not, the
#   Pi's copy stays on disk, untracked.
# The commit the Pi was on is recorded before anything moves, so a rerun after an
# interruption finishes the same sync. It stops if the Pi holds commits that are
# not on the default branch, because a change made on the Pi waits uncommitted
# until it is published. Files Home Assistant reads are listed
# afterwards, because applying them needs a reload or restart.
#
# Usage: tools/pi-sync.sh [checkout]   (default /config)

set -euo pipefail

cd "${1:-/config}"
branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
branch="${branch#origin/}"
branch="${branch:-master}"
marker="$(git rev-parse --absolute-git-dir)/pi-sync-from"

git fetch --quiet origin "$branch"
new="$(git rev-parse "origin/$branch")"
if [[ -s "$marker" ]]; then
	old="$(cat "$marker")"
	git cat-file -e "$old^{commit}" 2>/dev/null || {
		echo "pi-sync: $marker names no commit; inspect it before rerunning" >&2
		exit 1
	}
	echo "pi-sync: finishing the sync from ${old:0:12}"
else
	old="$(git rev-parse HEAD)"
	if [[ "$old" == "$new" ]]; then
		echo "pi-sync: already level with $branch at ${new:0:12}"
		exit 0
	fi
	# A commit made on the Pi and not yet on the default branch would be judged
	# as already in place and its files reset to the default branch, undoing a
	# live change. A Pi change waits uncommitted instead.
	if ! git merge-base --is-ancestor "$old" "$new"; then
		echo "pi-sync: stopped, nothing changed. The Pi holds commits that are not on $branch:" >&2
		git log --abbrev=12 --format='  %h %s' "$new..$old" >&2
		base="$(git merge-base "$old" "$new")"
		echo "Undo them with 'git reset --soft ${base:0:12}', which keeps the change live and uncommitted, then rerun." >&2
		exit 1
	fi
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git diff --name-only --no-renames "$old" "$new" >"$work/changed"

blob() { git rev-parse --quiet --verify "$1:$2" 2>/dev/null || echo absent; }
on_disk() {
	if [[ -L "$1" || -f "$1" ]]; then git hash-object -- "$1"; else echo absent; fi
}
# applied | apply | pi-changed | pi-kept for one changed path.
state() {
	local disk was now
	disk="$(on_disk "$1")"
	was="$(blob "$old" "$1")"
	now="$(blob "$new" "$1")"
	if [[ "$disk" == "$now" ]]; then
		echo applied
	elif [[ "$disk" == "$was" ]]; then
		echo apply
	elif [[ "$now" != absent ]]; then
		echo pi-changed
	else
		echo pi-kept
	fi
}

conflicts=0
while IFS= read -r path; do
	if [[ "$(state "$path")" == pi-changed ]]; then
		[[ "$conflicts" -eq 1 ]] || echo "pi-sync: stopped, nothing changed. $branch and the Pi both have a version of:" >&2
		echo "  $path" >&2
		conflicts=1
	fi
done <"$work/changed"
[[ "$conflicts" -eq 0 ]] || exit 1

echo "$old" >"$marker"
git reset --quiet --mixed "$new"
echo "pi-sync: ${old:0:12} -> ${new:0:12} on $branch"
: >"$work/applied"
# Bring in everything the default branch has first, .gitignore included, so a
# file it stopped tracking is judged against its own ignore rules.
while IFS= read -r path; do
	if [[ "$(blob "$new" "$path")" != absent && "$(state "$path")" == apply ]]; then
		git checkout --quiet -- "$path"
		echo "  updated  $path"
		echo "$path" >>"$work/applied"
	fi
done <"$work/changed"
while IFS= read -r path; do
	[[ "$(blob "$new" "$path")" == absent ]] || continue
	case "$(state "$path")" in
	pi-kept) echo "  kept, no longer tracked  $path" ;;
	apply)
		if git check-ignore --quiet --no-index -- "$path"; then
			echo "  kept, now ignored  $path"
		else
			rm -f -- "$path"
			echo "  removed  $path"
			echo "$path" >>"$work/applied"
		fi
		;;
	esac
done <"$work/changed"
rm -f "$marker"
# Everything now live as the default branch has it counts, including files an
# interrupted run had already brought in.
while IFS= read -r path; do
	if [[ "$(blob "$new" "$path")" != absent && "$(state "$path")" == applied ]]; then
		echo "$path"
	fi
done <"$work/changed" >>"$work/applied"
sort -u -o "$work/applied" "$work/applied"

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
