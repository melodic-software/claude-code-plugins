"""server.py with a stand-in live starter, for the live prototype browser suite (ui_proto_live.js): Approve answers a
fixed https origin per entry and starts no process. Takes server.py's arguments.

    python live_stub_server.py --dir DATA_DIR --guest-port P --control-port 0 --nonce N
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import server  # noqa: E402  (two folders up; sys.path is set just above)


class StubLiveStarter:
    def start(self, entry):
        return f"https://live-{entry['id'].lower()}.example.test"

    def stop(self, entry):
        pass


server.LIVE_STARTER = StubLiveStarter()
sys.exit(server.main())
