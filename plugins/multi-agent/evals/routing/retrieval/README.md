# Routing eval: retrieval cases

The retrieval role's cases for the paired model-routing eval
([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)), with the arm
configuration each setup needs. The paid runs belong to the run slice
([#10022](https://github.com/melodic-software/claude-code-plugins/issues/10022)).

## The cases

Each `rt-*` case asks one codebase-retrieval question: locate code, trace callers, or where
something happens. `fixtures/snapshot.sh`, called by each case's `scaffold.sh`, extracts
`plugins/multi-agent` and `plugins/evals` as they stood at commit
`af668bcb5c5380bb867be64f4d2cec96ce911bd3` into the run's workspace with `git archive`, so every
arm searches the same files. Run from a clone that holds that commit; in one that does not, such as
a shallow clone, the scaffold exits non-zero and the run scores 0.

Every grader is a deterministic `regex` over the final reply, and each has must-pass and must-fail
answers under `samples/`. No case has an `llm` or `baseline` grader, so no judge model scores a run
and no grader needs calibration. Each answer key was read off the snapshot's files.

| Case | Kind | Answer |
| --- | --- | --- |
| `rt-haiku-note-site` | Where it happens | `plugins/multi-agent/scripts/resolve-roles.sh`, `role_json` |
| `rt-resolver-callers` | Trace callers | `route.sh`, `setup.sh` and `list-pointers.sh` under `plugins/multi-agent/skills/` |
| `rt-call-matches-callers` | Trace callers | `grade_tool_used`, `grade_tool_order` |
| `rt-python-only-syntax` | Locate code | `plugins/evals/skills/validate/scripts/validate-cases.py`, `python_only_tokens` |
| `rt-fetch-host-gate` | Where it happens | `plugins/multi-agent/hooks/drift-checker-fetch-gate.mjs`, `decide`, `FETCH_HOSTS` |
| `rt-frontier-guard` | Where it happens | `plugins/multi-agent/scripts/resolve-roles.sh`, `role_json`, fallback `opus` |

Check the cases without a model call:

```bash
python3 plugins/evals/skills/validate/scripts/validate-cases.py plugins/multi-agent/evals/routing/retrieval
```

## Arms

Each arm runs the same command from the repository root, with `CLAUDE_CODE_EFFORT_LEVEL` set to the
arm's level in the shell's environment. Arms differ only in the model and the effort level:

```bash
claude plugin eval plugins/multi-agent --case 'rt-*' --scaffold --ablation none --model <model>
```

- `--scaffold` runs `scaffold.sh`; without it the workspace stays empty.
- `--ablation none` runs one arm per case: the comparison is between models, not with and without
  the plugin.
- `--model` sets the agent's model and overrides any case `model`. No case sets one.
- `CLAUDE_CODE_EFFORT_LEVEL` sets the effort level and takes precedence over `--effort`, `/effort`
  and the settings keys, though a `maxEffortLevel` cap still applies. A run inherits only an allowlist of the shell's environment. The `env`
  row says that list includes most `CLAUDE_CODE_*` configuration, but it does not name the
  variables. Confirm that the level reaches the run before comparing arms.

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
[alternative system prompt for Haiku on coding workloads](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#alternative-system-prompt-for-haiku-on-coding-workloads).
The page measured that prompt on Haiku 4.5, not Haiku 5.5. It reports that a close variant lowered
accuracy on a browse-comprehension benchmark, and it suggests its default blocks when a workload
mixes coding with substantial lookup or retrieval, which these cases are. Record the prompt the arm
ran with.

`claude plugin eval` does not run this arm as written. It has no advisor option, and a run loads
none of your user settings. No documented environment variable sets an advisor, and
`append_system_prompt` is a per-case field, so it cannot differ by arm. The run slice decides how
to run this arm.

## Sources

Read 2026-10-25. Recheck when `claude plugin eval` gains an advisor or effort option, or when any
of these sections changes:

- [Plugin evals](https://code.claude.com/docs/en/plugin-evals): command options, `prompt.md` and
  `case.yaml` fields, and how runs are isolated.
- [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) and the
  `CLAUDE_CODE_EFFORT_LEVEL` row of [environment variables](https://code.claude.com/docs/en/env-vars).
- [Enable the advisor](https://code.claude.com/docs/en/advisor#enable-the-advisor) and
  [choose an advisor model](https://code.claude.com/docs/en/advisor#choose-an-advisor-model).
- The advisor tool page's
  [model compatibility](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool#model-compatibility)
  table, for the model IDs.
