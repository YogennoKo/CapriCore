// SPDX-License-Identifier: GPL-3.0-only
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const digest = (data) => createHash('sha256').update(data).digest('hex');
export function macBridge(root) {
  const sources = ['Actions.swift', 'Audio.swift', 'Bridge.swift', 'Capture.swift'].map((name) =>
    path.join(root, 'integrations/desktop-actions/macos', name),
  );
  const revision = digest(
    sources.map((file) => digest(readFileSync(file))).join('') + process.arch,
  );
  const base = path.join(root, '.runtime/macos-native');
  const dir = path.join(base, revision);
  if (!existsSync(dir)) {
    mkdirSync(base, { recursive: true });
    const stage = mkdtempSync(path.join(base, 'build-'));
    try {
      const binary = path.join(stage, 'capri-native');
      execFileSync(
        '/usr/bin/swiftc',
        ['-module-cache-path', path.join(base, 'cache'), '-o', binary, ...sources],
        { stdio: 'inherit', timeout: 180000 },
      );
      writeFileSync(path.join(stage, 'sha256'), digest(readFileSync(binary)));
      try {
        renameSync(stage, dir);
      } catch (error) {
        if (!existsSync(dir)) throw error;
      }
    } finally {
      rmSync(stage, { recursive: true, force: true });
    }
  }
  const binary = path.join(dir, 'capri-native');
  if (digest(readFileSync(binary)) !== readFileSync(path.join(dir, 'sha256'), 'utf8'))
    throw new Error('macOS desktop bridge integrity check failed.');
  return binary;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const executable = macBridge(process.cwd());
  if (['--permissions', '--request-permissions'].includes(process.argv[2]))
    execFileSync(executable, [process.argv[2]], { stdio: 'inherit' });
}
