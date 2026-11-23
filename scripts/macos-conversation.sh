#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
python=$(command -v python3.13 || command -v python3.12) || { echo "Install Python 3.13 (brew install python@3.13)."; exit 1; }
export PIP_CACHE_DIR="$PWD/.runtime/pip-cache"
install_env() {
  local dir="$1"
  shift
  if [[ ! -x "$dir/bin/python" ]]; then "$python" -m venv --copies "$dir"; fi
  "$dir/bin/python" -m pip install --disable-pip-version-check "$@"
}
install_env .runtime/asr-venv sherpa-onnx==1.13.8 numpy==2.4.6
install_env .runtime/macos-kokoro kokoro-onnx==0.6.1
"$python" scripts/macos-conversation-models.py
