#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo "This launcher requires macOS."; exit 1; }
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
command -v npm >/dev/null || { echo "Install Node.js with npm first (brew install node)."; exit 1; }
toolchain="$PWD/.runtime/macos-node"
export npm_config_cache="$PWD/.runtime/npm-cache" electron_config_cache="$PWD/.runtime/electron-cache"
if [[ ! -x "$toolchain/node_modules/.bin/node" ]] || [[ "$("$toolchain/node_modules/.bin/node" -v)" != "v$(cat .node-version)" ]]; then
  npm install --prefix "$toolchain" --engine-strict=false --no-audit --no-fund "node@$(cat .node-version)" npm@12.2.2
fi
export PATH="$toolchain/node_modules/.bin:$PATH"
lockhash=$(shasum -a 256 package-lock.json | cut -d' ' -f1)
if [[ ! -f node_modules/openclaw/openclaw.mjs || ! -f .runtime/macos-deps || "$(cat .runtime/macos-deps)" != "$lockhash" ]]; then
  npm ci --no-audit --no-fund
  echo "$lockhash" > .runtime/macos-deps
fi
node -e 'require("electron")'
if [[ ! -f config/core.local.json ]]; then
  node packages/runtime/bin/capri.mjs setup --yes
  export CAPRI_SETUP_CHATGPT=1
fi
if [[ "${1:-}" == "--chatgpt" ]]; then export CAPRI_SETUP_CHATGPT=1; fi
exec node packages/runtime/bin/capri.mjs desktop
