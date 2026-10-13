#!/bin/bash
# read_signal picks the block for the newest technology the modem reports and
# drops placeholder blocks (an NSA LTE anchor's -156 dBm / -23 dB), whatever
# order mmcli prints them in. Run against a stub mmcli.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail() { printf 'test_read_signal.sh: %s\n' "$1" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/mmcli" <<'STUB'
#!/bin/sh
cat "$STUB_SIGNAL"
STUB
chmod 755 "$tmp/bin/mmcli"

{
  sed -n '/^signal_block_ok() {/,/^}/p' bin/maitri-cellular
  sed -n '/^read_signal() {/,/^}/p' bin/maitri-cellular
  echo 'modem_index() { echo 0; }'
} >"$tmp/funcs.sh"
grep -q '^read_signal()' "$tmp/funcs.sh" && grep -q '^signal_block_ok()' "$tmp/funcs.sh" \
  || fail "read_signal and signal_block_ok not found in bin/maitri-cellular"

header='  ------------------------------
  Signal |         refresh rate: 5 seconds
  ------------------------------'
lte_fake='  LTE    |                 rsrp: -156.00 dBm
         |                  s/n: -23.00 dB'
lte_real='  LTE    |                 rssi: -71.00 dBm
         |                 rsrp: -98.00 dBm
         |                 rsrq: -11.00 dB
         |                  s/n: 8.00 dB'
nr='  5G     |                 rsrp: -99.00 dBm
         |                  s/n: 3.00 dB'
umts='  UMTS   |                 rscp: -90.00 dBm
         |                 ecio: -7.00 dB'
sep='  ------------------------------'

check() { # check <TECH> <expected "tech rsrp snr"> <blocks...>
  local tech=$1 want=$2 got
  shift 2
  printf '%s\n' "$header" "$@" >"$tmp/signal"
  rm -rf "$tmp/state"
  got=$(PATH="$tmp/bin:$PATH" STUB_SIGNAL="$tmp/signal" STATE=connected TECH="$tech" STATE_DIR="$tmp/state" \
    bash -c "source '$tmp/funcs.sh'; read_signal; echo \"\$SIG_TECH|\$SIG_RSRP|\$SIG_SNR\"")
  [[ $got == "$want" ]] || fail "TECH=$tech: expected '$want', got '$got'"
}

check "LTE + 5GNR" "5G|-99.00 dBm|3.00 dB"  "$lte_fake" "$sep" "$nr"
check "LTE + 5GNR" "5G|-99.00 dBm|3.00 dB"  "$nr" "$sep" "$lte_fake"
check "5GNR"       "5G|-99.00 dBm|3.00 dB"  "$nr" "$sep" "$lte_fake"
check "5GNR"       "||"                     "$lte_fake"
check "LTE"        "LTE|-98.00 dBm|8.00 dB" "$lte_real" "$sep" "$nr"
check "LTE + 5GNR" "5G|-99.00 dBm|3.00 dB"  "$lte_real" "$sep" "$nr"
check "LTE"        "LTE|-98.00 dBm|8.00 dB" "$nr" "$sep" "$lte_real"
check "UMTS"       "UMTS||"                 "$umts"
check ""           "5G|-99.00 dBm|3.00 dB"  "$lte_fake" "$sep" "$nr"

printf 'test_read_signal.sh ok\n'
