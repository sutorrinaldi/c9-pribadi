#!/usr/bin/env bash
set -Eeuo pipefail

ubuntu_version="$(lsb_release -rs)"

C9_REPO_URL="${C9_REPO_URL:-https://github.com/c9/core.git}"
C9_BRANCH="${C9_BRANCH:-master}"
C9_COMMIT="${C9_COMMIT:-7e1ac98f51b85e8bed401c593774ef73ada3cd07}"
C9_INSTALL_DIR="${C9_INSTALL_DIR:-/opt/c9/core}"
C9_NODE_MAJOR="${C9_NODE_MAJOR:-14}"
C9_NODE_VERSION="${C9_NODE_VERSION:-}"
C9_NODE_DIST_MIRROR="${C9_NODE_DIST_MIRROR:-https://nodejs.org/dist}"
C9_PHP_VERSION="${C9_PHP_VERSION:-8.3}"
C9_PHP_PACKAGES="${C9_PHP_PACKAGES:-}"
C9_INSTALL_COMPOSER="${C9_INSTALL_COMPOSER:-1}"
C9_COMPOSER_APT_PACKAGE="${C9_COMPOSER_APT_PACKAGE:-composer}"
C9_INSTALL_PYTHON2_PIP="${C9_INSTALL_PYTHON2_PIP:-1}"
C9_PYTHON2_GET_PIP_URL="${C9_PYTHON2_GET_PIP_URL:-https://bootstrap.pypa.io/pip/2.7/get-pip.py}"
C9_INSTALL_PHP_IMAGICK="${C9_INSTALL_PHP_IMAGICK:-1}"
C9_PHP_IMAGICK_APT_PACKAGE="${C9_PHP_IMAGICK_APT_PACKAGE:-php-imagick}"
C9_INSTALL_PHP_REDIS="${C9_INSTALL_PHP_REDIS:-1}"
C9_PHP_REDIS_APT_PACKAGE="${C9_PHP_REDIS_APT_PACKAGE:-php-redis}"
C9_INSTALL_IMAGEMAGICK="${C9_INSTALL_IMAGEMAGICK:-1}"
C9_IMAGEMAGICK_APT_PACKAGE="${C9_IMAGEMAGICK_APT_PACKAGE:-imagemagick}"
C9_INSTALL_FFMPEG="${C9_INSTALL_FFMPEG:-1}"
C9_FFMPEG_APT_PACKAGE="${C9_FFMPEG_APT_PACKAGE:-ffmpeg}"
C9_INSTALL_REDIS_SERVER="${C9_INSTALL_REDIS_SERVER:-1}"
C9_REDIS_SERVER_APT_PACKAGE="${C9_REDIS_SERVER_APT_PACKAGE:-redis-server}"
C9_SERVICE_NAME="${C9_SERVICE_NAME:-c9-pribadi}"
C9_RUNTIME_USER="${C9_RUNTIME_USER:-c9pribadi}"
C9_RUNTIME_GROUP="${C9_RUNTIME_GROUP:-c9pribadi}"
C9_RUNTIME_HOME="${C9_RUNTIME_HOME:-/var/lib/c9-pribadi}"
C9_RUNTIME_SHELL="${C9_RUNTIME_SHELL:-/bin/bash}"
C9_WORKSPACE_DIR="${C9_WORKSPACE_DIR:-/var/lib/c9-pribadi/workspace}"
C9_LISTEN="${C9_LISTEN:-0.0.0.0}"
C9_PORT="${C9_PORT:-8181}"
C9_LAUNCHER_PATH="${C9_LAUNCHER_PATH:-/usr/local/bin/c9-pribadi-server}"
C9_SETTING_DIR="${C9_SETTING_DIR:-${C9_RUNTIME_HOME}/.c9}"
C9_NODE_LINK_DIR="${C9_NODE_LINK_DIR:-${C9_SETTING_DIR}/node/bin}"
C9_PTY_PACKAGE_NAME="${C9_PTY_PACKAGE_NAME:-node-pty-prebuilt-multiarch}"
C9_PTY_PACKAGE_VERSION="${C9_PTY_PACKAGE_VERSION:-0.10.1-pre.5}"
C9_PYTHON3_APT_PACKAGES="${C9_PYTHON3_APT_PACKAGES:-python3 python3-dev python3-pip python3-venv}"
C9_PYTHON2_BUILD_APT_PACKAGES="${C9_PYTHON2_BUILD_APT_PACKAGES:-libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libffi-dev libncurses-dev libgdbm-dev liblzma-dev uuid-dev}"
C9_PYTHON2_VERSION="${C9_PYTHON2_VERSION:-2.7.18}"
C9_PYTHON2_DIST_MIRROR="${C9_PYTHON2_DIST_MIRROR:-https://www.python.org/ftp/python}"
C9_PYTHON2_PREFIX="${C9_PYTHON2_PREFIX:-/opt/python2.7.18}"
C9_EXTRA_APT_PACKAGES="${C9_EXTRA_APT_PACKAGES:-}"

SUDO=()
if [ "${EUID}" -ne 0 ]; then
    SUDO=(sudo)
fi

AUTH_USER=""
AUTH_PASS=""
TEMP_DIRS=()
TEMP_FILES=()
NPM_CACHE_PATHS=()

log() {
    printf '[c9-personal] %s\n' "$*"
}

die() {
    printf '[c9-personal] ERROR: %s\n' "$*" >&2
    exit 1
}

register_temp_dir() {
    TEMP_DIRS+=("$1")
}

register_temp_file() {
    TEMP_FILES+=("$1")
}

register_npm_cache_path() {
    NPM_CACHE_PATHS+=("$1")
}

cleanup_on_exit() {
    local exit_code=$?
    local path

    trap - EXIT

    if (( exit_code != 0 )); then
        log "Installation failed. Cleaning temporary files and npm caches"

        for path in "${TEMP_FILES[@]}"; do
            [[ -n "${path}" ]] || continue
            "${SUDO[@]}" rm -f "${path}" || true
        done

        for path in "${TEMP_DIRS[@]}"; do
            [[ -n "${path}" ]] || continue
            "${SUDO[@]}" rm -rf "${path}" || true
        done

        for path in "${NPM_CACHE_PATHS[@]}"; do
            [[ -n "${path}" ]] || continue
            "${SUDO[@]}" rm -rf "${path}" || true
        done
    fi

    exit "${exit_code}"
}

trap cleanup_on_exit EXIT

is_enabled() {
    case "$1" in
        1|true|TRUE|yes|YES) return 0 ;;
        0|false|FALSE|no|NO) return 1 ;;
        *) return 2 ;;
    esac
}

require_ubuntu() {
    case "${ubuntu_version}" in
        18.04|20.04|22.04|24.04) ;;
        *) die "Unsupported Ubuntu version: ${ubuntu_version}" ;;
    esac
}

prompt_credentials() {
    local pass_confirm

    printf 'Username login Cloud9: '
    read -r AUTH_USER
    [[ -n "${AUTH_USER}" ]] || die "Username tidak boleh kosong."
    [[ "${AUTH_USER}" != *:* ]] || die "Username tidak boleh mengandung tanda titik dua (:)."

    printf 'Password login Cloud9: '
    read -r -s AUTH_PASS
    printf '\n'
    [[ -n "${AUTH_PASS}" ]] || die "Password tidak boleh kosong."

    printf 'Ulangi password: '
    read -r -s pass_confirm
    printf '\n'

    [[ "${AUTH_PASS}" == "${pass_confirm}" ]] || die "Password tidak cocok."
}

update_packages() {
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -y
}

