// SPDX-License-Identifier: GPL-3.0-only
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  electronBundleReady,
  macElectronBinary,
} from '../packages/runtime/src/host/electron-bundle.mjs';

test('recognizes a complete macOS Electron bundle without accepting it for the Windows updater', (t) => {
  const root = mkdtempSync(path.join(tmpdir(), 'capri-mac-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  function write(relative, data) {
    const file = path.join(root, relative);
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, data);
  }
  write('package.json', '{"version":"45.3.1"}');
  write('dist/version', '45.3.1');
  write('dist/' + macElectronBinary, 'test');
  assert.equal(electronBundleReady(root, undefined, 'darwin'), false);
  const framework = 'dist/Electron.app/Contents/Frameworks/Electron Framework.framework/';
  write(framework + 'Electron Framework', 'test');
  write(framework + 'Resources/icudtl.dat', 'test');
  assert.equal(electronBundleReady(root, '45.3.1', 'darwin'), true);
  assert.equal(electronBundleReady(root, '45.3.0', 'darwin'), false);
  assert.equal(electronBundleReady(root), false);
});
