"""Render one Capri speech segment as mono 24 kHz float PCM on private stdout."""
import sys

import numpy as np
from piper import PiperVoice

voice = PiperVoice.load(sys.argv[1], use_cuda=False)
for chunk in voice.synthesize(sys.stdin.buffer.read().decode("utf-8")):
    samples = chunk.audio_float_array.reshape(-1)
    if samples.size:
        positions = np.arange(round(samples.size * 24000 / chunk.sample_rate)) * chunk.sample_rate / 24000
        sys.stdout.buffer.write(np.interp(positions, np.arange(samples.size), samples).astype("<f4").tobytes())
