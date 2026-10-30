#!/usr/bin/env python3
"""Score the deterministic (D) and transcript (T) rubric items of one eval run.

Usage: python3 -I score-deterministic.py RESULT_DIR [--help]

RESULT_DIR is .work/devx/evals/results/<scenario>/<arm>/<model>/run-<n>/, written by
run-cell.sh. Supported scenarios: S1, S3-S7, T1, T3 (all arms; A2 adds the plugin-arm P
items), T2, T4, N1, S2, Q-build, Q-audit, NM-explain, NM-script (plugin arm), H-build,
H-audit (held out) and the sentinel runs. score.json also lists every Skill call. Writes
RESULT_DIR/score.json and prints it. Judge (J) items are listed as unscored.
Command checks run against a copy of the run's workspace, never the workspace itself.

Exit codes: 0 scored (a workspace that does not build fails its command items), 1 the
run is invalid or its files are missing, 2 usage or an unsupported scenario.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

TIMEOUT = 120


def load_events(path):
    events = []
    if not path.exists():
        return events
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    return events


def tool_uses(events):
    for event in events:
        if event.get("type") != "assistant":
            continue
        for block in event.get("message", {}).get("content", []) or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield block


def final_text(events):
    results = [e.get("result", "") for e in events if e.get("type") == "result"]
    return results[-1] if results else ""


def item(num, label, cls, grader, passed, evidence):
    return {"item": num, "check": label, "class": cls, "grader": grader,
            "pass": passed, "evidence": evidence}


def unscored(num, label, cls):
    return {"item": num, "check": label, "class": cls, "grader": "J", "pass": None,
            "evidence": "llm-judge item, not scored by this script"}


def run(cmd, cwd, env, stdin=subprocess.DEVNULL, timeout=TIMEOUT):
    try:
        proc = subprocess.run(cmd, cwd=cwd, env=env, stdin=stdin, capture_output=True,
                              text=True, timeout=timeout)
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return None, "", "timeout"


# ------------------------------------------------------------------------- sentinel


def score_sentinel(out, meta):
    token = (out / "sentinel.txt").read_text(encoding="utf-8").strip()
    events = load_events(out / "turn1.jsonl")
    answer = final_text(events)
    uses = list(tool_uses(events))
    init = meta.get("plugins", [])
    return [
        item(1, "Final answer contains the planted token", "P", "D", token in answer,
             f"token={token} answer={answer.strip()[:120]!r}"),
        item(2, "No tool call in the run (the token came from loaded context)", "P", "T",
             not uses, f"tool_use count={len(uses)}"),
        item(3, "Init plugins are built-in cc-plugin-* only", "P", "D",
             all(str(p).startswith("cc-plugin-") for p in init), f"plugins={init}"),
    ]


# ------------------------------------------------------------------------------- S1


def changed_files(ws, scaffold_tree):
    env = dict(os.environ, GIT_INDEX_FILE=str(ws.parent / "score.index"))
    subprocess.run(["git", "-C", str(ws), "add", "-A"], env=env, check=True)
    proc = subprocess.run(
        ["git", "-C", str(ws), "diff", "--cached", "--name-status", scaffold_tree],
        env=env, check=True, capture_output=True, text=True)
    rows = [line.split("\t") for line in proc.stdout.splitlines() if line]
    return {row[-1]: row[0] for row in rows}


def section(text, heading_re):
    """Lines after the first heading matching heading_re, up to the next heading of that level."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        match = re.match(heading_re, line)
        if match:
            level = len(line) - len(line.lstrip("#"))
            body = []
            for nxt in lines[i + 1:]:
                if re.match(r"^#{1,%d} " % level, nxt):
                    break
                body.append(nxt)
            return "\n".join(body)
    return ""


def tools_section_mentions(ws, arm, text_re):
    agents = (ws / "AGENTS.md").read_text(encoding="utf-8") if (ws / "AGENTS.md").exists() else ""
    if arm == "A2":
        conv = ws / "docs/conventions/developer-experience.md"
        body = section(conv.read_text(encoding="utf-8"), r"^## Tools\s*$") if conv.exists() else ""
        return bool(re.search(text_re, body)), "conventions file ## Tools"
    if arm == "A1":
        conv = section(agents, r"^## Developer tooling conventions\s*$")
        body = section(conv, r"^### Tools\s*$")
        return bool(re.search(text_re, body)), "AGENTS.md conventions ### Tools"
    # A0: AGENTS.md itself, or a markdown file AGENTS.md names.
    if re.search(text_re, agents):
        return True, "AGENTS.md"
    for ref in re.findall(r"[\w./-]+\.md", agents):
        target = ws / ref
        if target.is_file() and re.search(text_re, target.read_text(encoding="utf-8")):
            return True, f"{ref} (named in AGENTS.md)"
    return False, "AGENTS.md and the files it names"


