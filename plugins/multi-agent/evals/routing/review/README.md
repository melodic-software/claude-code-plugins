# Routing eval: review cases

The review role's cases for the paired model-routing eval
([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)), with the arm
configuration each setup needs. The paid runs belong to the run slice
([#10022](https://github.com/melodic-software/claude-code-plugins/issues/10022)).

## The cases

Two kinds of review task, each built from code in this repository:

- **Code review** (`rv-*`): the workspace holds a changed file and `change.diff`, the change that
  produced it. The change introduces one seeded defect beside one behavior-preserving edit, the
  decoy. The reply lists each defect as a `finding:` line.
- **Verification** (`vf-*`): the workspace holds a file and `findings.md`, four findings a reviewer
  raised against it. Two describe real defects and two are false. The reply marks each finding
  `confirmed` or `refuted`.

Each case's `scaffold.sh` writes its workspace; an `rv-*` scaffold writes the base and changed
versions and makes `change.diff` with `diff -u`, so the diff always matches the files. Every case
is read-only: it lists `Read`, `Glob` and `Grep`, and needs no `--allow-tools` grant.

| Case | Adapted from | Answer |
| --- | --- | --- |
| `rv-json-escape-order` | `json_str` in `scripts/resolve-roles.sh`, Bash | `json_str` escapes quotes before backslashes, so a quote yields invalid JSON. Decoy: a shared `note` helper |
| `rv-bounds-off-by-one` | `check_bounds` in the evals plugin's `validate-cases.py`, Python | `value <= low` reports a value at its inclusive minimum. Decoy: `%` to `str.format` in `check_env` |
| `rv-fetch-gate-prefix` | `decide` in `hooks/drift-checker-fetch-gate.mjs`, JavaScript | a `startsWith` fast path skips the host, userinfo and query checks. Decoy: `Buffer` chunks in `main` |
| `vf-route-findings` | `skills/route/scripts/route.sh`, Bash | F1 refuted, F2 confirmed, F3 refuted, F4 confirmed |
| `vf-check-fields-findings` | the field checks in `validate-cases.py`, Python | F1 confirmed, F2 refuted, F3 refuted, F4 confirmed |

The graders count verified findings. In an `rv-*` case, `names-defect` passes when a `finding:`
line names the function holding the seeded defect, and `one-finding` passes when the reply has
exactly one `finding:` line, so flagging the decoy or splitting the defect fails it. In a `vf-*`
case, one grader per finding passes when that finding's line carries the right verdict.

Every grader is a deterministic `regex` over the final reply, and each has must-pass and must-fail
answers under `samples/`. No case has an `llm` or `baseline` grader, so no judge model scores a run
and no grader needs calibration.

Check the cases before a paid run with
`/evals:validate plugins/multi-agent/evals/routing/review`.

## Arms

Each arm runs the same command from the repository root, with `CLAUDE_CODE_EFFORT_LEVEL` set to the
arm's level in the shell's environment. Arms differ only in the model and the effort level:

```bash
claude plugin eval plugins/multi-agent --tag review --scaffold --ablation none --model <model>
```

- `--tag review` selects these five cases. The target goes before `--tag`, since `--tag` takes a
  list.
- `--scaffold` runs `scaffold.sh`; without it the workspace stays empty. A scaffold runs with a
  minimal environment and a 120-second limit, and a non-zero exit fails the run. The `rv-*`
  scaffolds also call `mktemp` and `diff`.
- `--ablation none` runs one arm per case: the comparison is between models, not with and without
  the plugin.
- `--model` sets the agent's model and overrides any case `model`. No case sets one.
- `CLAUDE_CODE_EFFORT_LEVEL` is resolved before `--effort`, `/effort` and the settings keys, though
  a `maxEffortLevel` cap still applies. Haiku 5.5, Sonnet 5.5 and Opus 5.5 default to `medium` when
  nothing sets a level. A run inherits only an allowlist of the shell's environment, which the
  `env` row says includes most `CLAUDE_CODE_*` configuration without naming the variables, so
  confirm the level reaches the run before comparing arms.

| Arm | `--model` | `CLAUDE_CODE_EFFORT_LEVEL` | Advisor |
| --- | --- | --- | --- |
| `haiku-high` | `claude-haiku-5-5` | `high` | none |
| `haiku-xhigh` | `claude-haiku-5-5` | `xhigh` | none |
| `haiku-opus-advisor` | `claude-haiku-5-5` | `high` | `claude-opus-5-5`, with Anthropic's Haiku coding prompt |
| `sonnet-low` | `claude-sonnet-5-5` | `low` | none |
| `sonnet-medium` | `claude-sonnet-5-5` | `medium` | none |
| `sonnet-high` | `claude-sonnet-5-5` | `high` | none |
| `opus-low` | `claude-opus-5-5` | `low` | none |
| `opus-medium` | `claude-opus-5-5` | `medium` | none |

The advisor arm uses `high` because the
[routing rubric](../../../reference/routing-rubric.md#the-rule) runs a Haiku role at `high`. Its
system prompt is the advisor tool page's
[alternative system prompt for Haiku on coding workloads](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#alternative-system-prompt-for-haiku-on-coding-workloads),
kept verbatim in [`../mechanical-edit/haiku-advisor-prompt.txt`](../mechanical-edit/haiku-advisor-prompt.txt).
The page reports results for that prompt on Haiku 4.5, not Haiku 5.5, and recommends it for coding
or write-task workloads. These cases write nothing, so the prompt's hard rule about the first write
never fires, and its other checkpoints decide when the advisor is called. Record the prompt the arm
ran with.

Claude Code accepts Opus 4.7 or later as the advisor for a Haiku 5.5 main model, and Haiku 5.5 as
the main model needs Claude Code v2.1.293 or later. `claude plugin eval` does not run this arm as
written: it lists no advisor option, and a run loads none of your user settings, where
`advisorModel` lives. `append_system_prompt` is a per-case field, so it cannot differ by arm. When
the API refuses a pairing, Claude Code resends the request without the advisor and shows no error,
so check the transcripts for advisor calls. The run slice decides how to run this arm.

## Sources

Read 2026-10-28. Recheck when `claude plugin eval` gains an advisor or effort option, or when any
of these sections changes:

- [Plugin evals](https://code.claude.com/docs/en/plugin-evals): command options, `prompt.md` and
  `case.yaml` fields, the `env` allowlist, `context.scaffold_script`, how runs are isolated, and the
  `regex` grader's JavaScript syntax.
- [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level): the
  levels each model accepts, the resolution order and each model's default.
- [Enable the advisor](https://code.claude.com/docs/en/advisor#enable-the-advisor) and
  [choose an advisor model](https://code.claude.com/docs/en/advisor#choose-an-advisor-model).
- The advisor tool page's
  [model compatibility](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#model-compatibility)
  table, for the model IDs, and its Haiku coding prompt section.
