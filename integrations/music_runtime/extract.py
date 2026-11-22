"""Extract only the four expected model files from the pinned YAMNet archive."""
import shutil
import sys
import zipfile
from pathlib import Path

expected = {"yamnet.onnx", "yamnet.data", "labels.txt", "metadata.json"}
prefix = "yamnet-onnx-float/"
with zipfile.ZipFile(sys.argv[1]) as archive:
    for entry in archive.infolist():
        if entry.filename == prefix:
            continue
        name = entry.filename.removeprefix(prefix)
        if entry.filename != prefix + name or name not in expected or entry.file_size > 20 * 1024**2:
            raise ValueError("Invalid model archive entry")
        expected.remove(name)
        with archive.open(entry) as source, (Path(sys.argv[2]) / name).open("xb") as output:
            shutil.copyfileobj(source, output)
    if expected:
        raise ValueError("Incomplete model archive")