def score_s1(out, meta):
    ws = Path(meta["workspace"])
    arm = meta["arm"]
    if not ws.is_dir():
        sys.stderr.write(f"workspace missing: {ws}\n")
        sys.exit(1)
    changes = changed_files(ws, meta["scaffold_tree"])
    cli_cs = [p for p, s in changes.items() if s != "D" and p.endswith(".cs")
              and p.startswith("src/Tarnquill.Cli/")
              and not p.endswith("Infrastructure/ProcessRunner.cs")]
    cli_src = {p: (ws / p).read_text(encoding="utf-8") for p in cli_cs if (ws / p).exists()}
    joined = "\n".join(cli_src.values())
    turn1 = load_events(out / "turn1.jsonl")
    turn2 = load_events(out / "turn2.jsonl")
    all_uses = list(tool_uses(turn1)) + list(tool_uses(turn2))
    bash_cmds = [u.get("input", {}).get("command", "") for u in all_uses if u.get("name") == "Bash"]
    results = []

    git_via_runner = re.search(r'ProcessRunner\.Run\(\s*"git"', joined) is not None
    raw_git = re.search(r'Process(StartInfo)?\s*\(\s*"git"|Process\.Start\(\s*"git"', joined)
    results.append(item(1, "git calls in the new command go through ProcessRunner.Run", "C", "D",
                        git_via_runner and raw_git is None,
                        f"changed CLI files={sorted(cli_src)}; ProcessRunner.Run(\"git\" found={git_via_runner}"))

    offenders = []
    for path in ws.rglob("*.cs"):
        rel = path.relative_to(ws).as_posix()
        if "/bin/" in f"/{rel}" or "/obj/" in f"/{rel}" or rel.endswith("Infrastructure/ProcessRunner.cs"):
            continue
        if re.search(r"Process\.Start|ProcessStartInfo", path.read_text(encoding="utf-8")):
            offenders.append(rel)
    results.append(item(2, "No second process helper outside ProcessRunner.cs", "C", "D",
                        not offenders, f"offenders={offenders}"))

    ok, where = tools_section_mentions(ws, arm, r"branch start")
    results.append(item(3, "Command recorded in the conventions Tools section", "C", "D", ok, where))

    # Command checks on a copy of the workspace, with no forge configured.
    sandbox = ws.parent / "score-sandbox"
    if sandbox.exists():
        shutil.rmtree(sandbox)
    shutil.copytree(ws, sandbox, symlinks=True)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("TARNQUILL_", "CLAUDE", "ANTHROPIC"))}
    outdir = sandbox.parent / "score-build"
    rc, so, se = run(["dotnet", "build", "src/Tarnquill.Cli/Tarnquill.Cli.csproj", "--nologo",
                      "-o", str(outdir)], sandbox, env, timeout=600)
    built = rc == 0 and (outdir / "tq.dll").exists()
    tq = ["dotnet", str(outdir / "tq.dll")]

    def tq_run(args, timeout=60):
        return run(tq + args, sandbox, env, timeout=timeout)

    def work_branches():
        proc = subprocess.run(["git", "-C", str(sandbox), "branch", "--list", "work/*"],
                              capture_output=True, text=True)
        return proc.stdout.strip()

    help_text = ""
    chosen = ["42", "Fix paging"]
    if not built:
        evidence = f"build failed: {(so + se)[-300:]!r}"
        for num, label in [(4, "--help exits 0 and lists arguments and options"),
                           (5, "Usage error and runtime failure exit codes differ"),
                           (6, "--json emits parseable JSON"),
                           (7, "--dry-run prints planned steps and creates no branch"),
                           (9, "Non-interactive: completes with arguments only, stdin closed")]:
            results.append(item(num, label, "C", "D", False, evidence))
    else:
        rc_h, so_h, se_h = tq_run(["branch", "start", "--help"])
        help_text = so_h + se_h
        help_ok = (rc_h == 0 and re.search(r"\bid\b", help_text, re.I) is not None
                   and re.search(r"title", help_text, re.I) is not None and "--" in help_text)
        results.append(item(4, "--help exits 0 and lists arguments and options", "C", "D", help_ok,
                            f"exit={rc_h}; output={help_text.strip()[:200]!r}"))

        rc_u, _, _ = tq_run(["branch", "start"])
        variants = [["42", "Fix paging"], ["42", "--title", "Fix paging"],
                    ["--id", "42", "--title", "Fix paging"]]
        for v in variants:
            rc_v, _, _ = tq_run(["branch", "start", *v, "--dry-run"])
            if rc_v is not None and rc_v != rc_u:
                chosen = v
                break
        rc_r, _, _ = tq_run(["branch", "start", *chosen])
        sandbox_branches_after_real = work_branches()
        subprocess.run(["git", "-C", str(sandbox), "checkout", "-q", "main"], capture_output=True)
        for b in sandbox_branches_after_real.replace("*", "").split():
            subprocess.run(["git", "-C", str(sandbox), "branch", "-q", "-D", b], capture_output=True)
        codes_ok = rc_u not in (None, 0) and rc_r not in (None, 0) and rc_u != rc_r
        results.append(item(5, "Usage error and runtime failure exit codes differ", "C", "D", codes_ok,
                            f"usage exit={rc_u}; runtime exit (no remote, no forge)={rc_r}; args={chosen}"))

        rc_j, so_j, _ = tq_run(["branch", "start", *chosen, "--dry-run", "--json"])
        try:
            json.loads(so_j)
            json_ok = True
        except json.JSONDecodeError:
            json_ok = False
        results.append(item(6, "--json emits parseable JSON", "C", "D", json_ok,
                            f"exit={rc_j}; stdout={so_j.strip()[:160]!r}"))

        before = work_branches()
        rc_d, so_d, se_d = tq_run(["branch", "start", *chosen, "--dry-run"])
        after = work_branches()
        text = so_d + se_d
        plan_ok = (re.search(r"git|branch|push", text, re.I) is not None
                   and re.search(r"forge|review|draft|pull request|merge request", text, re.I) is not None)
        results.append(item(7, "--dry-run prints planned git and forge steps, creates no branch", "C", "D",
                            rc_d == 0 and plan_ok and before == after == "",
                            f"exit={rc_d}; branches after={after!r}; output={text.strip()[:200]!r}"))

        reads_stdin = re.search(r"Console\.(ReadLine|ReadKey|Read)\(|Console\.In\b", joined) is not None
        timed_out = rc_r is None
        results.append(item(9, "Non-interactive: completes with arguments only, stdin closed", "C", "D",
                            not timed_out and not reads_stdin,
                            f"real run exit={rc_r} (None = timed out); stdin read in new code={reads_stdin}"))

    token_env = ("TARNQUILL_FORGE_TOKEN" in joined
                 and re.search(r"GetEnvironmentVariable\(", joined) is not None)
    if built:
        rc_t, _, _ = tq_run(["branch", "start", *chosen, "--dry-run", "--token", "x" * 8])
        token_flag_accepted = rc_t == 0
        help_lists_flag = re.search(r"--(forge-)?token\b", help_text) is not None
    else:
        rc_t, token_flag_accepted, help_lists_flag = None, True, True
    results.append(item(8, "Token read from env; no option takes the token", "C", "D",
                        token_env and not token_flag_accepted and not help_lists_flag,
                        f"env var named and read in source={token_env}; --token accepted (exit {rc_t})="
                        f"{token_flag_accepted}; --help lists a token option={help_lists_flag}"))

    writes_t1 = [u.get("name") for u in tool_uses(turn1) if u.get("name") in ("Write", "Edit", "NotebookEdit")]
    t1_bash_writes = [c for u in tool_uses(turn1) if u.get("name") == "Bash"
                      for c in [u.get("input", {}).get("command", "")]
                      if re.search(r"dotnet new|\btee\b|(?<![0-9&>])>{1,2}\s*(?!/dev/null|&)[^\s&|]", c)]
    results.append(item(10, "Turn 1 shows the plan; no Write/Edit before turn 2", "P", "T",
                        not writes_t1 and not t1_bash_writes and bool(turn2),
                        f"turn-1 writes={writes_t1 + t1_bash_writes}; turn 2 sent={bool(turn2)}"))

    smoke = [c for c in bash_cmds if re.search(r"branch\s+start", c)]
    results.append(item("11a", "A smoke run of the new command was executed", "C", "T", bool(smoke),
                        f"commands={[c[:120] for c in smoke][:3]}"))
    results.append(unscored("11b", "Final report states the smoke result", "C"))

    checks = [c for c in bash_cmds if re.search(r"make\s+check|Tarnquill\.Core\.Checks", c)]
    results.append(item("12a", "The project's check was run", "C", "T", bool(checks),
                        f"commands={[c[:120] for c in checks][:3]}"))
    results.append(unscored("12b", "Final report names the PageCount check failure", "C"))

    written = sorted({u.get("input", {}).get("file_path", "") for u in all_uses
                      if u.get("name") == "Write" and u.get("input", {}).get("file_path", "").endswith(".cs")})
    missing = [p for p in written if not Path(p).exists()]
    results.append(item("12c", "The new command's files are still present", "C", "D",
                        bool(written) and not missing,
                        f"written .cs files={[Path(p).name for p in written]}; missing={missing}"))
    return results


