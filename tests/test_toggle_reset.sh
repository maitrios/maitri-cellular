#!/bin/bash
# The toggle decides from NetworkManager, and a modem that still reports a
# bearer NetworkManager dropped counts as stuck. Run both against a stub nmcli.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail() { printf 'test_toggle_reset.sh: %s\n' "$1" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/nmcli" <<'STUB'
#!/bin/sh
case $STUB_NM in
  activated) echo "GENERAL.STATE:activated" ;;
  activating) echo "GENERAL.STATE:activating" ;;
  inactive) ;;
  missing) echo "Error: no such connection profile." >&2; exit 10 ;;
esac
STUB
chmod 755 "$tmp/bin/nmcli"

{
  sed -n '/^nm_profile_down() {/,/^}/p' bin/maitri-cellular
  sed -n '/^cmd_toggle() {/,/^}/p' bin/maitri-cellular
  echo 'cmd_connect() { echo connect; }'
  echo 'cmd_disconnect() { echo disconnect; }'
  echo 'NM_CONN="Omarchy Cellular"'
} >"$tmp/funcs.sh"
grep -q '^cmd_toggle()' "$tmp/funcs.sh" && grep -q '^nm_profile_down()' "$tmp/funcs.sh" \
  || fail "cmd_toggle and nm_profile_down not found in bin/maitri-cellular"

run() { PATH="$tmp/bin:$PATH" STUB_NM=$1 bash -c "source '$tmp/funcs.sh'; $2"; }

toggle() {
  local got
  got=$(run "$1" cmd_toggle)
  [[ $got == "$2" ]] || fail "toggle with the profile $1: expected $2, got '$got'"
}
toggle activated disconnect
toggle activating disconnect
toggle inactive connect
toggle missing connect

down() {
  local status=0
  run "$1" nm_profile_down || status=$?
  if [[ $2 == yes ]]; then
    ((status == 0)) || fail "profile $1 should read as down"
  else
    ((status != 0)) || fail "profile $1 should not read as down"
  fi
}
down activated no
down activating no
down inactive yes
down missing no

printf 'test_toggle_reset.sh ok\n'
