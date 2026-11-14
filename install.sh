#!/usr/bin/env bash
set -euo pipefail
REPO_RAW="https://raw.githubusercontent.com/cosyzzz/cosy-client-setup/main/linux.sh"
if [ -f "$(dirname "${BASH_SOURCE[0]}")/linux.sh" ]; then
    exec bash "$(dirname "${BASH_SOURCE[0]}")/linux.sh" "$@"
elif command -v curl >/dev/null 2>&1; then
    exec bash -c "$(curl -fsSL "$REPO_RAW")" -- "$@"
elif command -v wget >/dev/null 2>&1; then
    exec bash -c "$(wget -qO- "$REPO_RAW")" -- "$@"
else
    echo "[ERROR] Cannot locate linux.sh and neither curl nor wget is installed." >&2
    exit 1
fi