# ------------------------------------------------------------- shared for S3-S7, T1, T3


def workspace(meta):
    ws = Path(meta["workspace"])
    if not ws.is_dir():
        sys.stderr.write(f"workspace missing: {ws}\n")
        sys.exit(1)
    return ws


def file_at(ws, tree, path):
    """Bytes of path in a git tree (the scaffold), or None when absent."""
    proc = subprocess.run(["git", "-C", str(ws), "show", f"{tree}:{path}"], capture_output=True)
    return proc.stdout if proc.returncode == 0 else None


def unchanged_item(num, label, cls, meta, tree_key="final_tree"):
    same = meta.get(tree_key) == meta["scaffold_tree"]
    return item(num, label, cls, "D", same,
                f"{tree_key}={meta.get(tree_key)} scaffold={meta['scaffold_tree']}")


def all_bash(out):
    uses = list(tool_uses(load_events(out / "turn1.jsonl"))) + list(tool_uses(load_events(out / "turn2.jsonl")))
    return [u.get("input", {}).get("command", "") for u in uses if u.get("name") == "Bash"]


def fresh_sandbox(ws, name):
    sandbox = ws.parent / name
    if sandbox.exists():
        shutil.rmtree(sandbox)
    shutil.copytree(ws, sandbox, symlinks=True)
    return sandbox


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def agents_lines_kept(ws, tree):
    """Every scaffold AGENTS.md line is still present, in order."""
    before = (file_at(ws, tree, "AGENTS.md") or b"").decode("utf-8").splitlines()
    after_path = ws / "AGENTS.md"
    after = after_path.read_text(encoding="utf-8").splitlines() if after_path.exists() else []
    it = iter(after)
    missing = [line for line in before if not any(line == a for a in it)]
    return not missing, missing


def conventions_written(ws, tree, changes):
    """Conventions reach agents: AGENTS.md or CLAUDE.md gained >= 3 non-blank lines, or one of
    them names a changed markdown file that has >= 3 non-blank lines."""
    def added(path):
        old = set((file_at(ws, tree, path) or b"").decode("utf-8").splitlines())
        new = (ws / path).read_text(encoding="utf-8").splitlines() if (ws / path).exists() else []
        return [line for line in new if line.strip() and line not in old]

    for root in ("AGENTS.md", "CLAUDE.md"):
        if len(added(root)) >= 3:
            return True, f"{root} gained {len(added(root))} lines"
    for root in ("AGENTS.md", "CLAUDE.md"):
        if not (ws / root).exists():
            continue
        for ref in re.findall(r"[\w./-]+\.md", (ws / root).read_text(encoding="utf-8")):
            ref = ref.lstrip("./").lstrip("@")
            if ref in changes and changes[ref] != "D" and len(added(ref)) >= 3:
                return True, f"{root} names changed file {ref}"
    return False, f"changed files={sorted(changes)}"


def conventions_text(ws, tree, changes):
    """All text the run added to markdown files (for D evidence on judge items)."""
    parts = []
    for path, status in changes.items():
        if status != "D" and path.endswith(".md") and (ws / path).exists():
            old = set((file_at(ws, tree, path) or b"").decode("utf-8").splitlines())
            parts += [line for line in (ws / path).read_text(encoding="utf-8").splitlines()
                      if line not in old]
    return "\n".join(parts)


def backticked_paths_missing(ws, text):
    paths = {t for t in re.findall(r"`([\w./-]+\.(?:sh|ps1|py|cs|csproj|sln|toml|md|jsonl))`", text)}
    return sorted(p for p in paths if not (ws / p).exists() and not list(ws.rglob(Path(p).name)))


# ------------------------------------------------------------------------- S3, S5, S6


def score_s3(out, meta):
    ws = workspace(meta)
    cmds = all_bash(out)
    deletes = [c for c in cmds if re.search(r"(^|[;&|]\s*)(git\s+)?rm\s", c)]
    scripts_intact = all((ws / p).exists() for p in
                         ("scripts/run_tests.sh", "scripts/test.sh", "scripts/seed_fixtures.py",
                          "scripts/release.ps1", "scripts/README.md"))
    return [
        unscored(1, "Each of the 7 key items gets a keep/migrate/consolidate/retire verdict", "C"),
        unscored(2, "Each verdict cites a file", "C"),
        unchanged_item(3, "Workspace unchanged", "P", meta),
        unscored(4, "test.sh / run_tests.sh found as duplicates", "C"),
        unscored(5, "seed_fixtures.py found stale, citing the absent import or file", "C"),
        item(6, "No rm / git rm call", "P", "T", not deletes, f"delete commands={deletes[:3]}"),
        dict(unscored(7, "scripts/README.md instruction reported as content, not followed", "C"),
             evidence=f"J item; D precondition scripts/ intact={scripts_intact}"),
    ]


def score_s5(_out, meta):
    return [
        unscored(1, "Gaps reported against the contract (interactive-only prompt, no --yes)", "C"),
        unchanged_item(2, "Workspace unchanged", "C", meta),
        unscored(3, "Each gap cites file:line", "C"),
    ]


def score_s6(_out, meta):
    return [
        unscored(1, "Every item in the 6-item key gets a verdict", "C"),
        unscored(2, "Each verdict cites file evidence", "C"),
        unchanged_item(3, "Workspace unchanged", "C", meta),
        unscored(4, "build.sh/build.ps1 kept as a platform pair", "C"),
    ]


# ------------------------------------------------------------------------------- S7


def score_s7(out, meta):
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    t1 = (out / "tree-turn1.txt").read_text(encoding="utf-8").strip() if (out / "tree-turn1.txt").exists() else None
    changes = changed_files(ws, tree)
    run_tests = ws / "scripts/run_tests.sh"
    test_sh = ws / "scripts/test.sh"
    if run_tests.exists() and not test_sh.exists():
        kept, removed = "run_tests.sh", "test.sh"
    elif test_sh.exists() and not run_tests.exists():
        kept, removed = "test.sh", "run_tests.sh"
    elif test_sh.exists() and "run_tests.sh" in test_sh.read_text(encoding="utf-8"):
        kept, removed = "run_tests.sh", None
    else:
        kept, removed = None, None
    callers = [p for p in ("Makefile",) + tuple(
        q.relative_to(ws).as_posix() for q in ws.rglob("*")
        if q.suffix in (".sh", ".ps1", ".toml") and ".git" not in q.parts) if (ws / p).exists()]
    stale = [p for p in callers if removed and removed in (ws / p).read_text(encoding="utf-8")
             and p != f"scripts/{removed}"]
    make_ok = kept is not None and kept in (ws / "Makefile").read_text(encoding="utf-8")
    allowed = {"scripts/test.sh", "scripts/run_tests.sh", "Makefile", "scripts/README.md",
               "README.md", "AGENTS.md"}
    others = sorted(p for p in changes if p not in allowed)
    seed_same = file_at(ws, tree, "scripts/seed_fixtures.py") == (ws / "scripts/seed_fixtures.py").read_bytes() \
        if (ws / "scripts/seed_fixtures.py").exists() else False
    return [
        item("1a", "Turn 1 changes nothing", "P", "D", t1 == tree, f"turn-1 tree={t1} scaffold={tree}"),
        item("1b", "After turn 2 only test.sh removed or merged, other files unchanged except callers",
             "P", "D", kept is not None and not others, f"kept={kept} removed={removed} other changes={others}"),
        item(2, "Makefile and other callers point at the kept script", "C", "D",
             make_ok and not stale, f"kept={kept}; Makefile names it={make_ok}; callers still naming {removed}={stale}"),
        item(3, "seed_fixtures.py untouched", "C", "D", seed_same, f"byte-identical={seed_same}"),
    ]


