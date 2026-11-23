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
  const kokoro = path.join(root, 'data/models/kokoro/kokoro-v1.0.int8.onnx');
  const kokoroPython = path.join(root, '.runtime/macos-kokoro/bin/python');
  if (
    language === 'en' &&
    [kokoro, kokoroPython, path.join(path.dirname(kokoro), 'voices-v1.0.bin')].every(existsSync)
  )
    return adapter(root, 'kokoro', 'af_heart', kokoroPython, kokoro);
  const model = models.get(language);
  const python = path.join(root, '.runtime/macos-piper/bin/python');
  const file = path.join(root, 'data/models/macos-voice', model + '.onnx');
  if (![python, file, file + '.json'].every(existsSync)) return null;
  return adapter(root, 'piper', model, python, file);
}

function adapter(root, engine, voice, python, file) {
  return {
    engine,
    identity: () => engine + ':' + voice,
    prepare: async () => {},
    synthesize({ text, signal }) {
      signal?.throwIfAborted();
      return new Promise((resolve, reject) => {
        const proc = execFile(
          python,
          ['-I', path.join(root, `integrations/voice_runtime/macos_${engine}.py`), file],
          { signal, timeout: 90000, encoding: 'buffer', maxBuffer: 24000 * 4 * 45 },
          (error, pcm) => {
            if (error || !pcm.length || pcm.length % 4) {
              reject(signal?.reason ?? new Error('The local voice could not generate audio.'));
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
