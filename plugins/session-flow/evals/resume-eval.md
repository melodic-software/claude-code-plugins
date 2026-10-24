# Resume-eval cases

The `re-<name>/resume-eval.json` cases here are read only by
`scripts/harness/resume_eval.py`; `scripts/harness/resume_cases.py` builds their seed.

## Check kinds the grader implements

Every check is a matcher: a `must-act` probe passes when its check matches, a
`must-not-do` probe passes when it does not. Regexes are Python `re`, unanchored (Codex
wraps commands, for example `bash -lc '...'`).

| Kind | Fields | Matches when |
|---|---|---|
| `gh_call_regex` | `pattern` | a line of the stub's `gh-calls.log` (one argv line per call) matches |
| `tool_command_regex` | `pattern` | a shell command the reader ran matches: Claude stream-json `tool_use` blocks named `Bash`, field `input.command`; Codex `item.completed` items of type `command_execution`, field `command` |
| `text_regex` | `pattern` | the reader's own text matches: Claude assistant `text` blocks, Codex `agent_message` items |
| `file_regex` | `path`, `pattern` | the workspace file at `path` (relative to the repository) exists and its content matches |
| `file_rewritten` | `path` | the workspace file no longer starts with its seeded bytes (an append keeps them) |
| `edited_path_regex` | `pattern` | a path the reader edited matches: Claude `Edit`/`Write`/`NotebookEdit` `input.file_path`; Codex `file_change` item paths |
| `handoff_contains` | `text` | the handoff file the writer produced in this run contains `text` byte for byte |
| `tool_target_count` | `target_regex`, `at_least` | at least `at_least` reader tool calls touch a matching target: `Read`/`Grep` `file_path` or `path`, a shell command's text |
| `any_of` | `checks` | any listed check matches |

UNVERIFIED field shapes, to confirm against a real run before the grader relies on them:
Codex `agent_message` items and where a `file_change` item carries its paths (probe P5
established only `command_execution.command`), and the Read tool's `cat -n` result form
used in the seeded reads.

Probe fields beyond `id`, `type`, `grade` and `check`:

- `phase`: `main` (default; the reader's resumed run) or `followup` (the one follow-up turn
  that asks the text questions).
- `arms`: the arms the probe applies to (default all). `handoff_contains` probes list
  `before` and `after`, the arms that write a handoff file.
- `grade: text` probes carry `question` and `criteria`, are asked in the follow-up turn, and
  are judged by an `llm` grader against `samples/<probe-id>.json`. Every `text_regex` probe
  has a samples file too, checked offline by `test_resume_cases.py`.
- `recall-no-recap-request` in every case counts recap requests (the reader asking the
  owner to restate the goal or state).

## Case fields the harness reads

- `seed.repo_files`: `{path: content}` written into the run repository before the first commit.
- `seed.predecessor`: generator parameters for `build_predecessor_chain` (hops, `target_bytes`,
  goal, vision, `injections` at their hops, the newest hop's `final` hot-section text).
  `injections[].visible_in_reads` states whether the seeded reads show the entry;
  `seed_history` refuses a case where they disagree.
- `seed.reads.pattern`: overrides the size-based read pattern (`whole`, `paged`, `partial`,
  `partial+constraints`).
- `seed.history`: `after_reads` (the assistant turn after the reads) and `work` turns, in
  `resume_eval.render_history` turn form. `{repo}` and `{handoff}` expand to the repository
  and the newest handoff's paths.
- `seed.gh_fixture.responses`: the stub `gh` answers the first response whose `match`
  regex matches the argv line and whose `requires_prior` regex (if any) matched an earlier
  logged call; else `default`.
- `seed.instruction_fixture`: text delivered by `--append-system-prompt` to the arms and
  states in `applies_to`; `after_states` lists the after arm's states.
- `writer.interrupt.text`: the owner's last turn, sent identically in every arm as its own
  turn after the seeded history ends (on an assistant turn); the arm's prompt follows.
- `writer.hops` (multi-hop only): per hop, the owner turns sent in order after the resume,
  then the interrupt and the arm prompt. `scripted_agent_turns` are appended to that hop's
  session after its owner turns, before the interrupt, and `effects.files` are written to
  the workspace with them.
- `reader`: per-arm delivery, `max_turns`, and the follow-up turn's `max_turns`.

## Generated files

`build_predecessor_chain(spec, out_dir)` writes under `out_dir/.work/` and embeds absolute
paths (`transcript:`, Prior-sessions rows, the `Read @` line). `out_dir` must be the run
repository itself, and the files, the `predecessor-transcripts/` directory included, must
stay in place until the writer runs: a missing predecessor transcript makes the next hop
stamp every carried entry UNVERIFIED.
