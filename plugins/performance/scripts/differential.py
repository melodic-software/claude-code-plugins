"""Differential: prove behavior did not change, rather than asserting it.

A passing test suite is not a behavior proof. It proves nothing ASSERTED broke,
which is a different claim. This runs a PRE-CHANGE subject and a POST-CHANGE
subject over the same corpus, with the same argv and the same stdin, across
every combination of a caller-declared matrix, and requires BYTE-IDENTICAL
stdout and identical exit codes.

Cover every MODE the subject runs in. The source run's differential covered one
of two modes and missed a real behavior downgrade in the other, so the matrix is
a first-class input here rather than a loop the caller writes by hand.

Three refusals are enforced, each closing a way this could report a confident
wrong answer:

* Two arms that resolve to the SAME file. The differential would compare a file
  with itself and report parity for a comparison it never made.
* An arm that DISCLOSES ITS OWN PATH in stdout. Byte-exactness is only the right
  bar when the two arms cannot differ merely by living at different paths; a
  subject that prints a `__file__`-derived path fails that, and the mismatch
  would be an artifact of the harness's own layout. The check is on the observed
  output rather than on a same-directory rule, so two worktrees are a perfectly
  legal input as long as neither arm leaks where it lives.
* A run in which NEITHER arm ever produced output and both failed identically.
  That is not parity, it is a harness that never exercised the subject, and it
  is the exact shape that reads as a clean, confident, wrong verdict.

Usage:
    differential.py --baseline <path> --candidate <path> --config <path>
                    [--harvest-from <suite.py>] [--limit <n>]

Exit: 0 parity; 1 mismatches; 2 a precondition or harness failure.

Config (JSON):
    {
      "argv":  ["{{python}}", "{{subject}}", ["--mode", "{{mode}}"], "--root", "{{var:root}}"],
      "matrix": {"mode": ["engine-gate", "belt", null], "tool": ["Bash", "PowerShell"]},
      "vars":   {"root": "/d/worktrees/repo"},
      "corpus": ["git status --porcelain", "rm -rf /"],
      "stdin_json": {"tool_name": "{{tool}}", "tool_input": {"command": "{{corpus}}"}},
      "harvest": {"helpers": ["run_guard"], "arg_index": 0},
      "timeout": 120
    }

    Tokens are `{{python}}` (this interpreter), `{{subject}}` (the arm's path),
    `{{corpus}}` (the current corpus item), `{{var:NAME}}` (from `vars`), and
    `{{NAME}}` for each matrix dimension.

    A NESTED LIST inside `argv` is an optional group: it is dropped entirely when
    any token in it resolves to null, and spliced in otherwise. That is how a
    mode of `null` means "pass no --mode at all", which is the shape a caller
    gets by default and therefore the one a differential most needs to cover.
"""

from __future__ import annotations

import argparse
import ast
import itertools
import json
import pathlib
import re
import subprocess
import sys
from collections import Counter

import pathfix

TOKEN = re.compile(r"\{\{([A-Za-z0-9_:]+)\}\}")
WHOLE_TOKEN = re.compile(r"^\{\{([A-Za-z0-9_:]+)\}\}$")


class HarnessError(Exception):
    """A precondition failed, or the harness could not have measured anything."""


def resolve_token(name: str, bindings: dict[str, object]) -> object:
    if name.startswith("var:"):
        variables = bindings.get("__vars__")
        assert isinstance(variables, dict)
        if name[4:] not in variables:
            raise HarnessError(f"config references {{{{{name}}}}} but `vars` has no {name[4:]!r}")
        return variables[name[4:]]
    if name not in bindings:
        raise HarnessError(
            f"config references {{{{{name}}}}}, which is neither a matrix dimension "
            f"nor a built-in token. Known: {sorted(k for k in bindings if k != '__vars__')}"
        )
    return bindings[name]


def substitute(value: object, bindings: dict[str, object]) -> object:
    """Replace tokens. A string that is EXACTLY one token keeps the raw type."""
    if isinstance(value, str):
        whole = WHOLE_TOKEN.match(value)
        if whole:
            return resolve_token(whole.group(1), bindings)

        def replace(match: re.Match[str]) -> str:
            resolved = resolve_token(match.group(1), bindings)
            if resolved is None:
                raise HarnessError(
                    f"{{{{{match.group(1)}}}}} resolved to null inside the larger string "
                    f"{value!r}; null is only meaningful as a whole argv element or an "
                    f"optional argv group."
                )
            return str(resolved)

        return TOKEN.sub(replace, value)
    if isinstance(value, dict):
        return {key: substitute(item, bindings) for key, item in value.items()}
    if isinstance(value, list):
        return [substitute(item, bindings) for item in value]
    return value


