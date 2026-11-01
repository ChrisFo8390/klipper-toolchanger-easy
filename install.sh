#!/bin/bash
#
# klipper-toolchanger-easy installer
#
# Links the Python modules into Klipper, the macros into the configuration and
# copies the files that you edit. Safe to run again.
#
# The modules are linked into klippy/extras, where add-ons expect them (AFC
# imports extras.toolchanger). A module that Klipper or Kalico has of its own,
# a file that git tracks, is never replaced: Moonraker would see a changed
# repository and refuse to update it. Kalico has a tools_calibrate.py, so that
# one is not linked and Kalico's is used (see kalico.md for the exception).
#
# Options:
#   --target extras|plugins        where to link the modules (default extras).
#                                  plugins is Kalico only: klippy/plugins is ignored by git, but
#                                  add-ons that import extras.<module> do not find the modules there
#   --z-probe tap|shuttle|none     how you probe Z, asked if you do not give it
#   --override-tools-calibrate     Kalico only: use our tools_calibrate.py instead of Kalico's, linked
#                                  into plugins (needs [danger_options] allow_plugin_override: True)
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
        --target)                    TARGET="${2:?--target needs extras or plugins}"; shift ;;
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
    *) echo "[ERROR] --target must be extras or plugins"; exit 1 ;;
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
        plugins) echo "plugins" ;;
        *) echo "extras" ;;
    esac
}

# A module of Klipper / Kalico itself: git tracks it
function is_part_of_host {
    is_git_repo && is_tracked "klippy/extras/$1"
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

# Links the Python modules into klippy/extras. A module that Klipper / Kalico has
# of its own is not replaced, a link of an older install in its place is removed
# and the file is restored from git.
function link_modules_extras {
    local file name
    echo "[INSTALL] Linking modules into ${EXTRAS}..."
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if is_part_of_host "${name}"; then
            if links_into_repo "${EXTRAS}/${name}"; then
                rm -f "${EXTRAS}/${name}"
                git -C "${KLIPPER_PATH}" checkout -- "klippy/extras/${name}"
                echo "[CLEANUP] restored klippy/extras/${name} from git"
            fi
            if [ "${name}" = "tools_calibrate.py" ] && [ "${OVERRIDE_TOOLS_CALIBRATE}" = "yes" ]; then
                continue
            fi
            echo "[INSTALL] ${name} skipped: ${KLIPPER_PATH} has its own (--override-tools-calibrate links ours on Kalico, see kalico.md)"
            continue
        fi
        ln -sfn "${file}" "${EXTRAS}/${name}"
    done
}

# Kalico only: modules in klippy/plugins. Git ignores that folder.
function link_modules_plugins {
    local file name
    echo "[INSTALL] Linking modules into ${PLUGINS} (git ignores this folder)..."
    mkdir -p "${PLUGINS}"
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if [ "${name}" = "tools_calibrate.py" ] && [ "${OVERRIDE_TOOLS_CALIBRATE}" != "yes" ]; then
            if links_into_repo "${PLUGINS}/${name}"; then
                echo "[INSTALL] ${name} stays linked from an earlier run with --override-tools-calibrate"
            else
                echo "[INSTALL] ${name} skipped: Kalico has its own, see kalico.md (--override-tools-calibrate links ours)"
                continue
            fi
        fi
        ln -sfn "${file}" "${PLUGINS}/${name}"
    done
}

# Our tools_calibrate instead of the one of Kalico. Kalico loads it from
# klippy/plugins and needs allow_plugin_override for a module of that name. It
# stays when the installer runs again without the option.
function link_override {
    local name="tools_calibrate.py"
    if [ "${OVERRIDE_TOOLS_CALIBRATE}" != "yes" ] && ! links_into_repo "${PLUGINS}/${name}"; then
        return 0
    fi
    if ! is_kalico; then
        echo "[ERROR] --override-tools-calibrate is for Kalico (klippy/plugins), ${KLIPPER_PATH} has none"
        exit 1
    fi
    ln -sfn "${MODULES_PATH}/${name}" "${PLUGINS}/${name}"
    echo "[INSTALL] ${name} of this repository linked into ${PLUGINS}, it replaces the one of Kalico"
}

# An earlier run linked the modules into klippy/plugins: they belong in klippy/extras
function leave_plugins {
    local file name
    [ -d "${PLUGINS}" ] || return 0
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if [ "${name}" = "tools_calibrate.py" ]; then
            continue
        fi
        if links_into_repo "${PLUGINS}/${name}"; then
            rm -f "${PLUGINS}/${name}"
            echo "[MIGRATE] ${name} moved from klippy/plugins to klippy/extras"
        fi
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

# For --target plugins. The old installer linked everything into klippy/extras.
# On Kalico that replaced its tools_calibrate.py (a change to a tracked file:
# Moonraker calls the repository dirty and refuses to update it).
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
    if [ "${WHERE}" = "plugins" ]; then
        echo "[KALICO] Modules are in ${PLUGINS}; add-ons that import extras.<module> (AFC: extras.toolchanger) do not find them there."
    else
        echo "[KALICO] Modules are in ${EXTRAS}; Kalico's own files are not touched."
    fi
    if links_into_repo "${PLUGINS}/tools_calibrate.py"; then
        echo "[KALICO] tools_calibrate of this repository replaces the one of Kalico, which needs allow_plugin_override in [danger_options]."
        if ! has_plugin_override; then
            echo "[WARNING] this Kalico does not know allow_plugin_override, update Kalico first"
        elif ! grep -rqs "allow_plugin_override" "${CONFIG_PATH}" 2>/dev/null; then
            echo "[WARNING] allow_plugin_override is not in your configuration:"
            echo "[WARNING] Kalico will stop with \"Module 'tools_calibrate' found in both extras and plugins\"."
        fi
    else
        echo "[KALICO] Kalico's own tools_calibrate is used. TOOL_CALIBRATE_PROBE_OFFSET exists only in ours, see kalico.md."
    fi
}

function show_status {
    local where
    where="$(resolve_target)"
    echo "[CHECK] Klipper path : ${KLIPPER_PATH}"
    echo "[CHECK] flavour      : $(if is_kalico; then echo Kalico; else echo Klipper; fi)"
    echo "[CHECK] module target: ${where}"
    local file name
    for file in "${MODULES_PATH}"/*.py; do
        name="$(basename "${file}")"
        if links_into_repo "${EXTRAS}/${name}" && links_into_repo "${PLUGINS}/${name}"; then
            echo "[CHECK]   ${name}: linked in extras AND plugins (Kalico refuses that, run the installer)"
        elif links_into_repo "${EXTRAS}/${name}"; then
            echo "[CHECK]   ${name}: linked in extras"
        elif links_into_repo "${PLUGINS}/${name}"; then
            echo "[CHECK]   ${name}: linked in plugins"
        elif is_part_of_host "${name}"; then
            echo "[CHECK]   ${name}: not linked, ${KLIPPER_PATH} has its own"
        else
            echo "[CHECK]   ${name}: not linked"
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
    link_modules_plugins
else
    leave_plugins
    link_modules_extras
    link_override
fi
z_probe_option
if is_kalico; then
    show_kalico_notes
fi
echo ""
report_git_state
restart_klipper
