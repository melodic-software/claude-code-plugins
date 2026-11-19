import json
import os
import pathlib
import sys

# The verdict reader's index mode turns on when its legacy FAILs file sits
# beside it (babysit_verify_evidence.LEGACY_FAILS_FILE); these suites fake the
# whole listing, so they read none unless a test names one.
os.environ.setdefault("BABYSIT_VERIFY_LEGACY_FAILS", "")

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
import babysit_merge_settings as _settings  # noqa: E402

REPO_SETTINGS_FILE = (
    pathlib.Path(__file__).resolve().parents[6] / ".github/source-control-settings.json"
)
REPO_SETTINGS = _settings.parse(
    json.loads(REPO_SETTINGS_FILE.read_text(encoding="utf-8"))["pluginConfigs"][
        "source-control@melodic-software"
    ]["options"]
)
_settings.set_override(REPO_SETTINGS)
