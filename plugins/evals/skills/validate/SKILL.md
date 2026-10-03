---
description: "Statically validate a `claude plugin eval` suite (`prompt.md`, `case.yaml`, `graders/*.md`) before any run spends money. A standard-library Python script reports FAIL for what the binary rejects at load (unknown frontmatter key, unknown grader option, no grader, duplicate grader name, non-positive weight, out-of-range runs / max_turns / timeout_seconds, an env key outside EVAL_[A-Z0-9_]*, an unsupported schema_version major) and WARN for the documented authoring mistakes (target: files, inline (?i), judge-only graders, a gated tool in allowed_tools, file_exists in a read-only case). It also grades each deterministic grader offline against the case's samples/GRADER.json answers. Use when: 'validate my eval cases', 'check my eval suite', 'will this suite load', 'lint case.yaml', 'check my graders', 'why did my case fail to load', or before paying for a run. Not for the skill-creator `evals/evals.json` format."
argument-hint: "[eval-dir]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Static FAIL/WARN check of an eval suite's cases and graders, with no model call
---

**Arguments.** `[eval-dir]`. default: evals/ under the plugin root

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
their bounds, an `env` key that does not match `EVAL_[A-Z0-9_]*`, a `case.yaml` with no companion
`prompt.md` and no `schema_version` or `name`, and a `schema_version` whose major is newer than the
binary supports. The sets the script checks, complete, so a question about a key or a type is
answered here without opening the script:

- `prompt.md` frontmatter keys: `schema_version`, `name`, `description`, `tags`, `plugins`,
  `runs`, `expected_outcome`, `model`, `max_turns`, `timeout_seconds`, `allowed_tools`,
  `append_system_prompt`, `env`. A time limit is `timeout_seconds`; `timeout` is an unknown key, so
  the case fails to load.
- Grader `type`: `regex`, `tool_order`, `tool_used`, `file_exists`, `llm`, `baseline`. Any other
  value, such as `contains` or `string_match`, is no usable type, so the case fails to load. A
  substring or pattern check is `type: regex` with the text in `pattern`.
- Options per type, beside the `type`, `weight`, `arm` and `name` every grader takes: `regex`
  `pattern`, `flags`, `match`, `target`; `tool_used` `tool`, `input_match`, `min`, `max`;
  `tool_order` `before`, `after`; `file_exists` `path`, `exists`; `llm` `criteria`, `focus`;
  `baseline` `baseline_file`, `criteria`.
- Bounds: `runs` 1 to 50, `max_turns` 1 to 200, `timeout_seconds` 1 to 3600.

The script's constants are the one place to correct when the schema moves, under the drift record
its header carries; this list follows them.

**WARN is an authoring mistake the suite loads with** and then scores badly on: `target: files`
(which reads the list of paths created, not their contents), an inline `(?i)` the grader's regex
engine does not honor, a case whose graders are all judges (the two types that cost money, with no
deterministic grader beside them), a tool in `allowed_tools` that the operator must grant with
`--allow-tools`, `file_exists` in a case that requests no write tool, so nothing it could match
is ever created, and a `prompt.md` key the binary loads but the reference page does not list, which
can change without notice (the script's `UNDOCUMENTED_PROMPT_KEYS`, under its own drift record).
The judge-only rule
is this skill's own pairing heuristic, not a rejection the binary makes. The sample-answer check
below adds its own FAIL and WARN findings; those are this skill's checks, not rejections either.

A WARN never sets exit 1, so a suite can ship with warnings on purpose. Read them once and decide.

## Sample answers

A grader that rejects a correct paraphrase scores the plugin down for nothing, and no run tells you
the grader was at fault. So each case can carry known answers, and the script runs the free graders
over them before any money is spent.

Put them in `samples/<grader-name>.json` inside the case directory, beside `graders/` and never in
it. That location rests on the case layout and run isolation described in the
[eval suite reference](https://code.claude.com/docs/en/plugin-evals#eval-suite-reference) and on the
case loader in Claude Code 2.1.287, which reads only `prompt.md`, `case.yaml` and `graders/`. As of
2026-10-01; recheck when a release adds a file the loader reads from a case directory.

```json
{
  "pass": [{"answer": "...", "why": "the ranking rule with 'and' for the comma"}],
  "fail": [{"answer": ""}, {"answer": "...", "why": "near miss: base-model phrasing"}]
}
```

`answer` is what the grader reads: text for a `regex` (the final reply on the default target), a
list of `{"tool", "input"}` calls for `tool_used` and `tool_order`, and a list of created paths for
`file_exists`. `why` is optional and is echoed in any finding. Give each grader several paraphrases
it must pass, near misses it must reject, an empty answer, and an answer to a different question.

| Finding | Level |
|---|---|
| A must-pass answer the grader rejects, or a must-fail answer it accepts | FAIL |
| A sample file that is not JSON in this shape, or an answer of the wrong kind for its grader | FAIL |
| A `regex`, `tool_used`, `tool_order` or `file_exists` grader with no sample file | WARN |
| A sample file with no must-pass or no must-fail answers, or named after no grader | WARN |
| A setting the script cannot reproduce offline, such as the `y` or `v` regex flag | WARN |
| An `llm` or `baseline` grader with samples: they need a paid judge calibration run | WARN |

The script never calls a judge. Samples on an `llm` grader are the labeled answers a calibration
run feeds the judge, and that run is the operator's to start.

**Claim:** the sample check grades as the binary does. **Basis:** the grader code in Claude Code
2.1.287, read against the [grader types](https://code.claude.com/docs/en/plugin-evals#grader-types)
table; Python's `re` stands in for the JavaScript regex engine, and the script's header lists where
the two differ. **As of:** 2026-10-01. **Recheck trigger:** the next Claude Code release, or a
grader whose sample verdict disagrees with its verdict in a real run.

## When the parser stops

The script reads a bounded YAML subset: scalars, quoted scalars, flow lists and mappings, block
lists including lists of mappings, and block mappings three levels deep. An anchor, an alias, a tag,
a block scalar, a merge key, tab indentation, a nested sequence in either spelling, a backslash
escape outside `\\`, `\"`, `\/`, `\n`, `\t`, `\r`, or nesting past three levels is reported as
`frontmatter not parsed (<construct>)` at FAIL, never waved through at exit 0. A validator that
green-lights input it could not read is worse than no validator. Simplify the file, or run the CLI,
which carries the full parser.

## Mirroring claim, and its recheck trigger

**Claim:** the load-time FAIL findings match what the binary rejects when it loads a case, so a
suite at exit 0 loads. **Basis:** the case schema recovered from the shipped Claude Code binary, read against the
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
- Samples that all sort correctly prove the grader handles those answers, not the ones the model
  will write. When a real run fails a correct answer, add that answer's phrasing as a sample.
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
