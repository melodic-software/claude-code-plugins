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
  $CLAUDE_PLUGIN_DATA    when the last path segment is harness-ops or starts
                         with harness-ops- (not a mere prefix such as
                         harness-opsx-foo); Claude Code exports it to hooks
                         and MCP servers, not to Bash-tool commands, and a
                         skill subprocess has been seen holding another
                         plugin's value
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
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
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
STALE_PARTIAL_SECONDS = 2 * NPM_TIMEOUT_SECONDS


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
    # Exact plugin match. startswith("harness-ops") also accepts a lookalike
    # such as harness-opsx-foo.
    if env:
        name = Path(env).name
        if name == "harness-ops" or name.startswith("harness-ops-"):
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


_PS_SINGLE_QUOTES = re.compile("['‘’‚‛]")


def _ps_q(path: Path) -> str:
    # PowerShell reads all four curly forms as single quotes; doubling escapes each.
    return "'" + _PS_SINGLE_QUOTES.sub(lambda m: m[0] * 2, str(path)) + "'"


def install_command(target: Path, platform: str = sys.platform) -> str:
    """One shell line that rebuilds `target` from the committed lockfile.

    POSIX shell elsewhere; Windows PowerShell 5.1 on win32, which has no `&&`.
    There it names `npm.cmd`: bare `npm` resolves to `npm.ps1`, which the
    default Restricted execution policy refuses to run. The sequence runs in a
    child script block so its `$ErrorActionPreference = 'Stop'` does not stay
    set in the session the user pastes it into.
    """
    flags = " ".join(NPM_CI_ARGS[1:])
    if platform == "win32":
        q = _ps_q
        sources = ", ".join(q(JS_DIR / m) for m in MANIFESTS)
        return (
            "& { $ErrorActionPreference = 'Stop'; "
            f"Remove-Item -LiteralPath {q(target)} -Recurse -Force -ErrorAction SilentlyContinue; "
            f"New-Item -ItemType Directory -Force -Path {q(target)} | Out-Null; "
            f"Copy-Item -LiteralPath {sources} -Destination {q(target)}; "
            f"npm.cmd {NPM_CI_ARGS[0]} --prefix {q(target)} {flags} }}"
        )
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


def remove_stale_partials(target: Path) -> None:
    """Delete `<target>.partial-*` siblings a killed install left behind.

    Only directories untouched for longer than STALE_PARTIAL_SECONDS go: no
    live `npm ci` runs that long, so a concurrent install's directory stays.
    """
    cutoff = time.time() - STALE_PARTIAL_SECONDS
    for partial in target.parent.glob(f"{target.name}.partial-*"):
        try:
            if partial.stat().st_mtime < cutoff:
                shutil.rmtree(partial, ignore_errors=True)
        except OSError:
            continue


