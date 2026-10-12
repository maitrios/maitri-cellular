#!/bin/bash

# Pull an omarchy-cellular release into maitri-cellular. Upstream tags are never
# merged into main directly: every upstream line that says "omarchy" would
# conflict with the rename. Instead the `upstream` branch tracks a *rebranded*
# copy of each release tag, so main only sees real feature-vs-upstream overlaps.
#
#   tools/sync-upstream.sh v2.1.0              rebrand the tag onto `upstream`, then merge into the current branch
#   tools/sync-upstream.sh --no-merge v2.1.0   only advance `upstream` (what .github/workflows/sync-upstream.yml runs)
#   tools/sync-upstream.sh --latest            print the newest upstream release tag `upstream` does not contain yet
#
# Upstream tags are fetched into refs/remotes/relctx/tags/ so they never
# collide with maitri-cellular's own vX.Y.Z release tags.
#
# Afterwards resolve conflicts on main, run tools/rebrand.sh --check and
# `make test`, then commit the merge.

set -euo pipefail

UPSTREAM_REMOTE=relctx
UPSTREAM_URL=https://github.com/relctx/omarchy-cellular.git
TAG_NAMESPACE=refs/remotes/$UPSTREAM_REMOTE/tags
RELEASE_TAG='^v[0-9]+\.[0-9]+(\.[0-9]+)?$'

# maitri-cellular's own tooling exists on our branches but not in any upstream
# tag, so the read-tree below removes it, including this script and the
# rebrander it then runs. Restore those files from the branch being synced
# before rebranding.
MAITRI_TOOLING=(tools/rebrand.sh tools/sync-upstream.sh)

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

usage() {
  sed -n '8,10p' "$0" >&2
  exit 2
}

fetch_upstream() {
  git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1 || git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
  git config "remote.$UPSTREAM_REMOTE.tagOpt" --no-tags
  git config --replace-all "remote.$UPSTREAM_REMOTE.fetch" "+refs/heads/*:refs/remotes/$UPSTREAM_REMOTE/*"
  git config --add "remote.$UPSTREAM_REMOTE.fetch" "+refs/tags/*:$TAG_NAMESPACE/*"
  git fetch -q "$UPSTREAM_REMOTE"
}

release_tags() {
  git for-each-ref --format='%(refname:lstrip=4)' "$@" "$TAG_NAMESPACE/" | grep -E "$RELEASE_TAG" | sort -V || true
}

latest_unsynced() {
  local newest synced
  newest=$(release_tags | tail -n 1)
  [[ -n $newest ]] || return 0
  synced=$(release_tags --merged=upstream | tail -n 1)
  if [[ -z $synced || $(printf '%s\n%s\n' "$synced" "$newest" | sort -V | tail -n 1) != "$synced" ]]; then
    printf '%s\n' "$newest"
  fi
}

merge=1
latest=0
while (( $# )); do
  case "$1" in
    --no-merge) merge=0 ;;
    --latest) latest=1 ;;
    -h|--help) usage ;;
    -*) echo "sync-upstream.sh: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

git rev-parse --verify -q refs/heads/upstream >/dev/null || { echo "no local upstream branch" >&2; exit 1; }
fetch_upstream

if (( latest )); then
  latest_unsynced
  exit 0
fi

tag=${1:-}
[[ -n $tag ]] || usage
ref="$TAG_NAMESPACE/$tag"
git rev-parse --verify -q "$ref^{commit}" >/dev/null || { echo "unknown omarchy-cellular tag $tag" >&2; exit 1; }

[[ -z $(git status --porcelain) ]] || { echo "working tree not clean" >&2; exit 1; }

start=$(git branch --show-current)
[[ -n $start && $start != "upstream" ]] || { echo "run this from main or a sync branch, not from upstream" >&2; exit 1; }

if git merge-base --is-ancestor "$ref" upstream; then
  echo "upstream: already contains omarchy-cellular $tag"
else
  git checkout -q upstream
  git merge --no-commit -s ours "$ref" >/dev/null
  git read-tree -u --reset "$ref"
  git checkout "$start" -- "${MAITRI_TOOLING[@]}"
  tools/rebrand.sh --all
  # Only tracked files belong in the rebranded tag: read-tree already staged
  # the tag, rebrand renames with git mv, and the tag's .gitignore does not
  # know about files main ignores, so `git add -A` would sweep them in.
  git add -u
  git commit -q -m "chore: merge omarchy-cellular $tag (rebranded)"
  echo "upstream: $(git rev-parse --short HEAD) = omarchy-cellular $tag, rebranded"
  git checkout -q "$start"
fi

(( merge )) || exit 0

if git merge --no-edit -m "chore: merge upstream (omarchy-cellular $tag)" upstream; then
  tools/rebrand.sh --check
  echo "sync: merged cleanly; run make test"
else
  echo "sync: resolve conflicts, then: tools/rebrand.sh --paths <files>; tools/rebrand.sh --check; git commit" >&2
  exit 1
fi
