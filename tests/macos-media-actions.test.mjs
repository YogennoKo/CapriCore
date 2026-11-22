// SPDX-License-Identifier: GPL-3.0-only
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { macBridge } from '../integrations/desktop-actions/macos-build.mjs';
import { callApplicationBridge } from '../integrations/desktop-actions/service.mjs';
import { virtualCallCable } from '../apps/desktop/call-audio-setup.mjs';
import { physicalCallInputs } from '../apps/desktop/renderer/call-microphone.mjs';
import { isVerifiedSeparateCallCable } from '../apps/desktop/renderer/call-audio-route.mjs';

test('pairs BlackHole 2ch and prevents mixing its recording endpoint back into itself', () => {
  const endpoint = (kind, deviceId, label) => ({ kind, deviceId, label, groupId: 'hardware' });
  const input = endpoint('audioinput', 'in', 'BlackHole 2ch');
  const output = endpoint('audiooutput', 'out', 'BlackHole 2ch');
  const mic = endpoint('audioinput', 'mic', 'Studio microphone');
  const devices = [mic, input, output];
  assert.deepEqual(physicalCallInputs(devices), [mic]);
  assert.equal(virtualCallCable(devices).deviceId, output.deviceId);
  assert.equal(virtualCallCable([mic, output]), null);
  assert.equal(virtualCallCable([...devices, { ...input, deviceId: 'duplicate' }]), null);
  const check = (track) =>
    isVerifiedSeparateCallCable(devices, { output, microphone: { ...track, readyState: 'live' } });
  assert.equal(check(mic), true);
  assert.equal(check(input), false);
});

test(
  'native macOS bridge discovers an installed application and returns a bounded error frame',
  { skip: process.platform !== 'darwin' },
  async () => {
    const root = process.cwd();
    const found = await callApplicationBridge(root, {
      action: 'catalog_discover',
      query: 'TextEdit',
    });
    assert.ok(found.matches.some((app) => app.executable.endsWith('/TextEdit.app')));
    const result = spawnSync(macBridge(root), ['--frames'], { input: 'invalid\n', timeout: 5000 });
    assert.equal(result.status, 0);
    assert.equal(result.stdout.length, 32);
    assert.equal(result.stdout.readInt32LE(0), 1);
    assert.equal(result.stdout.readInt32LE(28), 0);
  },
);
