#!/bin/bash
#
# Runs the KTC-E tests on a Kalico checkout, set up the way a user's printer is:
# install.sh links the modules into klippy/extras (all but the tools_calibrate
# that Kalico has) and the configuration into a config folder, then Kalico's own
# test harness runs klippy on the test configs.
#
#   KALICO=/path/to/kalico DICTDIR=/path/to/dict tests/kalico/run.sh
#
#   KALICO   a Kalico git checkout, with the python requirements of klippy and
#            pytest installed for PYTHON
#   DICTDIR  folder with the firmware dictionaries (atmega2560.dict, stm32g0b1.dict)
#   PYTHON   python of that environment (default: python3)
#
# Linux or macOS (symlinks, and klippy needs its C helper).

set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KALICO="$(cd "${KALICO:?set KALICO to a Kalico checkout}" && pwd)"
DICTDIR="$(cd "${DICTDIR:?set DICTDIR to the folder with the .dict files}" && pwd)"
PYTHON="${PYTHON:-python3}"

TESTS="${REPO}/tests/kalico"
TEST_DIR="${KALICO}/test/klippy"
CONFIG="${TEST_DIR}/ktce_printer"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAILED: %s\n' "$*"; exit 1; }

kalico_state() { git -C "${KALICO}" status --porcelain --untracked-files=no; }

assert_clean() {
    local changes
    changes="$(kalico_state)"
    if [ -n "${changes}" ]; then
        printf '%s\n' "${changes}"
        fail "$1: Kalico has changes to tracked files, Moonraker would not update it"
    fi
    if git -C "${KALICO}" describe --always --tags --long --dirty | grep -q -- '-dirty$'; then
        fail "$1: git describe says dirty"
    fi
    echo "Kalico is clean: $1"
}

install_ktce() {
    KLIPPER_PATH="${KALICO}" INSTALL_PATH="${REPO}" CONFIG_PATH="${CONFIG}" \
        bash "${REPO}/install.sh" --no-restart --no-requirements --z-probe tap "$@"
}

run_tests() {
    (cd "${KALICO}" && "${PYTHON}" -m pytest -p no:cacheprovider -v \
        --dictdir "${DICTDIR}" "$@")
}

step "Kalico before the install"
assert_clean "before"
git -C "${KALICO}" log -1 --format='Kalico %h %s'

step "What the old installer did: every module linked into klippy/extras"
for f in "${REPO}"/klipper/extras/*.py; do ln -sfn "${f}" "${KALICO}/klippy/extras/"; done
if [ -z "$(kalico_state)" ]; then
    fail "expected the old way of installing to leave Kalico dirty"
fi
kalico_state
git -C "${KALICO}" describe --always --tags --long --dirty

step "Install (puts back what the old installer replaced, links the other modules into klippy/extras)"
install_ktce
assert_clean "after the install"
for f in "${REPO}"/klipper/extras/*.py; do
    name="$(basename "${f}")"
    if [ "${name}" = "tools_calibrate.py" ]; then
        if [ -L "${KALICO}/klippy/extras/${name}" ] || [ -e "${KALICO}/klippy/plugins/${name}" ]; then
            fail "Kalico's own ${name} was replaced"
        fi
    elif [ ! -L "${KALICO}/klippy/extras/${name}" ]; then
        fail "${name} is not linked into klippy/extras"
    elif [ -e "${KALICO}/klippy/plugins/${name}" ]; then
        fail "${name} is also in klippy/plugins, Kalico refuses that"
    fi
done
install_ktce
assert_clean "after the second install"

step "Add-ons import our modules as extras.<name> (AFC: from extras.toolchanger import DETECT_PRESENT)"
(cd "${KALICO}" && "${PYTHON}" -c "
import klippy.compat
klippy.compat.install()
from extras.toolchanger import DETECT_PRESENT
from extras.tool import Tool
print('extras.toolchanger and extras.tool are found, DETECT_PRESENT =', DETECT_PRESENT)
")

step "Prepare the tests"
cp "${TESTS}"/ktce_*.cfg "${TESTS}"/ktce_*.test "${TEST_DIR}/"
# the toolhead board of the tap example, as a serial board for the simulator
cp "${CONFIG}/toolchanger/tools/example_T0.cfg" "${CONFIG}/toolchanger/tools/T0.cfg"
sed -i 's/^canbus_uuid:.*/serial: \/dev\/ttyACM1/' "${CONFIG}/toolchanger/tools/T0.cfg"
assert_clean "with the tests copied in"

