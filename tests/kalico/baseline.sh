#!/bin/bash
#
# What the unmodified upstream KTC-E does on Kalico. Informational: shows why
# the changes of this branch are needed, and tells when upstream starts to work
# on Kalico by itself (this script then fails on purpose, so that it is noticed).
#
#   KALICO=/path/to/kalico DICTDIR=/path/to/dict UPSTREAM=/path/to/upstream-ktce \
#       tests/kalico/baseline.sh
#
# Same requirements as run.sh.

set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KALICO="$(cd "${KALICO:?set KALICO to a Kalico checkout}" && pwd)"
DICTDIR="$(cd "${DICTDIR:?set DICTDIR to the folder with the .dict files}" && pwd)"
UPSTREAM="$(cd "${UPSTREAM:?set UPSTREAM to a checkout of the unmodified KTC-E}" && pwd)"
PYTHON="${PYTHON:-python3}"

TESTS="${REPO}/tests/kalico"
TEST_DIR="${KALICO}/test/klippy"

cp "${TESTS}/ktce_basic.cfg" "${TESTS}/ktce_basic.test" "${TEST_DIR}/"

try_test() {
    local out
    set +e
    out="$(cd "${KALICO}" && "${PYTHON}" -m pytest -p no:cacheprovider -q --dictdir "${DICTDIR}" \
        test/klippy/ktce_basic.test 2>&1)"
    local status=$?
    set -e
    printf '%s\n' "${out}" | grep -E "Config error|Error|error:|has no attribute|Unable to load|not found|passed|failed" | head -8
    return ${status}
}

echo "==> The way the upstream installer works: every module linked into klippy/extras"
for f in "${UPSTREAM}"/klipper/extras/*.py; do ln -sfn "${f}" "${KALICO}/klippy/extras/"; done
echo "Moonraker's view of Kalico now:"
git -C "${KALICO}" status --porcelain --untracked-files=no
git -C "${KALICO}" describe --always --tags --long --dirty
if try_test; then
    echo "Upstream works on Kalico by itself now, this branch may not be needed any more"
    exit 1
fi
echo "-> does not run on Kalico"

echo
echo "==> Upstream modules in klippy/plugins instead (keeps Kalico clean)"
for f in "${UPSTREAM}"/klipper/extras/*.py; do
    name="$(basename "${f}")"
    rm -f "${KALICO}/klippy/extras/${name}"
    if [ "${name}" != "tools_calibrate.py" ]; then
        ln -sfn "${f}" "${KALICO}/klippy/plugins/${name}"
    fi
done
git -C "${KALICO}" checkout -- klippy/extras
if try_test; then
    echo "Upstream works from klippy/plugins on Kalico, this branch may not be needed any more"
    exit 1
fi
echo "-> does not run on Kalico either"
