#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
runtime="$PWD/.runtime/macos-piper"
export PIP_CACHE_DIR="$PWD/.runtime/pip-cache"
if [[ ! -x "$runtime/bin/python" ]]; then
  python=$(command -v python3.13 || command -v python3.12) || { echo "Install Python 3.13 (brew install python@3.13)."; exit 1; }
  "$python" -m venv --copies "$runtime"
fi
"$runtime/bin/python" -m pip install --disable-pip-version-check --only-binary=:all: piper-tts==1.8.0
mkdir -p data/models/macos-voice
cd data/models/macos-voice
verify() {
  shasum -a 256 -c --status <<'SUMS'
5efe09e69902187827af646e1a6e9d269dee769f9877d17b16b1b46eeaaf019f  en_US-lessac-medium.onnx
efe19c417bed055f2d69908248c6ba650fa135bc868b0e6abb3da181dab690a0  en_US-lessac-medium.onnx.json
8ff38212d23da300bbe3705c645e6e5b9475f0bfde01558eb17813e22acaaaaa  ru_RU-irina-medium.onnx
c2ec28bb38e2b59e93b959b3e40348c1afebbd272f30fed5d41205d08e98a9d7  ru_RU-irina-medium.onnx.json
SUMS
}
if ! verify 2>/dev/null; then
  stage=$(mktemp -d "$PWD/.install-XXXXXX")
  trap 'rm -rf "$stage"' EXIT
  (cd "$stage" && "$runtime/bin/python" -m piper.download_voices ru_RU-irina-medium en_US-lessac-medium && verify)
  for file in "$stage"/*.onnx "$stage"/*.onnx.json; do mv -f "$file" .; done
fi