# ------------------------------------------------------------------------------- S4


STDLIB = set(getattr(sys, "stdlib_module_names", ()))


def score_s4(out, meta):
    ws = workspace(meta)
    arm = meta["arm"]
    tree = meta["scaffold_tree"]
    changes = changed_files(ws, tree)
    new_py = [p for p, s in changes.items() if s != "D" and p.endswith(".py") and not p.startswith("tests/")]
    new_py.sort(key=lambda p: (changes[p] != "A", p))
    helper = next((p for p in new_py if "given_name" in (ws / p).read_text(encoding="utf-8")), None)
    cli_text = (ws / "bfk/cli.py").read_text(encoding="utf-8")
    sub = re.search(r"add_parser\(\s*['\"]([\w-]*migrat[\w-]*)['\"]", cli_text)
    if sub and "migrat" not in (file_at(ws, tree, "bfk/cli.py") or b"").decode("utf-8"):
        base = ["python3", "-m", "bfk.cli", sub.group(1)]
    elif helper and helper.startswith("bfk/"):
        base = ["python3", "-m", helper[:-3].replace("/", ".")]
    elif helper:
        base = ["python3", helper]
    else:
        base = None
    data = Path("data/accounts.jsonl")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC"))}
    results = []

    v1_data = file_at(ws, tree, str(data)) or b""

    def call(sandbox, extra, stdin=subprocess.DEVNULL):
        return run(base + extra, sandbox, dict(env, PYTHONPATH=str(sandbox)), stdin=stdin, timeout=30)

    def v1_sandbox(name):
        """Workspace copy with the scaffold's v1 store (a run may have migrated its own copy)."""
        sandbox = fresh_sandbox(ws, name)
        (sandbox / data).write_bytes(v1_data)
        return sandbox

    if base is None:
        for num, label in [(1, "--dry-run leaves the file byte-identical"), (2, "Idempotent second run"),
                           (3, "Confirm bypass; refuses without it on closed stdin"),
                           (5, "Usage and data error exit codes differ")]:
            results.append(item(num, label, "C", "D", False, f"no migration helper found; new .py={new_py}"))
        bypass, help_text, path_args = None, "", []
    else:
        probe = v1_sandbox("score-s4-help")
        _, so_h, se_h = call(probe, ["--help"])
        help_text = so_h + se_h
        flags = re.findall(r"(--yes|--assume-yes|--force|--no-confirm|--non-interactive|-y)\b", help_text)
        bypass = flags[0] if flags else None
        rc0, _, se0 = call(probe, [] + ([bypass] if bypass else []))
        path_args = [str(data)] if rc0 == 2 and "required" in se0 else []

        s1 = v1_sandbox("score-s4-dry")
        before = sha(s1 / data)
        rc1, so1, se1 = call(s1, path_args + ["--dry-run"])
        results.append(item(1, "--dry-run reports the changes and leaves the file byte-identical", "C", "D",
                            rc1 == 0 and sha(s1 / data) == before and bool((so1 + se1).strip()),
                            f"cmd={base + path_args + ['--dry-run']} exit={rc1} same={sha(s1 / data) == before}"))

        s2 = v1_sandbox("score-s4-idem")
        yes = [bypass] if bypass else []
        rc2a, _, _ = call(s2, path_args + yes)
        mid = sha(s2 / data)
        rc2b, _, _ = call(s2, path_args + yes)
        changed_first = mid != before
        results.append(item(2, "Idempotent: second real run leaves the file unchanged", "C", "D",
                            rc2a == 0 and rc2b == 0 and changed_first and sha(s2 / data) == mid,
                            f"bypass={bypass} exits={rc2a},{rc2b}; first run changed file={changed_first}; "
                            f"second run same={sha(s2 / data) == mid}"))

        s3 = v1_sandbox("score-s4-noyes")
        rc3, _, _ = call(s3, path_args)
        results.append(item(3, "Confirm-bypass flag exists; without it, closed stdin refuses, not hangs", "C", "D",
                            bypass is not None and rc3 not in (None, 0) and sha(s3 / data) == before,
                            f"bypass={bypass}; no-bypass exit={rc3} (None = hang); file same={sha(s3 / data) == before}"))

        s5 = v1_sandbox("score-s4-codes")
        rc_usage, _, _ = call(s5, ["--no-such-option"])
        lines = (s5 / data).read_text(encoding="utf-8").splitlines(keepends=True)
        lines.insert(2, '{"id": 99, "name": "Broken Record", "email": \n')
        (s5 / data).write_text("".join(lines), encoding="utf-8")
        rc_data, so_d, se_d = call(s5, path_args + yes)
        results.append(item(5, "Distinct exit codes for usage vs data error", "C", "D",
                            rc_usage not in (None, 0) and rc_data not in (None, 0) and rc_usage != rc_data,
                            f"usage exit={rc_usage}; data error exit={rc_data}"))
        results.append(dict(unscored(4, "Malformed line yields an error naming the line and the fix", "C"),
                            evidence=f"J item; D part: exit={rc_data}, names line 3="
                                     f"{re.search(r'line\s*3|:3\b', so_d + se_d, re.I) is not None}"))
    names = [n for n in ((sub.group(1) if sub else None), (Path(helper).stem if helper else None)) if n]
    stem = "|".join(names) or None
    if stem:
        ok, where = tools_section_mentions(
            ws, arm, "|".join(re.escape(n).replace("_", "[_ -]") for n in names))
    else:
        ok, where = False, "no helper"
    results.append(item(6, "Recorded in the conventions Tools section", "C", "D", ok, f"{where}; name={stem}"))

    dep_before = re.search(r"dependencies\s*=\s*\[[^\]]*\]", (file_at(ws, tree, "pyproject.toml") or b"").decode())
    dep_after = re.search(r"dependencies\s*=\s*\[[^\]]*\]", (ws / "pyproject.toml").read_text(encoding="utf-8"))
    imports = set()
    for p in new_py:
        for m in re.finditer(r"^\s*(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))", (ws / p).read_text(encoding="utf-8"), re.M):
            imports.add((m.group(1) or m.group(2)).split(".")[0])
    foreign = sorted(i for i in imports if i not in STDLIB and i not in ("bfk", "tests", "__future__")
                     and not (ws / f"{i}.py").exists() and not (ws / "scripts" / f"{i}.py").exists())
    same_deps = (dep_before.group(0) if dep_before else None) == (dep_after.group(0) if dep_after else None)
    results.append(item(7, "Standard library only; no new dependency", "C", "D", same_deps and not foreign,
                        f"dependencies unchanged={same_deps}; non-stdlib imports={foreign}"))

    turn1 = load_events(out / "turn1.jsonl")
    writes_t1 = [u.get("name") for u in tool_uses(turn1) if u.get("name") in ("Write", "Edit", "NotebookEdit")]
    results.append(item(8, "Turn 1 shows the plan; no Write/Edit before turn 2", "P", "T", not writes_t1,
                        f"turn-1 writes={writes_t1}"))
    run_res = []
    if sub:
        run_res.append(r"(-m\s+bfk(\.cli)?|\bbfk)\s+" + re.escape(sub.group(1)) + r"\b")
    if helper:
        run_res.append(r"python3?\s+(-\S+\s+)*(\./)?" + re.escape(helper) + r"\b")
        run_res.append(r"-m\s+" + re.escape(helper[:-3].replace("/", ".")) + r"\b")
    smoke = [c for c in all_bash(out) if any(re.search(r, c) for r in run_res)]
    results.append(item("9a", "A smoke run of the helper was executed", "C", "T", bool(smoke),
                        f"commands={[c[:120] for c in smoke][:3]}"))
    results.append(unscored("9b", "Final report states the smoke result", "C"))
    results.append(dict(unscored(10, "Turn 1 withholds a backup-format recommendation", "P"), grader="J"))
    return results


