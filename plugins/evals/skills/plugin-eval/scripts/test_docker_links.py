#!/usr/bin/env python3
"""Fixture suite for docker-links.py.

Each test builds a temporary HOME whose .docker store holds a directory link
and a file link into a second temporary directory standing in for /mnt/c, the
shape Docker Desktop's WSL integration leaves, plus one plain file. The oracle
for "swapped" is the preflight's own check, `find <store> -mindepth 1 -type l`
printing nothing, and for "restored" the link values the fixture itself wrote.
The real ~/.docker is never touched: every call runs with HOME set to the
fixture.

The suite is executed by docker-links.test.sh, which run-plugin-tests.sh
discovers. Run it directly with: python3 test_docker_links.py
"""

import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "docker-links.py"

# The child each wrapped run executes: list the store's links the way the
# preflight does, into a file the test reads afterwards.
LIST_LINKS = 'find "$HOME/.docker" -mindepth 1 -type l > "$HOME/links-during-run"'


@unittest.skipUnless(os.name == "posix", "the swap targets WSL2 and Linux stores")
class DockerLinksTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        self.home = root / "home"
        self.store = self.home / ".docker"
        self.desktop = root / "mnt-c" / ".docker"
        (self.desktop / "contexts" / "meta").mkdir(parents=True)
        (self.desktop / "contexts" / "meta" / "meta.json").write_text(
            '{"Name": "desktop-linux"}\n', encoding="utf-8"
        )
        (self.desktop / "features.json").write_text('{"a": 1}\n', encoding="utf-8")
        self.store.mkdir(parents=True)
        (self.store / "config.json").write_text('{"auths": {}}\n', encoding="utf-8")
        self.links = {
            "contexts": str(self.desktop / "contexts"),
            "features.json": str(self.desktop / "features.json"),
        }
        for name, target in self.links.items():
            os.symlink(target, self.store / name)
        self.env = dict(os.environ, HOME=str(self.home))
        self.env.pop("DOCKER_CONFIG", None)

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def wrapped(self, shell_command):
        return self.cli("run", "--", "sh", "-c", shell_command)

    def find_links(self):
        out = subprocess.run(
            ["find", str(self.store), "-mindepth", "1", "-type", "l"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        return sorted(line for line in out.splitlines() if line)

    def assert_restored(self):
        for name, target in self.links.items():
            path = self.store / name
            self.assertTrue(path.is_symlink(), f"{name} is not a link again")
            self.assertEqual(os.readlink(path), target)
        self.assertEqual(
            (self.store / "config.json").read_text(encoding="utf-8"),
            '{"auths": {}}\n',
        )
        self.assertFalse((self.home / ".docker-link-swap.json").exists())

    def links_during_run(self):
        return (self.home / "links-during-run").read_text(encoding="utf-8")

    def test_successful_run_sees_no_links_and_restores_them(self):
        result = self.wrapped(
            LIST_LINKS + ' && cat "$HOME/.docker/contexts/meta/meta.json"'
            ' "$HOME/.docker/features.json"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.links_during_run(), "")
        self.assertEqual(result.stdout, '{"Name": "desktop-linux"}\n{"a": 1}\n')
        self.assert_restored()

    def test_failed_run_keeps_its_exit_code_and_restores_the_links(self):
        result = self.wrapped(LIST_LINKS + " && exit 3")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(self.links_during_run(), "")
        self.assert_restored()

    def test_interrupted_run_restores_the_links(self):
        marker = self.home / "child-started"
        proc = subprocess.Popen(
            [
                sys.executable,
                str(SCRIPT),
                "run",
                "--",
                "sh",
                "-c",
                LIST_LINKS + ' && touch "$HOME/child-started" && exec sleep 30',
            ],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        deadline = time.monotonic() + 20
        while not marker.exists():
            self.assertIsNone(
                proc.poll(), "the wrapper exited before its child started"
            )
            self.assertLess(time.monotonic(), deadline, "the child never started")
            time.sleep(0.05)
        proc.send_signal(signal.SIGTERM)
        _, stderr = proc.communicate(timeout=20)
        self.assertEqual(proc.returncode, 128 + signal.SIGTERM, stderr)
        self.assertEqual(self.links_during_run(), "")
        self.assert_restored()

    def test_swap_then_restore_recovers_a_killed_run(self):
        swap = self.cli("swap")
        self.assertEqual(swap.returncode, 0, swap.stderr)
        self.assertEqual(self.find_links(), [])
        self.assertTrue((self.store / "contexts").is_dir())
        self.assertTrue((self.home / ".docker-link-swap.json").is_file())
        restore = self.cli("restore")
        self.assertEqual(restore.returncode, 0, restore.stderr)
        self.assert_restored()

    def test_swap_refuses_while_an_earlier_record_is_unrestored(self):
        self.assertEqual(self.cli("swap").returncode, 0)
        again = self.wrapped(LIST_LINKS)
        self.assertEqual(again.returncode, 2)
        self.assertIn("restore", again.stderr)
        self.assertFalse((self.home / "links-during-run").exists())
        self.assertEqual(self.cli("restore").returncode, 0)
        self.assert_restored()

    def test_dangling_link_refuses_and_changes_nothing(self):
        os.symlink(str(self.desktop / "gone"), self.store / "dangling")
        before = self.find_links()
        result = self.wrapped(LIST_LINKS)
        self.assertEqual(result.returncode, 2)
        self.assertIn("dangling", result.stderr)
        self.assertEqual(self.find_links(), before)
        self.assertFalse((self.home / "links-during-run").exists())
        self.assertFalse((self.home / ".docker-link-swap.json").exists())

    def test_store_root_that_is_itself_a_link_is_swapped_and_restored(self):
        # ~/.docker -> <mnt-c>/.docker, whose contexts entry is itself a link.
        real_store = self.desktop.parent / "linked-store"
        self.store.rename(real_store)
        os.symlink(str(real_store), self.store)
        result = self.wrapped(
            LIST_LINKS + ' && test ! -L "$HOME/.docker"'
            ' && cat "$HOME/.docker/contexts/meta/meta.json"'
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.links_during_run(), "")
        self.assertEqual(result.stdout, '{"Name": "desktop-linux"}\n')
        self.assertTrue(self.store.is_symlink())
        self.assertEqual(os.readlink(self.store), str(real_store))
        for name, target in self.links.items():
            self.assertEqual(os.readlink(real_store / name), target)
        self.assertFalse((self.home / ".docker-link-swap.json").exists())

    def test_restore_leaves_a_link_docker_desktop_recreated(self):
        self.assertEqual(self.cli("swap").returncode, 0)
        copy = self.store / "features.json"
        copy.unlink()
        os.symlink(self.links["features.json"], copy)
        self.assertEqual(self.cli("restore").returncode, 0)
        self.assert_restored()


if __name__ == "__main__":
    unittest.main(verbosity=2)