install_base_packages() {
    local packages=(
        build-essential
        ca-certificates
        curl
        git
        gnupg
        lsb-release
        python3
        software-properties-common
        tar
        tmux
        unzip
        wget
        xz-utils
        zip
    )
    local python3_packages=()
    local python2_build_packages=()
    local extra_packages=()

    if [[ -n "${C9_PYTHON3_APT_PACKAGES}" ]]; then
        read -r -a python3_packages <<< "${C9_PYTHON3_APT_PACKAGES}"
        packages+=("${python3_packages[@]}")
    fi

    if [[ -n "${C9_PYTHON2_BUILD_APT_PACKAGES}" ]]; then
        read -r -a python2_build_packages <<< "${C9_PYTHON2_BUILD_APT_PACKAGES}"
        packages+=("${python2_build_packages[@]}")
    fi

    if [[ -n "${C9_EXTRA_APT_PACKAGES}" ]]; then
        read -r -a extra_packages <<< "${C9_EXTRA_APT_PACKAGES}"
        packages+=("${extra_packages[@]}")
    fi

    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

build_php_package_list() {
    local package_name

    if [[ -n "${C9_PHP_PACKAGES}" ]]; then
        for package_name in ${C9_PHP_PACKAGES}; do
            printf '%s\n' "${package_name}"
        done
        return
    fi

    cat <<EOF
php${C9_PHP_VERSION}
php${C9_PHP_VERSION}-cli
php${C9_PHP_VERSION}-common
php${C9_PHP_VERSION}-curl
php${C9_PHP_VERSION}-mbstring
php${C9_PHP_VERSION}-xml
php${C9_PHP_VERSION}-zip
php${C9_PHP_VERSION}-mysql
php${C9_PHP_VERSION}-sqlite3
php${C9_PHP_VERSION}-gd
php${C9_PHP_VERSION}-bcmath
php${C9_PHP_VERSION}-intl
php${C9_PHP_VERSION}-soap
php${C9_PHP_VERSION}-readline
php${C9_PHP_VERSION}-opcache
EOF
}

prepare_php_repository() {
    local primary_package
    primary_package="php${C9_PHP_VERSION}-cli"

    if "${SUDO[@]}" apt-cache show "${primary_package}" >/dev/null 2>&1; then
        return
    fi

    log "PHP ${C9_PHP_VERSION} not found in current apt sources. Adding Ondrej PHP PPA"
    if ! "${SUDO[@]}" grep -Rqs "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        "${SUDO[@]}" add-apt-repository -y ppa:ondrej/php
    fi

    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update -y
    "${SUDO[@]}" apt-cache show "${primary_package}" >/dev/null 2>&1 \
        || die "Package ${primary_package} still unavailable after adding PHP repository."
}

install_php_runtime() {
    local php_packages=()
    local package_name

    prepare_php_repository
    while IFS= read -r package_name; do
        [[ -n "${package_name}" ]] || continue
        php_packages+=("${package_name}")
    done < <(build_php_package_list)

    [[ "${#php_packages[@]}" -gt 0 ]] || die "PHP package list is empty."

    log "Installing PHP ${C9_PHP_VERSION} runtime"
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${php_packages[@]}"
}

install_composer_runtime() {
    if is_enabled "${C9_INSTALL_COMPOSER}"; then
        :
    elif [[ $? -eq 1 ]]; then
        return
    else
        die "C9_INSTALL_COMPOSER must be 1/0, true/false, or yes/no."
    fi

    [[ -n "${C9_COMPOSER_APT_PACKAGE}" ]] || die "C9_COMPOSER_APT_PACKAGE must not be empty."

    log "Installing Composer runtime"
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${C9_COMPOSER_APT_PACKAGE}"
}

install_optional_runtime_packages() {
    local packages=()

    if is_enabled "${C9_INSTALL_IMAGEMAGICK}"; then
        [[ -n "${C9_IMAGEMAGICK_APT_PACKAGE}" ]] || die "C9_IMAGEMAGICK_APT_PACKAGE must not be empty."
        packages+=("${C9_IMAGEMAGICK_APT_PACKAGE}")
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_IMAGEMAGICK must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_FFMPEG}"; then
        [[ -n "${C9_FFMPEG_APT_PACKAGE}" ]] || die "C9_FFMPEG_APT_PACKAGE must not be empty."
        packages+=("${C9_FFMPEG_APT_PACKAGE}")
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_FFMPEG must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_PHP_IMAGICK}"; then
        [[ -n "${C9_PHP_IMAGICK_APT_PACKAGE}" ]] || die "C9_PHP_IMAGICK_APT_PACKAGE must not be empty."
        packages+=("${C9_PHP_IMAGICK_APT_PACKAGE}")
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_PHP_IMAGICK must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_PHP_REDIS}"; then
        [[ -n "${C9_PHP_REDIS_APT_PACKAGE}" ]] || die "C9_PHP_REDIS_APT_PACKAGE must not be empty."
        packages+=("${C9_PHP_REDIS_APT_PACKAGE}")
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_PHP_REDIS must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_REDIS_SERVER}"; then
        [[ -n "${C9_REDIS_SERVER_APT_PACKAGE}" ]] || die "C9_REDIS_SERVER_APT_PACKAGE must not be empty."
        packages+=("${C9_REDIS_SERVER_APT_PACKAGE}")
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_REDIS_SERVER must be 1/0, true/false, or yes/no."
    fi

    if [[ "${#packages[@]}" -eq 0 ]]; then
        return
    fi

    log "Installing optional runtimes: ${packages[*]}"
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

install_python2_runtime() {
    local python2_version python2_prefix python2_bin python2_tarball python2_url temp_dir build_jobs

    python2_version="${C9_PYTHON2_VERSION}"
    python2_prefix="${C9_PYTHON2_PREFIX}"
    python2_bin="${python2_prefix}/bin/python2.7"

    if [[ -x "${python2_bin}" ]] && "${python2_bin}" - <<'PY' >/dev/null 2>&1
import sys
sys.exit(0 if sys.version_info[:2] == (2, 7) else 1)
PY
    then
        log "Python 2.7 already installed at ${python2_prefix}"
    else
        python2_tarball="Python-${python2_version}.tgz"
        python2_url="${C9_PYTHON2_DIST_MIRROR}/${python2_version}/${python2_tarball}"
        temp_dir="$(mktemp -d)"
        register_temp_dir "${temp_dir}"
        register_temp_file "${temp_dir}/${python2_tarball}"
        build_jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"

        log "Installing Python ${python2_version} runtime"
        wget -q -O "${temp_dir}/${python2_tarball}" "${python2_url}"
        tar -xzf "${temp_dir}/${python2_tarball}" -C "${temp_dir}"

        (
            cd "${temp_dir}/Python-${python2_version}"
            ./configure --prefix="${python2_prefix}"
            make -j"${build_jobs}"
            "${SUDO[@]}" rm -rf "${python2_prefix}"
            "${SUDO[@]}" make altinstall
        )
    fi

    [[ -x "${python2_bin}" ]] || die "Python 2.7 binary missing after install: ${python2_bin}"
    "${SUDO[@]}" ln -sfn "${python2_bin}" /usr/local/bin/python2
    "${SUDO[@]}" ln -sfn "${python2_bin}" /usr/local/bin/python2.7
}

install_python2_pip_runtime() {
    local python2_bin python2_pip_bin temp_dir get_pip_path

    if is_enabled "${C9_INSTALL_PYTHON2_PIP}"; then
        :
    elif [[ $? -eq 1 ]]; then
        return
    else
        die "C9_INSTALL_PYTHON2_PIP must be 1/0, true/false, or yes/no."
    fi

    python2_bin="${C9_PYTHON2_PREFIX}/bin/python2.7"
    [[ -x "${python2_bin}" ]] || die "Python 2.7 binary missing before pip install: ${python2_bin}"

    if ! "${python2_bin}" -m pip --version >/dev/null 2>&1; then
        log "Installing pip for Python 2.7"
        temp_dir="$(mktemp -d)"
        register_temp_dir "${temp_dir}"
        get_pip_path="${temp_dir}/get-pip.py"
        register_temp_file "${get_pip_path}"
        curl -fsSL "${C9_PYTHON2_GET_PIP_URL}" -o "${get_pip_path}"
        "${SUDO[@]}" "${python2_bin}" "${get_pip_path}" "pip<21" "setuptools<45" "wheel<1"
    fi

    python2_pip_bin="${C9_PYTHON2_PREFIX}/bin/pip2.7"
    if [[ ! -x "${python2_pip_bin}" && -x "${C9_PYTHON2_PREFIX}/bin/pip2" ]]; then
        python2_pip_bin="${C9_PYTHON2_PREFIX}/bin/pip2"
    fi

    [[ -x "${python2_pip_bin}" ]] || die "Python 2 pip binary missing after install."
    "${SUDO[@]}" ln -sfn "${python2_pip_bin}" /usr/local/bin/pip2
    "${SUDO[@]}" ln -sfn "${python2_pip_bin}" /usr/local/bin/pip2.7
}