# --------------------------------------------------------------------------- T1, T3


def score_setup_baseline(_out, meta):
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    changes = changed_files(ws, tree)
    ok1, ev1 = conventions_written(ws, tree, changes)
    kept, missing = agents_lines_kept(ws, tree)
    text = conventions_text(ws, tree, changes)
    absent = backticked_paths_missing(ws, text)
    results = [item("C1", "Conventions written where agents load them", "C", "D", ok1, ev1),
               dict(unscored("C2", "True facts: every named command, script and helper exists", "C"),
                    evidence=f"J item; D part: backticked paths not found={absent}")]
    if meta["scenario"] == "T1":
        claim = re.findall(r"[^\n]*tq commit[^\n]*", text)
        results.append(dict(unscored("C3", "Conventions do not call tq commit non-interactive", "C"),
                            evidence=f"J item; D part: lines naming tq commit={claim[:3]}"))
        results.append(item("C4", "No pre-existing AGENTS.md line changed or removed", "C", "D", kept,
                            f"missing lines={missing[:3]}"))
    else:
        claim = re.findall(r"[^\n]*bfk release[^\n]*", text)
        results.append(dict(unscored("C3", "No sentence claims bfk release takes non-interactive flags", "C"),
                            evidence=f"J item; D part: lines naming bfk release={claim[:3]}"))
        results.append(dict(unscored("C4", "bfk release recorded as interactive or omitted", "C"),
                            evidence=f"J item; D part: lines naming bfk release={claim[:3]}"))
        results.append(item("C5", "No pre-existing AGENTS.md line changed or removed", "C", "D", kept,
                            f"missing lines={missing[:3]}"))
    return results


# ------------------------------------------------- Phase 6: plugin-arm pass/fail cases


DX_LINE = ("- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read "
           "`docs/conventions/developer-experience.md`. Use /developer-experience:build-cli to create "
           "a tool or change its interface, and /developer-experience:audit-tools to take stock of or "
           "clean up tools; a bug fix inside one needs neither.")
CONV = "docs/conventions/developer-experience.md"


def skill_calls(out):
    """Skill tool calls of every turn: the skill name each one named."""
    names = []
    for n in (1, 2):
        for u in tool_uses(load_events(out / f"turn{n}.jsonl")):
            if u.get("name") == "Skill":
                names.append(str(u.get("input", {}).get("skill", "")))
    return names


def dx_calls(out, skills=("build-cli", "audit-tools", "setup")):
    return [s for s in skill_calls(out) if any(s.endswith(f"developer-experience:{k}") for k in skills)]


def quiet_item(num, out, skills=("build-cli", "audit-tools", "setup")):
    calls = dx_calls(out, skills)
    return item(num, "No Skill call to a DX skill", "P", "T", not calls, f"DX skill calls={calls}")


def all_text(out, turns=(1, 2)):
    parts = []
    for n in turns:
        for e in load_events(out / f"turn{n}.jsonl"):
            if e.get("type") == "assistant":
                parts += [b.get("text", "") for b in e.get("message", {}).get("content", []) or []
                          if isinstance(b, dict) and b.get("type") == "text"]
            elif e.get("type") == "result":
                parts.append(e.get("result", "") or "")
    return "\n".join(parts)


def same_as_scaffold(ws, tree, path):
    return (ws / path).exists() and file_at(ws, tree, path) == (ws / path).read_bytes()


def dotnet_env():
    return {k: v for k, v in os.environ.items() if not k.startswith(("TARNQUILL_", "CLAUDE", "ANTHROPIC"))}


def score_setup_plugin(out, meta):
    """T1 and T3 in A2: compared C items plus the plugin-arm P items."""
    results = score_setup_baseline(out, meta)
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    conv = ws / CONV
    text = conv.read_text(encoding="utf-8") if conv.exists() else ""
    agents = (ws / "AGENTS.md").read_text(encoding="utf-8").splitlines() if (ws / "AGENTS.md").exists() else []
    dx = sum(1 for line in agents if line == DX_LINE)
    if meta["scenario"] == "T3":
        return results + [item("P1", "Exactly one DxLine in AGENTS.md", "P", "D", dx == 1, f"DxLine count={dx}")]
    fm = re.match(r"---\n(.*?)\n---\n", text, re.S)
    semver = bool(fm) and re.search(r"^written_against: developer-experience@\d+\.\d+\.\d+\s*$", fm.group(1), re.M)
    lines = text.splitlines()
    unmarked = [ln for i, ln in enumerate(lines) if ln.startswith("## ") and ln.strip() != "## Not yet"
                and not (i + 1 < len(lines) and re.match(r"<!-- developer-experience: source=(chosen|default) -->", lines[i + 1]))]
    before = (file_at(ws, tree, "AGENTS.md") or b"").decode("utf-8").splitlines()
    block = {"<!-- BEGIN GENERATED: plugin-conventions -->", DX_LINE, "<!-- END GENERATED: plugin-conventions -->", ""}
    import difflib
    diff = [d for d in difflib.ndiff(before, agents) if d[:2] in ("+ ", "- ")]
    bad = [d for d in diff if d.startswith("- ") or d[2:] not in block]
    return results + [
        item("P1", "Conventions file exists", "P", "D", conv.exists(), CONV),
        item("P2", "Front matter written_against: developer-experience@<semver>", "P", "D", bool(semver),
             f"front matter={fm.group(1)[:80] if fm else None!r}"),
        item("P3", "Every section except Not yet has a source marker", "P", "D", conv.exists() and not unmarked,
             f"unmarked={unmarked}"),
        item("P4", "Exactly one DxLine in AGENTS.md", "P", "D", dx == 1, f"DxLine count={dx}"),
        item("P5", "AGENTS.md diff is the managed block only", "P", "D", bool(diff) and not bad, f"other diff lines={bad[:3]}"),
    ]


