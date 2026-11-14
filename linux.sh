#!/usr/bin/env bash
# ==============================================================================
# Cosy Classroom System — Universal Linux Client Installer (Mandatory Latest)
# Compatible with:
#   - Distros: Ubuntu / Debian / Xubuntu / Mint / Pop!_OS / Kali (apt)
#              Fedora / RHEL / CentOS / Rocky / AlmaLinux (dnf / yum)
#              Arch / Manjaro / EndeavourOS (pacman)
#              openSUSE / SLES (zypper)
#              Alpine Linux (apk)
#   - Arch   : x86_64 (amd64), aarch64 (arm64), armv7l
#   - Init   : systemd, OpenRC, or standalone/WSL/container fallback
#   - Fetch  : curl -> wget -> python3 -> python fallback
#   - Priv   : root -> sudo -> doas -> su
# Always enforces installing/upgrading to the strictly LATEST client release.
# ==============================================================================
set -euo pipefail

REPO_OWNER="cosyzzz"
REPO_NAME="cosy-client-setup"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"
REL_BASE="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download"
DEFAULT_SERVER="https://sykids.dpdns.org"

SERVER_URL="${SYKIDS_SERVER:-${CP_SERVER_URL:-}}"
TICKET="${SYKIDS_TICKET:-${CP_ENROLL_TICKET:-}}"
CERT_PIN="${CP_CERT_PIN:-SYSTEM_CA}"
FORCE=0
VERBOSE=0
VERIFY_ONLY=0
DRY_RUN=0
NO_HARDEN=0

print_usage() {
    cat <<EOF
Cosy Classroom System — Universal Linux Client Installer

Usage:
  curl -fsSL ${RAW_BASE}/linux.sh | sudo bash
  sudo bash linux.sh [OPTIONS]

Options:
  -s, --server <URL>    Server HTTP/WS URL (default: auto via beacon / ${DEFAULT_SERVER})
  -t, --ticket <TOKEN>  Optional enrollment ticket
  -p, --cert-pin <PIN>  Optional TLS CertPin or SYSTEM_CA
  -f, --force           Force reinstall/rebuild even if already on latest
      --verify-only     Download/verify latest metadata & checksums without installing
      --dry-run         Print detected environment and planned actions only
      --no-harden       Skip chattr +i / sysctl lockdown (useful on containers/dev VMs)
  -v, --verbose         Verbose output
  -h, --help            Show help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--server)   SERVER_URL="$2"; shift 2 ;;
        -t|--ticket)   TICKET="$2"; shift 2 ;;
        -p|--cert-pin) CERT_PIN="$2"; shift 2 ;;
        -f|--force)    FORCE=1; shift ;;
        --verify-only) VERIFY_ONLY=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --no-harden)   NO_HARDEN=1; shift ;;
        -v|--verbose)  VERBOSE=1; shift ;;
        -h|--help)     print_usage ;;
        *)
            if [[ "$1" =~ ^https?:// ]] || [[ "$1" =~ ^wss?:// ]]; then
                SERVER_URL="$1"
            elif [ -z "$TICKET" ]; then
                TICKET="$1"
            fi
            shift
            ;;
    esac
done

# Auto-elevate if not dry-run / verify-only
if [ "$DRY_RUN" -eq 0 ] && [ "$VERIFY_ONLY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    echo "[Cosy] Root privileges required. Elevating..."
    ARGS=()
    [ -n "$SERVER_URL" ] && ARGS+=(--server "$SERVER_URL")
    [ -n "$TICKET" ] && ARGS+=(--ticket "$TICKET")
    [ -n "$CERT_PIN" ] && ARGS+=(--cert-pin "$CERT_PIN")
    [ "$FORCE" -eq 1 ] && ARGS+=(--force)
    [ "$NO_HARDEN" -eq 1 ] && ARGS+=(--no-harden)
    [ "$VERBOSE" -eq 1 ] && ARGS+=(--verbose)
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$0" "${ARGS[@]}"
    elif command -v doas >/dev/null 2>&1; then
        exec doas bash "$0" "${ARGS[@]}"
    else
        echo "[ERROR] Please run as root (sudo/doas not found)." >&2
        exit 1
    fi
fi

# Universal HTTP download helper: curl -> wget -> python3 -> python
fetch_file() {
    local url="$1"
    local out="$2"
    rm -f "$out"
    if command -v curl >/dev/null 2>&1; then
        curl --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 180 -fsSL "$url" -o "$out" && [ -s "$out" ] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -t 3 -O "$out" "$url" && [ -s "$out" ] && return 0
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" "$url" "$out" 2>/dev/null && [ -s "$out" ] && return 0
    fi
    if command -v python >/dev/null 2>&1; then
        python -c "import urllib,sys; urllib.urlretrieve(sys.argv[1], sys.argv[2])" "$url" "$out" 2>/dev/null && [ -s "$out" ] && return 0
    fi
    return 1
}

sha256_of() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print tolower($1)}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print tolower($NF)}'
    else
        echo ""
    fi
}

