"""Executes the guard contract in `guard_contract.py` against the real entry points.

Every assertion here exercises a fact a consumer is told to rely on, and fails
with the prose claim that just became false rather than a bare exit-code
mismatch. The refusal rows need no gh stub: a fail-closed guard rejects on
argument shape alone, before any network call. The effect rows run offline
against a throwaway state directory, and the predicate rows call the classifier
directly because their conditions are boolean expressions over fetched API data
that no argument shape can express.

The contract's markdown rendering in `../reference/guard-contract.md` is what
consumers cite; `GeneratedDocIsCurrent` is what keeps it honest.
"""

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import UTC, datetime, timedelta

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_resolve_thread  # noqa: E402
import guard_contract as contract  # noqa: E402

BASH = shutil.which("bash")


def invoke(entry_point: str, argv: tuple[str, ...]) -> subprocess.CompletedProcess[str]:
    """Run an entry point the way an operator would -- wrapper via bash, CLI via Python."""
    target = contract.plugin_path(entry_point)
    command = (
        [BASH, str(target), *argv]
        if entry_point.startswith("bin/")
        else [sys.executable, str(target), *argv]
    )
    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        # A foreign cwd proves the wrappers' self-location, and keeps a stray
        # repo-relative default from being read as a guard holding.
        cwd=tempfile.gettempdir(),
    )


def envelope(proc: subprocess.CompletedProcess[str]) -> dict[str, object]:
    """The engine's JSON refusal envelope, or {} when the refusal never reached Python."""
    if not proc.stdout.strip():
        return {}
    try:
        parsed = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def state_fingerprint(state_dir: pathlib.Path) -> dict[str, bytes]:
    """Durable state contents, ignoring the advisory .lock files every run creates."""
    return {
        str(path.relative_to(state_dir)): path.read_bytes()
        for path in sorted(state_dir.rglob("*"))
        if path.is_file() and path.suffix != ".lock"
    }


def observed_delta(before: dict[str, bytes], after: dict[str, bytes]) -> str:
    """Which way the state directory's file set moved.

    Directional, because a boolean cannot tell deletion from a rewrite: a reap
    that rewrote the expired lease instead of removing it would satisfy
    `before != after` and pass a row whose claim is deletion. Compared over the
    key set rather than named paths -- a path literal in a drift-detection
    artifact couples it to the writer's internal layout.
    """
    if before == after:
        return contract.UNCHANGED
    kept, arrived = set(before), set(after)
    if arrived > kept:
        return contract.ADDED
    if arrived < kept:
        return contract.REMOVED
    if arrived == kept:
        return contract.REWRITTEN
    return f"mixed: +{sorted(arrived - kept)} -{sorted(kept - arrived)}"


def seed(fixture: str, state_dir: pathlib.Path) -> None:
    if fixture == contract.EMPTY_STATE:
        return
    if fixture == contract.EXPIRED_WORKER_LEASE:
        # Acquire a real lease so the file shape stays the engine's, then age it
        # past expiry -- a hand-written record would drift from the writer.
        proc = invoke(
            contract.LEASE_CLI,
            (
                "acquire",
                "--scope",
                "worker",
                "--pr",
                "owner/repo#1",
                "--state-dir",
                str(state_dir),
            ),
        )
        if proc.returncode != 0:
            raise AssertionError(f"lease fixture setup failed: {proc.stderr}")
        lease_path = pathlib.Path(str(json.loads(proc.stdout)["path"]))
        record = json.loads(lease_path.read_text(encoding="utf-8"))
        stale = (datetime.now(UTC) - timedelta(days=1)).isoformat()
        record.update({"expires_at": stale, "updated_at": stale})
        lease_path.write_text(json.dumps(record), encoding="utf-8")
        return
    raise AssertionError(f"unknown fixture: {fixture}")


