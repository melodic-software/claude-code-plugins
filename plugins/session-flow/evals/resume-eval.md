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
| `handoff_regex` | `pattern` | that handoff file matches `pattern` |
| `tool_target_count` | `target_regex`, `at_least` | at least `at_least` reader tool calls touch a matching target: `Read`/`Grep` `file_path` or `path`, a shell command's text |
| `any_of` | `checks` | any listed check matches |

`gh_call_regex`, `tool_command_regex`, `text_regex` and `edited_path_regex` also take `after`, a
regex: only lines after the first line it matches count (a watch after a dispatch), and none count
when nothing matches it.

UNVERIFIED field shapes, to confirm against a real run before the grader relies on them:
Codex `agent_message` items and where a `file_change` item carries its paths (probe P5
established only `command_execution.command`), and the Read tool's `cat -n` result form
used in the seeded reads.

Probe fields beyond `id`, `type`, `grade` and `check`:

- `phase`: `main` (default; the reader's resumed run) or `followup` (the one follow-up turn
  that asks the text questions).
- `arms`: the arms the probe applies to (default all). `handoff_contains` probes list
  `before` and `after`, the arms that write a handoff file. A probe listing `after` also
  applies to `after-promoted`, the restated-preference case's promoted state: it runs the after
  arm's prompts and plugin copy plus the case's instruction fixture, and reports under its own
  arm label, never pooled into `after`.
- `requires`: another probe's id; this probe is graded only in runs where that probe passed.
- `grade: text` probes carry `question` and `criteria`, are asked in the follow-up turn, and
  are judged by an `llm` grader against `samples/<probe-id>.json`. Every `text_regex` probe
  has a samples file too, and any other non-text probe may: `test_resume_cases.py` grades each
  sample through the real grader. A sample gives `answer` or `texts` (reader text), `commands`,
  `reads`, `edits`, `gh_calls`, `files` (workspace content) or `handoff`.
- `recall-no-recap-request` in every case counts recap requests (the reader asking the
  owner to restate the goal or state); asking what to do next after the work is done is not one.

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
- `seed.instruction_fixture`: text delivered by `--append-system-prompt` to the arm labels in
  `applies_to` (`after-promoted` in the restated-preference case).
- `writer.interrupt.text`: the owner's last turn, sent identically in every arm as its own
  turn after the seeded history ends (on an assistant turn); the arm's prompt follows.
- `writer.hops` (multi-hop only): per hop, a live hop opens by resuming the previous
  hop's delivery, sends its `owner_turns` in order, appends any `scripted_agent_turns` to the
  session, writes `effects.files`, then sends the interrupt and the arm prompt. A hop with
  `"scripted": true` has no live turn before its hand-off: its session is the previous delivery
  plus `scripted_turns` (owner and agent turns, rendered as a transcript), its `effects.files`
  are written, and only the interrupt and the arm prompt run live. In `re-multi-hop`, hops 4 and
  5 are scripted, so parts (1) and (2) of the goal land and part (3) stays open by
  construction. After the last writer hop the harness re-reads the seeded files, so
  `file_rewritten` and the continuation probes grade the final reader against the hop-5
  workspace, not the seed.
- `measured` (multi-hop only): declares outputs the run reports but no probe grades. The
  harness records each hop's handoff bytes as `hop_bytes` in the graded run, so per-hop growth
  is measured.
- `reader`: per-arm delivery, `max_turns`, and the follow-up turn's `max_turns`.

## Generated files

`build_predecessor_chain(spec, out_dir)` writes under `out_dir/.work/` and embeds absolute
paths (`transcript:`, Prior-sessions rows, the `Read @` line). `out_dir` must be the run
repository itself, and the files, the `predecessor-transcripts/` directory included, must
stay in place until the writer runs: a missing predecessor transcript makes the next hop
stamp every carried entry UNVERIFIED.

## When and how to re-run

Re-run the before and after arms on any change to how session-flow writes or reads a
handoff, and on a Claude Code release that changes compaction, Read or context behavior.
Run from a plain `claude` session (not `--worktree`), with every directory outside any
repository and a short `TMPDIR` (a long one breaks the sandbox's Bash bridge sockets):

```bash
env TMPDIR=<short-dir> python3 -I plugins/session-flow/scripts/harness/resume_eval.py run \
  --root <eval-root> --tmpdir <short-dir> --case <re-name> ... \
  --arm before --arm free-hand --arm compact --reader claude-code --reader codex \
  --copy before=<plugin-copy> --codex-model <codex-default-model> --runs 10 -j 4 --out <out-dir>
python3 -I plugins/session-flow/scripts/harness/resume_eval.py report \
  --graded <out-dir>/graded.jsonl --out <report-dir>
```

`run` resumes: it skips runs already graded without error and stops after the first
usage-limit exclusion, so the same command continues after a reset. Each arm and reader
gets its own result file in plugin eval's schema. Compare two of them with
`plugins/evals/skills/plugin-eval/scripts/noise-report.py <after> --baseline <before> --margin 0.05`.