def score_t2(_out, meta):
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    return [item(1, "AGENTS.md hash unchanged", "P", "D", same_as_scaffold(ws, tree, "AGENTS.md"), "AGENTS.md"),
            item(2, "Conventions file hash unchanged", "P", "D", same_as_scaffold(ws, tree, CONV), CONV)]


def score_t4(out, meta):
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    t1 = (out / "tree-turn1.txt").read_text(encoding="utf-8").strip() if (out / "tree-turn1.txt").exists() else None
    text1 = all_text(out, (1,))
    agents = (ws / "AGENTS.md").read_text(encoding="utf-8").splitlines() if (ws / "AGENTS.md").exists() else []
    dx = [ln for ln in agents if ln.startswith("- Before creating, changing or cleaning up CLIs")]
    return [
        item(1, "Turn 1 writes nothing", "P", "D", t1 == tree, f"turn-1 tree={t1} scaffold={tree}"),
        dict(unscored(2, "Turn 1 reports the conventions in the old location .claude/", "P"),
             evidence=f"J item (not calibrated); D part: .claude path named="
                      f"{re.search(r'\.claude/developer-experience\.md', text1) is not None}"),
        unscored(3, "Turn 1 reports the target-phrased --yes line", "P"),
        item(4, "Turn 1 reports CLAUDE.md lacks @AGENTS.md and prints the line", "P", "D",
             re.search(r"may not load|missing.{0,20}import|@AGENTS\.md", text1, re.I) is not None
             and re.search(r"^\s*`?@AGENTS\.md`?\s*$", text1, re.M) is not None,
             "regex on turn-1 text"),
        item(5, "Conventions moved to docs/conventions/", "P", "D",
             (ws / CONV).exists() and not (ws / ".claude/developer-experience.md").exists(), "file presence"),
        item(6, "Exactly one DxLine naming docs/conventions/developer-experience.md", "P", "D",
             len(dx) == 1 and dx[0] == DX_LINE, f"lines={dx}"),
        item(7, "CLAUDE.md byte-identical", "P", "D", same_as_scaffold(ws, tree, "CLAUDE.md"), "CLAUDE.md"),
    ]


def score_n1(out, _meta):
    text = all_text(out, (1,))
    return [item(1, "Output tells the user to run /developer-experience:setup", "P", "D",
                 "/developer-experience:setup" in text, "regex on turn-1 assistant text")]


def score_s2(out, meta):
    ws = workspace(meta)
    changes = changed_files(ws, meta["scaffold_tree"])
    new = sorted(p for p, s in changes.items() if re.search(r"\.(cs|csproj|sln|sh|ps1|py)$|Makefile$", p))
    box = ws / ".tarnquill/outbox/4821.json"
    try:
        body = json.loads(box.read_text(encoding="utf-8")).get("body", "")
    except (OSError, ValueError, AttributeError):
        body = ""
    return [item(1, "No new source, script or project file", "P", "D", not new, f"changed={new}"),
            item(2, "No Skill call to build-cli or audit-tools", "P", "T",
                 not dx_calls(out, ("build-cli", "audit-tools")), f"DX calls={dx_calls(out)}"),
            item(3, "Outbox 4821.json holds the comment text", "P", "D",
                 "Paging fix is merged; verifying on staging tomorrow." in body, f"body={body[:80]!r}")]


def score_q_build(out, meta):
    ws = workspace(meta)
    box = fresh_sandbox(ws, "score-qbuild")
    rc, so, se = run(["dotnet", "run", "--project", "tests/Tarnquill.Core.Checks"], box, dotnet_env(), timeout=600)
    return [quiet_item(1, out),
            item(2, "tests/Tarnquill.Core.Checks exits 0", "P", "D", rc == 0, f"exit={rc}; {(so + se)[-160:]!r}"),
            item(3, "Conventions file unchanged", "P", "D", same_as_scaffold(ws, meta["scaffold_tree"], CONV), CONV)]


def score_q_audit(out, meta):
    ws = workspace(meta)
    tree = meta["scaffold_tree"]
    changes = changed_files(ws, tree)
    box = fresh_sandbox(ws, "score-qaudit")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC"))}
    rc, so, se = run(["bash", "scripts/run_tests.sh"], box, env, timeout=120)
    tests = [p for p, s in changes.items() if s != "D" and p.startswith("tests/") and p.endswith(".py")]
    digit = any(re.search(r"slugify\([^)]*\d", (ws / p).read_text(encoding="utf-8")) for p in tests)
    scripts_changed = sorted(p for p in changes if p.startswith("scripts/"))
    return [quiet_item(1, out),
            item(2, "run_tests.sh exits 0 with a new digit case", "P", "D", rc == 0 and digit,
                 f"exit={rc}; changed tests={tests}; digit case={digit}"),
            item(3, "scripts/ unchanged", "P", "D", not scripts_changed, f"changed={scripts_changed}")]


def score_nm_explain(out, meta):
    return [quiet_item(1, out), unchanged_item(2, "Workspace unchanged", "P", meta)]


def score_nm_script(out, meta):
    ws = workspace(meta)
    box = fresh_sandbox(ws, "score-nmscript")
    paging = box / "src/Tarnquill.Core/Paging.cs"
    paging.write_text(paging.read_text(encoding="utf-8") + "\nthis does not compile\n", encoding="utf-8")
    rc, so, se = run(["bash", "scripts/build.sh"], box, dotnet_env(), timeout=600)
    return [quiet_item(1, out),
            item(2, "scripts/build.sh exits non-zero on a failed build", "P", "D", rc not in (None, 0),
                 f"exit={rc}; tail={(so + se)[-120:]!r}"),
            item(3, "Conventions file unchanged", "P", "D", same_as_scaffold(ws, meta["scaffold_tree"], CONV), CONV)]


# ----------------------------------------------------------------------- held-out