def ensure_installed(target: Path) -> bool:
    """Install into `target` unless already there; True when this call installed.

    `npm ci` runs in a sibling directory that is renamed into place, so a run
    killed mid-install leaves nothing `installed` accepts, and two concurrent
    first runs both finish with one complete directory.
    """
    if installed(target):
        return False
    remove_stale_partials(target)
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
                "node is not on PATH: install Node.js, then rerun (the parser "
                f"packages need no reinstall; they are in {target})"
            )
        env = dict(os.environ, NODE_PATH=str(target / "node_modules"))
        self._stderr = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
        self._next_id = 0
        self._keys: dict[tuple[int, int, int], tuple[str, str]] = {}
        self._spans: dict[int, list[tuple[int, int]]] = {}
        self._paths: dict[int, tuple[str, dict[int, str]]] = {}
        self._answers: dict[tuple[Any, ...], dict[str, Any] | None] = {}
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

    def parse_module(self, src: str, lo: int, hi: int) -> tuple[bool, str | None]:
        """`parse_ok` for the module `src[lo:hi]`, which also files the
        module among the ones `keys_used` reads for `src`."""
        self._spans.setdefault(id(src), []).append((lo, hi))
        res = self.request(
            "parse_ok", source=src[lo:hi], module=self._module_key(src, lo, hi)
        )
        return bool(res["parsed"]), res.get("error")

    def flow(self, src: str, lo: int, hi: int, start: dict[str, Any]) -> dict[str, Any]:
        """Whether an array value stays unchanged in the module `src[lo:hi]`
        (the helper's `flow` op). `start["offset"]`, when present, is a
        position in `src`; so is the `at` of an unsafe answer."""
        key = ("flow", id(src), lo, json.dumps(start, sort_keys=True))
        cached = self._answers.get(key)
        if cached is not None:
            return cached
        fields = dict(start)
        if "offset" in fields:
            fields["offset"] -= lo
        res = self._send("flow", src, lo, hi, start=fields)
        if res.get("unreadable"):
            answer = {
                "safe": False,
                "reason": "the module holds a character outside the BMP",
                "at": None,
            }
        elif res["safe"]:
            answer = {
                "safe": True,
                "exits": [tuple(hop) for hop in res["exits"]],
                "trusted": res.get("trusted", []),
            }
        else:
            at = res.get("at")
            answer = {
                "safe": False,
                "reason": res["reason"],
                "at": None if at is None else at + lo,
            }
        self._answers[key] = answer
        return answer

    def sinks(
        self, src: str, lo: int, hi: int, names: list[str]
    ) -> list[tuple[str, str | None, int]]:
        """Where the module `src[lo:hi]` may write one of `names` on an object
        that could be a built-in prototype (the helper's `sinks` op), each
        (kind, name, offset in `src`). A module that does not parse, calls
        `eval` directly, or holds a character outside the BMP is one hit."""
        res = self._send("sinks", src, lo, hi, names=names)
        if res.get("unreadable"):
            return [("unreadable", None, lo)]
        return [(kind, name, at + lo) for kind, name, at in res["hits"]]

    def set_module_paths(self, src: str, paths: dict[int, str]) -> None:
        """File `src`'s module paths by module start (`read_bundle`)."""
        self._paths[id(src)] = (src, paths)

    def module_start(self, src: str, path: str) -> int | None:
        """The start of the module whose path is `path`, if one is filed."""
        held = self._paths.get(id(src))
        if not held:
            return None
        return next((lo for lo, p in held[1].items() if p == path), None)

    def modules_named(self, src: str, file: str) -> list[int]:
        """The starts of the modules whose path ends in the file name `file`."""
        held = self._paths.get(id(src))
        if not held:
            return []
        return [lo for lo, p in held[1].items() if p.rsplit("/", 1)[-1] == file]

    def module_path(self, src: str, lo: int) -> str | None:
        """The `/$bunfs/root/...` path of the module starting at `lo`."""
        held = self._paths.get(id(src))
        return held[1].get(lo) if held else None

    def module_spans(self, src: str) -> list[tuple[int, int]] | None:
        """The modules `parse_module` filed for `src`, in order, if any."""
        return self._spans.get(id(src))

    def exports(self, src: str, lo: int, hi: int) -> list[str] | None:
        """Every name the module `src[lo:hi]` exports, or None when it does
        not parse or holds an `export*`, whose names it cannot list."""
        res = self._send("exports", src, lo, hi)
        if res.get("unreadable") or "error" in res or res["star"]:
            return None
        return res["names"]

    def export_binding(
        self, src: str, lo: int, hi: int, name: str
    ) -> tuple[str | None, str | None] | None:
        """How the module `src[lo:hi]` exports `name`: (local, from), `from`
        being the path of a re-export and None for a local binding, `local`
        None when it names no binding. None when the module does not parse
        or does not list the name."""
        res = self._send("exports", src, lo, hi)
        if res.get("unreadable") or "error" in res:
            return None
        found = res["bindings"].get(name)
        if found is None:
            return None
        return found[0], found[1]

    def loads(self, src: str, lo: int, hi: int) -> list[str] | None:
        """The file names the module `src[lo:hi]` loads whole (`import(f)`,
        `require(f)`, `import*as N from f`, `export*from f`, `f` a literal),
        holding "*" when it may load a file it cannot name, or None when it
        does not parse."""
        key = ("loads", id(src), lo)
        if key not in self._answers:
            res = self._send("loads", src, lo, hi)
            self._answers[key] = {
                "files": None if res.get("unreadable") else res["files"]
            }
        cached = self._answers[key]
        assert cached is not None
        return cached["files"]

    def namespace(
        self, src: str, lo: int, hi: int, file: str, name: str
    ) -> dict[str, Any]:
        """Whether every whole load of `file` in the module `src[lo:hi]`
        reads only exports other than `name`, by name (the helper's
        `namespace` op): {"safe": True, "trusted": [...], "thenable": bool}
        or {"safe": False, "reason": ..., "at": offset in `src` or None}."""
        key = ("namespace", id(src), lo, file, name)
        cached = self._answers.get(key)
        if cached is not None:
            return cached
        res = self._send("namespace", src, lo, hi, file=file, name=name)
        if res.get("unreadable"):
            answer: dict[str, Any] = {
                "safe": False,
                "reason": "the module holds a character outside the BMP",
                "at": None,
            }
        elif res["safe"]:
            answer = {
                "safe": True,
                "trusted": res["trusted"],
                "thenable": res["thenable"],
            }
        else:
            at = res.get("at")
            answer = {
                "safe": False,
                "reason": res["reason"],
                "at": None if at is None else at + lo,
            }
        self._answers[key] = answer
        return answer

    def keys_used(
        self, src: str, name: str, spans: list[tuple[int, int]] | None = None
    ) -> bool:
        """Whether any module of `src` reads `name` by name as a property:
        `x.name`, `x["name"]`, or a destructured key. A computed read with
        any other key is not seen. The modules are those `parse_module`
        filed for `src`, else `spans`. A module that does not parse reads
        every name."""
        key = ("keys", id(src), name)
        cached = self._answers.get(key)
        if cached is None:
            cached = {"used": False}
            for lo, hi in self._spans.get(id(src)) or spans or [(0, len(src))]:
                res = self._send("keys_used", src, lo, hi, names=[name])
                if res.get("unreadable") or res["used"]:
                    cached["used"] = True
                    break
            self._answers[key] = cached
        return cached["used"]

    def binding(
        self, src: str, lo: int, hi: int, name: str, offset: int | None
    ) -> dict[str, Any] | None:
        """The variable `name` read at `offset` resolves to in the module
        `src[lo:hi]`, or its module-scope variable when `offset` is None.

        Offsets in and out are positions in `src`. None when the name is
        undeclared there or the module does not parse, and for a module
        holding a character outside the Basic Multilingual Plane, where the
        helper's UTF-16 offsets stop matching Python's (a bundle read as
        latin1 never holds one). Answers are memoized per reader.
        """
        key = ("binding", id(src), lo, name, offset)
        if key in self._answers:
            return self._answers[key]
        res = self._query("binding", src, lo, hi, name, offset)
        answer = None
        if res.get("found") and res["kind"] == "import":
            answer = {"kind": "import", "imported": res["imported"]}
        elif res.get("found"):
            answer = {
                "kind": res["kind"],
                "defs": [(t, n + lo, s + lo, top) for t, n, s, top in res["defs"]],
                "writes": [(w + lo, top) for w, top in res["writes"]],
            }
        self._answers[key] = answer
        return answer

    def writes(
        self, src: str, lo: int, hi: int, name: str, offset: int
    ) -> dict[str, Any] | None:
        """Every place that may change the variable `name` read at `offset`
        resolves to in the module `src[lo:hi]`, from the AST: `writes` and
        `mutations`, each a list of (kind, offset, top), and `declares`,
        whether `offset` names a plain declarator of it. None whenever
        `binding` would be, and for a module that calls `eval` directly.
        """
        key = ("writes", id(src), lo, name, offset)
        if key in self._answers:
            return self._answers[key]
        res = self._query("writes", src, lo, hi, name, offset)
        answer = None
        if res.get("found"):
            answer = {
                "declares": bool(res["declares"]),
                **{
                    field: [(k, w + lo, top) for k, w, top in res[field]]
                    for field in ("writes", "mutations")
                },
            }
        self._answers[key] = answer
        return answer

    def _query(
        self, op: str, src: str, lo: int, hi: int, name: str, offset: int | None
    ) -> dict[str, Any]:
        """Ask `op` about `name` in the module `src[lo:hi]`, sending the
        module's text when the helper does not hold it."""
        fields: dict[str, Any] = {"name": name}
        fields.update({"top": True} if offset is None else {"offset": offset - lo})
        res = self._send(op, src, lo, hi, **fields)
        return {"found": False} if res.get("unreadable") else res

    def _send(
        self, op: str, src: str, lo: int, hi: int, **fields: Any
    ) -> dict[str, Any]:
        """Ask `op` about the module `src[lo:hi]`, sending its text when the
        helper does not hold it. `unreadable` when the module holds a
        character outside the BMP, where offsets stop matching."""
        fields["module"] = self._module_key(src, lo, hi)
        res = self.request(op, **fields)
        if res.get("need_source"):
            text = src[lo:hi]
            if any(ord(c) > 0xFFFF for c in text):
                return {"unreadable": True}
            res = self.request(op, source=text, **fields)
        return res

    @property
    def lookups(self) -> int:
        """Distinct binding lookups answered so far."""
        return sum(key[0] == "binding" for key in self._answers)

    @property
    def write_lookups(self) -> int:
        """Distinct writes lookups answered so far."""
        return sum(key[0] == "writes" for key in self._answers)

    @property
    def flow_lookups(self) -> int:
        """Distinct flow lookups answered so far."""
        return sum(key[0] == "flow" for key in self._answers)

    def _module_key(self, src: str, lo: int, hi: int) -> str:
        """A name for the module the helper caches it under. `src` is held
        here, so its id is not reused while the key stands."""
        held = (id(src), lo, hi)
        if held not in self._keys:
            digest = hashlib.sha256(src[lo:hi].encode("utf-8", "surrogatepass"))
            self._keys[held] = (src, f"{hi - lo}:{digest.hexdigest()[:16]}")
        return self._keys[held][1]

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
