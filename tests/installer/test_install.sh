#!/bin/bash
#
# Tests of install.sh on fake Klipper and Kalico trees (no printer, no Klipper
# needed). Needs git and a filesystem with symlinks, so Linux or macOS.
#
#   tests/installer/test_install.sh

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="${REPO}/install.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

PASSED=0
FAILED=0

function pass { PASSED=$((PASSED + 1)); echo "  ok    $1"; }
function fail { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; }

function check {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "${description}"; else fail "${description}"; fi
}

function check_not {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "${description}"; else pass "${description}"; fi
}

# A git repository that looks enough like Klipper / Kalico for the installer:
#   kalico: klippy/plugins (ignored by git, __init__.py tracked) and a tracked
#           klippy/extras/tools_calibrate.py of its own
#   klipper: only klippy/extras
function make_tree {
    local flavour="$1" dir="$2"
    mkdir -p "${dir}/klippy/extras"
    echo "# probe" > "${dir}/klippy/extras/probe.py"
    if [ "${flavour}" = "kalico" ]; then
        mkdir -p "${dir}/klippy/plugins"
        echo "# plugin package" > "${dir}/klippy/plugins/__init__.py"
        echo "# kalico's own tools_calibrate" > "${dir}/klippy/extras/tools_calibrate.py"
        echo "allow_plugin_override" > "${dir}/klippy/printer.py"
        printf 'klippy/plugins/*\n!klippy/plugins/__init__.py\n__pycache__/\n' > "${dir}/.gitignore"
    else
        echo "# printer" > "${dir}/klippy/printer.py"
    fi
    git -C "${dir}" init -q
    git -C "${dir}" add -A
    git -C "${dir}" commit -q -m initial
}

# What Moonraker looks at: tracked files modified or replaced
function is_clean {
    [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ]
}

function describe_dirty {
    git -C "$1" describe --always --tags --long --dirty | grep -q -- '-dirty$'
}

function run_install {
    local tree="$1" config="$2"
    shift 2
    KLIPPER_PATH="${tree}" INSTALL_PATH="${REPO}" CONFIG_PATH="${config}" \
        bash "${INSTALL}" --no-restart --no-requirements --z-probe tap "$@"
}

