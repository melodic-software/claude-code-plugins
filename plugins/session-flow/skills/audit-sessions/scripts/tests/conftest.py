from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1]
PLUGIN_SCRIPTS = Path(__file__).resolve().parents[4] / "scripts"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
LOCK = ("--lock-name", f"claude-transcript-run.t-{uuid.uuid4().hex[:16]}")

for _path in (str(SCRIPTS), str(PLUGIN_SCRIPTS)):
    if _path not in sys.path:
        sys.path.insert(0, _path)


def run_cli(script: str, *args: str, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    """Run an audit-sessions script, or a plugin-level one it uses, by subprocess, as a consumer would."""
    path = SCRIPTS / script if (SCRIPTS / script).is_file() else PLUGIN_SCRIPTS / script
    if script == "collect.py" and args[:1] in (("collect",), ("migrate",)):
        args = (args[0], *LOCK, *args[1:])
    return subprocess.run(
        [sys.executable, str(path), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60,
        env=env,
    )


def config_env(projects: Path, base: dict | None = None) -> dict:
    """An environment whose local transcript source is the configuration directory holding `projects`."""
    return {**(os.environ if base is None else base), "CLAUDE_CONFIG_DIR": str(projects.parent)}


def collect_cli(data_dir: Path, projects: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """`collect.py collect` over the local source whose `projects` directory is `projects`."""
    return run_cli("collect.py", "collect", "--data-dir", str(data_dir), *args, env=config_env(projects))


def stored_records(data_dir: Path, source: str = "local") -> list[Path]:
    return sorted((data_dir / "audit-sessions" / "store" / "v2" / source).glob("p-*/*.json"))


def envelope(result: subprocess.CompletedProcess[str]) -> dict:
    return json.loads(result.stdout)


@pytest.fixture
def data_dir(tmp_path: Path) -> Path:
    path = tmp_path / "data"
    path.mkdir()
    return path


@pytest.fixture
def copy_fixture(tmp_path: Path):
    """Copy a named fixture tree under `fixtures/` to the `projects` directory of a configuration directory under `tmp_path`."""
    def _copy(name: str) -> Path:
        dest = tmp_path / "configs" / name / "projects"
        shutil.copytree(FIXTURES / name, dest)
        return dest

    return _copy


@pytest.fixture
def multi(copy_fixture, tmp_path):
    """The multi fixture with `cwd` placeholders pointing at a real and a removed directory."""
    root = copy_fixture("multi")
    cwd_a = tmp_path / "work" / "repo-a"
    cwd_a.mkdir(parents=True)
    gone = tmp_path / "work" / "removed"
    for path in root.rglob("*.jsonl"):
        text = path.read_text(encoding="utf-8")
        text = text.replace("__CWD_A__", json.dumps(str(cwd_a))[1:-1])
        text = text.replace("__CWD_GONE__", json.dumps(str(gone))[1:-1])
        path.write_text(text, encoding="utf-8", newline="\n")
    return root, cwd_a


HASHED_INPUTS = (
    "scripts/collect.py",
    "scripts/census.py",
    "scripts/claude_projects.py",
    "scripts/friction_scan.py",
    "scripts/redact.py",
    "scripts/session_record.py",
    "scripts/transcript_limits.py",
    "scripts/transcript_reader.py",
    "scripts/transcript_run.py",
    "scripts/transcript_sources.py",
    "scripts/transcript_values.py",
    "vendor/gitleaks/gitleaks-rules.json",
    "lib/state-key.sh",
)
PLUGIN_ROOT = SCRIPTS.parents[2]


@pytest.fixture
def plugin_copy(tmp_path):
    """A copy of the plugin files collect.py runs or reads, laid out as in the plugin."""
    dest = tmp_path / "plugin" / "session-flow"
    for relative in (*HASHED_INPUTS, ".claude-plugin/plugin.json"):
        (dest / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PLUGIN_ROOT / relative, dest / relative)
    return dest


FAKE_CC_VERSION = "9.9.9"


@pytest.fixture
def fleet(tmp_path, multi):
    """Two invented hosts' configuration directories, the second read through an `sh -c` via, and a fake claude on PATH."""
    root, _ = multi
    other = tmp_path / "host-b" / "config"
    shutil.copytree(root, other / "projects")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    (bin_dir / "claude").write_text(f"#!/bin/sh\necho '{FAKE_CC_VERSION} (Claude Code)'\n", encoding="utf-8")
    (bin_dir / "claude").chmod(0o755)
    env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
    sources = tmp_path / "sources.json"
    sources.write_text(json.dumps({
        "schema": "transcript-sources/v1",
        "sources": [
            {"name": "host-a-wsl", "host": "host-a", "platform": "wsl", "config_dir": str(root.parent)},
            {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": str(other), "via": ["sh", "-c"]},
        ],
    }), encoding="utf-8")
    return sources, env, root, other
