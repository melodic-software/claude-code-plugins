"""Tests for publish.py, the fail-closed loader of the publish redactor, over invented hosts."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

import publish
from conftest import PLUGIN_SCRIPTS


def sources_file(tmp_path: Path, *entries: dict) -> str:
    path = tmp_path / "secret-fleet" / "sources.json"
    path.parent.mkdir()
    path.write_text(json.dumps({"schema": "transcript-sources/v1", "sources": list(entries)}), encoding="utf-8")
    return str(path)


HOST_B = {"name": "host-b-wsl", "host": "host-b", "platform": "wsl", "config_dir": "/srv/user-b/.claude", "via": ["ssh", "host-b"]}


def test_a_usable_sources_file_and_identifiers_give_a_publisher(tmp_path: Path) -> None:
    p = publish.publisher(sources_file(tmp_path, HOST_B), "project-zeta, /opt/zeta")
    assert p.redact("host-b ran project-zeta in /opt/zeta/x") == "<host-1> ran <identifier> in <identifier>/x"


def test_no_sources_file_reads_this_hosts_sources() -> None:
    assert not publish.publisher("").fail_closed


def test_a_missing_named_sources_file_publishes_nothing_and_names_no_path(tmp_path: Path) -> None:
    with pytest.raises(publish.PublishError) as caught:
        publish.publisher(str(tmp_path / "secret-fleet" / "absent.json"))
    assert str(caught.value) == "nothing published: the sources file was not found"


def test_an_unusable_sources_file_names_neither_its_path_nor_its_sources(tmp_path: Path) -> None:
    path = sources_file(tmp_path, HOST_B, HOST_B)
    with pytest.raises(publish.PublishError) as caught:
        publish.publisher(path)
    message = str(caught.value)
    assert message == "nothing published: the sources file: source name <value> appears more than once"
    assert "secret-fleet" not in message and "host-b" not in message


def test_secret_rules_that_do_not_load_publish_nothing(tmp_path: Path) -> None:
    with pytest.raises(publish.PublishError) as caught:
        publish.publisher(sources_file(tmp_path, HOST_B), rules=tmp_path / "absent-rules.json")
    assert str(caught.value) == "nothing published: the secret redaction rules did not load"


def test_an_invalid_hosts_block_names_no_host(tmp_path: Path) -> None:
    path = tmp_path / "sources.json"
    path.write_text(json.dumps({"schema": "transcript-sources/v1", "sources": [HOST_B], "hosts": {"host-b": {"bogus": 1}}}), encoding="utf-8")
    with pytest.raises(publish.PublishError) as caught:
        publish.publisher(str(path))
    assert str(caught.value) == "nothing published: the sources file: hosts.<value> has unknown key <value>"


def run_cli(*args: str, text: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([sys.executable, str(PLUGIN_SCRIPTS / "publish.py"), *args], input=text,
                          capture_output=True, text=True, encoding="utf-8", timeout=30)


def test_the_cli_redacts_stdin_for_a_skill_body(tmp_path: Path) -> None:
    done = run_cli("--sources-file", sources_file(tmp_path, HOST_B), "--redact-identifiers", "project-zeta",
                   text="Learned on host-b: project-zeta needs ops-b@example.org\n")
    assert (done.returncode, done.stdout) == (0, "Learned on <host-1>: <identifier> needs <email>\n")


def test_the_cli_prints_nothing_when_the_redactor_fails_closed(tmp_path: Path) -> None:
    done = run_cli("--sources-file", str(tmp_path / "absent.json"), text="host-b learned this\n")
    assert (done.returncode, done.stdout) == (2, "")
    assert done.stderr == "publish: nothing published: the sources file was not found\n"
