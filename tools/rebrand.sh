#!/bin/bash

# Rebrand an upstream omarchy-cellular tree into maitri-cellular. Idempotent and
# deterministic: the same input tree always yields the same output, and running
# it twice is a no-op. tools/sync-upstream.sh runs it after every upstream
# merge; run `tools/rebrand.sh --check` before committing to catch anything that
# slipped in.
#
#   tools/rebrand.sh [--all]        delete upstream-only files, rename paths, rewrite contents
#   tools/rebrand.sh --no-delete    rename + rewrite only
#   tools/rebrand.sh --paths F...   rewrite contents of the given files only (after a hand merge)
#   tools/rebrand.sh --check        exit 1 and list offenders if any unprotected brand token remains

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# A line that mentions Omarchy on purpose (credit, an upstream command name)
# carries the marker `rebrand:keep` -- as an HTML comment in markdown, a `#`
# comment in shell or YAML -- and is left alone.
#
# Upstream identifiers that must survive the rename: attribution, the upstream
# repos, hosts maitri does not own, and the NetworkManager profile name, which
# existing installs already have on disk. Anything else spelled "omarchy" or
# "relctx.cellular" is ours to rename.
PROTECTED_TOKENS=(
  'relctx/omarchy-cellular'
  'Erruviel/omarchy-wwan'
  'github.com/basecamp/omarchy'
  'omacom/omarchy'
  'omarchy.org'
  # Headers and names an omarchy-wwan-era config carries; the self-migration
  # matches them verbatim.
  'omarchy-wwan'
  'Omarchy WWAN'
  # The gsm connection profile every existing install already has. Renaming
  # the default would orphan it and leave two profiles competing.
  ':-Omarchy Cellular}'
  'named `Omarchy Cellular`'
  'delete "Omarchy Cellular"'
)

# Files whose contents are never rewritten.
CONTENT_EXCLUDE=(
  'tools/rebrand.sh'
  'tools/sync-upstream.sh'
  'LICENSE'
  'MAITRI.md'
  '.github/workflows/sync-upstream.yml'
  'tests/test_maitri.sh'
)

# Upstream-only files maitri-cellular does not ship. Applied on every sync so
# they do not resurrect. Globs are expanded against the index.
DELETE_LIST=(
  # Upstream CI and funding. maitri-cellular keeps its own workflows on main.
  '.github'
)

mode=all
paths=()
while (( $# )); do
  case "$1" in
    --all) mode=all ;;
    --no-delete) mode=no-delete ;;
    --check) mode=check ;;
    --paths) mode=paths; shift; paths=("$@"); break ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) echo "rebrand.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