def build_argv(template: list[object], bindings: dict[str, object]) -> list[str]:
    argv: list[str] = []
    for element in template:
        if isinstance(element, list):
            group = [substitute(item, bindings) for item in element]
            if any(item is None for item in group):
                continue
            argv.extend(str(item) for item in group)
            continue
        resolved = substitute(element, bindings)
        if resolved is None:
            raise HarnessError(
                f"argv element {element!r} resolved to null. Wrap it and its flag in a "
                f"nested list to make it an optional group, for example "
                f'["--mode", "{{{{mode}}}}"].'
            )
        argv.append(str(resolved))
    return argv


def harvest_from_suite(path: pathlib.Path, helpers: set[str], arg_index: int) -> list[str]:
    """Every string literal the suite hands positionally to a named helper.

    Harvesting from the suite means every shape the authors thought worth testing
    is covered. f-strings and concatenations are skipped deliberately: their
    runtime value depends on per-test fixtures this harness does not reproduce,
    and a wrong reconstruction would compare two arms on an input neither test
    ever ran.
    """
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute):
            name = func.attr
        elif isinstance(func, ast.Name):
            name = func.id
        else:
            continue
        if name not in helpers or len(node.args) <= arg_index:
            continue
        argument = node.args[arg_index]
        if isinstance(argument, ast.Constant) and isinstance(argument.value, str):
            found.append(argument.value)
    return found


def path_spellings(path: pathlib.Path) -> set[str]:
    """Every spelling of `path` a subject could plausibly print.

    Both the MSYS and the native forms are included: an arm invoked through a
    native Windows interpreter discloses `D:\\...` even when this harness was
    handed `/d/...`, and a leak the harness cannot recognize is a leak it will
    report as a legitimate mismatch.
    """
    literal = {str(path), path.as_posix(), str(path.resolve()), path.resolve().as_posix()}
    folded = {pathfix.native_to_msys(item) for item in literal}
    folded |= {pathfix.msys_to_native(item) for item in literal}
    return {item for item in literal | folded if item}