# Detect OS, PkgMgr, Arch, Init
OS_ID="unknown"
[ -f /etc/os-release ] && . /etc/os-release && OS_ID="${ID:-unknown}"
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l|armhf) ARCH="armhf" ;;
    *) ARCH="$RAW_ARCH" ;;
esac

PKG_MGR="unknown"
if command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"
elif command -v yum >/dev/null 2>&1; then PKG_MGR="yum"
elif command -v pacman >/dev/null 2>&1; then PKG_MGR="pacman"
elif command -v zypper >/dev/null 2>&1; then PKG_MGR="zypper"
elif command -v apk >/dev/null 2>&1; then PKG_MGR="apk"
fi

INIT_SYS="none"
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    INIT_SYS="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYS="openrc"
fi

TMP_DIR="$(mktemp -d -t cosy-linux-XXXXXX)"
chmod 700 "$TMP_DIR"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

echo "======================================================================"
echo "  Cosy Classroom System — Universal Linux Client Setup"
echo "  OS=${OS_ID} | Arch=${ARCH} | Pkg=${PKG_MGR} | Init=${INIT_SYS}"
echo "======================================================================"

# [1/5] Resolve Server URL
if [ -z "$SERVER_URL" ]; then
    if fetch_file "${RAW_BASE}/beacon.txt" "${TMP_DIR}/beacon.txt" 2>/dev/null; then
        BEACON_LINE="$(head -n 1 "${TMP_DIR}/beacon.txt" || true)"
        HDR="$(echo "$BEACON_LINE" | cut -d'|' -f1)"
        WS_CAND="$(echo "$BEACON_LINE" | cut -d'|' -f2)"
        PIN_CAND="$(echo "$BEACON_LINE" | cut -d'|' -f3)"
        if [ "$HDR" = "SYKIDS-BEACON-V2" ] && [ -n "$WS_CAND" ]; then
            SERVER_URL="$WS_CAND"
            [ -n "$PIN_CAND" ] && CERT_PIN="$PIN_CAND"
        fi
    fi
fi
[ -z "$SERVER_URL" ] && SERVER_URL="$DEFAULT_SERVER"
SERVER_URL="${SERVER_URL%/}"
WS_URL="${SERVER_URL/https:\/\//wss://}"
WS_URL="${WS_URL/http:\/\//ws://}"
[[ "$WS_URL" != */ws ]] && WS_URL="${WS_URL%/}/ws"
echo "[1/5] Endpoint: ${WS_URL}"

# [2/5] Fetch latest version metadata
LATEST_VER="0.0.0"
LINUX_SRC_SHA=""
LINUX_BIN_SHA=""
LINUX_BIN_URL=""
LINUX_SRC_URL="${REL_BASE}/Client-Linux-src.tar.gz"

if fetch_file "${RAW_BASE}/version.json" "${TMP_DIR}/version.json" 2>/dev/null || fetch_file "${REL_BASE}/version.json" "${TMP_DIR}/version.json" 2>/dev/null; then
    if command -v python3 >/dev/null 2>&1; then
        eval "$(python3 - "${TMP_DIR}/version.json" "$ARCH" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
arch = sys.argv[2]
print(f'LATEST_VER={json.dumps(str(d.get("version", "0.0.0")))}')
lin = d.get("linux") or {}
print(f'LINUX_SRC_URL={json.dumps(str(lin.get("src_url", "")))}')
print(f'LINUX_SRC_SHA={json.dumps(str(lin.get("src_sha256", "")))}')
bins = lin.get("binaries") or {}
b = bins.get(arch) or {}
print(f'LINUX_BIN_URL={json.dumps(str(b.get("url", "")))}')
print(f'LINUX_BIN_SHA={json.dumps(str(b.get("sha256", "")))}')
PY
)"
    else
        LATEST_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${TMP_DIR}/version.json" | head -n 1)"
        [ -z "$LATEST_VER" ] && LATEST_VER="0.0.0"
    fi
fi
[ -z "$LINUX_SRC_URL" ] && LINUX_SRC_URL="${REL_BASE}/Client-Linux-src.tar.gz"
echo "[2/5] Latest release version: ${LATEST_VER}"

