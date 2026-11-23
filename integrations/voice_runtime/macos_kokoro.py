"""Render one English reply segment with Kokoro Heart as Capri's 24 kHz PCM."""
import sys
from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro

model = Path(sys.argv[1])
voice = Kokoro(str(model), str(model.with_name("voices-v1.0.bin")))
samples, rate = voice.create(sys.stdin.buffer.read().decode("utf-8"), voice="af_heart", lang="en-us")
if rate != 24000:
    raise ValueError("Unexpected sample rate")
sys.stdout.buffer.write(np.asarray(samples, dtype="<f4").tobytes())