def write_gh_shim(directory: pathlib.Path, sentinel: pathlib.Path) -> None:
    """A `gh` that records the fact it ran and then fails.

    Exit 127 mimics the not-found status a caller is most likely to swallow, so
    a guard that resolved `@me` before checking scope reaches the same refusal
    exit code -- and is caught by the sentinel rather than by the exit code.
    """
    posix = directory / "gh"
    posix.write_text(
        f'#!/usr/bin/env bash\nprintf called > "{sentinel.as_posix()}"\nexit 127\n',
        encoding="utf-8",
        newline="\n",
    )
    posix.chmod(0o755)
    if os.name == "nt":
        # Windows resolves a bare `gh` through PATHEXT, never the extensionless
        # file above, so the shim needs a .cmd sibling to be reachable at all.
        (directory / "gh.cmd").write_text(
            f'@echo off\r\n(echo called) > "{sentinel}"\r\nexit /b 127\r\n',
            encoding="utf-8",
            newline="",
        )


def because(row_id: str, claim: str, detail: str = "") -> str:
    suffix = f"\n  observed: {detail}" if detail else ""
    return (
        f"\nGUARD CONTRACT ROW `{row_id}` NO LONGER HOLDS."
        f"\n  claim: {claim}"
        f"\n  Fix the guard, or update the row in scripts/tests/guard_contract.py and"
        f" regenerate reference/guard-contract.md."
        f"{suffix}"
    )


class RefusalsFireOnArgumentShape(unittest.TestCase):
    def test_every_refusal_row(self) -> None:
        for row in contract.REFUSALS:
            with self.subTest(row=row.id):
                if row.entry_point.startswith("bin/") and BASH is None:
                    self.skipTest("bash unavailable; wrapper rows need it")
                with tempfile.TemporaryDirectory() as tmp:
                    argv = tuple(arg.format(state_dir=tmp) for arg in row.argv)
                    proc = invoke(row.entry_point, argv)
                payload = envelope(proc)
                message = str(payload.get("error", ""))
                combined = "\n".join((message, proc.stdout, proc.stderr))
                self.assertEqual(
                    proc.returncode,
                    row.exit_code,
                    because(row.id, row.claim, f"exit {proc.returncode}: {combined[:400]}"),
                )
                for token in row.error_contains:
                    self.assertIn(
                        token, combined, because(row.id, row.claim, combined[:400])
                    )
                for key, value in row.envelope_fields:
                    self.assertIn(
                        key, payload, because(row.id, row.claim, f"no `{key}` in the envelope")
                    )
                    self.assertEqual(
                        payload[key],
                        value,
                        because(row.id, row.claim, f"{key}={payload[key]!r}"),
                    )
                if row.entry_point.startswith("bin/"):
                    # The observable bash-vs-Python discriminator: a wrapper-level
                    # refusal never reaches the interpreter, so it emits no envelope.
                    if row.refused_by == contract.BASH_WRAPPER:
                        self.assertEqual(
                            payload,
                            {},
                            because(row.id, row.claim, "a JSON envelope was emitted"),
                        )
                        self.assertTrue(
                            proc.stderr.strip(),
                            because(row.id, row.claim, "no stderr from the wrapper"),
                        )
                    else:
                        self.assertNotEqual(
                            payload,
                            {},
                            because(row.id, row.claim, "no JSON envelope: bash refused"),
                        )

    def test_scope_refusal_precedes_every_network_call(self) -> None:
        # The rows claiming "no gh invocation at all" are replayed against a
        # recording shim rather than an emptied PATH. Emptying PATH proves only
        # that the refusal survives gh being unreachable -- a swallowed lookup
        # failure falling through to the same exit code would pass it while the
        # claim stayed false. The shim is the only executable on PATH, so any
        # attempt to resolve `@me` leaves a sentinel behind.
        rows = [row for row in contract.REFUSALS if row.gh_free]
        self.assertTrue(rows, "no refusal row claims network-free refusal")
        for row in rows:
            with self.subTest(row=row.id):
                if BASH is None:
                    self.skipTest("bash unavailable; the gh shim needs it")
                with tempfile.TemporaryDirectory() as tmp:
                    shim_dir = pathlib.Path(tmp)
                    sentinel = shim_dir / "gh-was-called"
                    write_gh_shim(shim_dir, sentinel)
                    env = dict(os.environ, PATH=str(shim_dir))
                    proc = subprocess.run(
                        [
                            sys.executable,
                            str(contract.plugin_path(row.entry_point)),
                            *row.argv,
                        ],
                        capture_output=True,
                        text=True,
                        env=env,
                        cwd=tempfile.gettempdir(),
                    )
                    called = sentinel.exists()
                self.assertFalse(
                    called,
                    because(row.id, row.claim, "the gh shim was invoked"),
                )
                self.assertEqual(
                    proc.returncode,
                    row.exit_code,
                    because(row.id, row.claim, f"exit {proc.returncode}: {proc.stderr[:400]}"),
                )
                payload = envelope(proc)
                for key, value in row.envelope_fields:
                    self.assertEqual(
                        payload.get(key),
                        value,
                        because(row.id, row.claim, f"{key}={payload.get(key)!r}"),
                    )