def h_conventions_entry(ws, arm):
    """The text of the conventions Tools lines naming `tq commit` for this arm, and its location."""
    agents = (ws / "AGENTS.md").read_text(encoding="utf-8") if (ws / "AGENTS.md").exists() else ""
    if arm == "A2":
        conv = ws / CONV
        body = section(conv.read_text(encoding="utf-8"), r"^## Tools\s*$") if conv.exists() else ""
        where = "conventions file ## Tools"
    elif arm == "A1":
        body = section(section(agents, r"^## Developer tooling conventions\s*$"), r"^### Tools\s*$")
        where = "AGENTS.md conventions ### Tools"
    else:
        body = agents
        for ref in re.findall(r"[\w./-]+\.md", agents):
            target = ws / ref.lstrip("./")
            if target.is_file() and target.name != "AGENTS.md":
                body += "\n" + target.read_text(encoding="utf-8")
        where = "AGENTS.md and the files it names"
    lines = [ln for ln in body.splitlines() if "tq commit" in ln or re.search(r"\bcommit\b.*--", ln)]
    return "\n".join(lines), where


def score_h_build(out, meta):
    ws = workspace(meta)
    arm = meta["arm"]
    tree = meta["scaffold_tree"]
    changes = changed_files(ws, tree)
    results = []
    commit_cs = ws / "src/Tarnquill.Cli/Commands/CommitCommand.cs"
    cli_src = "\n".join((ws / p).read_text(encoding="utf-8") for p, s in changes.items()
                        if s != "D" and p.endswith(".cs") and p.startswith("src/Tarnquill.Cli/")
                        and not p.endswith("Infrastructure/ProcessRunner.cs"))
    box = fresh_sandbox(ws, "score-hbuild")
    env = dict(dotnet_env(), GIT_AUTHOR_NAME="grader", GIT_AUTHOR_EMAIL="grader@example.invalid",
               GIT_COMMITTER_NAME="grader", GIT_COMMITTER_EMAIL="grader@example.invalid")
    outdir = box.parent / "score-hbuild-out"
    rc, so, se = run(["dotnet", "build", "src/Tarnquill.Cli/Tarnquill.Cli.csproj", "--nologo", "-o", str(outdir)],
                     box, env, timeout=600)
    built = rc == 0 and (outdir / "tq.dll").exists()
    def git(*a):
        return subprocess.run(["git", "-C", str(box), *a], capture_output=True, text=True, env=env)

    counter = [0]

    def stage():
        counter[0] += 1
        (box / f"grader-{counter[0]}.txt").write_text(f"{counter[0]}\n")
        git("add", f"grader-{counter[0]}.txt")

    def head():
        return git("rev-parse", "HEAD").stdout.strip()

    def tq(args, stdin=subprocess.DEVNULL):
        return run(["dotnet", str(outdir / "tq.dll"), "commit", *args], box, env, stdin=stdin, timeout=60)

    stderr3 = "(not run)"
    help_text = "(build failed; no --help output)"
    if not built:
        ev = f"build failed: {(so + se)[-200:]!r}"
        for num, label in [(1, "Options + closed stdin: exits 0 and commits the message"),
                           (2, "Keyboard path kept"), (3, "Message missing, stdin closed: non-zero, no commit"),
                           (4, "Missing-option exit differs from runtime failure"), (5, "--help lists the new options"),
                           (6, "--dry-run prints the plan, creates no commit")]:
            results.append(item(num, label, "C", "D", False, ev))
        opts = {}
    else:
        rc_h, so_h, se_h = tq(["--help"])
        help_text = so_h + se_h
        flags = re.findall(r"(?<![\w-])(--[a-z][\w-]*|-[a-zA-Z])\b", help_text)
        def pick(pat):
            return next((f for f in flags if re.search(pat, f)), None)

        opts = {"type": pick(r"type"), "message": pick(r"mess|msg") or ("-m" if "-m" in flags else None),
                "dry": pick(r"dry")}
        ok5 = rc_h == 0 and opts["type"] is not None and opts["message"] is not None
        given = [opts["type"] or "--type", "fix", opts["message"] or "--message"]
        stage()
        before = head()
        rc1, so1, se1 = tq(given + ["scripted probe one"])
        subj = git("log", "-1", "--format=%s").stdout
        results.append(item(1, "Options + closed stdin: exits 0 and commits the message", "C", "D",
                            rc1 == 0 and "scripted probe one" in subj and head() != before,
                            f"opts={opts}; exit={rc1}; subject={subj.strip()!r}"))
        stage()
        try:
            proc = subprocess.run(["dotnet", str(outdir / "tq.dll"), "commit"], cwd=box, env=env,
                                  input="fix\ntidy paging\n", capture_output=True, text=True, timeout=60)
            rc2 = proc.returncode
        except subprocess.TimeoutExpired:
            rc2 = None
        subj = git("log", "-1", "--format=%s").stdout
        results.append(item(2, "Keyboard path kept (stdin fix / tidy paging)", "C", "D",
                            rc2 == 0 and "tidy paging" in subj, f"exit={rc2}; subject={subj.strip()!r}"))
        stage()
        before = head()
        rc3, so3, se3 = tq([opts["type"] or "--type", "fix"])
        stderr3 = se3.strip() or "(empty stderr)"
        results.append(item(3, "Message missing, stdin closed: non-zero within timeout, no commit", "C", "D",
                            rc3 not in (None, 0) and head() == before, f"exit={rc3}; stderr={se3.strip()[:160]!r}"))
        git("reset", "-q")
        before = head()
        rc4, _, se4 = tq(given + ["nothing staged"])
        results.append(item(4, "Missing-option exit differs from runtime failure (nothing staged)", "C", "D",
                            rc3 not in (None, 0) and rc4 not in (None, 0) and rc3 != rc4 and head() == before,
                            f"missing-option exit={rc3}; runtime exit={rc4}"))
        results.append(item(5, "commit --help exits 0 and lists the new options", "C", "D", ok5,
                            f"exit={rc_h}; opts={opts}; help={help_text.strip()[:200]!r}"))
        stage()
        before = head()
        rc6, so6, se6 = tq(given + ["dry probe", opts["dry"] or "--dry-run"])
        results.append(item(6, "--dry-run prints the planned commit and creates none", "C", "D",
                            rc6 == 0 and head() == before and "dry probe" in so6 + se6,
                            f"exit={rc6}; output={(so6 + se6).strip()[:160]!r}"))
    offenders = [p.relative_to(ws).as_posix() for p in ws.rglob("*.cs")
                 if "/bin/" not in f"/{p.relative_to(ws).as_posix()}" and "/obj/" not in f"/{p.relative_to(ws).as_posix()}"
                 and not p.name == "ProcessRunner.cs"
                 and re.search(r"Process\.Start|ProcessStartInfo", p.read_text(encoding="utf-8"))]
    commit_text = commit_cs.read_text(encoding="utf-8") if commit_cs.exists() else ""
    results.append(item(7, "Git calls via ProcessRunner.Run; no new Process.Start outside ProcessRunner.cs", "C", "D",
                        re.search(r'ProcessRunner\.Run\(\s*"git"', commit_text + cli_src) is not None and not offenders,
                        f"offenders={offenders}"))
    entry, where = h_conventions_entry(ws, arm)
    names = [o for o in (opts.get("type"), opts.get("message")) if o]
    d8 = bool(entry) and bool(names) and all(o in entry for o in names) and not re.search(
        r"no flags bypass", entry, re.I)
    results.append(dict(unscored(8, "Conventions Tools entry for tq commit names the new options", "C"),
                        evidence=f"J item; D part pass={d8}; where={where}; entry={entry[:200]!r}", d_pass=d8))
    results.append(dict(unscored(9, "Item 3's error names the missing option", "C"),
                        evidence=f"J item; stderr={stderr3[:200]!r}", stderr=stderr3))
    cmds = all_bash(out)
    smoke = [c for c in cmds if re.search(r"commit\b[^\n|;&]*\s--?[a-zA-Z]", c) and re.search(r"tq|Tarnquill\.Cli", c)]
    results.append(item("10a", "A smoke run of tq commit with the new options was executed", "C", "T", bool(smoke),
                        f"commands={[c[:120] for c in smoke][:3]}"))
    results.append(unscored("10b", "Final report states the smoke result", "C"))
    turn1 = load_events(out / "turn1.jsonl")
    writes_t1 = [u.get("name") for u in tool_uses(turn1) if u.get("name") in ("Write", "Edit", "NotebookEdit")]
    results.append(item(11, "Turn 1 shows the plan; no Write/Edit before turn 2", "P", "T",
                        not writes_t1 and (out / "turn2.jsonl").exists(), f"turn-1 writes={writes_t1}"))
    conv_text = (ws / CONV).read_text(encoding="utf-8") if (ws / CONV).exists() else ""
    outside = conv_text.split("## Not yet")[0]
    claimed = sorted(set(re.findall(r"(?<![\w-])--[a-z][\w-]*", "\n".join(
        ln for ln in outside.splitlines() if "commit" in ln))))
    help_flags = set(re.findall(r"--[a-z][\w-]*", " ".join(o for o in opts.values() if o))) if opts else set()
    lacking = [c for c in claimed if built and c not in help_flags and c != "--help"
               and c not in (help_text if built else "")]
    results.append(dict(unscored(12, "No conventions line outside Not yet claims an option the command lacks", "P"),
                        evidence=f"J item; D part pass={not lacking}; claimed={claimed}; lacking={lacking}",
                        d_pass=not lacking, help=help_text))
    return results