def run_one(argv: list[str], stdin: str | None, timeout: int) -> tuple[int, str, str]:
    completed = subprocess.run(  # noqa: S603 - argv is caller-declared, never a shell string
        argv,
        input=stdin if stdin is not None else "",
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    return completed.returncode, completed.stdout, completed.stderr


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--harvest-from")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    baseline, baseline_note = pathfix.resolve_existing(args.baseline)
    candidate, candidate_note = pathfix.resolve_existing(args.candidate)
    for note in (baseline_note, candidate_note):
        if note:
            print(f"NOTE: {note}", file=sys.stderr)
    for label, path, given in (
        ("baseline", baseline, args.baseline),
        ("candidate", candidate, args.candidate),
    ):
        if not path.is_file():
            raise HarnessError(pathfix.spellings_message(f"the {label}", given))
    if baseline.resolve() == candidate.resolve():
        raise HarnessError(
            f"the baseline and the candidate resolve to the same file ({baseline.resolve()}). "
            f"The differential would compare a file with itself and report parity for a "
            f"comparison it never made."
        )

    config_path, config_note = pathfix.resolve_existing(args.config)
    if config_note:
        print(f"NOTE: {config_note}", file=sys.stderr)
    if not config_path.is_file():
        raise HarnessError(pathfix.spellings_message("the config", args.config))
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise HarnessError(f"{config_path} is not valid JSON: {error}") from None
    argv_template = config.get("argv")
    if not isinstance(argv_template, list) or not argv_template:
        raise HarnessError("config `argv` must be a non-empty list")
    matrix: dict[str, list[object]] = config.get("matrix") or {}
    for dimension, values in matrix.items():
        if not isinstance(values, list) or not values:
            raise HarnessError(f"matrix dimension {dimension!r} must be a non-empty list")
    variables = config.get("vars") or {}
    stdin_template = config.get("stdin_json")
    timeout = int(config.get("timeout", 120))

    corpus: list[str] = []
    seen: set[str] = set()
    if args.harvest_from:
        harvest = config.get("harvest") or {}
        helpers = set(harvest.get("helpers") or [])
        if not helpers:
            raise HarnessError(
                "--harvest-from was given but config `harvest.helpers` is empty, so the "
                "harvest would silently contribute nothing."
            )
        suite_path, suite_note = pathfix.resolve_existing(args.harvest_from)
        if suite_note:
            print(f"NOTE: {suite_note}", file=sys.stderr)
        if not suite_path.is_file():
            raise HarnessError(pathfix.spellings_message("the harvest suite", args.harvest_from))
        harvested = harvest_from_suite(
            suite_path, helpers, int(harvest.get("arg_index", 0))
        )
        if not harvested:
            raise HarnessError(
                f"--harvest-from {args.harvest_from} yielded no literals for helpers "
                f"{sorted(helpers)}. An empty harvest that passed would claim coverage "
                f"the corpus does not have."
            )
        corpus.extend(harvested)
    corpus.extend(config.get("corpus") or [])
    corpus = [item for item in corpus if not (item in seen or seen.add(item))]
    if not corpus:
        raise HarnessError("the corpus is empty; there is nothing to compare")
    if args.limit > 0:
        corpus = corpus[: args.limit]

    dimensions = sorted(matrix)
    combinations = [
        dict(zip(dimensions, combo))
        for combo in itertools.product(*(matrix[name] for name in dimensions))
    ] or [{}]

    baseline_leaks = path_spellings(baseline)
    candidate_leaks = path_spellings(candidate)
    if baseline.resolve().parent != candidate.resolve().parent:
        baseline_leaks |= path_spellings(baseline.resolve().parent)
        candidate_leaks |= path_spellings(candidate.resolve().parent)

    mismatches: list[str] = []
    disclosures: list[str] = []
    results: dict[str, list[tuple[int, str]]] = {"baseline": [], "candidate": []}
    checked = 0
    stderr_differences = 0

    for combo in combinations:
        for command in corpus:
            bindings: dict[str, object] = dict(combo)
            bindings["__vars__"] = variables
            bindings["corpus"] = command
            bindings["python"] = sys.executable

            outcome: dict[str, tuple[int, str, str]] = {}
            for label, subject, leaks in (
                ("baseline", baseline, baseline_leaks),
                ("candidate", candidate, candidate_leaks),
            ):
                bindings["subject"] = str(subject)
                argv = build_argv(argv_template, bindings)
                stdin = (
                    json.dumps(substitute(stdin_template, bindings))
                    if stdin_template is not None
                    else None
                )
                code, out, err = run_one(argv, stdin, timeout)
                if code == 127:
                    raise HarnessError(
                        f"the {label} arm exited 127 (command not found) on argv {argv!r}. "
                        f"An arm that never ran cannot disprove a behavior change, and two "
                        f"arms failing this way identically read as parity."
                    )
                leaked = sorted(spelling for spelling in leaks if spelling and spelling in out)
                if leaked:
                    disclosures.append(
                        f"  {label} arm disclosed its own location {leaked[0]!r} in stdout "
                        f"for {command!r} with {combo}"
                    )
                outcome[label] = (code, out, err)
                results[label].append((code, out))

            checked += 1
            base_code, base_out, base_err = outcome["baseline"]
            cand_code, cand_out, cand_err = outcome["candidate"]
            # stderr is COUNTED but not compared for parity. Diagnostics carry
            # timings, paths and warnings that legitimately differ between two
            # copies, so failing on them would drown the signal. Reporting the
            # count is what keeps the verdict honest: "byte-identical stdout and
            # exit code" is a narrower claim than "behavior did not change", and a
            # reader cannot tell the difference if the gap is invisible.
            if base_err != cand_err:
                stderr_differences += 1
            if base_code != cand_code or base_out != cand_out:
                mismatches.append(
                    f"  {combo} command={command!r}\n"
                    f"    baseline  rc={base_code} out={base_out.strip()!r}\n"
                    f"    candidate rc={cand_code} out={cand_out.strip()!r}"
                )

    distinct = {label: len(set(rows)) for label, rows in results.items()}
    codes = {label: dict(Counter(code for code, _ in rows)) for label, rows in results.items()}

    print(f"corpus items         : {len(corpus)}")
    print(f"matrix combinations  : {len(combinations)}")
    print(f"invocations compared : {checked} (x2 arms = {checked * 2} runs)")
    print(f"distinct results     : baseline={distinct['baseline']} candidate={distinct['candidate']}")
    print(f"exit codes           : baseline={codes['baseline']} candidate={codes['candidate']}")

    never_exercised = all(
        not out and code != 0 for rows in results.values() for code, out in rows
    ) and distinct == {"baseline": 1, "candidate": 1}
    if never_exercised:
        raise HarnessError(
            "every invocation in BOTH arms produced empty stdout and the same non-zero exit "
            "code. That is not parity, it is a harness that never exercised the subject, and "
            "it is the shape that reads as a clean, confident, wrong verdict."
        )

    if disclosures:
        print(f"\nSELF-DISCLOSURE: {len(disclosures)}")
        for entry in disclosures[:10]:
            print(entry)
        raise HarnessError(
            "an arm printed its own path, so byte-identical stdout is not a valid bar here: "
            "the arms can differ purely by living at different paths. Place the two copies in "
            "one directory, or normalize the disclosed path, then re-run."
        )

    if mismatches:
        print(f"\nMISMATCHES: {len(mismatches)}")
        for entry in mismatches:
            print(entry)
        return 1

    print("\nPARITY: byte-identical stdout and exit code on every invocation.")
    if stderr_differences:
        print(
            f"SCOPE: stderr differed on {stderr_differences} of {checked} invocations and is "
            f"NOT part of the parity bar. Diagnostics carry timings and paths that two copies "
            f"legitimately differ on. This verdict covers stdout and the exit code; if stderr "
            f"is behavior for this subject, it is UNVERIFIED here."
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as failure:
        print(f"HARNESS FAIL: {failure}", file=sys.stderr)
        raise SystemExit(2) from None
