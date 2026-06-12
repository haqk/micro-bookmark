#!/usr/bin/env bash
# Cut a new bookmark release: bump VERSION, prepend repo.json, move CHANGELOG
# [Unreleased] under the new version, commit, tag, and remind to push.
#
# Usage: scripts/release.sh <new-version>          # e.g. 2.3.11
#        scripts/release.sh --dry-run <new-version>
#
# Requires: jq, git. Run from the repository root.

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi

NEW="${1:-}"
if [[ -z "$NEW" ]]; then
    echo "usage: $0 [--dry-run] <new-version>" >&2
    exit 2
fi
if ! [[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must be MAJOR.MINOR.PATCH, got '$NEW'" >&2
    exit 2
fi

cd "$(git rev-parse --show-toplevel)"

CUR=$(grep -oP '^VERSION\s*=\s*"\K[0-9]+\.[0-9]+\.[0-9]+' bookmark.lua)
if [[ "$NEW" == "$CUR" ]]; then
    echo "error: VERSION is already $NEW" >&2
    exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree is dirty; commit or stash first" >&2
    exit 2
fi

TAG="v$NEW"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists" >&2
    exit 2
fi

URL="https://github.com/haqk/micro-bookmark/archive/${TAG}.zip"
TODAY=$(date +%Y-%m-%d)

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "DRY: $*"
    else
        eval "$@"
    fi
}

echo "→ bumping $CUR → $NEW"

# 1. VERSION in bookmark.lua
if [[ $DRY_RUN -eq 0 ]]; then
    sed -i -E "s/^VERSION\s*=\s*\"$CUR\"/VERSION = \"$NEW\"/" bookmark.lua
else
    echo "DRY: sed -i bookmark.lua  VERSION → $NEW"
fi

# 2. prepend new version to repo.json Versions array
if [[ $DRY_RUN -eq 0 ]]; then
    tmp=$(mktemp)
    jq --arg v "$NEW" --arg u "$URL" \
       '.[0].Versions = ([{Version:$v, Url:$u, Require:{micro:">=2.0.0"}}] + .[0].Versions)' \
       repo.json > "$tmp"
    mv "$tmp" repo.json
else
    echo "DRY: jq prepend $NEW → repo.json"
fi

# 3. move CHANGELOG [Unreleased] under the new version header
if [[ -f CHANGELOG.md ]] && [[ $DRY_RUN -eq 0 ]]; then
    awk -v ver="$NEW" -v date="$TODAY" '
        /^## \[Unreleased\]/ {
            print
            print ""
            print "## [" ver "] - " date
            next
        }
        { print }
    ' CHANGELOG.md > CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
elif [[ -f CHANGELOG.md ]]; then
    echo "DRY: insert ## [$NEW] - $TODAY under [Unreleased] in CHANGELOG.md"
fi

# 4. commit + tag
run git add bookmark.lua repo.json CHANGELOG.md 2>/dev/null || true
run "git commit -m 'release: v$NEW'"
run "git tag -a $TAG -m 'v$NEW'"

cat <<EOF

✓ release prepared

Next:
  git push origin main $TAG
  scripts/sync-channel.sh   # if syncing to plugin-channel

EOF