function modules {
    for f in "${REPO}"/klipper/extras/*.py; do basename "${f}"; done
}

function links_into_repo {
    [ -L "$1" ] && case "$(readlink "$1")" in "${REPO}"/klipper/extras/*) true ;; *) false ;; esac
}

function all_modules_linked_in {
    local dir="$1" skip="${2:-}" m
    for m in $(modules); do
        [ "${m}" = "${skip}" ] && continue
        links_into_repo "${dir}/${m}" || return 1
    done
}

function no_module_linked_in {
    local dir="$1" m
    for m in $(modules); do
        links_into_repo "${dir}/${m}" && return 1
    done
    return 0
}

# the old installer: every module of the repository linked into klippy/extras
function legacy_install {
    local tree="$1" f
    for f in "${REPO}"/klipper/extras/*.py; do ln -sfn "${f}" "${tree}/klippy/extras/"; done
}

echo "== module list"
MODULES="$(modules | tr '\n' ' ')"
echo "  ${MODULES}"
check "tools_calibrate.py is one of the modules" test -f "${REPO}/klipper/extras/tools_calibrate.py"

# ------------------------------------------------------------------------------
echo "== Kalico: fresh install goes to klippy/plugins and leaves Kalico clean"
K="${WORK}/kalico"; C="${WORK}/kalico-config"
make_tree kalico "${K}"
check "tree is clean before" is_clean "${K}"
check "install succeeds" run_install "${K}" "${C}"
check "all modules but tools_calibrate are linked in plugins" all_modules_linked_in "${K}/klippy/plugins" tools_calibrate.py
check_not "tools_calibrate.py is not linked in plugins" test -e "${K}/klippy/plugins/tools_calibrate.py"
check "nothing of ours is linked in extras" no_module_linked_in "${K}/klippy/extras"
check "Kalico's tools_calibrate.py is still a regular file" test -f "${K}/klippy/extras/tools_calibrate.py" -a ! -L "${K}/klippy/extras/tools_calibrate.py"
check "tracked files unchanged" is_clean "${K}"
check_not "git describe is not dirty" describe_dirty "${K}"
check "configuration: toolchanger.cfg linked" test -L "${C}/toolchanger/readonly-configs/toolchanger.cfg"
check "configuration: user config copied" test -f "${C}/toolchanger/toolchanger-config.cfg"
check "configuration: tap tool configs copied" test -f "${C}/toolchanger/tools/example_T0.cfg"
check "configuration: tap include linked" test -L "${C}/toolchanger/readonly-configs/toolchanger-include.cfg"

echo "== Kalico: second run changes nothing, user files are kept"
echo "# my change" >> "${C}/toolchanger/toolchanger-config.cfg"
check "install succeeds again" run_install "${K}" "${C}"
check "modules still linked" all_modules_linked_in "${K}/klippy/plugins" tools_calibrate.py
check "tracked files unchanged" is_clean "${K}"
check "user config not overwritten" grep -q "# my change" "${C}/toolchanger/toolchanger-config.cfg"

echo "== Kalico: --check"
OUT="$(KLIPPER_PATH="${K}" INSTALL_PATH="${REPO}" CONFIG_PATH="${C}" bash "${INSTALL}" --check 2>&1)"
check "reports Kalico" grep -q "flavour      : Kalico" <<<"${OUT}"
check "reports plugins as the target" grep -q "module target: plugins" <<<"${OUT}"
check "reports a clean tree" grep -q "can update it" <<<"${OUT}"

echo "== Kalico: --override-tools-calibrate"
check "install succeeds" run_install "${K}" "${C}" --override-tools-calibrate
check "all modules linked in plugins" all_modules_linked_in "${K}/klippy/plugins"
check "Kalico's tools_calibrate.py untouched" is_clean "${K}"
check "install without the option keeps our tools_calibrate" run_install "${K}" "${C}"
check "... still linked" links_into_repo "${K}/klippy/plugins/tools_calibrate.py"

echo "== Kalico: --uninstall"
check "uninstall succeeds" run_install "${K}" "${C}" --uninstall
check "no module linked in plugins" no_module_linked_in "${K}/klippy/plugins"
check "tracked files unchanged" is_clean "${K}"
check "configuration is kept" test -f "${C}/toolchanger/toolchanger-config.cfg"

# ------------------------------------------------------------------------------
echo "== Kalico: an install of the old installer is migrated"
K="${WORK}/kalico-legacy"; C="${WORK}/kalico-legacy-config"
make_tree kalico "${K}"
legacy_install "${K}"
check_not "the old installer leaves Kalico dirty (what blocked the update)" is_clean "${K}"
check "git describe is dirty" describe_dirty "${K}"
check "tools_calibrate.py is a link now" test -L "${K}/klippy/extras/tools_calibrate.py"
check "install succeeds" run_install "${K}" "${C}"
check "Kalico is clean again" is_clean "${K}"
check_not "git describe is not dirty" describe_dirty "${K}"
check "Kalico's tools_calibrate.py is back" grep -q "kalico's own" "${K}/klippy/extras/tools_calibrate.py"
check "no old links in extras" no_module_linked_in "${K}/klippy/extras"
check "modules are in plugins" all_modules_linked_in "${K}/klippy/plugins" tools_calibrate.py

echo "== Kalico: links that do not belong to us are left alone"
K="${WORK}/kalico-other"; C="${WORK}/kalico-other-config"
make_tree kalico "${K}"
mkdir -p "${WORK}/elsewhere"
echo "# somebody else's module" > "${WORK}/elsewhere/mine.py"
ln -sfn "${WORK}/elsewhere/mine.py" "${K}/klippy/extras/mine.py"
legacy_install "${K}"
check "install succeeds" run_install "${K}" "${C}"
check "other links untouched" test -L "${K}/klippy/extras/mine.py"

# ------------------------------------------------------------------------------
echo "== Klipper: modules go to klippy/extras as before"
K="${WORK}/klipper"; C="${WORK}/klipper-config"
make_tree klipper "${K}"
check "install succeeds" run_install "${K}" "${C}"
check "all modules are linked in extras" all_modules_linked_in "${K}/klippy/extras"
check_not "no plugins folder is created" test -e "${K}/klippy/plugins"
check "--target plugins is refused" bash -c "! KLIPPER_PATH='${K}' INSTALL_PATH='${REPO}' CONFIG_PATH='${C}' bash '${INSTALL}' --no-restart --no-requirements --z-probe tap --target plugins"
check "--uninstall removes the links" run_install "${K}" "${C}" --uninstall
check "no module linked in extras" no_module_linked_in "${K}/klippy/extras"

echo "== Kalico: --target extras puts everything where the old installer did"
K="${WORK}/kalico-extras"; C="${WORK}/kalico-extras-config"
make_tree kalico "${K}"
check "install succeeds" run_install "${K}" "${C}" --target extras
check "all modules are linked in extras" all_modules_linked_in "${K}/klippy/extras"

# ------------------------------------------------------------------------------
echo "== Z probe on a shuttle"
K="${WORK}/kalico-shuttle"; C="${WORK}/kalico-shuttle-config"
make_tree kalico "${K}"
check "install succeeds" bash -c "KLIPPER_PATH='${K}' INSTALL_PATH='${REPO}' CONFIG_PATH='${C}' bash '${INSTALL}' --no-restart --no-requirements --z-probe shuttle"
check "scanner include linked" bash -c "readlink '${C}/toolchanger/readonly-configs/toolchanger-include.cfg' | grep -q toolchanger-include_scanner.cfg"
check "shuttle tool configs copied" test -f "${C}/toolchanger/tools/example_T0.cfg"

echo "== Errors"
check "no Klipper at KLIPPER_PATH" bash -c "! KLIPPER_PATH='${WORK}/nothing' INSTALL_PATH='${REPO}' CONFIG_PATH='${WORK}/c' bash '${INSTALL}' --no-restart --no-requirements --z-probe tap"
check "unknown option" bash -c "! bash '${INSTALL}' --bogus"
check "bad --z-probe" bash -c "! bash '${INSTALL}' --z-probe foo"
check "bad --target" bash -c "! bash '${INSTALL}' --target foo"

echo
echo "${PASSED} passed, ${FAILED} failed"
[ "${FAILED}" -eq 0 ]