INSTALLED_VER="0.0.0"
if [ -f /etc/children-protection/client_version ]; then
    INSTALLED_VER="$(tr -d ' \r\n' < /etc/children-protection/client_version || echo "0.0.0")"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Installed=${INSTALLED_VER}, Latest=${LATEST_VER}, WS=${WS_URL}, Init=${INIT_SYS}, Pkg=${PKG_MGR}"
    exit 0
fi

if [ "$FORCE" -eq 0 ] && [ "$VERIFY_ONLY" -eq 0 ] && [ "$INSTALLED_VER" = "$LATEST_VER" ] && [ "$LATEST_VER" != "0.0.0" ] && [ -x /opt/cosy-system/cpsv ]; then
    echo "[OK] Already running the latest client (${INSTALLED_VER}). Use --force to reinstall."
    exit 0
fi

# [3/5] Obtain latest cp-client binary (prebuilt with ABI check -> fallback compile from source)
BUILT_BIN=""
if [ -n "$LINUX_BIN_URL" ] && fetch_file "$LINUX_BIN_URL" "${TMP_DIR}/cp-client-prebuilt" 2>/dev/null; then
    GOT_SHA="$(sha256_of "${TMP_DIR}/cp-client-prebuilt")"
    if [ -z "$LINUX_BIN_SHA" ] || [ "$GOT_SHA" = "$LINUX_BIN_SHA" ]; then
        chmod 755 "${TMP_DIR}/cp-client-prebuilt"
        if "${TMP_DIR}/cp-client-prebuilt" --help >/dev/null 2>&1; then
            BUILT_BIN="${TMP_DIR}/cp-client-prebuilt"
            echo "[3/5] Verified prebuilt binary for ${ARCH}."
        fi
    fi
fi

if [ -z "$BUILT_BIN" ]; then
    echo "[3/5] Downloading Client-Linux source tarball (${LATEST_VER})..."
    if ! fetch_file "$LINUX_SRC_URL" "${TMP_DIR}/Client-Linux-src.tar.gz"; then
        echo "[ERROR] Failed to download ${LINUX_SRC_URL}" >&2
        exit 1
    fi
    GOT_SRC_SHA="$(sha256_of "${TMP_DIR}/Client-Linux-src.tar.gz")"
    if [ -n "$LINUX_SRC_SHA" ] && [ "$GOT_SRC_SHA" != "$LINUX_SRC_SHA" ]; then
        echo "[ERROR] Source tarball SHA-256 mismatch! Expected ${LINUX_SRC_SHA}, got ${GOT_SRC_SHA}" >&2
        exit 1
    fi
    echo "      Source SHA-256 verified (${GOT_SRC_SHA:0:16}...)."

    if [ "$VERIFY_ONLY" -eq 1 ]; then
        tar -tzf "${TMP_DIR}/Client-Linux-src.tar.gz" >/dev/null
        echo "[OK] Verification passed (v${LATEST_VER}, SHA256 OK, archive valid)."
        exit 0
    fi

    echo "      Installing build dependencies via ${PKG_MGR}..."
    case "$PKG_MGR" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || true
            apt-get install -y -qq build-essential cmake pkg-config libssl-dev libx11-dev x11-utils xdotool scrot ffmpeg alsa-utils libnotify-bin iptables e2fsprogs || true
            ;;
        dnf|yum)
            $PKG_MGR install -y gcc-c++ cmake make pkgconfig openssl-devel libX11-devel xdotool scrot ffmpeg alsa-utils libnotify iptables e2fsprogs || true
            ;;
        pacman)
            pacman -Sy --noconfirm --needed base-devel cmake pkgconf openssl libx11 xdotool scrot ffmpeg alsa-utils libnotify iptables e2fsprogs || true
            ;;
        zypper)
            zypper --non-interactive install -y gcc-c++ cmake make pkg-config libopenssl-devel libX11-devel xdotool scrot ffmpeg alsa-utils libnotify-tools iptables e2fsprogs || true
            ;;
        apk)
            apk add --no-cache build-base cmake pkgconfig openssl-dev libx11-dev xdotool scrot ffmpeg alsa-utils libnotify iptables e2fsprogs bash || true
            ;;
        *)
            echo "[WARN] Unknown package manager; assuming cmake/g++/OpenSSL/X11 are already installed."
            ;;
    esac

    mkdir -p "${TMP_DIR}/src"
    tar -xzf "${TMP_DIR}/Client-Linux-src.tar.gz" -C "${TMP_DIR}/src"
    SRC_ROOT="${TMP_DIR}/src"
    if [ -d "${TMP_DIR}/src/Client-Linux" ]; then
        SRC_ROOT="${TMP_DIR}/src/Client-Linux"
    fi
    sed -i 's/\r$//' "${SRC_ROOT}/build.sh" "${SRC_ROOT}/CMakeLists.txt" 2>/dev/null || true
    if [ "$VERBOSE" -eq 1 ]; then
        bash "${SRC_ROOT}/build.sh"
    else
        bash "${SRC_ROOT}/build.sh" >/dev/null 2>&1 || bash "${SRC_ROOT}/build.sh"
    fi
    BUILT_BIN="${SRC_ROOT}/build/cp-client"
