import json
import os
import pathlib
import sys

os.environ["BABYSIT_VERIFY_LEGACY_FAILS"] = ""

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
