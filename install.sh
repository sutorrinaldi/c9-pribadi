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

SUDO=()
if [ "${EUID}" -ne 0 ]; then
    SUDO=(sudo)
fi

AUTH_USER=""
AUTH_PASS=""

log() {
    printf '[c9-personal] %s\n' "$*"
}

die() {
    printf '[c9-personal] ERROR: %s\n' "$*" >&2
    exit 1
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
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

install_base_packages() {
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        ca-certificates \
        curl \
        git \
        lsb-release \
        python3 \
        tar \
        tmux \
        xz-utils
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

run_npm_install() {
    local npm_major legacy_flag=()
    npm_major="$(npm --version | cut -d. -f1)"
    if [[ "${npm_major}" =~ ^[0-9]+$ ]] && (( npm_major >= 7 )); then
        legacy_flag+=(--legacy-peer-deps)
    fi

    log "Installing Cloud9 registry dependencies"
    "${SUDO[@]}" env \
        npm_config_cache="${C9_INSTALL_DIR}/.npm-cache" \
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
    log "Installing Cloud9 user components"
    "${SUDO[@]}" env \
        HOME="${C9_RUNTIME_HOME}" \
        npm_config_cache="${C9_SETTING_DIR}/.npm-cache" \
        npm_config_update_notifier=false \
        npm --prefix "${C9_SETTING_DIR}" install --no-package-lock \
        "https://github.com/c9/nak/tarball/c9" \
        "node-pty-prebuilt@0.7.6"

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
    if [[ ! -d "${C9_SETTING_DIR}/node_modules/node-pty-prebuilt" && ! -d "${C9_SETTING_DIR}/node_modules/pty.js" ]]; then
        die "Missing PTY module: expected node-pty-prebuilt or pty.js under ${C9_SETTING_DIR}/node_modules"
    fi
    "${SUDO[@]}" env \
        HOME="${C9_RUNTIME_HOME}" \
        node <<EOF
const path = require("path");
const root = ${C9_SETTING_DIR@Q};
const candidates = [
  path.join(root, "node_modules/node-pty-prebuilt"),
  path.join(root, "node_modules/pty.js")
];

let loaded = false;
for (const candidate of candidates) {
  try {
    const mod = require(candidate);
    if (mod) {
      loaded = true;
      break;
    }
  } catch (err) {}
}

if (!loaded) {
  console.error("Unable to load PTY module from " + candidates.join(", "));
  process.exit(1);
}
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
    "${SUDO[@]}" systemctl enable --now "${C9_SERVICE_NAME}.service"
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
    install_node_runtime
    prepare_c9_checkout
    verify_c9_commit
    run_npm_install
    restore_vendored_modules
    repair_c9_install
    validate_c9_install
    ensure_runtime_user
    install_terminal_components
    validate_terminal_components
    install_user_components
    validate_user_components
    validate_workspace_backend
    create_launcher
    create_systemd_service
    print_summary
}

main "$@"