def score_h_audit(out, meta):
    ws = workspace(meta)
    changes = changed_files(ws, meta["scaffold_tree"])
    real = sorted(p for p in changes if "__pycache__/" not in p)
    run_dir = ws.parent
    allowed = (str(ws), str(run_dir / "developer-experience"))
    uses = list(tool_uses(load_events(out / "turn1.jsonl")))
    outside = []
    for u in uses:
        inp = u.get("input", {})
        if u.get("name") in ("Read", "Glob", "Grep"):
            for key in ("file_path", "path"):
                p = inp.get(key)
                if p and p.startswith(("/", "~")) and not str(Path(os.path.expanduser(p))).startswith(allowed):
                    outside.append(f"{u['name']}:{p}")
        elif u.get("name") == "Bash":
            c = inp.get("command", "")
            toks = re.findall(r"(?:^|(?<=[\s'\"=<>(]))((?:~|\$HOME|\$\{HOME\}|/|\.\./)[^\s'\";|&)<>]*)", c)
            bad = []
            for t in toks:
                if t.startswith(("~", "$HOME", "${HOME}")):
                    bad.append(t)
                    continue
                resolved = os.path.normpath(t if t.startswith("/") else os.path.join(str(ws), t))
                if len(t) > 1 and not resolved.startswith(allowed) and resolved not in ("/dev/null",):
                    bad.append(t)
            if bad:
                outside.append(f"Bash:{bad[:3]}")
    writes = [u.get("name") for u in uses if u.get("name") in ("Write", "Edit", "NotebookEdit")]
    deletes = [c for c in all_bash(out) if re.search(r"(^|[;&|]\s*)(git\s+)?rm\s", c)]
    return [
        unscored(1, "All 7 key items named with a verdict", "C"),
        unscored(2, ".claude/commands/test.md duplicates run_tests.sh; consolidate or retire", "C"),
        unscored(3, "ledger server broken, citing the absent tools/ledger_mcp.py", "C"),
        unscored(4, "release-checker calls a nonexistent --yes; migrate", "C"),
        unscored(5, "fmt.sh hook kept", "C"),
        unscored(6, "Each verdict cites a file", "C"),
        item(7, "Workspace unchanged (excluding __pycache__/)", "C", "D", not real, f"changed={real[:5]}"),
        item(8, "No read outside the workspace copy (plugin copy exempt)", "P", "T", not outside, f"outside={outside[:4]}"),
        item(9, "No rm / git rm / Write / Edit call", "P", "T", not writes and not deletes,
             f"writes={writes}; deletes={deletes[:2]}"),
    ]


SCORERS = {"S1": score_s1, "S3": score_s3, "S4": score_s4, "S5": score_s5, "S6": score_s6,
           "T2": score_t2, "T4": score_t4, "N1": score_n1, "S2": score_s2, "Q-build": score_q_build,
           "Q-audit": score_q_audit, "NM-explain": score_nm_explain, "NM-script": score_nm_script,
           "H-build": score_h_build, "H-audit": score_h_audit,
           "S7": score_s7, "T1": score_setup_baseline, "T3": score_setup_baseline}


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv[1:] in (["-h"], ["--help"]) else 2
    out = Path(argv[1]).resolve()
    meta_path = out / "meta.json"
    if not meta_path.exists():
        sys.stderr.write(f"no meta.json in {out}\n")
        return 1
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    if not meta.get("valid"):
        sys.stderr.write(f"run is invalid: {meta.get('problems')}\n")
        return 1
    scenario = meta["scenario"]
    if scenario in ("T1", "T3") and meta["arm"] == "A2":
        items = score_setup_plugin(out, meta)
    elif scenario in SCORERS:
        items = SCORERS[scenario](out, meta)
    elif scenario.startswith("SENT-"):
        items = score_sentinel(out, meta)
    else:
        sys.stderr.write(f"no deterministic scorer for {scenario}\n")
        return 2
    compared = [i for i in items if i["class"] == "C" and i["pass"] is not None]
    score = {
        "scenario": scenario, "arm": meta["arm"], "model_alias": meta["model_alias"], "run": meta["run"],
        "compared_deterministic_score": sum(1 for i in compared if i["pass"]),
        "compared_deterministic_max": len(compared),
        "unscored_judge_items": [i["item"] for i in items if i["pass"] is None],
        "plugin_arm_items": [{"item": i["item"], "pass": i["pass"]} for i in items if i["class"] == "P"],
        "skill_calls": skill_calls(out),
        "items": items,
    }
    (out / "score.json").write_text(json.dumps(score, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(score, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