class PredicatesHoldOverRuntimeData(unittest.TestCase):
    def test_every_predicate_row(self) -> None:
        for row in contract.PREDICATES:
            with self.subTest(row=row.id):
                observed = babysit_resolve_thread.classify(dict(row.thread), **row.flags)
                self.assertEqual(
                    observed,
                    row.expected,
                    because(row.id, row.claim, f"classify returned {observed!r}"),
                )

    def test_anchor_symbol_exists(self) -> None:
        # The anchors are the contract's substitute for line numbers; a rename
        # must fail here rather than leave the doc pointing at nothing.
        for row in contract.PREDICATES:
            module, _, symbol = row.enforced_at.partition("::")
            with self.subTest(row=row.id):
                self.assertEqual(module, "babysit_resolve_thread.py")
                self.assertTrue(
                    hasattr(babysit_resolve_thread, symbol),
                    because(row.id, row.claim, f"no symbol named {symbol!r}"),
                )


class EffectsReachDiskAsClaimed(unittest.TestCase):
    def test_every_effect_row(self) -> None:
        for row in contract.EFFECTS:
            with self.subTest(row=row.id):
                with tempfile.TemporaryDirectory() as tmp:
                    state_dir = pathlib.Path(tmp)
                    seed(row.fixture, state_dir)
                    before = state_fingerprint(state_dir)
                    argv = tuple(arg.format(state_dir=tmp) for arg in row.argv)
                    proc = invoke(row.entry_point, argv)
                    after = state_fingerprint(state_dir)
                self.assertEqual(
                    proc.returncode,
                    row.exit_code,
                    because(row.id, row.claim, f"exit {proc.returncode}: {proc.stderr[:400]}"),
                )
                self.assertEqual(
                    observed_delta(before, after),
                    row.delta,
                    because(
                        row.id,
                        row.claim,
                        f"observed {observed_delta(before, after)!r}",
                    ),
                )


class MechanismsMatchTheSource(unittest.TestCase):
    def test_every_mechanism_row(self) -> None:
        for row in contract.MECHANISMS:
            with self.subTest(row=row.id):
                source = contract.plugin_path(row.entry_point).read_text(encoding="utf-8")
                for token in row.must_contain:
                    self.assertIn(
                        token, source, because(row.id, row.claim, f"{token!r} is absent")
                    )
                for token in row.must_not_contain:
                    self.assertNotIn(
                        token, source, because(row.id, row.claim, f"{token!r} appeared")
                    )


