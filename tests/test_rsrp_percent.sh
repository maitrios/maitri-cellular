#!/bin/bash
# rsrp_percent derives the bars from live RSRP because ModemManager's own
# signal-quality stalls on this modem. Run it against a stub mmcli.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail() { printf 'test_rsrp_percent.sh: %s\n' "$1" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/mmcli" <<'STUB'
#!/bin/sh
cat "$STUB_SIGNAL"
STUB
chmod 755 "$tmp/bin/mmcli"

{
  sed -n '/^kv() {/,/^}/p' bin/maitri-cellular
  sed -n '/^rsrp_percent() {/,/^}/p' bin/maitri-cellular
} >"$tmp/funcs.sh"
[[ -s $tmp/funcs.sh ]] || fail "kv and rsrp_percent not found in bin/maitri-cellular"

check() {
  local want=$1 got status=0
  got=$(PATH="$tmp/bin:$PATH" STUB_SIGNAL="$tmp/signal" bash -c "source '$tmp/funcs.sh'; rsrp_percent 0") || status=$?
  if [[ $want == none ]]; then
    ((status != 0)) || fail "expected no reading, got '$got'"
  else
    ((status == 0)) || fail "expected $want%, got no reading"
    [[ $got == "$want" ]] || fail "expected $want%, got '$got'"
  fi
}

signal() {
  printf 'modem.signal.lte.rsrp : %s\nmodem.signal.5g.rsrp : %s\n' "$1" "$2" >"$tmp/signal"
}

signal -156.00 -98.00;  check 55
signal -156.00 -104.00; check 40
signal -156.00 -80.00;  check 100
signal -156.00 -70.00;  check 100
signal -156.00 -120.00; check 0
signal -156.00 -135.00; check 0
signal -95.00 --;       check 62
signal -156.00 --;      check none
signal -156.00 -156.00; check none
printf 'modem.signal.lte.rsrp : --\n' >"$tmp/signal"; check none

printf 'test_rsrp_percent.sh ok\n'
