#!/bin/bash
#
# klipper-toolchanger-easy installer
#
# Links the Python modules into Klipper, the macros into the configuration and
# copies the files that you edit. Safe to run again.
#
# Klipper:  the modules are linked into klippy/extras.
# Kalico:   the modules are linked into klippy/plugins instead. That folder is
#           ignored by git, so Kalico stays "clean" and can be updated from
#           Mainsail / Moonraker. Kalico already has a tools_calibrate.py of its
#           own in klippy/extras; it is kept (see kalico.md for the exception).
#
# Options:
#   --target auto|extras|plugins   where to link the modules (default auto: plugins on Kalico, extras otherwise)
#   --z-probe tap|shuttle|none     how you probe Z, asked if you do not give it
#   --override-tools-calibrate     Kalico only: also link our tools_calibrate.py into plugins
#                                  (needs [danger_options] allow_plugin_override: True)
#   --no-requirements              do not install the Python requirements
#   --no-restart                   do not restart Klipper
#   --uninstall                    remove the links (and restore what an old install replaced), keep the configuration
#   --check                        only report what is installed and whether Klipper/Kalico is clean
#   -h, --help
#
# Other locations: KLIPPER_PATH, KLIPPY_ENV_PATH, INSTALL_PATH, CONFIG_PATH (environment)

REPO_URL="${REPO_URL:-https://github.com/jwellman80/klipper-toolchanger-easy.git}"
KLIPPER_PATH="${KLIPPER_PATH:-${HOME}/klipper}"
KLIPPY_ENV_PATH="${KLIPPY_ENV_PATH:-${HOME}/klippy-env}"
CONFIG_PATH="${CONFIG_PATH:-${HOME}/printer_data/config}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${INSTALL_PATH:-}" ]; then
    if [ -d "${SCRIPT_DIR}/klipper/extras" ]; then
        INSTALL_PATH="${SCRIPT_DIR}"
    else
        INSTALL_PATH="${HOME}/klipper-toolchanger-easy"
    fi
fi

set -eu
export LC_ALL=C

TARGET="auto"
Z_PROBE=""
OVERRIDE_TOOLS_CALIBRATE="no"
DO_REQUIREMENTS="yes"
DO_RESTART="yes"
MODE="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --target)                    TARGET="${2:?--target needs auto, extras or plugins}"; shift ;;
        --z-probe)                   Z_PROBE="${2:?--z-probe needs tap, shuttle or none}"; shift ;;
        --override-tools-calibrate)  OVERRIDE_TOOLS_CALIBRATE="yes" ;;
        --no-requirements)           DO_REQUIREMENTS="no" ;;
        --no-restart)                DO_RESTART="no" ;;
        --uninstall)                 MODE="uninstall" ;;
        --check)                     MODE="check" ;;
        -h|--help)
            sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: $1 (see --help)"
            exit 1
            ;;
    esac
    shift
done

case "${TARGET}" in
    auto|extras|plugins) ;;
    *) echo "[ERROR] --target must be auto, extras or plugins"; exit 1 ;;
esac
case "${Z_PROBE}" in
    ""|tap|shuttle|none) ;;
    *) echo "[ERROR] --z-probe must be tap, shuttle or none"; exit 1 ;;
esac

EXTRAS="${KLIPPER_PATH}/klippy/extras"
PLUGINS="${KLIPPER_PATH}/klippy/plugins"
MODULES_PATH="${INSTALL_PATH}/klipper/extras"

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

function is_kalico {
    # Kalico loads modules from klippy/plugins; Klipper has no such folder
    [ -f "${PLUGINS}/__init__.py" ]
}

# Kalico can be told to let a module of klippy/plugins replace one of klippy/extras
function has_plugin_override {
    grep -q "allow_plugin_override" "${KLIPPER_PATH}/klippy/printer.py" 2>/dev/null
}

function resolve_target {
    case "${TARGET}" in
        extras|plugins) echo "${TARGET}" ;;
        *) if is_kalico; then echo "plugins"; else echo "extras"; fi ;;
    esac
}