install_python_command_aliases() {
    local python3_bin pip3_bin

    python3_bin="$(command -v python3 || true)"
    [[ -n "${python3_bin}" ]] || die "python3 binary not found after package installation."
    pip3_bin="$(command -v pip3 || true)"
    [[ -n "${pip3_bin}" ]] || die "pip3 binary not found after package installation."

    "${SUDO[@]}" ln -sfn "${python3_bin}" /usr/local/bin/python
    "${SUDO[@]}" ln -sfn "${python3_bin}" /usr/local/bin/python3
    "${SUDO[@]}" ln -sfn "${pip3_bin}" /usr/local/bin/pip
    "${SUDO[@]}" ln -sfn "${pip3_bin}" /usr/local/bin/pip3
}

validate_language_commands() {
    command -v php >/dev/null 2>&1 || die "php binary not found after package installation."
    command -v python >/dev/null 2>&1 || die "python binary not found after alias setup."
    command -v python2 >/dev/null 2>&1 || die "python2 binary not found after Python 2.7 install."
    command -v python3 >/dev/null 2>&1 || die "python3 binary not found after package installation."
    command -v pip >/dev/null 2>&1 || die "pip binary not found after alias setup."
    command -v pip3 >/dev/null 2>&1 || die "pip3 binary not found after package installation."

    php -r 'exit((int)(PHP_MAJOR_VERSION !== 8));' >/dev/null 2>&1 \
        || die "php must point to PHP 8."

    python - <<'PY' >/dev/null 2>&1 || die "python must point to Python 3."
import sys
sys.exit(0 if sys.version_info[0] == 3 else 1)
PY

    python3 - <<'PY' >/dev/null 2>&1 || die "python3 command failed validation."
import sys
sys.exit(0 if sys.version_info[0] == 3 else 1)
PY

    pip --version >/dev/null 2>&1 || die "pip command failed validation."
    pip3 --version >/dev/null 2>&1 || die "pip3 command failed validation."

    python2 - <<'PY' >/dev/null 2>&1 || die "python2 must point to Python 2.7."
import sys
sys.exit(0 if sys.version_info[:2] == (2, 7) else 1)
PY

    if is_enabled "${C9_INSTALL_PYTHON2_PIP}"; then
        command -v pip2 >/dev/null 2>&1 || die "pip2 binary not found after Python 2 pip install."
        pip2 --version >/dev/null 2>&1 || die "pip2 command failed validation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_PYTHON2_PIP must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_COMPOSER}"; then
        command -v composer >/dev/null 2>&1 || die "composer binary not found after package installation."
        composer --version >/dev/null 2>&1 || die "composer command failed after package installation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_COMPOSER must be 1/0, true/false, or yes/no."
    fi
}

validate_optional_runtime_packages() {
    if is_enabled "${C9_INSTALL_IMAGEMAGICK}"; then
        command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 \
            || die "ImageMagick binary not found after package installation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_IMAGEMAGICK must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_FFMPEG}"; then
        command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg binary not found after package installation."
        command -v ffprobe >/dev/null 2>&1 || die "ffprobe binary not found after package installation."
        ffmpeg -version >/dev/null 2>&1 || die "ffmpeg command failed validation."
        ffprobe -version >/dev/null 2>&1 || die "ffprobe command failed validation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_FFMPEG must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_PHP_IMAGICK}"; then
        php -r 'exit((int)!extension_loaded("imagick"));' >/dev/null 2>&1 \
            || die "PHP imagick extension failed validation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_PHP_IMAGICK must be 1/0, true/false, or yes/no."
    fi

    if is_enabled "${C9_INSTALL_PHP_REDIS}"; then
        php -r 'exit((int)!extension_loaded("redis"));' >/dev/null 2>&1 \
            || die "PHP redis extension failed validation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_PHP_REDIS must be 1/0, true/false, or yes/no."
    fi
}

validate_node_commands() {
    command -v node >/dev/null 2>&1 || die "node binary not found after runtime installation."
    command -v npm >/dev/null 2>&1 || die "npm binary not found after runtime installation."
    command -v npx >/dev/null 2>&1 || die "npx binary not found after runtime installation."

    node --version >/dev/null 2>&1 || die "node command failed validation."
    npm --version >/dev/null 2>&1 || die "npm command failed validation."
    npx --version >/dev/null 2>&1 || die "npx command failed validation."
}

enable_optional_runtime_services() {
    if is_enabled "${C9_INSTALL_REDIS_SERVER}"; then
        log "Enabling Redis service"
        "${SUDO[@]}" systemctl enable --now redis-server >/dev/null 2>&1 \
            || die "Failed to enable redis-server service."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_REDIS_SERVER must be 1/0, true/false, or yes/no."
    fi
}

validate_optional_runtime_services() {
    if is_enabled "${C9_INSTALL_REDIS_SERVER}"; then
        command -v redis-server >/dev/null 2>&1 || die "redis-server binary not found after package installation."
        command -v redis-cli >/dev/null 2>&1 || die "redis-cli binary not found after package installation."
        "${SUDO[@]}" systemctl is-active redis-server >/dev/null 2>&1 \
            || die "redis-server service is not active after installation."
        redis-cli ping >/dev/null 2>&1 || die "redis-cli ping failed after installation."
    elif [[ $? -ne 1 ]]; then
        die "C9_INSTALL_REDIS_SERVER must be 1/0, true/false, or yes/no."
    fi
}

normalize_arch() {
    local raw_arch
    raw_arch="$(uname -m)"
    case "${raw_arch}" in
        x86_64|amd64) echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7l" ;;
        *) die "Unsupported architecture for Node.js binary install: ${raw_arch}" ;;
    esac
}

resolve_node_version() {
    if [[ -n "${C9_NODE_VERSION}" ]]; then
        printf '%s\n' "${C9_NODE_VERSION}"
        return
    fi

    case "${C9_NODE_MAJOR}" in
        12|14|16|18) ;;
        *) die "C9_NODE_MAJOR must be one of 12, 14, 16, or 18." ;;
    esac

    curl -fsSL "${C9_NODE_DIST_MIRROR}/index.json" \
        | python3 -c 'import json, sys
major = sys.argv[1]
for item in json.load(sys.stdin):
    version = item["version"].lstrip("v")
    if version.startswith(major + "."):
        print(version)
        break
else:
    raise SystemExit(1)
' "${C9_NODE_MAJOR}"
}

install_node_runtime() {
    local node_version node_arch node_dir node_tarball node_url temp_dir

    node_version="$(resolve_node_version)"
    [[ -n "${node_version}" ]] || die "Unable to resolve a Node.js release."

    node_arch="$(normalize_arch)"
    node_dir="/opt/node-v${node_version}-linux-${node_arch}"
    node_tarball="node-v${node_version}-linux-${node_arch}.tar.xz"
    node_url="${C9_NODE_DIST_MIRROR}/v${node_version}/${node_tarball}"
    temp_dir="$(mktemp -d)"
    register_temp_dir "${temp_dir}"
    register_temp_file "${temp_dir}/${node_tarball}"

    log "Installing Node.js v${node_version}"
    curl -fsSL "${node_url}" -o "${temp_dir}/${node_tarball}"
    "${SUDO[@]}" mkdir -p /opt
    "${SUDO[@]}" rm -rf "${node_dir}"
    "${SUDO[@]}" tar -xJf "${temp_dir}/${node_tarball}" -C /opt
    "${SUDO[@]}" ln -sfn "${node_dir}/bin/node" /usr/local/bin/node
    "${SUDO[@]}" ln -sfn "${node_dir}/bin/npm" /usr/local/bin/npm
    "${SUDO[@]}" ln -sfn "${node_dir}/bin/npx" /usr/local/bin/npx

    rm -rf "${temp_dir}"
}