class EntryPointCatalogueIsComplete(unittest.TestCase):
    def test_every_executable_script_is_classified(self) -> None:
        # A new entry point must arrive with its mutation classification, or a
        # consumer's permission rule silently has no row to cite for it.
        catalogued = {entry.path for entry in contract.ENTRY_POINTS}
        present = {
            f"skills/babysit-prs/scripts/{path.name}"
            for path in contract.SCRIPTS.glob("*.py")
            if "__main__" in path.read_text(encoding="utf-8")
        }
        # The lane is not confined to the skill's own scripts directory: SKILL.md
        # invokes the plugin-level readiness gate by name, and a shell entry point
        # there would otherwise evade this gate entirely.
        present |= {
            f"scripts/{path.name}"
            for path in (contract.PLUGIN_ROOT / "scripts").glob("babysit-*.sh")
            if not path.name.endswith(".test.sh")
        }
        self.assertEqual(
            present - catalogued,
            set(),
            "entry points with no guard-contract classification; add them to"
            " ENTRY_POINTS in scripts/tests/guard_contract.py",
        )
        self.assertEqual(catalogued - present, set(), "classified scripts that no longer exist")

    def test_every_wrapper_is_classified(self) -> None:
        wrappers = {
            f"bin/{path.name}"
            for path in (contract.PLUGIN_ROOT / "bin").iterdir()
            if path.is_file() and path.name.startswith("source-control-babysit-")
        }
        self.assertEqual(
            wrappers,
            {entry.wrapper for entry in contract.ENTRY_POINTS if entry.wrapper},
            "a babysit wrapper is missing from ENTRY_POINTS",
        )

    def test_classifications_cite_only_real_rows(self) -> None:
        known = {row.id for row in contract.REFUSALS}
        known |= {row.id for row in contract.PREDICATES}
        known |= {row.id for row in contract.EFFECTS}
        known |= {row.id for row in contract.MECHANISMS}
        for entry in contract.ENTRY_POINTS:
            for row_id in entry.backed_by:
                with self.subTest(entry=entry.path, row=row_id):
                    self.assertIn(row_id, known, "backed_by names a row that does not exist")

    def test_row_ids_are_unique(self) -> None:
        ids = [
            row.id
            for table in (
                contract.REFUSALS,
                contract.PREDICATES,
                contract.EFFECTS,
                contract.MECHANISMS,
                contract.DOC_COMMAND_SOURCES,
            )
            for row in table
        ]
        self.assertEqual(sorted(ids), sorted(set(ids)), "row IDs are citation anchors")

    def test_every_mutating_entry_point_is_backed(self) -> None:
        for entry in contract.ENTRY_POINTS:
            if entry.mutation == contract.READ_ONLY:
                continue
            with self.subTest(entry=entry.path):
                self.assertTrue(
                    entry.backed_by,
                    f"`{entry.path}` is classified {entry.mutation} with nothing asserting it",
                )

    def test_read_only_entry_points_cite_no_mutation_evidence(self) -> None:
        # The one direction of the Class column CI can bind offline. The reverse
        # -- proving a mutating class -- cannot be bound for the four entry
        # points whose mutation is a GitHub write, because every row here runs
        # without network access; the generated doc's "Not covered here" section
        # states that gap rather than letting the column read as proven.
        moves_state = {row.id for row in contract.EFFECTS if row.delta != contract.UNCHANGED}
        moves_state |= {row.id for row in contract.MECHANISMS}
        for entry in contract.ENTRY_POINTS:
            if entry.mutation != contract.READ_ONLY:
                continue
            with self.subTest(entry=entry.path):
                self.assertEqual(
                    set(entry.backed_by) & moves_state,
                    set(),
                    f"`{entry.path}` is classified read-only but cites rows asserting"
                    " a mutation; reclassify it or move the evidence",
                )


WRAPPER_COMMAND = re.compile(
    r'bash "\$\{CLAUDE_PLUGIN_ROOT\}/(bin/source-control-babysit-[a-z-]+)"'
)


def documented_commands(text: str) -> list[tuple[str, str]]:
    """Wrapper commands in a document, each paired with its argument tail.

    A command runs to the end of its inline-code span or fenced block, which
    prose wraps across lines, so the tail is truncated at the first blank line
    rather than the first newline. The truncation is done here instead of in the
    pattern: expressing the stop set as an alternation backtracks
    catastrophically on a document this size. A fenced block may hold several
    commands, so a tail also stops at the next wrapper invocation -- one greedy
    tail swallowing its successors would check the later commands' flags against
    the first command's CLI, or skip them entirely.
    """
    matches = list(WRAPPER_COMMAND.finditer(text))
    commands = []
    for index, match in enumerate(matches):
        limit = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        tail = text[match.end() : limit].split("`", 1)[0].split("\n\n", 1)[0]
        commands.append((match.group(1), " ".join(tail.split())))
    return commands