# Perl program shared by the path rename, the rewrite and the check: protect
# upstream tokens, rewrite, restore. Order matters: the specific rules run
# before the generic Omarchy -> maitri fallback.
#
#   plugin id                   relctx.cellular      -> maitrios.cellular
#   install URL, Omarchy link   relctx/omarchy-cellular.git -> maitrios/maitri-cellular.git, omarchy.org -> maitrios/maitri
#   Omarchy 4 and its codename  Omarchy 4.0 (quattro) -> maitri
#   articles                    an Omarchy           -> a maitri
#   everything else             OMARCHY/Omarchy/omarchy -> MAITRI/maitri/maitri
#                               (binaries, env vars, ~/.config/omarchy, state dirs, prose)
PERL_REWRITE='
  BEGIN { @p = grep { length } split /\n/, $ENV{REBRAND_PROTECT}; }
  unless (/rebrand:keep/) {
    s{\[Omarchy\]\(https://omarchy\.org/?\)}{[maitri](https://github.com/maitrios/maitri)}g;
    s{https://github\.com/relctx/omarchy-cellular\.git}{https://github.com/maitrios/maitri-cellular.git}g;
    s/^Omarchy 4\.0 \(quattro\) or newer\./A current maitri./;
    for my $i (0..$#p) { my $t = $p[$i]; s/\Q$t\E/\x01P${i}\x01/g; }
    s/\brelctx\.cellular\b/maitrios.cellular/g;
    s/\b([Aa])n Omarchy\b/$1 Omarchy/g;
    s/\bOmarchy 4(?:\.0)?(?: \(quattro\))?/maitri/g;
    s/OMARCHY/MAITRI/g;
    s/Omarchy/maitri/g;
    s/omarchy/maitri/g;
    for my $i (0..$#p) { my $t = $p[$i]; s/\x01P${i}\x01/$t/g; }
  }
'
export REBRAND_PROTECT
REBRAND_PROTECT=$(printf '%s\n' "${PROTECTED_TOKENS[@]}")

brand_re='omarchy|relctx\.cellular'

rename_path() {
  perl -pe "$PERL_REWRITE" <<<"$1"
}

is_excluded() {
  local f=$1 x
  for x in "${CONTENT_EXCLUDE[@]}"; do [[ $f == "$x" ]] && return 0; done
  return 1
}

is_text() {
  grep -Iq . "$1" 2>/dev/null
}

rewrite_file() {
  local f=$1
  is_excluded "$f" && return 0
  [[ -f $f ]] || return 0
  is_text "$f" || return 0
  grep -q -i -E "$brand_re" "$f" || return 0
  perl -pi -e "$PERL_REWRITE" "$f"
}

delete_upstream_only() {
  local entry
  for entry in "${DELETE_LIST[@]}"; do
    git rm -rqf --ignore-unmatch -- "$entry" "$(rename_path "$entry")" 2>/dev/null || true
  done
}

rename_paths() {
  local old new dir
  # Deepest paths first so a file moves before its parent directory is emptied.
  while IFS= read -r old; do
    new=$(rename_path "$old")
    [[ $new == "$old" ]] && continue
    dir=$(dirname -- "$new")
    mkdir -p -- "$dir"
    git mv -k -- "$old" "$new"
  done < <(git ls-files | grep -i -E "$brand_re" | awk '{ print gsub("/","/") "\t" $0 }' | sort -rn | cut -f2-)
}

rewrite_all() {
  local f
  while IFS= read -r -d '' f; do
    rewrite_file "$f"
  done < <(git ls-files -z)
}

check() {
  local rc=0 f
  if git ls-files | grep -v -x -F -f <(printf '%s\n' "${CONTENT_EXCLUDE[@]}") | grep -qi -E "$brand_re"; then
    echo "rebrand: paths still carry the upstream brand:" >&2
    git ls-files | grep -v -x -F -f <(printf '%s\n' "${CONTENT_EXCLUDE[@]}") | grep -i -E "$brand_re" >&2
    rc=1
  fi
  while IFS= read -r -d '' f; do
    is_excluded "$f" && continue
    [[ -f $f ]] || continue
    is_text "$f" || continue
    grep -q -i -E "$brand_re" "$f" || continue
    if ! diff -q "$f" <(perl -pe "$PERL_REWRITE" "$f") >/dev/null; then
      echo "rebrand: unprotected brand token in $f" >&2
      rc=1
    fi
  done < <(git ls-files -z)
  (( rc == 0 )) && echo "rebrand: clean"
  return $rc
}

# --all deletes upstream-only paths, including the upstream .github/ that main
# replaces with its own workflows. It only ever runs on the rebranded upstream
# tree.
if [[ $mode == "all" && $(git branch --show-current) != "upstream" ]]; then
  echo "rebrand.sh: --all rewrites an upstream tag tree; run it on the upstream branch (tools/sync-upstream.sh does)." >&2
  echo "rebrand.sh: on main use --paths <files> or --check." >&2
  exit 1
fi

case "$mode" in
  all)
    delete_upstream_only
    rename_paths
    rewrite_all
    ;;
  no-delete)
    rename_paths
    rewrite_all
    ;;
  paths)
    for f in "${paths[@]}"; do rewrite_file "$f"; done
    ;;
  check)
    check
    ;;
esac
