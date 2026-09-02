"""Does this check actually FAIL without the fix?

A test that passes both with and without the fix proves nothing. This patches a
target file to disable the fix, runs the check, restores the file, runs the
check again, and reports whether the two arms genuinely differ.

Consolidated from five source-run variants, four of which were broken. The
fixed semantics are these, and each one is a defect that shipped:

1. THE ARMS MUST DIFFER, on an extracted SIGNAL rather than on raw output.
   Raw stdout differs almost every run on noise alone (`Ran 1 test in 0.003s`),
   so a raw-output comparison would always pass and would silently defeat the
   whole check. Four of five source failures were both arms exiting 127
   identically and reporting a confident "NOT DISCRIMINATING".

2. THE SIGNAL MUST APPEAR IN AT LEAST ONE ARM. A pattern that matches in
   neither arm is not a negative result, it is a check that never ran. This is
   the assertion that catches source failures 3 and 4, where a `D:/...` path
   handed to bash resolved nowhere and the grep found nothing in either arm.

3. THE PATCH MUST HAVE APPLIED. The anchor must occur exactly once, the patched
   bytes must differ from the original, and the patched bytes must be what is
   actually on disk before the arm runs.

4. RESTORE FROM SAVED BYTES, NEVER FROM VERSION CONTROL. This script never
   invokes git to restore. `git checkout --` is correct only when the code under
   test is already committed and is actively destructive otherwise: source
   failure 5 reverted the uncommitted fix it was verifying, so the "with fix"
   arm ran without it and the work was destroyed. The pre-patch bytes are
   written to a SIDECAR FILE ON DISK before anything is mutated, so a kill
   between patch and restore leaves a recoverable copy rather than nothing. The
   restore is then VERIFIED by byte comparison; "I restored it" is not evidence.

An uncommitted target is a loud WARNING rather than a failure. Committing first
is the doctrine's own cheap mitigation for restoring badly, and the sidecar plus
the verified restore is the enforcement.

Usage:
    discriminate.py --config <path> [--keep-backup]

Exit: 0 DISCRIMINATING; 1 NOT DISCRIMINATING; 2 HARNESS BROKEN or a precondition
failed. The 1/2 split is the point: "the check does not discriminate" and "the
harness never ran" are different findings, and conflating them is what produced
four confident wrong verdicts.

Config (JSON):
    {
      "target":      "/d/worktrees/repo/hooks/run-hook.sh",
      "anchor":      "  interp_base=\"${interp_base##*\\\\}\"",
      "replacement": "  : # split disabled for the discrimination check",
      "check": {
        "argv":    ["bash", "hooks/run-hook.test.sh"],
        "cwd":     "/d/worktrees/repo",
        "timeout": 900
      },
      "signal": {"regex": "^(PASS|FAIL): a native Windows interpreter path.*$"},
      "expect": {"negative_contains": "FAIL:", "positive_contains": "PASS:"}
    }

    `anchor_file` and `replacement_file` may be used instead, for content awkward
    to embed. With no `signal`, the signal is the check's exit code and the
    expectation is non-zero without the fix and zero with it.

    `argv` is handed straight to the operating system and is deliberately NOT
    rewritten: a bash check needs MSYS paths in its arguments and a native check
    needs native ones, so rewriting would break whichever the caller meant. Name
    the check RELATIVE to `cwd`, which this harness does resolve, rather than
    embedding an absolute path in either spelling.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

import pathfix

BACKUP_SUFFIX = ".discriminate-backup"


def note(message: str | None) -> None:
    if message:
        print(f"NOTE: {message}", file=sys.stderr)


class HarnessError(Exception):
    """The harness could not run, or could not have measured what it claims."""


def load_bytes(config: dict[str, object], key: str, base: pathlib.Path) -> bytes:
    inline = config.get(key)
    from_file = config.get(f"{key}_file")
    if inline is not None and from_file is not None:
        raise HarnessError(f"config sets both {key!r} and {key}_file; pick one")
    if inline is not None:
        if not isinstance(inline, str):
            raise HarnessError(f"config {key!r} must be a string")
        return inline.encode("utf-8")
    if from_file is None:
        raise HarnessError(f"config must set either {key!r} or {key}_file")
    path, conversion = pathfix.resolve_existing(str(from_file))
    note(conversion)
    if not path.is_absolute():
        path = base / path
    if not path.is_file():
        raise HarnessError(pathfix.spellings_message(f"{key}_file", str(from_file)))
    return path.read_bytes()


def run_check(check: dict[str, object]) -> subprocess.CompletedProcess[str]:
    argv = check.get("argv")
    if not isinstance(argv, list) or not argv:
        raise HarnessError("config `check.argv` must be a non-empty list")
    # `cwd` is handed to the OS process launcher, so on Windows it needs the
    # NATIVE spelling. `argv` is deliberately left untouched: argv[0] is usually
    # bash, and bash needs the MSYS spelling for its own arguments. Converting
    # both would break one of them, and this is the one place the two rules meet.
    cwd = check.get("cwd")
    resolved_cwd: str | None = None
    if cwd:
        cwd_path, conversion = pathfix.resolve_existing(str(cwd))
        note(conversion)
        if not cwd_path.is_dir():
            raise HarnessError(pathfix.spellings_message("check.cwd", str(cwd)))
        resolved_cwd = str(cwd_path)
    try:
        return subprocess.run(  # noqa: S603 - argv is caller-declared, never a shell string
            [str(item) for item in argv],
            cwd=resolved_cwd,
            capture_output=True,
            text=True,
            timeout=int(check.get("timeout", 900)),
            check=False,
        )
    except FileNotFoundError as error:
        # A check that could not be LAUNCHED is a broken harness, not a failing
        # arm. Letting the OSError escape as a traceback would strand the caller
        # with no verdict at all, and the restore still runs either way because
        # the caller wraps this in a finally.
        raise HarnessError(
            f"the check command could not be launched: {argv[0]!r} ({error}). Nothing was "
            f"measured. On a mixed MSYS and native-Windows host, remember that argv is "
            f"handed straight to the OS: a bash check needs MSYS paths in its arguments, "
            f"and a native check needs native ones. This harness deliberately does not "
            f"rewrite argv, because rewriting it would break whichever of the two the "
            f"caller actually meant."
        ) from None
    except subprocess.TimeoutExpired as error:
        raise HarnessError(
            f"the check command timed out after {error.timeout}s. A timeout in one arm and "
            f"not the other would look like discrimination, so this is refused rather than "
            f"scored."
        ) from None


def combined(result: subprocess.CompletedProcess[str]) -> str:
    return result.stdout + result.stderr


def extract_signal(
    pattern: re.Pattern[str] | None, result: subprocess.CompletedProcess[str]
) -> str | None:
    if pattern is None:
        return f"rc={result.returncode}"
    found = pattern.search(combined(result))
    return found.group(0) if found else None


def last_line(text: str) -> str:
    lines = text.strip().splitlines()
    return lines[-1] if lines else "(no output)"


def warn_uncommitted(target: pathlib.Path) -> None:
    """Rule 5, reported rather than enforced: committing first makes an
    accidental clobber recoverable, and it costs nothing. The enforcement that
    actually protects the file is the sidecar and the verified restore."""
    # `-C` changes directory, it does not isolate. An inherited absolute GIT_DIR
    # overrides repository discovery and GIT_CONFIG replaces the file git reads,
    # so an ambient environment would make this warning describe a different
    # repository than the one holding the target.
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in {"GIT_DIR", "GIT_WORK_TREE", "GIT_CONFIG"}
    }
    try:
        result = subprocess.run(
            ["git", "-C", str(target.parent), "status", "--porcelain", "--", target.name],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
            env=environment,
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(f"HARNESS WARNING: cannot ask git about {target}: {error}", file=sys.stderr)
        return
    if result.returncode != 0:
        print(
            f"HARNESS WARNING: {target} is not inside a git working tree, so this run "
            f"cannot confirm the code under test is committed.",
            file=sys.stderr,
        )
        return
    if result.stdout.strip():
        print(
            f"HARNESS WARNING: {target} has uncommitted changes. Committing before "
            f"verifying is the cheapest way to make an accidental clobber recoverable. "
            f"This run restores from saved bytes and never from git, so the uncommitted "
            f"work is safe here, but commit it anyway.",
            file=sys.stderr,
        )


def verdict(code: int, headline: str, detail: str) -> int:
    print(f"\nVERDICT: {headline}")
    print(detail)
    return code


def main() -> int:
    parser = argparse.ArgumentParser(description="Prove a check fails without the fix.")
    parser.add_argument("--config", required=True)
    parser.add_argument(
        "--keep-backup",
        action="store_true",
        help="keep the pre-patch sidecar even after the restore verifies",
    )
    args = parser.parse_args()

    config_path, conversion = pathfix.resolve_existing(args.config)
    note(conversion)
    if not config_path.is_file():
        raise HarnessError(pathfix.spellings_message("the config", args.config))
    config_path = config_path.resolve()
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise HarnessError(f"{config_path} is not valid JSON: {error}") from None
    base = config_path.parent

    given_target = str(config.get("target", ""))
    target, conversion = pathfix.resolve_existing(given_target)
    note(conversion)
    if not target.is_absolute():
        target = base / target
    if not target.is_file():
        raise HarnessError(pathfix.spellings_message("target", given_target))

    check = config.get("check")
    if not isinstance(check, dict):
        raise HarnessError("config `check` must be an object with an `argv` list")

    signal_config = config.get("signal")
    pattern: re.Pattern[str] | None = None
    if signal_config is not None:
        if not isinstance(signal_config, dict) or "regex" not in signal_config:
            raise HarnessError("config `signal` must be an object with a `regex`")
        pattern = re.compile(str(signal_config["regex"]), re.MULTILINE)

    expect = config.get("expect") or {}

    original = target.read_bytes()
    anchor = load_bytes(config, "anchor", base)
    replacement = load_bytes(config, "replacement", base)

    occurrences = original.count(anchor)
    if occurrences != 1:
        hint = ""
        if occurrences == 0 and b"\r\n" in original and b"\r\n" not in anchor:
            hint = (
                " The target has CRLF line endings and the anchor does not. On a checkout "
                "with core.autocrlf=true that alone is enough to miss."
            )
        raise HarnessError(
            f"the anchor occurs {occurrences} times in {target}; it must occur exactly "
            f"once, or the patch is ambiguous and the arms would not test what you "
            f"think.{hint}"
        )

    patched = original.replace(anchor, replacement)
    if patched == original:
        raise HarnessError(
            "the patch changed nothing: the replacement is byte-identical to the anchor. "
            "A patch that silently applied nothing makes both arms the same run, which is "
            "how a harness reports a confident verdict about a check it never varied."
        )

    if config.get("backup_dir"):
        backup_dir, conversion = pathfix.resolve_existing(str(config["backup_dir"]))
        note(conversion)
    else:
        backup_dir = target.parent
    backup = backup_dir / (target.name + BACKUP_SUFFIX)
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_bytes(original)
    if backup.read_bytes() != original:
        raise HarnessError(
            f"the pre-patch sidecar at {backup} does not match the target's bytes. "
            f"Refusing to mutate {target} without a verified copy to restore from."
        )

    warn_uncommitted(target)

    negative: subprocess.CompletedProcess[str] | None = None
    restore_failure: str | None = None
    try:
        target.write_bytes(patched)
        if target.read_bytes() != patched:
            raise HarnessError(
                f"the patched bytes did not reach disk at {target}; the negative arm would "
                f"have run against the unpatched file and reported a false 'not "
                f"discriminating'."
            )
        negative = run_check(check)
    finally:
        target.write_bytes(original)
        if target.read_bytes() != original:
            restore_failure = (
                f"RESTORE FAILED. {target} does not match its pre-patch bytes. The saved "
                f"copy is at {backup.resolve()}; restore it by hand before doing anything "
                f"else in this tree."
            )
            # Printed here as well as raised below, because an exception already in
            # flight would otherwise swallow the one message that names the sidecar.
            print(f"HARNESS FAIL: {restore_failure}", file=sys.stderr)
        elif not args.keep_backup:
            # Removed HERE rather than after the try, so a check that could not be
            # launched does not strand a *.discriminate-backup beside a source file
            # in a live worktree, where the next `git add -A` would sweep it up. The
            # copy is kept for exactly the one case that needs it: a restore that
            # did not verify.
            backup.unlink(missing_ok=True)

    if restore_failure is not None:
        raise HarnessError(restore_failure)

    assert negative is not None
    positive = run_check(check)

    negative_signal = extract_signal(pattern, negative)
    positive_signal = extract_signal(pattern, positive)

    print(f"WITHOUT the fix (patched)  : rc={negative.returncode} "
          f"signal={negative_signal!r} last={last_line(combined(negative))!r}")
    print(f"WITH the fix (restored)    : rc={positive.returncode} "
          f"signal={positive_signal!r} last={last_line(combined(positive))!r}")
    print(f"restore verified byte-identical: {target.read_bytes() == original}")

    if 127 in (negative.returncode, positive.returncode):
        arms = [
            name
            for name, result in (("negative", negative), ("positive", positive))
            if result.returncode == 127
        ]
        return verdict(
            2,
            "HARNESS BROKEN",
            f"the check command exited 127 (command not found) in the {', '.join(arms)} arm(s). "
            f"Under MSYS that is what a D:/... path handed to bash produces, and it is how "
            f"four of the five source-run harnesses reported a confident verdict for a check "
            f"that never ran. Hand bash a /d/... path.",
        )

    if negative_signal is None and positive_signal is None:
        return verdict(
            2,
            "HARNESS BROKEN",
            "the signal pattern matched in NEITHER arm, so this run observed nothing. An "
            "absent signal in both arms is not a negative result, it is a check that never "
            "ran. Verify the check command actually executes and that the pattern matches "
            "its real output.",
        )

    negative_ok = (
        expect["negative_contains"] in (negative_signal or "")
        if "negative_contains" in expect
        else negative.returncode != 0
    )
    positive_ok = (
        expect["positive_contains"] in (positive_signal or "")
        if "positive_contains" in expect
        else positive.returncode == 0
    )

    if negative_signal == positive_signal:
        # Identical arms split on WHETHER THE SHARED OUTCOME IS A FAILURE, and the
        # split is the whole point. Two arms that both FAILED the same way are
        # indistinguishable from two arms that never ran: 127 is only the most
        # visible spelling of that, and with no `signal` regex the signal is the
        # exit code, so any shared non-zero code lands here. Scoring it as a
        # discrimination verdict would be a confident claim about a check that may
        # never have executed. Two arms that both PASSED are a different and
        # genuinely knowable finding: the check cannot fail.
        if negative_ok:
            return verdict(
                2,
                "HARNESS BROKEN",
                f"both arms produced the IDENTICAL FAILING signal {negative_signal!r}. This "
                f"harness cannot tell a check that fails the same way with and without the "
                f"patch from a check that never ran at all, so it refuses to score either. "
                f"The patch itself WAS verified applied on disk, so that is not the cause. "
                f"Confirm the check command executes and that it exercises the patched code "
                f"path, then re-run.",
            )
        return verdict(
            1,
            "NOT DISCRIMINATING (the arms did not differ)",
            f"both arms produced the IDENTICAL PASSING signal {negative_signal!r}. The check "
            f"passes whether the fix is present or not, so it proves nothing about it. The "
            f"patch WAS verified applied on disk, so this is not a patch that failed to land.",
        )

    if negative_ok and positive_ok:
        return verdict(
            0,
            "DISCRIMINATING",
            "the check failed without the fix, passed with it, and the two arms differ.",
        )
    if not negative_ok:
        return verdict(
            1,
            "NOT DISCRIMINATING",
            "the check did NOT fail with the fix disabled, so it passes whether the fix is "
            "present or not and proves nothing about it.",
        )
    return verdict(
        1,
        "NOT DISCRIMINATING",
        "the check failed WITH the fix present, so the check itself is broken independently "
        "of the fix under test.",
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HarnessError as failure:
        print(f"HARNESS FAIL: {failure}", file=sys.stderr)
        raise SystemExit(2) from None
