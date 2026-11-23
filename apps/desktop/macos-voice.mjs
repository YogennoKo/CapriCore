// SPDX-License-Identifier: GPL-3.0-only
import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

const models = new Map([
  ['ru', 'ru_RU-irina-medium'],
  ['en', 'en_US-lessac-medium'],
]);

export function macVoice(root, language) {
  if (process.platform !== 'darwin' || !models.has(language)) return null;
  const model = models.get(language);
  const python = path.join(root, '.runtime/macos-piper/bin/python');
  const file = path.join(root, 'data/models/macos-voice', model + '.onnx');
  if (![python, file, file + '.json'].every(existsSync)) return null;
  return {
    identity: () => 'piper:' + model,
    prepare: async () => {},
    synthesize({ text, signal }) {
      signal?.throwIfAborted();
      return new Promise((resolve, reject) => {
        const proc = execFile(
          python,
          ['-I', path.join(root, 'integrations/voice_runtime/macos_piper.py'), file],
          { signal, timeout: 90000, encoding: 'buffer', maxBuffer: 24000 * 4 * 45 },
          (error, pcm) => {
            if (error || !pcm.length || pcm.length % 4) {
              reject(signal?.reason ?? new Error('Local Piper voice could not generate audio.'));
              return;
            }
            resolve(
              new Response(pcm, {
                headers: { 'content-type': 'application/octet-stream', 'x-sample-rate': '24000' },
              }),
            );
          },
        );
        proc.stdin.on('error', reject);
        proc.stdin.end(text, 'utf8');
      });
    },
  };
}
