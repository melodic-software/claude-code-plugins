#!/usr/bin/env bash
# An empty workspace holding one short mono WAV the scene embeds.
set -euo pipefail
python3 - <<'EOF'
import math
import wave

rate = 8000
with wave.open("chime.wav", "wb") as out:
    out.setnchannels(1)
    out.setsampwidth(1)
    out.setframerate(rate)
    out.writeframes(bytes(128 + int(60 * math.sin(2 * math.pi * 880 * i / rate)) for i in range(rate // 4)))
EOF