# True if the symlink $1 points into this repository
function links_into_repo {
    local link="$1" dest
    [ -L "${link}" ] || return 1
    dest="$(readlink "${link}")"
    case "${dest}" in
        "${MODULES_PATH}"/*) return 0 ;;
        *klipper-toolchanger-easy*/klipper/extras/*) return 0 ;;
    esac
    return 1
}

function is_git_repo {
    git -C "${KLIPPER_PATH}" rev-parse --git-dir >/dev/null 2>&1
}

function is_tracked {
    git -C "${KLIPPER_PATH}" ls-files --error-unmatch "$1" >/dev/null 2>&1
}

# Moonraker refuses to update a repository with changes to tracked files
function report_git_state {
    if ! is_git_repo; then
        echo "[INFO] ${KLIPPER_PATH} is not a git repository, nothing to check"
        return 0
    fi
    local changes
    changes="$(git -C "${KLIPPER_PATH}" status --porcelain --untracked-files=no)"
    if [ -z "${changes}" ]; then
        echo "[OK] ${KLIPPER_PATH} has no changes to tracked files: Moonraker / Mainsail can update it"
    else
        echo "[WARNING] ${KLIPPER_PATH} has changes to tracked files, Moonraker will refuse to update it:"
        echo "${changes}" | sed 's/^/          /'
    fi
}

# ------------------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------------------

function preflight_checks {
    if [ "$EUID" -eq 0 ]; then
        echo "[PRE-CHECK] This script must not be run as root!"
        exit 1
    fi
    if [ ! -d "${EXTRAS}" ]; then
        echo "[ERROR] Klipper not found at ${KLIPPER_PATH} (set KLIPPER_PATH=...)"
        exit 1
    fi
    if [ "${DO_RESTART}" = "yes" ]; then
        if sudo systemctl list-units --full -all -t service --no-legend | grep -qF 'klipper.service'; then
            printf "[PRE-CHECK] Klipper service found! Continuing...\n\n"
        else
            echo "[ERROR] Klipper service not found, please install Klipper first!"
            exit 1
        fi
    fi
}

function check_download {
    local installdirname installbasename
    installdirname="$(dirname "${INSTALL_PATH}")"
    installbasename="$(basename "${INSTALL_PATH}")"

    if [ ! -d "${INSTALL_PATH}" ]; then
        echo "[DOWNLOAD] Downloading repository..."
        if git -C "${installdirname}" clone "${REPO_URL}" "${installbasename}"; then
            chmod +x "${INSTALL_PATH}/install.sh"
            printf "[DOWNLOAD] Download complete!\n\n"
        else
            echo "[ERROR] Download of git repository failed!"
            exit 1
        fi
    else
        printf "[DOWNLOAD] repository already found locally. Continuing...\n\n"
    fi
}

function install_requirements {
    if [ "${DO_REQUIREMENTS}" != "yes" ]; then
        echo "[REQUIREMENTS] skipped"
        return
    fi
    if [ -f "${INSTALL_PATH}/requirements.txt" ]; then
        echo "[REQUIREMENTS] Installing Python requirements..."

        # Use Klipper's Python environment
        if [ -f "${KLIPPY_ENV_PATH}/bin/pip" ]; then
            "${KLIPPY_ENV_PATH}/bin/pip" install -r "${INSTALL_PATH}/requirements.txt"
            printf "[REQUIREMENTS] Requirements installed successfully!\n\n"
        else
            echo "[ERROR] Klipper Python environment not found at ${KLIPPY_ENV_PATH}"
            exit 1
        fi
    else
        printf "[REQUIREMENTS] No requirements.txt found, skipping...\n\n"
    fi
}

function use_tap_per_tool {
    echo "[INSTALL] Tap Per Tool"

    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/tool_detection.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs/
    cp -n "${INSTALL_PATH}"/examples/easy-additions/user-configs/tools/tap_per_tool/* "${CONFIG_PATH}"/toolchanger/tools
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/user-configs/toolchanger-include.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs/toolchanger-include.cfg
}

function z_probe_on_shuttle {
    echo "[INSTALL] Z Probe on Shuttle"

    cp -n "${INSTALL_PATH}"/examples/easy-additions/user-configs/tools/probe_on_shuttle/* "${CONFIG_PATH}"/toolchanger/tools
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/user-configs/toolchanger-include_scanner.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs/toolchanger-include.cfg
}

function do_shared_config {

    mkdir -p "${CONFIG_PATH}"/toolchanger
    mkdir -p "${CONFIG_PATH}"/toolchanger/tools
    mkdir -p "${CONFIG_PATH}"/toolchanger/readonly-configs

    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/toolchanger.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/homing.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/calibrate-offsets.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/toolchanger-macros.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs
    ln -sfn "${INSTALL_PATH}"/examples/easy-additions/crash-detection.cfg "${CONFIG_PATH}"/toolchanger/readonly-configs

    cp -n "${INSTALL_PATH}"/examples/easy-additions/user-configs/toolchanger-config.cfg "${CONFIG_PATH}"/toolchanger
}

function z_probe_option {
    local choice="${Z_PROBE}"
    if [ -z "${choice}" ]; then
        if [ ! -t 0 ]; then
            echo "[ERROR] Not running in a terminal: give --z-probe tap, shuttle or none"
            exit 1
        fi
        echo -e "\n\n\nHow will you Z probe?"
        echo "1. I will use the TAP sensor as my Z probe on each tool"
        echo "2. I will use a shuttle mounted Beacon/Cartographer/Eddy/etc as my Z probe"
        read -rp "Select an option [1-2]: " z_probe_choice
        case $z_probe_choice in
            1) choice="tap" ;;
            2) choice="shuttle" ;;
            *)
                echo "[ERROR] Invalid option selected!"
                exit 1
                ;;
        esac
    fi

    case "${choice}" in
        tap)     use_tap_per_tool ;;
        shuttle) z_probe_on_shuttle ;;
        none)    echo "[INSTALL] Z probe configuration left alone" ;;
    esac
}

# Links the Python modules into the folder where Klipper / Kalico loads them from.
# $1: extras or plugins
function link_modules {
    local where="$1" dest file name
    if [ "${where}" = "plugins" ]; then
        dest="${PLUGINS}"
        echo "[INSTALL] Linking modules into ${dest} (git ignores this folder, Kalico stays updatable)..."
    else
        dest="${EXTRAS}"
        echo "[INSTALL] Linking modules into ${dest}..."
    fi
    mkdir -p "${dest}"
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if [ "${where}" = "plugins" ] && [ "${name}" = "tools_calibrate.py" ] && [ "${OVERRIDE_TOOLS_CALIBRATE}" != "yes" ]; then
            if links_into_repo "${dest}/${name}"; then
                echo "[INSTALL] ${name} stays linked from an earlier run with --override-tools-calibrate"
            else
                echo "[INSTALL] ${name} skipped: Kalico has its own, see kalico.md (--override-tools-calibrate links ours)"
                continue
            fi
        fi
        if [ "${where}" = "extras" ] && [ -e "${dest}/${name}" ] && [ ! -L "${dest}/${name}" ] && is_git_repo && is_tracked "klippy/extras/${name}"; then
            echo "[WARNING] ${dest}/${name} is part of ${KLIPPER_PATH} and will be replaced by a link: Moonraker will see changes and refuse to update it"
            if is_kalico; then
                echo "[WARNING] Use --target plugins"
            fi
        fi
        ln -sfn "${file}" "${dest}/${name}"
    done
}

# Removes the links of this repository from $1 and puts back the files of
# Klipper / Kalico that an old install replaced (git checkout of a tracked file)
function unlink_modules {
    local where="$1" dest file name rel
    if [ "${where}" = "plugins" ]; then dest="${PLUGINS}"; else dest="${EXTRAS}"; fi
    [ -d "${dest}" ] || return 0
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if links_into_repo "${dest}/${name}"; then
            rm -f "${dest}/${name}"
            echo "[CLEANUP] removed ${dest}/${name}"
            rel="klippy/${where}/${name}"
            if is_git_repo && is_tracked "${rel}"; then
                git -C "${KLIPPER_PATH}" checkout -- "${rel}"
                echo "[CLEANUP] restored ${rel} from git"
            fi
        fi
    done
}

# The old installer linked everything into klippy/extras. On Kalico that replaced
# its tools_calibrate.py (a change to a tracked file: Moonraker calls the
# repository dirty and refuses to update it) and added untracked files.
function migrate_to_plugins {
    echo "[MIGRATE] looking for links of an older install in ${EXTRAS}..."
    unlink_modules extras
}

function restart_klipper {
    if [ "${DO_RESTART}" != "yes" ]; then
        echo "[POST-INSTALL] Restart Klipper when you are ready:  sudo systemctl restart klipper"
        return
    fi
    echo "[POST-INSTALL] Restarting Klipper..."
    sudo systemctl restart klipper
}

function show_kalico_notes {
    echo ""
    echo "[KALICO] Modules are in ${PLUGINS}; Kalico's own tools_calibrate is used."
    echo "[KALICO] The macros work with it; TOOL_CALIBRATE_PROBE_OFFSET exists only in our tools_calibrate,"
    echo "[KALICO] see kalico.md. To use ours add this to printer.cfg and run the install with --override-tools-calibrate:"
    echo "[KALICO]     [danger_options]"
    echo "[KALICO]     allow_plugin_override: True"
    if [ "${OVERRIDE_TOOLS_CALIBRATE}" = "yes" ]; then
        if ! has_plugin_override; then
            echo "[WARNING] --override-tools-calibrate: this Kalico does not know allow_plugin_override, update Kalico first"
        elif ! grep -rqs "allow_plugin_override" "${CONFIG_PATH}" 2>/dev/null; then
            echo "[WARNING] --override-tools-calibrate is set but allow_plugin_override is not in your configuration:"
            echo "[WARNING] Kalico will stop with \"Module 'tools_calibrate' found in both extras and plugins\"."
        fi
    fi
}

function show_status {
    local where
    where="$(resolve_target)"
    echo "[CHECK] Klipper path : ${KLIPPER_PATH}"
    echo "[CHECK] flavour      : $(if is_kalico; then echo Kalico; else echo Klipper; fi)"
    echo "[CHECK] module target: ${where}"
    local dest file name
    if [ "${where}" = "plugins" ]; then dest="${PLUGINS}"; else dest="${EXTRAS}"; fi
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if links_into_repo "${dest}/${name}"; then
            echo "[CHECK]   ${name}: linked in ${where}"
        else
            echo "[CHECK]   ${name}: not linked in ${where}"
        fi
        if [ "${where}" = "plugins" ] && links_into_repo "${EXTRAS}/${name}"; then
            echo "[CHECK]   ${name}: OLD link in extras (run the installer to clean it up)"
        fi
    done
    report_git_state
}

# ------------------------------------------------------------------------------

printf "\n======================================\n"
echo "- Klipper toolchanger install script -"
printf "======================================\n\n"

case "${MODE}" in
    check)
        show_status
        exit 0
        ;;
    uninstall)
        preflight_checks
        unlink_modules extras
        unlink_modules plugins
        report_git_state
        restart_klipper
        exit 0
        ;;
esac

preflight_checks
check_download
install_requirements
do_shared_config

WHERE="$(resolve_target)"
if [ "${WHERE}" = "plugins" ] && ! is_kalico; then
    echo "[ERROR] ${KLIPPER_PATH} does not load modules from klippy/plugins (only Kalico does), use --target extras"
    exit 1
fi
if [ "${WHERE}" = "plugins" ]; then
    migrate_to_plugins
    link_modules plugins
else
    link_modules extras
fi
z_probe_option
if [ "${WHERE}" = "plugins" ]; then
    show_kalico_notes
fi
echo ""
report_git_state
restart_klipper
