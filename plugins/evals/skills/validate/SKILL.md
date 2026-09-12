---
description: "Statically validate a `claude plugin eval` suite (`prompt.md`, `case.yaml`, `graders/*.md`) before any run spends money. A standard-library Python script reports FAIL for what the binary rejects at load (unknown frontmatter key, unknown grader option, no grader, duplicate grader name, non-positive weight, out-of-range runs / max_turns / timeout_seconds, an env key outside EVAL_[A-Z0-9_]*) and WARN for the documented authoring mistakes (target: files, inline (?i), judge-only graders, a gated tool in allowed_tools, file_exists in a read-only suite). Use when: 'validate my eval cases', 'check my eval suite', 'will this suite load', 'lint case.yaml', 'check my graders', 'why did my case fail to load', or before paying for a run. Not for the skill-creator `evals/evals.json` format."
argument-hint: "[eval-dir (default: evals/ under the plugin root)]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Static FAIL/WARN check of an eval suite's cases and graders, with no model call
---

# Validate eval cases before a run spends money

Every run of an eval suite is a real model call on the operator's account, and a case that fails to
load costs the same as one that works. `scripts/validate-cases.py` reads the suite off disk and
reports what would break, with no model call and no network access.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/validate/scripts/validate-cases.py" <eval-dir>
```

`<eval-dir>` is the directory holding the cases, `evals/` under the plugin root by default. Add
`--json` for the same findings as an array of `{level, case, file, message}` objects, and `--help`
for the full contract, which the script's own header carries.

| Exit | Meaning |
|---|---|
| 0 | no FAIL finding. WARN findings are printed and do not gate |
| 1 | at least one FAIL finding |
| 2 | usage error, or the eval dir is missing or unreadable |

Findings print one per line as `<FAIL|WARN> <case>/<file>: <message>`, sorted by case then file; a
finding about the suite as a whole carries the eval dir in place of `<case>/<file>`.

## What the two tiers mean

**FAIL is what the binary itself rejects**: an unknown `prompt.md` frontmatter key, a grader with no
usable `type`, an unknown option for the declared grader type, a case with no grader at all, two
graders sharing a name, a non-positive `weight`, `runs` / `max_turns` / `timeout_seconds` outside
their bounds, and an `env` key that does not match `EVAL_[A-Z0-9_]*`. The exact key sets and bounds
live in the script's own constants, under the drift record its header carries, so there is one place
to correct when the schema moves.

**WARN is an authoring mistake the suite loads with** and then scores badly on: `target: files`
(which reads the list of paths created, not their contents), an inline `(?i)` the grader's regex
engine does not honor, a case whose graders are all judges (the two types that cost money, with no
deterministic grader beside them), a tool in `allowed_tools` that the operator must grant with
`--allow-tools`, and `file_exists` in a suite where no case can create a file. The judge-only rule
is this skill's own pairing heuristic, not a rejection the binary makes.

A WARN never sets exit 1, so a suite can ship with warnings on purpose. Read them once and decide.

## When the parser stops

The script reads a bounded YAML subset: scalars, quoted scalars, flow lists and mappings, block
lists including lists of mappings, and block mappings three levels deep. An anchor, an alias, a tag,
a block scalar, a merge key, tab indentation, or nesting past three levels is reported as
`frontmatter not parsed (<construct>)` at FAIL, never waved through at exit 0. A validator that
green-lights input it could not read is worse than no validator. Simplify the file, or run the CLI,
which carries the full parser.

## Mirroring claim, and its recheck trigger

**Claim:** the FAIL tier matches what the binary rejects when it loads a case, so a suite at exit 0
loads. **Basis:** the case schema recovered from the shipped Claude Code binary, read against the
eval-suite reference at <https://code.claude.com/docs/en/plugin-evals>. **As of:** 2026-09-12.
**Recheck trigger:** the next Claude Code release, which can add a frontmatter key, add a grader
type, or move a bound. On a firing, re-derive both lists from the schema rather than patching one
value.

This skill asserts nothing about whether the `claude plugin eval` command is available in your
install; it reads files and never invokes anything. The runner skill's preflight owns that question.

## Boundary

Two eval formats coexist and are not interchangeable. This validator reads only the
`prompt.md` / `case.yaml` / `graders/*.md` layout. The skill-creator `evals/evals.json` format is
owned by `/skill-quality:check validate-evals <skill>` when the `skill-quality` plugin is installed;
where it is not, that file goes unvalidated and this script says nothing about it, since pointing a
case validator at an `evals.json` reports only that the directory holds no cases.

## Next

`/evals:plugin-eval <target>`. A suite at exit 0 is one worth paying to run.

## Gotchas

- Exit 0 means the suite **loads**, not that it measures anything. A case whose graders pass in both
  arms proves the plugin contributed nothing; the delta is read after a run, not here.
- A case is a directory holding `prompt.md` or `case.yaml`. A directory holding neither is skipped
  silently, so a case whose prompt file is misnamed reads as absent rather than as an error. An eval
  dir with no case at all is a FAIL.
- `results/` and `mocks/` are never treated as cases, whatever they contain.
- When both files exist, `prompt.md` frontmatter overrides the matching `case.yaml` field, and the
  bounds check reports the file the effective value came from, which may not be the file you edited.
- Unknown top-level keys in `case.yaml` are not reported. The unknown-key rejection is recorded for
  `prompt.md`, and this validator invents no rejection the binary does not make.
- The script is Python 3.8+, standard library only, so it runs from a consumer checkout where no
  package is provisioned. It never writes to the suite it reads.
