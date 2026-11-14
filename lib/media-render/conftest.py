"""pytest (CI's test-python lane): media_scan imports redact.py, which sits one level up here and beside it in a
plugin. media-render.test.sh does the same for unittest through PYTHONPATH."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