class DocumentedCommandsMatchTheParsers(unittest.TestCase):
    def _accepted_flags(self, cli: str) -> set[str]:
        """The parser's registered long options, read from its usage block only.

        Scraping the whole `--help` output would treat any flag NAMED IN PROSE as
        accepted: every one of these CLIs describes the broad `gh pr merge
        --admin` grant it exists to replace, so `--admin` would be admitted here
        while the parser exits 2 on it, and a document carrying that stale flag
        would pass. Argparse renders the usage block from the registered option
        strings and nothing else, so it -- not the description, not the help
        text -- is the registry. It runs from `usage:` to the first blank line.
        """
        proc = subprocess.run(
            [sys.executable, str(contract.plugin_path(cli)), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, f"{cli} --help failed: {proc.stderr}")
        self.assertTrue(
            proc.stdout.startswith("usage:"),
            f"{cli} --help does not open with a usage block; the registry moved",
        )
        usage = proc.stdout.split("usage:", 1)[1].split("\n\n", 1)[0]
        flags = set(re.findall(r"(?<![\w-])--[a-z0-9][a-z0-9-]*", usage))
        # `--help` is deliberately absent: argparse renders it as `-h` in usage.
        self.assertTrue(flags, f"{cli} usage block parsed to no long options")
        return flags

    def test_prose_only_flags_are_not_read_as_accepted(self) -> None:
        # The regression this parse exists to prevent, pinned: `--admin` appears
        # in the merge gate's description and is rejected by its parser.
        self.assertNotIn("--admin", self._accepted_flags(contract.MERGE_CLI))

    def test_every_documented_wrapper_command(self) -> None:
        accepted: dict[str, set[str]] = {}
        for row in contract.DOC_COMMAND_SOURCES:
            text = contract.plugin_path(row.doc).read_text(encoding="utf-8")
            commands = documented_commands(text)
            self.assertTrue(
                commands,
                because(row.id, row.claim, f"no wrapper command lines found in {row.doc}"),
            )
            for wrapper, tail in commands:
                with self.subTest(doc=row.doc, wrapper=wrapper):
                    self.assertTrue(
                        contract.plugin_path(wrapper).is_file(),
                        because(row.id, row.claim, f"{wrapper} does not exist"),
                    )
                    cli = contract.WRAPPER_BACKING_CLI[wrapper]
                    if cli not in accepted:
                        accepted[cli] = self._accepted_flags(cli)
                    for flag in re.findall(r"(?<![\w-])--[a-z0-9][a-z0-9-]*", tail):
                        self.assertIn(
                            flag,
                            accepted[cli],
                            because(
                                row.id,
                                row.claim,
                                f"{row.doc} spells `{flag}`, which {cli} does not accept",
                            ),
                        )

    def test_every_doc_naming_a_wrapper_is_covered(self) -> None:
        # A second document growing its own copy of a command line must be added
        # to DOC_COMMAND_SOURCES, not left unchecked.
        covered = {row.doc for row in contract.DOC_COMMAND_SOURCES}
        # The whole plugin, not just the babysit skill: a command line copied
        # into a command, agent, or sibling skill drifts exactly the same way.
        naming = {
            str(path.relative_to(contract.PLUGIN_ROOT)).replace("\\", "/")
            for path in contract.PLUGIN_ROOT.rglob("*.md")
            if WRAPPER_COMMAND.search(path.read_text(encoding="utf-8"))
        }
        self.assertEqual(
            naming - covered,
            set(),
            "documents spelling out wrapper command lines with no DOC_COMMAND_SOURCES row",
        )


class GeneratedDocIsCurrent(unittest.TestCase):
    def test_reference_doc_matches_the_tables(self) -> None:
        # splitlines(), not bytes: the checkout's line endings are not the claim.
        expected = contract.render_markdown().splitlines()
        actual = contract.GENERATED_DOC.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            actual,
            expected,
            "reference/guard-contract.md is stale -- regenerate it with"
            " `python tests/guard_contract.py --emit`",
        )


if __name__ == "__main__":
    unittest.main()
