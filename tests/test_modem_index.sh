#!/bin/bash
# modem_index must not cache an empty modem list: wait_for_modem polls it right
# after a ModemManager restart, while the list is briefly empty.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail() { printf 'test_modem_index.sh: %s\n' "$1" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

{
  sed -n '/^modem_index() {/,/^}/p' bin/maitri-cellular
  echo 'get_cfg() { :; }'
  echo 'modem_list() { cat "$LIST"; }'
} >"$tmp/funcs.sh"
grep -q '^modem_index()' "$tmp/funcs.sh" || fail "modem_index not found in bin/maitri-cellular"

got=$(CACHE_DIR="$tmp/cache" LIST="$tmp/list" bash -c "
  source '$tmp/funcs.sh'
  : >'$tmp/list'
  first=\$(modem_index)
  echo 4 >'$tmp/list'
  printf '%s|%s' \"\$first\" \"\$(modem_index)\"
")
[[ $got == "|4" ]] || fail "expected an empty first answer and 4 once the modem is listed, got '$got'"

printf 'test_modem_index.sh ok\n'
