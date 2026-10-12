#!/bin/bash
# maitri-cellular's own invariants: the rebrand holds, the plugin is maitri's
# maitrios.cellular, the scripts parse, the Qt 6.12 palette qualification stays,
# and the bars derive from live RSRP.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

fail() { printf 'test_maitri.sh: %s\n' "$1" >&2; exit 1; }

tools/rebrand.sh --check >/dev/null || fail "upstream brand leaked; run tools/rebrand.sh --check"

python3 - <<'PY' || fail "manifest metadata is wrong"
import json
from pathlib import Path

manifest = json.loads(Path("manifest.json").read_text())
assert manifest["schemaVersion"] == 1
assert manifest["id"] == "maitrios.cellular", manifest["id"]
assert manifest["kinds"] == ["bar-widget"], manifest["kinds"]
assert manifest["homepage"] == "https://github.com/maitrios/maitri-cellular", manifest.get("homepage")
entry = manifest["entryPoints"]["barWidget"]
assert Path(entry).is_file() and not entry.startswith(("/", "..")), entry
assert manifest["barWidget"]["defaultSection"] in ("left", "center", "right")
PY

[[ -x bin/maitri-cellular && -x bin/maitri-cellular-providers ]] || fail "bin scripts must stay executable"
[[ ! -e bin/omarchy-cellular ]] || fail "the upstream binary name came back"
bash -n bin/maitri-cellular || fail "bin/maitri-cellular does not parse"
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' bin/maitri-cellular-providers \
  || fail "bin/maitri-cellular-providers does not parse"

# Qt 6.12's QtQuick Color type shadows the qs.Commons palette singleton, so a
# bare Color.x reads undefined. A sync from an upstream release without the
# qualification would bring the bare reads back.
if grep -rnP '(?<![\w.$])Color\.(?!qml\b)(?=[A-Za-z_])' shell --include='*.qml'; then
  fail "read the palette as Commons.Color (import qs.Commons as Commons); a bare Color is undefined on Qt 6.12"
fi

grep -q '^rsrp_percent() {' bin/maitri-cellular && grep -q 'live=$(rsrp_percent "$idx") && SIGNAL=$live' bin/maitri-cellular \
  || fail "read_state must derive SIGNAL from live RSRP"
bash tests/test_rsrp_percent.sh

[[ ! -e .github/workflows/pages.yml ]] || fail "upstream workflows are on the delete list but came back"

extra=$(find . -path ./.git -prune -o -mindepth 2 -type f \( -name manifest.json -o -name '*.manifest.json' \) -print)
[[ -z $extra ]] || fail "extra manifests the shell would load as plugins: $extra"

printf 'test_maitri.sh ok\n'
