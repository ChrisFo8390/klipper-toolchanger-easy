#!/bin/bash
#
# Runs the KTC-E tests on a Klipper checkout (the code path for the probe API of
# Klipper): install.sh links the modules into klippy/extras, klippy runs the
# test configurations against a simulated MCU.
#
#   KLIPPER=/path/to/klipper DICTDIR=/path/to/dict tests/klipper/run.sh
#
#   KLIPPER  a Klipper git checkout, python requirements of klippy installed for PYTHON
#   DICTDIR  folder with the firmware dictionaries (atmega2560.dict, stm32g0b1.dict)
#   PYTHON   python of that environment (default: python3)
#
# Linux or macOS (symlinks, and klippy needs its C helper).

set -eu

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KLIPPER="$(cd "${KLIPPER:?set KLIPPER to a Klipper checkout}" && pwd)"
DICTDIR="$(cd "${DICTDIR:?set DICTDIR to the folder with the .dict files}" && pwd)"
PYTHON="${PYTHON:-python3}"

WORK="${KLIPPER}/test/ktce"
CONFIG="${WORK}/ktce_printer"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAILED: %s\n' "$*"; exit 1; }

step "Install"
mkdir -p "${WORK}"
KLIPPER_PATH="${KLIPPER}" INSTALL_PATH="${REPO}" CONFIG_PATH="${CONFIG}" \
    bash "${REPO}/install.sh" --no-restart --no-requirements --z-probe tap
if [ -n "$(git -C "${KLIPPER}" status --porcelain --untracked-files=no)" ]; then
    fail "Klipper has changes to tracked files"
fi
cp "${REPO}/tests/klipper/testing.py" "${KLIPPER}/klippy/extras/testing.py"
cp "${REPO}"/tests/kalico/ktce_basic.cfg "${REPO}"/tests/kalico/ktce_easy.cfg "${REPO}"/tests/kalico/ktce_noprobe.cfg "${WORK}/"
cp "${CONFIG}/toolchanger/tools/example_T0.cfg" "${CONFIG}/toolchanger/tools/T0.cfg"
sed -i 's/^canbus_uuid:.*/serial: \/dev\/ttyACM1/' "${CONFIG}/toolchanger/tools/T0.cfg"
printf '[include ktce_basic.cfg]\n\n[testing]\n' > "${WORK}/klipper_basic.cfg"
printf '[include ktce_easy.cfg]\n\n[testing]\n' > "${WORK}/klipper_easy.cfg"
printf '[include ktce_noprobe.cfg]

[testing]
' > "${WORK}/klipper_noprobe.cfg"

run_klippy() {
    local name="$1" log="${WORK}/$1.log" status
    shift
    set +e
    (cd "${KLIPPER}" && "${PYTHON}" klippy/klippy.py "${WORK}/klipper_${name}.cfg" \
        -i "${REPO}/tests/klipper/${name}.gcode" -o "${WORK}/${name}.out" -v "$@") > "${log}" 2>&1
    status=$?
    set -e
    # (Klipper logs a harmless traceback inside a debug message when it looks for the board model)
    if [ "${status}" -ne 0 ] || grep -q "^Traceback\|^ERROR\|Unknown command\|Transition to shutdown\|Config error" "${log}"; then
        grep -n "^Traceback\|^ERROR\|Error\|Unknown command\|Transition to shutdown\|ASSERT\|Config error" "${log}" | head -30
        tail -30 "${log}"
        fail "${name} (exit status ${status})"
    fi
    echo "${name} passed"
}

step "KTC-E on Klipper: toolchanger, tool probes, homing, probing, bed mesh, tool change"
run_klippy basic -d "${DICTDIR}/atmega2560.dict"

step "KTC-E on Klipper: easy-additions configuration from install.sh"
run_klippy easy -d "${DICTDIR}/atmega2560.dict" -d "EBBT0=${DICTDIR}/stm32g0b1.dict"

step "KTC-E on Klipper without tool probes: tool changes and CALIBRATE_ALL_OFFSETS"
run_klippy noprobe -d "${DICTDIR}/atmega2560.dict"

step "Uninstall"
KLIPPER_PATH="${KLIPPER}" INSTALL_PATH="${REPO}" CONFIG_PATH="${CONFIG}" \
    bash "${REPO}/install.sh" --no-restart --uninstall
for f in "${REPO}"/klipper/extras/*.py; do
    if [ -L "${KLIPPER}/klippy/extras/$(basename "${f}")" ]; then
        fail "$(basename "${f}") is still linked"
    fi
done

printf '\nAll KTC-E tests on Klipper passed\n'
