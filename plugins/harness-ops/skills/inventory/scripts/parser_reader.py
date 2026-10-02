#!/usr/bin/env python3
"""The parser side of `inventory.py --reader=parser`: install the pinned
JavaScript parser on first use, then talk to it as one long-lived node process.

Dependencies are never vendored (docs/conventions/on-demand-dependencies/).
`js/package.json` and `js/package-lock.json` pin acorn and eslint-scope; the
first parser run copies both into an install directory and runs `npm ci`
there, which installs exactly the locked versions and checks each tarball
against the lockfile's integrity hash. Later runs reuse that directory. The
directory is keyed by the lockfile's hash, so a plugin update that changes
the lockfile installs beside the old set instead of over it.

Install base, first match wins:

  --deps-dir <dir>       explicit
  $CLAUDE_PLUGIN_DATA    when it names a harness-ops data directory; Claude
                         Code exports it to hooks and MCP servers, not to
                         Bash-tool commands, and a skill subprocess has been
                         seen holding another plugin's value
  <checkout>/.work/harness-ops
                         when this file runs from a git checkout of the
                         marketplace, whose .work/ is gitignored
  <config dir>/plugins/data/harness-ops-melodic-software
                         where Claude Code puts this plugin's data directory

Anything that stops the reader (no node, no npm, a failed install, a helper
that does not load) raises ReaderBroken carrying the exact command that
repairs it. Nothing here falls back to the regex reader.

Run: python3 parser_reader.py --install [--deps-dir <dir>]
     installs if needed, probes the helper, and prints what it found.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

JS_DIR = Path(__file__).resolve().parent / "js"
HELPER = JS_DIR / "parser_helper.cjs"
MANIFESTS = ("package.json", "package-lock.json")
REQUIRED_PACKAGES = ("acorn", "eslint-scope")
COMPONENT = "inventory-parser"
PLUGIN_DATA_ID = "harness-ops-melodic-software"
NPM_CI_ARGS = ("ci", "--ignore-scripts", "--no-audit", "--no-fund")
NPM_TIMEOUT_SECONDS = 600


class ReaderBroken(Exception):
    """The parser reader cannot run; `command` repairs it when one exists."""

    def __init__(self, reason: str, command: str | None = None) -> None:
        super().__init__(reason)
        self.reason = reason
        self.command = command

    def __str__(self) -> str:
        return f"{self.reason}; run: {self.command}" if self.command else self.reason


def lock_key() -> str:
    return hashlib.sha256((JS_DIR / "package-lock.json").read_bytes()).hexdigest()[:12]


def checkout_root() -> Path | None:
    """The marketplace checkout this file runs from, when its .work/ is ignored."""
    root = Path(__file__).resolve().parents[5]
    if not (root / ".git").exists() or not (root / ".claude-plugin").is_dir():
        return None
    try:
        ignored = (root / ".gitignore").read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    return (
        root if any(line.strip() in (".work/", ".work") for line in ignored) else None
    )


def deps_base(explicit: str | None) -> tuple[Path, str]:
    """The install base and the rule that chose it."""
    if explicit:
        return Path(explicit), "--deps-dir"
    env = os.environ.get("CLAUDE_PLUGIN_DATA")
    if env and Path(env).name.startswith("harness-ops"):
        return Path(env), "CLAUDE_PLUGIN_DATA"
    root = checkout_root()
    if root is not None:
        return root / ".work" / "harness-ops", "checkout .work/"
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    base = Path(config) if config else Path.home() / ".claude"
    return base / "plugins" / "data" / PLUGIN_DATA_ID, "plugin data directory"


def install_dir(base: Path) -> Path:
    return base / COMPONENT / lock_key()


def _q(path: Path) -> str:
    return shlex.quote(path.as_posix())


def install_command(target: Path) -> str:
    """One shell line that rebuilds `target` from the committed lockfile."""
    q = _q
    sources = " ".join(q(JS_DIR / m) for m in MANIFESTS)
    return (
        f"rm -rf {q(target)} && mkdir -p {q(target)} && cp {sources} {q(target)}/ "
        f"&& npm {NPM_CI_ARGS[0]} --prefix {q(target)} {' '.join(NPM_CI_ARGS[1:])}"
    )


def installed(target: Path) -> bool:
    return all(
        (target / "node_modules" / name / "package.json").is_file()
        for name in REQUIRED_PACKAGES
    )


def ensure_installed(target: Path) -> bool:
    """Install into `target` unless already there; True when this call installed.

    `npm ci` runs in a sibling directory that is renamed into place, so a run
    killed mid-install leaves nothing `installed` accepts, and two concurrent
    first runs both finish with one complete directory.
    """
    if installed(target):
        return False
    command = install_command(target)
    npm = shutil.which("npm")
    if npm is None:
        raise ReaderBroken(
            "npm is not on PATH, so the parser cannot be installed (install "
            "Node.js, which ships npm)",
            command,
        )
    partial = target.with_name(f"{target.name}.partial-{os.getpid()}")
    shutil.rmtree(partial, ignore_errors=True)
    try:
        partial.mkdir(parents=True)
        for name in MANIFESTS:
            shutil.copyfile(JS_DIR / name, partial / name)
        run = subprocess.run(
            [npm, *NPM_CI_ARGS],
            cwd=partial,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=NPM_TIMEOUT_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        shutil.rmtree(partial, ignore_errors=True)
        raise ReaderBroken(f"npm ci could not run: {exc}", command) from exc
    if run.returncode != 0 or not installed(partial):
        shutil.rmtree(partial, ignore_errors=True)
        tail = [ln for ln in (run.stderr or run.stdout).splitlines() if ln.strip()][-3:]
        raise ReaderBroken(
            f"npm ci failed (exit {run.returncode}): " + " | ".join(tail), command
        )
    try:
        partial.rename(target)
    except OSError:
        shutil.rmtree(partial, ignore_errors=True)
        if not installed(target):
            raise ReaderBroken(f"cannot move the install into {target}", command)
        return False
    return True


class ParserReader:
    """The helper process. Requests go one at a time, each answered in turn."""

    def __init__(self, target: Path) -> None:
        self.target = target
        node = shutil.which("node")
        if node is None:
            raise ReaderBroken(
                "node is not on PATH (install Node.js)", install_command(target)
            )
        env = dict(os.environ, NODE_PATH=str(target / "node_modules"))
        self._stderr = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
        self._next_id = 0
        try:
            self._proc = subprocess.Popen(
                [node, str(HELPER)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self._stderr,
                text=True,
                encoding="utf-8",
                env=env,
            )
        except OSError as exc:
            self._stderr.close()
            raise ReaderBroken(f"cannot start node: {exc}") from exc

    def request(self, op: str, **fields: Any) -> dict[str, Any]:
        self._next_id += 1
        line = json.dumps({"id": self._next_id, "op": op, **fields})
        assert self._proc.stdin is not None and self._proc.stdout is not None
        try:
            self._proc.stdin.write(line + "\n")
            self._proc.stdin.flush()
            reply = self._proc.stdout.readline()
        except OSError:
            reply = ""
        if not reply:
            raise ReaderBroken(
                f"the parser helper exited: {self._stderr_tail()}",
                install_command(self.target),
            )
        res = json.loads(reply)
        if res.get("id") != self._next_id or not res.get("ok"):
            raise ReaderBroken(f"the parser helper answered {op} with {reply.strip()}")
        return res

    def _stderr_tail(self) -> str:
        try:
            self._proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        self._stderr.seek(0)
        lines = [ln for ln in self._stderr.read().splitlines() if ln.strip()]
        return " | ".join(lines[-3:]) or f"exit {self._proc.returncode}"

    def ping(self) -> dict[str, Any]:
        """Versions of node, acorn and eslint-scope, proving the helper loads."""
        res = self.request("ping")
        return {k: res.get(k) for k in ("node", "acorn", "eslint_scope")}

    def parse_ok(self, source: str) -> tuple[bool, str | None]:
        res = self.request("parse_ok", source=source)
        return bool(res["parsed"]), res.get("error")

    def close(self) -> None:
        if self._proc.stdin:
            self._proc.stdin.close()
        try:
            self._proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self._proc.kill()
            self._proc.wait()
        if self._proc.stdout:
            self._proc.stdout.close()
        self._stderr.close()

    def __enter__(self) -> ParserReader:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def open_reader(deps_dir: str | None) -> tuple[ParserReader, dict[str, Any]]:
    """Install if needed, start the helper and probe it; raises ReaderBroken."""
    base, how = deps_base(deps_dir)
    target = install_dir(base)
    installed_now = ensure_installed(target)
    reader = ParserReader(target)
    try:
        helper = reader.ping()
    except ReaderBroken:
        reader.close()
        raise
    return reader, {
        "deps_dir": str(target),
        "deps_dir_selected_by": how,
        "installed_now": installed_now,
        "helper": helper,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Install and probe the parser helper.")
    ap.add_argument("--install", action="store_true", required=True)
    ap.add_argument("--deps-dir", help="install base (default: see module docstring)")
    args = ap.parse_args(argv)
    try:
        reader, info = open_reader(args.deps_dir)
    except ReaderBroken as exc:
        print(f"BROKEN: {exc}", file=sys.stderr)
        return 1
    reader.close()
    print(json.dumps(info, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
