#!/usr/bin/env python3
"""Find a repository's CI systems and the jobs that run the comment lint.

  comment-lint-ci-scan.py [--repo <dir>]

Prints one JSON object for /code-tidying:setup to reason over; it decides
nothing and writes nothing:

  interface  the call the shipped script takes
  systems    [{system, files}], CI systems whose configuration files are present
  runners    [{runner, files}], task-runner files a CI job may call
  tools      {python3: [files], pygments: [files]}, scanned files naming each
  callers    [{file, line, form, text, args?}], form `script` for a call of
             comment-lint-ci.sh, `recipe` for comment-lint.sh run directly or
             the older check-comment-lint.sh wrapper
  decisions  [{kind, ...}]: no-ci-system, several-systems, no-caller,
             recipe-caller, drift, unparsed, missing-tool

Only configuration files at the paths below are read, from disk, so a file
written moments ago counts before it is committed. A job that reaches the lint
through another script is not followed: the setup agent reads that script.

Exit 0 with the JSON; 2 on a usage error.
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path

SCRIPT = "comment-lint-ci.sh"
INTERFACE = f"{SCRIPT} <head> <base>"
ARITY = 2

SYSTEMS: dict[str, tuple[str, ...]] = {
    "github-actions": (".github/workflows/*.yml", ".github/workflows/*.yaml"),
    "gitea-actions": (".gitea/workflows/*.yml", ".gitea/workflows/*.yaml"),
    "forgejo-actions": (".forgejo/workflows/*.yml", ".forgejo/workflows/*.yaml"),
    "azure-pipelines": (
        "azure-pipelines.yml",
        "azure-pipelines.yaml",
        ".azure-pipelines/**/*.yml",
        ".azure-pipelines/**/*.yaml",
        ".azuredevops/**/*.yml",
        ".azuredevops/**/*.yaml",
    ),
    "gitlab-ci": (".gitlab-ci.yml", ".gitlab/ci/**/*.yml", ".gitlab/ci/**/*.yaml"),
    "jenkins": ("Jenkinsfile", "Jenkinsfile.*", "*.Jenkinsfile"),
    "circleci": (".circleci/config.yml", ".circleci/config.yaml"),
    "bitbucket-pipelines": ("bitbucket-pipelines.yml",),
    "travis-ci": (".travis.yml",),
    "drone": (".drone.yml",),
    "woodpecker": (".woodpecker.yml", ".woodpecker.yaml", ".woodpecker/*.yml", ".woodpecker/*.yaml"),
    "buildkite": (".buildkite/**/*.yml", ".buildkite/**/*.yaml"),
    "appveyor": ("appveyor.yml", ".appveyor.yml"),
    "teamcity": (".teamcity/**/*.kts", ".teamcity/**/*.xml"),
    "aws-codebuild": ("buildspec.yml", "buildspec.yaml"),
    "google-cloud-build": ("cloudbuild.yaml", "cloudbuild.yml"),
    "semaphore": (".semaphore/*.yml", ".semaphore/*.yaml"),
    "tekton": (".tekton/*.yaml", ".tekton/*.yml"),
}
RUNNERS: dict[str, tuple[str, ...]] = {
    "make": ("Makefile", "makefile", "GNUmakefile"),
    "task": ("Taskfile.yml", "Taskfile.yaml"),
    "just": ("justfile", "Justfile", ".justfile"),
}

RECIPE = re.compile(r"(?<![\w-])(?:check-)?comment-lint\.sh\b")
EXPRESSION = re.compile(r"\$\{\{.*?\}\}|\$\(.*?\)|\$\[.*?\]|\{\{.*?\}\}")
STOP = {";", "&&", "||", "|", "&", ")", "(", ">", ">>", "<", "2>", "2>&1"}


def found(root: Path, patterns: tuple[str, ...]) -> list[str]:
    hits = {p for pattern in patterns for p in root.glob(pattern) if p.is_file()}
    return sorted(p.relative_to(root).as_posix() for p in hits)


def logical_lines(text: str) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []
    start, buf = 0, ""
    for n, raw in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
        line = raw.rstrip()
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        out.append((start, buf + line))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def tokens(rest: str) -> list[str] | None:
    lexer = shlex.shlex(rest, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError:
        return None


def call_args(rest: str) -> list[str] | None:
    rest = EXPRESSION.sub("EXPR", rest)
    words = tokens(rest)
    if words is None:
        words = tokens(rest.rstrip().rstrip("\"'),"))
    if words is None:
        return None
    args: list[str] = []
    for token in words:
        if token in STOP or token.startswith("#"):
            break
        args.append(token)
    return args


def caller(file: str, line: int, text: str) -> dict:
    record: dict = {"file": file, "line": line, "text": text.strip()}
    at = text.find(SCRIPT)
    if at < 0:
        record["form"] = "recipe"
        return record
    record["form"] = "script"
    args = call_args(text[at + len(SCRIPT) :].lstrip("\"'"))
    if args is not None:
        record["args"] = args
    return record


def scan(root: Path) -> dict:
    systems = [{"system": s, "files": f} for s, pats in SYSTEMS.items() if (f := found(root, pats))]
    runners = [{"runner": r, "files": f} for r, pats in RUNNERS.items() if (f := found(root, pats))]
    files = [f for group in systems + runners for f in group["files"]]
    tools: dict[str, list[str]] = {"python3": [], "pygments": []}
    callers: list[dict] = []
    for file in files:
        text = (root / file).read_text(encoding="utf-8", errors="replace")
        for tool in tools:
            if tool in text or (tool == "python3" and re.search(r"\bpython\b", text)):
                tools[tool].append(file)
        for line, logical in logical_lines(text):
            if SCRIPT in logical or RECIPE.search(logical):
                callers.append(caller(file, line, logical))

    decisions: list[dict] = []
    if not systems:
        decisions.append({"kind": "no-ci-system", "runners": [r["runner"] for r in runners]})
    elif len(systems) > 1:
        decisions.append({"kind": "several-systems", "systems": [s["system"] for s in systems]})
    if systems and not callers:
        decisions.append({"kind": "no-caller"})
    for c in callers:
        where = {"file": c["file"], "line": c["line"]}
        if c["form"] == "recipe":
            decisions.append({"kind": "recipe-caller", **where})
        elif "args" not in c:
            decisions.append({"kind": "unparsed", **where})
        elif len(c["args"]) != ARITY or any(a.startswith("-") for a in c["args"]):
            decisions.append({"kind": "drift", **where, "args": c["args"], "interface": INTERFACE})
    for tool, named in tools.items():
        caller_files = {c["file"] for c in callers}
        if callers and not caller_files & set(named):
            decisions.append({"kind": "missing-tool", "tool": tool, "files": sorted(caller_files)})

    return {
        "interface": INTERFACE,
        "systems": systems,
        "runners": runners,
        "tools": tools,
        "callers": callers,
        "decisions": decisions,
    }


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True, usage="comment-lint-ci-scan.py [--repo <dir>]")
    parser.add_argument("--repo", default=".")
    try:
        opts = parser.parse_args()
    except SystemExit as exc:
        return 0 if exc.code == 0 else 2
    root = Path(opts.repo)
    if not root.is_dir():
        print(f"comment-lint-ci-scan: --repo {opts.repo} is not a directory", file=sys.stderr)
        return 2
    json.dump(scan(root.resolve()), sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