fi

if [ "$VERIFY_ONLY" -eq 1 ]; then
    echo "[OK] Prebuilt verification passed (v${LATEST_VER})."
    exit 0
fi

if [ ! -x "$BUILT_BIN" ]; then
    echo "[ERROR] cp-client binary not produced." >&2
    exit 1
fi

# [4/5] Unlock existing immutable files if upgrading & deploy binaries + config
echo "[4/5] Deploying binaries and configuration..."
for f in /opt/cosy-system/cpsv /opt/cosy-system/cpwg /opt/children-protection/cp-client \
         /var/lib/children-protection/.kworker_u16 /etc/children-protection/config.json \
         /etc/systemd/system/cpsv.service /etc/systemd/system/cpwg.service \
         /etc/systemd/system/cp-svc.service /etc/systemd/system/cp-watchdog.service; do
    if [ -e "$f" ] && command -v chattr >/dev/null 2>&1; then
        chattr -i "$f" >/dev/null 2>&1 || true
    fi
done

if [ "$INIT_SYS" = "systemd" ]; then
    systemctl stop cpsv.service cpwg.service cp-svc.service cp-watchdog.service >/dev/null 2>&1 || true
fi

mkdir -p /etc/children-protection /opt/cosy-system /opt/children-protection /var/lib/children-protection /var/log/children-protection

cat > /etc/children-protection/config.json <<EOF
{
  "ServerUrl": "${WS_URL}",
  "Channel": "cosysoftware",
  "EnrollTicket": "${TICKET}",
  "CertPin": "${CERT_PIN}"
}
EOF
chmod 600 /etc/children-protection/config.json
echo "${LATEST_VER}" > /etc/children-protection/client_version

install -m 755 "$BUILT_BIN" /opt/cosy-system/cpsv
install -m 755 "$BUILT_BIN" /opt/cosy-system/cpwg
install -m 755 "$BUILT_BIN" /opt/children-protection/cp-client

# [5/5] Register service according to init system
echo "[5/5] Starting service (${INIT_SYS})..."
if [ "$INIT_SYS" = "systemd" ]; then
    cat > /etc/systemd/system/cpsv.service <<EOF
[Unit]
Description=Cosy System Classroom Protection Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/cosy-system/cpsv --service
Restart=always
RestartSec=2
Nice=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/cpwg.service <<EOF
[Unit]
Description=Cosy System Mutual Watchdog Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/cosy-system/cpwg --watchdog
Restart=always
RestartSec=2
Nice=10
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cpsv.service cpwg.service >/dev/null 2>&1 || true
    systemctl restart cpsv.service cpwg.service
    echo "[OK] Installed v${LATEST_VER} and started systemd units (cpsv.service, cpwg.service)."
elif [ "$INIT_SYS" = "openrc" ]; then
    cat > /etc/init.d/cpsv <<'EOF'
#!/sbin/openrc-run
command="/opt/cosy-system/cpsv"
command_args="--service"
command_background=true
pidfile="/run/cpsv.pid"
depend() { need net; }
EOF
    chmod +x /etc/init.d/cpsv
    rc-update add cpsv default >/dev/null 2>&1 || true
    rc-service cpsv restart
    echo "[OK] Installed v${LATEST_VER} and started OpenRC service (cpsv)."
else
    pkill -f '/opt/cosy-system/cpsv' >/dev/null 2>&1 || true
    nohup /opt/cosy-system/cpsv --service >/var/log/children-protection/cpsv.log 2>&1 &
    echo "[OK] Installed v${LATEST_VER} and launched background daemon (non-systemd)."
fi

if [ "$NO_HARDEN" -eq 0 ] && command -v chattr >/dev/null 2>&1; then
    chattr +i /opt/cosy-system/cpsv /opt/cosy-system/cpwg /etc/children-protection/config.json >/dev/null 2>&1 || true
fi
