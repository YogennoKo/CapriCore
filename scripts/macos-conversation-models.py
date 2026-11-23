"""Install the pinned local Mac wake recognizer, VAD and English voice assets."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

root = Path(__file__).resolve().parents[1]
def config(name):
    return json.loads((root / 'config' / name).read_text())
def install(job):
    url, destination, checksum = job
    def valid(file):
        if not file.is_file():
            return False
        with file.open('rb') as src:
            return hashlib.file_digest(src, 'sha256').hexdigest() == checksum
    if valid(destination):
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as stage:
        tmp = Path(stage) / destination.name
        subprocess.run(['curl', '-fsSL', '--retry', '3', '-o', str(tmp), url], check=True)
        if not valid(tmp):
            raise ValueError('Checksum mismatch: ' + destination.name)
        os.replace(tmp, destination)

asr = config('multilingual-candidates.json')['asr']
jobs = [(f"https://huggingface.co/{asr['model']}/resolve/{asr['revision']}/{f['file']}",
         root / asr['directory'] / f['file'], f['sha256']) for f in asr['files']]
vad = config('asr-vad-upstream.json')['files']['model']
jobs.append((vad['url'], root / config('companion-asr.json')['vad']['modelDir'] / vad['file'], vad['sha256']))
release = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
for name, checksum in {
    "kokoro-v1.0.int8.onnx": "6e742170d309016e5891a994e1ce1559c702a2ccd0075e67ef7157974f6406cb",
    "voices-v1.0.bin": "bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d",
}.items():
    jobs.append((release + name, root / 'data/models/kokoro' / name, checksum))

with ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(install, jobs))
