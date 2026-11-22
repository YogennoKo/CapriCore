#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
export PIP_CACHE_DIR="$PWD/.runtime/pip-cache"
runtime="$PWD/.runtime/music-venv"
if [[ ! -x "$runtime/bin/python" ]]; then
  python=$(command -v python3.13 || command -v python3.12) || { echo "Install Python 3.13 (brew install python@3.13)."; exit 1; }
  "$python" -m venv --copies "$runtime"
fi
"$runtime/bin/python" -m pip install --disable-pip-version-check --only-binary=:all: numpy==2.4.6 onnxruntime==1.31.0