prepare_c9_checkout() {
    "${SUDO[@]}" mkdir -p "$(dirname "${C9_INSTALL_DIR}")"

    if [[ ! -d "${C9_INSTALL_DIR}/.git" ]]; then
        "${SUDO[@]}" rm -rf "${C9_INSTALL_DIR}"
        "${SUDO[@]}" git clone --branch "${C9_BRANCH}" "${C9_REPO_URL}" "${C9_INSTALL_DIR}"
    fi

    "${SUDO[@]}" git -C "${C9_INSTALL_DIR}" fetch --tags origin "${C9_BRANCH}"
    "${SUDO[@]}" git -C "${C9_INSTALL_DIR}" checkout --force "${C9_COMMIT}"
}

verify_c9_commit() {
    local current
    current="$("${SUDO[@]}" git -C "${C9_INSTALL_DIR}" rev-parse HEAD)"
    [[ "${current}" == "${C9_COMMIT}" ]] || die "Unexpected commit: got ${current}, expected ${C9_COMMIT}"
}

patch_c9_pty_loader() {
    local localfs_path
    localfs_path="${C9_INSTALL_DIR}/plugins/node_modules/vfs-local/localfs.js"
    [[ -f "${localfs_path}" ]] || die "Missing localfs loader: ${localfs_path}"

    if "${SUDO[@]}" grep -q "node-pty-prebuilt-multiarch" "${localfs_path}"; then
        return
    fi

    log "Patching Cloud9 PTY loader for multiarch runtime support"
    "${SUDO[@]}" python3 - "${localfs_path}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = """    if (!fsOptions.nopty) {\n        var modulesPath = fsOptions.nodePath || process.env.HOME + \"/.c9/node_modules\";\n        // on darwin trying to load binary for a wrong version crashes the process\n        [modulesPath + \"/node-pty-prebuilt\",\n         modulesPath + \"/pty.js\",\n         \"node-pty-prebuilt\",\n         \"pty.js\"\n        ].some(function(p) {\n            try {\n                pty = require(p);\n                return true;\n            } catch(e) {}\n        });\n        if (!pty)\n            console.warn(\"unable to initialize pty.js:\");\n    }\n"""
new = """    if (!fsOptions.nopty) {\n        var modulesPath = fsOptions.nodePath || process.env.HOME + \"/.c9/node_modules\";\n        var ptyError;\n        // on darwin trying to load binary for a wrong version crashes the process\n        [modulesPath + \"/node-pty-prebuilt\",\n         modulesPath + \"/node-pty-prebuilt-multiarch\",\n         modulesPath + \"/pty.js\",\n         \"node-pty-prebuilt\",\n         \"node-pty-prebuilt-multiarch\",\n         \"pty.js\"\n        ].some(function(p) {\n            try {\n                pty = require(p);\n                return true;\n            } catch(e) {\n                ptyError = e;\n            }\n        });\n        if (!pty)\n            console.warn(\"unable to initialize pty.js:\", ptyError && (ptyError.stack || ptyError));\n    }\n"""
if old not in text:
    raise SystemExit("Unable to patch localfs.js PTY loader block")
path.write_text(text.replace(old, new, 1))
PY
}

patch_c9_workspace_bootstrap() {
    local tree_path default_config_path standalone_config_path
    tree_path="${C9_INSTALL_DIR}/plugins/c9.ide.tree/tree.js"
    default_config_path="${C9_INSTALL_DIR}/configs/ide/default.js"
    standalone_config_path="${C9_INSTALL_DIR}/configs/standalone.js"

    [[ -f "${tree_path}" ]] || die "Missing tree plugin: ${tree_path}"
    [[ -f "${default_config_path}" ]] || die "Missing IDE default config: ${default_config_path}"
    [[ -f "${standalone_config_path}" ]] || die "Missing standalone config: ${standalone_config_path}"

    log "Patching Cloud9 workspace bootstrap"

    if ! "${SUDO[@]}" python3 - "${tree_path}" "${default_config_path}" "${standalone_config_path}" <<'PY'
import pathlib
import sys

tree_path = pathlib.Path(sys.argv[1])
default_config_path = pathlib.Path(sys.argv[2])
standalone_config_path = pathlib.Path(sys.argv[3])

tree_text = tree_path.read_text()
tree_replacements = [
    (
        """                if (settings.exist("state/projecttree/expanded")) {\n                    var paths = settings.getJson("state/projecttree/expanded") || ["/"];\n                    paths.forEach(function(path) { expandedList[path] = true; });\n""",
        """                if (settings.exist("state/projecttree/expanded")) {\n                    var paths = settings.getJson("state/projecttree/expanded");\n                    if (!Array.isArray(paths) || !paths.length)\n                        paths = ["/"];\n                    paths.forEach(function(path) { expandedList[path] = true; });\n"""
    ),
    (
        """            if (!count) {\n                refreshing = false; // Needed because settings.on("read") sets it\n                return callback && callback("Nothing to do");\n            }\n""",
        """            if (!count) {\n                expandedList["/"] = true;\n                expandedNodes = ["/"];\n                count = 1;\n            }\n"""
    )
]

for old, new in tree_replacements:
    if old not in tree_text and new not in tree_text:
        raise SystemExit("Unable to patch workspace tree bootstrap logic")
    if old in tree_text:
        tree_text = tree_text.replace(old, new, 1)

default_text = default_config_path.read_text()
default_old = """            installSelfCheck: true,\n"""
default_new = """            installSelfCheck: options.installSelfCheck !== false,\n"""
if default_old not in default_text and default_new not in default_text:
    raise SystemExit("Unable to patch IDE installer self-check flag")
if default_old in default_text:
    default_text = default_text.replace(default_old, default_new, 1)

standalone_text = standalone_config_path.read_text()
standalone_old = """    config.settingDir = argv["setting-path"];\n"""
standalone_new = """    config.settingDir = argv["setting-path"];\n    config.installSelfCheck = false;\n"""
if standalone_old not in standalone_text and standalone_new not in standalone_text:
    raise SystemExit("Unable to patch standalone self-check config")
if standalone_old in standalone_text:
    standalone_text = standalone_text.replace(standalone_old, standalone_new, 1)

tree_path.write_text(tree_text)
default_config_path.write_text(default_text)
standalone_config_path.write_text(standalone_text)
PY
    then
        die "Failed to patch Cloud9 workspace bootstrap logic."
    fi
}

patch_c9_vfs_write_stream() {
    local restful_path localfs_path
    restful_path="${C9_INSTALL_DIR}/plugins/node_modules/vfs-http-adapter/restful.js"
    localfs_path="${C9_INSTALL_DIR}/plugins/node_modules/vfs-local/localfs.js"

    [[ -f "${restful_path}" ]] || die "Missing VFS HTTP adapter: ${restful_path}"
    [[ -f "${localfs_path}" ]] || die "Missing local VFS implementation: ${localfs_path}"

    log "Patching Cloud9 VFS write stream compatibility"

    if ! "${SUDO[@]}" python3 - "${restful_path}" "${localfs_path}" <<'PY'
import pathlib
import sys

restful_path = pathlib.Path(sys.argv[1])
localfs_path = pathlib.Path(sys.argv[2])

restful_text = restful_path.read_text()
restful_old = """            else {\n                var opts = { stream: req, parents: true };\n                if (parseInt(req.headers[\"content-length\"], 10) < MAX_BUFFER_FILESIZE)\n                    opts.bufferWrite = true;\n                    \n                vfs.mkfile(path, opts, function (err, meta) {\n                    if (err) return abort(err);\n                    res.statusCode = 201;\n                    res.end();\n                });\n            }\n"""
restful_new = """            else {\n                var input = req;\n                if (input && input.readable === false && input.body != null) {\n                    input = new Stream();\n                    input.readable = true;\n                    process.nextTick(function() {\n                        var body = req.body;\n                        if (typeof body === \"object\" && !Buffer.isBuffer(body))\n                            body = JSON.stringify(body);\n                        if (body)\n                            input.emit(\"data\", body);\n                        input.emit(\"end\");\n                    });\n                }\n                else if (input && input.readable !== true\n                  && (typeof input.on === \"function\" || typeof input.pipe === \"function\")) {\n                    input.readable = true;\n                }\n\n                var opts = { stream: input, parents: true };\n                if (parseInt(req.headers[\"content-length\"], 10) < MAX_BUFFER_FILESIZE)\n                    opts.bufferWrite = true;\n                    \n                vfs.mkfile(path, opts, function (err, meta) {\n                    if (err) return abort(err);\n                    res.statusCode = 201;\n                    res.end();\n                });\n            }\n"""
if restful_old not in restful_text and restful_new not in restful_text:
    raise SystemExit("Unable to patch VFS HTTP PUT stream handling")
if restful_old in restful_text:
    restful_text = restful_text.replace(restful_old, restful_new, 1)

localfs_text = localfs_path.read_text()
localfs_old = """        if (options.stream && !options.stream.readable) {\n            return callback(new TypeError(\"options.stream must be readable.\"));\n        }\n"""
localfs_new = """        if (options.stream\n          && options.stream.readable === false\n          && typeof options.stream.on !== \"function\"\n          && typeof options.stream.pipe !== \"function\") {\n            return callback(new TypeError(\"options.stream must be readable.\"));\n        }\n"""
if localfs_old not in localfs_text and localfs_new not in localfs_text:
    raise SystemExit("Unable to patch local VFS stream validation")
if localfs_old in localfs_text:
    localfs_text = localfs_text.replace(localfs_old, localfs_new, 1)

restful_path.write_text(restful_text)
localfs_path.write_text(localfs_text)
PY
    then
        die "Failed to patch Cloud9 VFS write stream compatibility."
    fi
}

patch_c9_upload_drop_behavior() {
    local upload_path dragdrop_path
    upload_path="${C9_INSTALL_DIR}/plugins/c9.ide.upload/upload.js"
    dragdrop_path="${C9_INSTALL_DIR}/plugins/c9.ide.upload/dragdrop.js"

    [[ -f "${upload_path}" ]] || die "Missing upload plugin: ${upload_path}"
    [[ -f "${dragdrop_path}" ]] || die "Missing dragdrop plugin: ${dragdrop_path}"

    log "Patching Cloud9 drag-and-drop upload behavior"

    if ! "${SUDO[@]}" python3 - "${upload_path}" "${dragdrop_path}" <<'PY'
import pathlib
import sys

upload_path = pathlib.Path(sys.argv[1])
dragdrop_path = pathlib.Path(sys.argv[2])
text = upload_path.read_text()

old_signature = """        function uploadBatch(batch, targetPath) {\n"""
new_signature = """        function uploadBatch(batch, targetPath, sourceType) {\n"""
if old_signature not in text and new_signature not in text:
    raise SystemExit("Unable to patch uploadBatch signature")
if old_signature in text:
    text = text.replace(old_signature, new_signature, 1)

old_call = """                uploadBatch(batch, targetPath.path || targetPath);\n"""
new_call = """                uploadBatch(batch, targetPath.path || targetPath, type);\n"""
if old_call not in text and new_call not in text:
    raise SystemExit("Unable to patch upload drop caller")
if old_call in text:
    text = text.replace(old_call, new_call, 1)

old_block = """            var targetFolder;\n            if (targetPath && typeof targetPath === \"object\") {\n                if (!window.FileReader)\n                    return alert(\n                        \"Unable to open files\",\n                        \"Drop files on the tree to upload\",\n                        \"\"\n                    );\n                if (batch.files.length > MAX_OPEN_COUNT)\n                    return alert(\n                        \"Maximum open count exceeded (\" + batch.files.length + \")\",\n                        \"Drop files on the tree to upload\",\n                        \"\"\n                    );\n                    \n                var hasImage = false;\n                batch.files.forEach(function(file, i) {\n                    if (/image/i.test(file.type))\n                        return hasImage = true;\n                    var reader = new FileReader();\n                    reader.onload = function() {\n                        tabManager.open({\n                            path: \"/\" + file.name, \n                            value: reader.result, \n                            document: { meta: { newfile: true }},\n                            active: i === 0,\n                            pane: targetPath\n                        }, function(err, tab) {});\n                    };\n                    reader.readAsText(file);\n                });\n                \n                if (hasImage)\n                    alert(\n                        \"Can't open an image\",\n                        \"Drop files on the tree to upload\",\n                        \"\"\n                    );\n                    \n                return;\n            }\n"""
new_block = """            var targetFolder;\n            if (targetPath && typeof targetPath === \"object\") {\n                var shouldUploadToTree = !window.FileReader\n                    || sourceType === \"tree\"\n                    || batch.files.length > MAX_OPEN_COUNT;\n\n                if (!shouldUploadToTree) {\n                    var hasImage = false;\n                    batch.files.forEach(function(file, i) {\n                        if (/image/i.test(file.type)) {\n                            hasImage = true;\n                            return;\n                        }\n                        var reader = new FileReader();\n                        reader.onload = function() {\n                            tabManager.open({\n                                path: \"/\" + file.name, \n                                value: reader.result, \n                                document: { meta: { newfile: true }},\n                                active: i === 0,\n                                pane: targetPath\n                            }, function(err, tab) {});\n                        };\n                        reader.readAsText(file);\n                    });\n\n                    if (!hasImage)\n                        return;\n                }\n\n                targetFolder = getTargetFolder();\n                targetPath = targetFolder.path;\n            }\n"""
if old_block not in text and new_block not in text:
    raise SystemExit("Unable to patch upload drag-and-drop behavior")
if old_block in text:
    text = text.replace(old_block, new_block, 1)

dragdrop_text = dragdrop_path.read_text()
dragdrop_old = """        function findHost(el, e) {\n            var ctrlKey = dragContext.ctrlKey = e.ctrlKey;\n            var treeEl = tree.getElement(\"container\");\n            if (treeAsPane && !ctrlKey) {\n                treeEl = treeEl.parentNode;\n            }\n            \n            while (el) {\n                var host = el.host;\n                if (host && (host.cloud9pane))\n                    return host;\n                if (host && (host === treeEl))\n                    return treeAsPane && !ctrlKey ? {\n                        cloud9pane: {\n                            isTree: true,\n                            container: host.$ext,\n                            dropboxTitle: \"Drop a file or folder\"\n                        }\n                    } : host;\n                \n                if (el === dropbox) {\n                    if (treeAsPane && ctrlKey && dragContext.pane.isTree)\n                        return treeEl;\n                    return { cloud9pane: dragContext.pane };\n                }\n                \n                el = el.parentNode;\n            }\n        }\n"""
dragdrop_new = """        function findHost(el, e) {\n            var ctrlKey = dragContext.ctrlKey = e.ctrlKey;\n            var treeNode = tree.getElement(\"container\");\n            var treeEl = treeNode && (treeNode.$ext || treeNode);\n            var treeInt = treeNode && (treeNode.$int || treeNode);\n            if (treeAsPane && !ctrlKey && treeEl && treeEl.parentNode) {\n                treeEl = treeEl.parentNode;\n            }\n            \n            while (el) {\n                if ((treeInt && treeInt.contains && treeInt.contains(el))\n                  || (treeEl && treeEl.contains && treeEl.contains(el))\n                  || el === treeEl || el === treeInt) {\n                    return treeAsPane && !ctrlKey ? {\n                        cloud9pane: {\n                            isTree: true,\n                            container: treeNode.$ext,\n                            dropboxTitle: \"Drop a file or folder\"\n                        }\n                    } : treeNode;\n                }\n\n                var host = el.host;\n                if (host && (host.cloud9pane))\n                    return host;\n                if (host && (host === treeNode))\n                    return treeAsPane && !ctrlKey ? {\n                        cloud9pane: {\n                            isTree: true,\n                            container: host.$ext,\n                            dropboxTitle: \"Drop a file or folder\"\n                        }\n                    } : host;\n                \n                if (el === dropbox) {\n                    if (treeAsPane && ctrlKey && dragContext.pane.isTree)\n                        return treeNode;\n                    return { cloud9pane: dragContext.pane };\n                }\n                \n                el = el.parentNode || el.host;\n            }\n        }\n"""
if dragdrop_old not in dragdrop_text and dragdrop_new not in dragdrop_text:
    raise SystemExit("Unable to patch dragdrop tree target detection")
if dragdrop_old in dragdrop_text:
    dragdrop_text = dragdrop_text.replace(dragdrop_old, dragdrop_new, 1)

upload_path.write_text(text)
dragdrop_path.write_text(dragdrop_text)
PY
    then
        die "Failed to patch Cloud9 drag-and-drop upload behavior."
    fi
}

run_npm_install() {
    local npm_major legacy_flag=()
    local npm_cache_dir
    npm_major="$(npm --version | cut -d. -f1)"
    if [[ "${npm_major}" =~ ^[0-9]+$ ]] && (( npm_major >= 7 )); then
        legacy_flag+=(--legacy-peer-deps)
    fi
    npm_cache_dir="${C9_INSTALL_DIR}/.npm-cache"
    register_npm_cache_path "${npm_cache_dir}"

    log "Installing Cloud9 registry dependencies"
    "${SUDO[@]}" env \
        npm_config_cache="${npm_cache_dir}" \
        npm_config_update_notifier=false \
        npm --prefix "${C9_INSTALL_DIR}" install --production --no-package-lock "${legacy_flag[@]}"
}

restore_vendored_modules() {
    log "Restoring vendored modules"
    "${SUDO[@]}" git -C "${C9_INSTALL_DIR}" checkout HEAD -- node_modules plugins/node_modules
    "${SUDO[@]}" rm -f "${C9_INSTALL_DIR}/package-lock.json"
}

repair_c9_install() {
    local vendored_modules=(
        amd-loader
        architect
        c9
        connect-architect
        frontdoor
        treehugger
    )
    local module_name
    local missing_vendored=0
    local repaired_connect=0

    for module_name in "${vendored_modules[@]}"; do
        if [[ ! -e "${C9_INSTALL_DIR}/node_modules/${module_name}" ]]; then
            missing_vendored=1
            break
        fi
    done

    if (( missing_vendored )); then
        log "Vendored modules missing. Restoring from git."
        restore_vendored_modules
    fi

    if [[ ! -d "${C9_INSTALL_DIR}/node_modules/connect" || ! -f "${C9_INSTALL_DIR}/node_modules/connect/lib/utils.js" ]]; then
        log "connect incomplete. Re-running npm install."
        run_npm_install
        repaired_connect=1
    fi

    if (( repaired_connect )); then
        log "Re-restoring vendored modules after npm repair."
        restore_vendored_modules
    fi
}

validate_c9_patches() {
    local localfs_path restful_path tree_path default_config_path standalone_config_path upload_path dragdrop_path
    localfs_path="${C9_INSTALL_DIR}/plugins/node_modules/vfs-local/localfs.js"
    restful_path="${C9_INSTALL_DIR}/plugins/node_modules/vfs-http-adapter/restful.js"
    tree_path="${C9_INSTALL_DIR}/plugins/c9.ide.tree/tree.js"
    default_config_path="${C9_INSTALL_DIR}/configs/ide/default.js"
    standalone_config_path="${C9_INSTALL_DIR}/configs/standalone.js"
    upload_path="${C9_INSTALL_DIR}/plugins/c9.ide.upload/upload.js"
    dragdrop_path="${C9_INSTALL_DIR}/plugins/c9.ide.upload/dragdrop.js"

    "${SUDO[@]}" grep -q "node-pty-prebuilt-multiarch" "${localfs_path}" \
        || die "Cloud9 PTY loader patch missing after install repair."
    "${SUDO[@]}" grep -q "options.stream.readable === false" "${localfs_path}" \
        || die "Cloud9 local VFS stream patch missing after install repair."
    "${SUDO[@]}" grep -q "input && input.readable === false && input.body != null" "${restful_path}" \
        || die "Cloud9 REST VFS stream patch missing after install repair."
    "${SUDO[@]}" grep -q "Array.isArray(paths) || !paths.length" "${tree_path}" \
        || die "Cloud9 workspace bootstrap patch missing after install repair."
    "${SUDO[@]}" grep -q 'installSelfCheck: options.installSelfCheck !== false' "${default_config_path}" \
        || die "Cloud9 IDE self-check patch missing after install repair."
    "${SUDO[@]}" grep -q 'config.installSelfCheck = false;' "${standalone_config_path}" \
        || die "Cloud9 standalone self-check patch missing after install repair."
    "${SUDO[@]}" grep -q 'var shouldUploadToTree = !window.FileReader' "${upload_path}" \
        || die "Cloud9 drag-and-drop upload patch missing after install repair."
    "${SUDO[@]}" grep -q 'treeInt.contains && treeInt.contains(el)' "${dragdrop_path}" \
        || die "Cloud9 drag-and-drop tree target patch missing after install repair."
}

validate_c9_install() {
    local required_modules=(
        amd-loader
        architect
        connect
        c9
        connect-architect
        frontdoor
        simple-mime
        treehugger
        engine.io
        kaefer
        smith
    )
    local required_plugin_modules=(
        vfs-child
        vfs-http-adapter
        vfs-local
        vfs-nodefs-adapter
        vfs-socket
    )
    local module_name

    for module_name in "${required_modules[@]}"; do
        [[ -e "${C9_INSTALL_DIR}/node_modules/${module_name}" ]] \
            || die "Missing module: ${module_name}"
    done

    for module_name in "${required_plugin_modules[@]}"; do
        [[ -e "${C9_INSTALL_DIR}/plugins/node_modules/${module_name}" ]] \
            || die "Missing plugin module: ${module_name}"
    done

    [[ -f "${C9_INSTALL_DIR}/node_modules/connect/lib/utils.js" ]] \
        || die "connect/lib/utils.js missing"

    (
        cd "${C9_INSTALL_DIR}"
        node -e "require.resolve('amd-loader'); require.resolve('architect'); require.resolve('connect/lib/utils'); require.resolve('simple-mime'); require.resolve('engine.io'); require.resolve('kaefer'); require.resolve('smith'); require.resolve('./plugins/node_modules/vfs-child'); require.resolve('./plugins/node_modules/vfs-local'); require.resolve('./plugins/node_modules/vfs-socket/consumer'); require.resolve('./plugins/node_modules/vfs-http-adapter/restful'); require.resolve('./plugins/node_modules/vfs-nodefs-adapter/nodefs'); require('./server.js');"
    )
}

ensure_runtime_user() {
    if ! "${SUDO[@]}" getent group "${C9_RUNTIME_GROUP}" >/dev/null; then
        "${SUDO[@]}" groupadd --system "${C9_RUNTIME_GROUP}"
    fi

    if ! "${SUDO[@]}" id -u "${C9_RUNTIME_USER}" >/dev/null 2>&1; then
        "${SUDO[@]}" useradd \
            --system \
            --gid "${C9_RUNTIME_GROUP}" \
            --home-dir "${C9_RUNTIME_HOME}" \
            --create-home \
            --shell "${C9_RUNTIME_SHELL}" \
            "${C9_RUNTIME_USER}"
    else
        "${SUDO[@]}" usermod --shell "${C9_RUNTIME_SHELL}" "${C9_RUNTIME_USER}"
    fi

    "${SUDO[@]}" mkdir -p "${C9_RUNTIME_HOME}" "${C9_WORKSPACE_DIR}" "${C9_SETTING_DIR}" "${C9_SETTING_DIR}/bin" "${C9_NODE_LINK_DIR}"
    "${SUDO[@]}" mkdir -p "${C9_INSTALL_DIR}/build"
    "${SUDO[@]}" chown -R "${C9_RUNTIME_USER}:${C9_RUNTIME_GROUP}" "${C9_RUNTIME_HOME}"
    "${SUDO[@]}" chown -R "${C9_RUNTIME_USER}:${C9_RUNTIME_GROUP}" "${C9_INSTALL_DIR}/build"
}

repair_workspace_settings() {
    log "Repairing Cloud9 workspace state"
    "${SUDO[@]}" mkdir -p "${C9_WORKSPACE_DIR}/.c9"
    run_as_runtime_user \
        python3 - "${C9_WORKSPACE_DIR}" <<'PY'
import json
import pathlib
import sys

workspace_dir = pathlib.Path(sys.argv[1])
settings_dir = workspace_dir / ".c9"
state_path = settings_dir / "state.settings"
project_path = settings_dir / "project.settings"

def load_json(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}

state = load_json(state_path)
project = load_json(project_path)

projecttree = state.setdefault("projecttree", {})
projecttree.setdefault("@showfs", True)

expanded = projecttree.get("expanded")
if not isinstance(expanded, dict):
    expanded = {}
projecttree["expanded"] = expanded

expanded_value = expanded.get("json()")
if not isinstance(expanded_value, list) or not expanded_value:
    expanded["json()"] = ["/"]

tree_selection = state.get("tree_selection")
if not isinstance(tree_selection, dict):
    tree_selection = {}
state["tree_selection"] = tree_selection

tree_selection_value = tree_selection.get("json()")
if not isinstance(tree_selection_value, list) or not tree_selection_value:
    tree_selection["json()"] = ["/"]

state_path.write_text(json.dumps(state, indent=2) + "\n")
project_path.write_text(json.dumps(project, indent=2) + "\n")
PY
}

install_terminal_components() {
    local tmux_path node_path
    tmux_path="$(command -v tmux || true)"
    [[ -n "${tmux_path}" ]] || die "tmux binary not found after package installation."
    node_path="$(command -v node || true)"
    [[ -n "${node_path}" ]] || die "node binary not found after runtime installation."

    log "Preparing Cloud9 terminal components"
    "${SUDO[@]}" ln -sfn "${tmux_path}" "${C9_SETTING_DIR}/bin/tmux"
    "${SUDO[@]}" ln -sfn "${node_path}" "${C9_NODE_LINK_DIR}/node"
    "${SUDO[@]}" chown -h "${C9_RUNTIME_USER}:${C9_RUNTIME_GROUP}" "${C9_SETTING_DIR}/bin/tmux"
    "${SUDO[@]}" chown -h "${C9_RUNTIME_USER}:${C9_RUNTIME_GROUP}" "${C9_NODE_LINK_DIR}/node"
}

validate_terminal_components() {
    [[ -x "${C9_SETTING_DIR}/bin/tmux" ]] \
        || die "Missing tmux binary link: ${C9_SETTING_DIR}/bin/tmux"
    [[ -x "${C9_NODE_LINK_DIR}/node" ]] \
        || die "Missing node binary link: ${C9_NODE_LINK_DIR}/node"
}

run_as_runtime_user() {
    if [ "${#SUDO[@]}" -gt 0 ]; then
        "${SUDO[@]}" -u "${C9_RUNTIME_USER}" env \
            HOME="${C9_RUNTIME_HOME}" \
            SHELL="${C9_RUNTIME_SHELL}" \
            PATH="${C9_SETTING_DIR}/bin:${C9_SETTING_DIR}/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
            "$@"
    else
        runuser -u "${C9_RUNTIME_USER}" -- env \
            HOME="${C9_RUNTIME_HOME}" \
            SHELL="${C9_RUNTIME_SHELL}" \
            PATH="${C9_SETTING_DIR}/bin:${C9_SETTING_DIR}/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
            "$@"
    fi
}

validate_workspace_backend() {
    log "Validating Cloud9 workspace backend"
    "${SUDO[@]}" env \
        HOME="${C9_RUNTIME_HOME}" \
        SHELL="${C9_RUNTIME_SHELL}" \
        PATH="${C9_SETTING_DIR}/bin:${C9_SETTING_DIR}/node_modules/.bin:/usr/local/bin:/usr/bin:/bin" \
        node <<EOF
const installDir = ${C9_INSTALL_DIR@Q};
const workspaceDir = ${C9_WORKSPACE_DIR@Q};
const settingDir = ${C9_SETTING_DIR@Q};

process.chdir(installDir);

const path = require("path");
const Parent = require(path.join(installDir, "plugins/node_modules/vfs-child")).Parent;
const parent = new Parent({
    root: "/",
    metapath: "/.c9/metadata",
    wsmetapath: "/.c9/metadata/workspace",
    local: false,
    readOnly: false,
    debug: false,
    homeDir: process.env.HOME,
    projectDir: workspaceDir,
    nakBin: settingDir + "/node_modules/.bin/nak",
    nodeBin: [process.execPath],
    tmuxBin: settingDir + "/bin/tmux",
    bashBin: process.env.SHELL || "bash",
    defaultEnv: Object.assign({}, process.env)
});

const timeout = setTimeout(() => {
    console.error("Workspace backend smoke test timed out");
    process.exit(1);
}, 10000);

function fail(err) {
    clearTimeout(timeout);
    console.error(err && err.stack ? err.stack : err);
    process.exit(1);
}

parent.connect((err, vfs) => {
    if (err)
        return fail(err);

    vfs.readdir("/", { encoding: null }, (err, meta) => {
        if (err)
            return fail(err);

        const stream = meta && meta.stream;
        if (!stream)
            return fail(new Error("Workspace backend returned no directory stream"));

        stream.on("data", function() {});
        stream.on("error", fail);
        stream.on("end", () => {
            clearTimeout(timeout);
            parent.disconnect();
            process.exit(0);
        });
    });
});
EOF
}

install_user_components() {
    local npm_cache_dir
    npm_cache_dir="${C9_SETTING_DIR}/.npm-cache"
    register_npm_cache_path "${npm_cache_dir}"

    log "Installing Cloud9 user components"
    "${SUDO[@]}" env \
        HOME="${C9_RUNTIME_HOME}" \
        npm_config_cache="${npm_cache_dir}" \
        npm_config_update_notifier=false \
        npm --prefix "${C9_SETTING_DIR}" install --no-package-lock \
        "https://github.com/c9/nak/tarball/c9" \
        "${C9_PTY_PACKAGE_NAME}@${C9_PTY_PACKAGE_VERSION}"

    "${SUDO[@]}" mkdir -p "${C9_SETTING_DIR}/node_modules/node-pty-prebuilt"
    "${SUDO[@]}" tee "${C9_SETTING_DIR}/node_modules/node-pty-prebuilt/package.json" >/dev/null <<EOF
{
  "name": "node-pty-prebuilt",
  "private": true,
  "main": "index.js"
}
EOF
    "${SUDO[@]}" tee "${C9_SETTING_DIR}/node_modules/node-pty-prebuilt/index.js" >/dev/null <<EOF
module.exports = require("../${C9_PTY_PACKAGE_NAME}");
EOF

    "${SUDO[@]}" tee "${C9_SETTING_DIR}/installed" >/dev/null <<'EOF'
Cloud9 IDE@1
c9.ide.collab@1
c9.ide.find@1
Cloud9 CLI@1
EOF

    "${SUDO[@]}" chown -R "${C9_RUNTIME_USER}:${C9_RUNTIME_GROUP}" "${C9_SETTING_DIR}"
}

validate_user_components() {
    [[ -f "${C9_SETTING_DIR}/installed" ]] \
        || die "Missing Cloud9 installed manifest: ${C9_SETTING_DIR}/installed"
    [[ -f "${C9_SETTING_DIR}/node_modules/nak/bin/nak" ]] \
        || die "Missing nak binary: ${C9_SETTING_DIR}/node_modules/nak/bin/nak"
    if [[ ! -d "${C9_SETTING_DIR}/node_modules/node-pty-prebuilt" ]]; then
        die "Missing PTY compatibility module: ${C9_SETTING_DIR}/node_modules/node-pty-prebuilt"
    fi
    if [[ ! -d "${C9_SETTING_DIR}/node_modules/${C9_PTY_PACKAGE_NAME}" ]]; then
        die "Missing PTY runtime module: ${C9_SETTING_DIR}/node_modules/${C9_PTY_PACKAGE_NAME}"
    fi
    run_as_runtime_user \
        node <<EOF
const path = require("path");
const root = ${C9_SETTING_DIR@Q};
const candidates = [
  path.join(root, "node_modules/node-pty-prebuilt"),
  path.join(root, "node_modules/${C9_PTY_PACKAGE_NAME}")
];

let loaded = false;
let lastError = null;
for (const candidate of candidates) {
  try {
    const mod = require(candidate);
    if (mod) {
      loaded = true;
      break;
    }
  } catch (err) {
    lastError = err;
  }
}

if (!loaded) {
  console.error("Unable to load PTY module from " + candidates.join(", "));
  if (lastError)
    console.error(lastError && (lastError.stack || lastError));
  process.exit(1);
}
EOF
}

validate_pty_runtime() {
    log "Validating PTY runtime"
    run_as_runtime_user \
        node <<EOF
const path = require("path");
const root = ${C9_SETTING_DIR@Q};
const shell = process.env.SHELL || "/bin/bash";
const pty = require(path.join(root, "node_modules/node-pty-prebuilt"));
const marker = "__C9_PTY_OK__";
const term = pty.spawn(shell, ["-lc", "printf " + marker], {
  name: "xterm-color",
  cols: 80,
  rows: 24,
  cwd: process.env.HOME,
  env: Object.assign({}, process.env)
});

let seen = "";
let finished = false;
const timeout = setTimeout(() => fail(new Error("PTY smoke test timed out")), 5000);

function cleanup(code) {
  if (finished)
    return;
  finished = true;
  clearTimeout(timeout);
  try { term.kill(); } catch (err) {}
  process.exit(code);
}

function fail(err) {
  console.error(err && (err.stack || err));
  cleanup(1);
}

term.on("data", (data) => {
  seen += data;
  if (seen.indexOf(marker) !== -1)
    cleanup(0);
});

term.on("error", fail);
term.on("exit", (code, signal) => {
  if (seen.indexOf(marker) === -1) {
    fail(new Error("PTY exited before producing expected output. code=" + code + " signal=" + signal + " output=" + JSON.stringify(seen)));
  }
});
EOF
}

escape_single_quotes() {
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

create_launcher() {
    local esc_user esc_pass esc_listen esc_port esc_home esc_work esc_install esc_setting esc_shell
    esc_user="$(escape_single_quotes "${AUTH_USER}")"
    esc_pass="$(escape_single_quotes "${AUTH_PASS}")"
    esc_listen="$(escape_single_quotes "${C9_LISTEN}")"
    esc_port="$(escape_single_quotes "${C9_PORT}")"
    esc_home="$(escape_single_quotes "${C9_RUNTIME_HOME}")"
    esc_work="$(escape_single_quotes "${C9_WORKSPACE_DIR}")"
    esc_install="$(escape_single_quotes "${C9_INSTALL_DIR}")"
    esc_setting="$(escape_single_quotes "${C9_SETTING_DIR}")"
    esc_shell="$(escape_single_quotes "${C9_RUNTIME_SHELL}")"

    "${SUDO[@]}" tee "${C9_LAUNCHER_PATH}" >/dev/null <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME='${esc_home}'
export SHELL='${esc_shell}'
export PATH='${esc_setting}/bin:${esc_setting}/node_modules/.bin:/usr/local/bin:/usr/bin:/bin'
cd '${esc_install}'
exec /usr/local/bin/node '${esc_install}/server.js' \\
    --listen '${esc_listen}' \\
    --port '${esc_port}' \\
    --auth '${esc_user}:${esc_pass}' \\
    --setting-path '${esc_setting}' \\
    -w '${esc_work}'
EOF
    "${SUDO[@]}" chmod 0755 "${C9_LAUNCHER_PATH}"
}

create_systemd_service() {
    "${SUDO[@]}" tee "/etc/systemd/system/${C9_SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=Cloud9 Pribadi Server
After=network.target

[Service]
Type=simple
User=${C9_RUNTIME_USER}
Group=${C9_RUNTIME_GROUP}
WorkingDirectory=${C9_INSTALL_DIR}
ExecStart=${C9_LAUNCHER_PATH}
Restart=always
RestartSec=3
Environment=HOME=${C9_RUNTIME_HOME}
Environment=SHELL=${C9_RUNTIME_SHELL}

[Install]
WantedBy=multi-user.target
EOF

    "${SUDO[@]}" systemctl daemon-reload
    if ! "${SUDO[@]}" systemctl enable --now "${C9_SERVICE_NAME}.service"; then
        "${SUDO[@]}" journalctl -u "${C9_SERVICE_NAME}.service" -n 50 -l --no-pager || true
        die "Failed to enable and start ${C9_SERVICE_NAME}.service"
    fi
}

validate_systemd_service() {
    local service_status
    service_status="$("${SUDO[@]}" systemctl is-active "${C9_SERVICE_NAME}.service" 2>/dev/null || true)"
    if [[ "${service_status}" != "active" ]]; then
        "${SUDO[@]}" journalctl -u "${C9_SERVICE_NAME}.service" -n 50 -l --no-pager || true
        die "Service ${C9_SERVICE_NAME}.service is not active after install (status: ${service_status:-unknown})"
    fi
}

print_summary() {
    local host_ip
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    if [[ -z "${host_ip}" ]]; then
        host_ip="<IP-SERVER-ANDA>"
    fi

    log "Install selesai."
    log "URL      : http://${host_ip}:${C9_PORT}/"
    log "Username : ${AUTH_USER}"
    log "Password : sesuai yang tadi Anda masukkan"
    log "Service  : ${C9_SERVICE_NAME}"
    log "Status   : systemctl status ${C9_SERVICE_NAME}"
}

main() {
    require_ubuntu
    prompt_credentials
    update_packages
    install_base_packages
    install_php_runtime
    install_optional_runtime_packages
    install_composer_runtime
    install_python2_runtime
    install_python2_pip_runtime
    install_python_command_aliases
    validate_language_commands
    validate_optional_runtime_packages
    install_node_runtime
    validate_node_commands
    prepare_c9_checkout
    verify_c9_commit
    run_npm_install
    restore_vendored_modules
    repair_c9_install
    patch_c9_pty_loader
    patch_c9_workspace_bootstrap
    patch_c9_vfs_write_stream
    patch_c9_upload_drop_behavior
    validate_c9_patches
    validate_c9_install
    ensure_runtime_user
    repair_workspace_settings
    install_terminal_components
    validate_terminal_components
    install_user_components
    validate_user_components
    validate_pty_runtime
    validate_workspace_backend
    create_launcher
    create_systemd_service
    enable_optional_runtime_services
    validate_optional_runtime_services
    validate_systemd_service
    print_summary
}

main "$@"