step "Kalico's own tests still pass with the modules installed"
run_tests test/klippy/bed_mesh_default.test test/klippy/commands.test test/test_tools_calibrate.py

step "KTC-E on Kalico: toolchanger, tool probes, homing, probing, bed mesh, tool change"
run_tests test/klippy/ktce_basic.test

step "KTC-E on Kalico: easy-additions configuration from install.sh"
run_tests test/klippy/ktce_easy.test

# klippy must stop with a message that contains $2 when it loads the configuration $1
expect_klippy_failure() {
    local cfg="$1" message="$2" out status
    echo "G28" > "${CONFIG}/_gcode"
    set +e
    out="$(cd "${KALICO}" && "${PYTHON}" -m klippy "${TEST_DIR}/${cfg}" -i "${CONFIG}/_gcode" \
        -o "${CONFIG}/_out" -v -d "${DICTDIR}/atmega2560.dict" 2>&1)"
    status=$?
    set -e
    if [ "${status}" -eq 0 ]; then
        echo "${out}" | tail -20
        fail "expected klippy to refuse ${cfg}"
    fi
    if ! echo "${out}" | grep -q "${message}"; then
        echo "${out}" | tail -20
        fail "klippy stopped on ${cfg}, but not with: ${message}"
    fi
    echo "klippy refuses ${cfg} (${message}), as expected"
}

step "KTC-E on Kalico without tool probes (Cartographer, Beacon, ...): tool changes and CALIBRATE_ALL_OFFSETS"
run_tests test/klippy/ktce_noprobe.test

step "The smaller modules: multi_fan, manual_rail, bed_thermal_adjust"
run_tests test/klippy/ktce_modules.test

step "The same with the modules in klippy/plugins (--target plugins)"
install_ktce --target plugins
assert_clean "with the modules in klippy/plugins"
for f in "${REPO}"/klipper/extras/*.py; do
    name="$(basename "${f}")"
    if [ "${name}" != "tools_calibrate.py" ] && { [ ! -L "${KALICO}/klippy/plugins/${name}" ] || [ -L "${KALICO}/klippy/extras/${name}" ]; }; then
        fail "${name} is not only in klippy/plugins"
    fi
done
run_tests test/klippy/ktce_basic.test test/klippy/ktce_modules.test
step "... and back to klippy/extras"
install_ktce
assert_clean "back in klippy/extras"
for f in "${REPO}"/klipper/extras/*.py; do
    name="$(basename "${f}")"
    if [ -e "${KALICO}/klippy/plugins/${name}" ]; then
        fail "${name} is still in klippy/plugins"
    fi
done

step "A z_offset outside of the range of the Z stepper is refused when the configuration is loaded"
expect_klippy_failure ktce_range.cfg "outside of position_min"

step "Our tools_calibrate without allow_plugin_override is refused by Kalico (so install.sh only links it on request)"
install_ktce --override-tools-calibrate
expect_klippy_failure ktce_basic.cfg "found in both extras and plugins"

step "Our tools_calibrate with allow_plugin_override"
run_tests test/klippy/ktce_override.test
assert_clean "with our tools_calibrate"

step "Uninstall"
install_ktce --uninstall
assert_clean "after the uninstall"
for f in "${REPO}"/klipper/extras/*.py; do
    name="$(basename "${f}")"
    if [ -L "${KALICO}/klippy/plugins/${name}" ] || [ -L "${KALICO}/klippy/extras/${name}" ]; then
        fail "${name} is still linked after the uninstall"
    fi
done

printf '\nAll KTC-E tests on Kalico passed\n'
