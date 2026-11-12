# Case authoring checklist

Read when writing or repairing cases for `claude plugin eval`. Every item is a check to make before
a run, because each one costs a paid pass to discover afterwards.

## Contents

- [Layout](#layout)
- [Precedence](#precedence)
- [The workspace starts empty](#the-workspace-starts-empty)
- [Graders](#graders)
- [Mocks](#mocks)
- [Frontmatter bounds](#frontmatter-bounds)
- [Calibration samples](#calibration-samples)
- [Common mistakes](#common-mistakes)

## Layout

```text
<eval dir>/                     where the run finds it: the first item below
  <case-name>/
    prompt.md                   frontmatter plus the prompt body
    case.yaml                   alternative or companion; schema_version and name required
    graders/<grader-name>.md    one grader per file; the name is the filename minus .md
  mocks/<server>/<tool>.md      MCP tool answers
  mocks/.replay/                recorded agent-mock responses; commit these
```

- [ ] The run can locate the eval dir: it sits where the CLI looks by default, or the plugin
      records where it is. Keep the run's results out of git. Where the CLI looks and how a plugin
      records another directory:
      [Use a different eval directory](https://code.claude.com/docs/en/plugin-evals#use-a-different-eval-directory).
- [ ] Each case is a directory with `prompt.md`, `case.yaml`, or both. A loose file is not a case.
- [ ] Grader names are unique within the case. Duplicates are rejected at load, which exits 1 and
      looks exactly like a failing case.

## Precedence

- [ ] Which file wins when both are present, what `case.yaml` requires, and which fields exist
      only there: [case.yaml fields](https://code.claude.com/docs/en/plugin-evals#case-yaml-fields).
- [ ] Author one or the other per field; two sources for one value is how a suite starts
      measuring something nobody intended.

## The workspace starts empty

Nothing on the authoring machine reaches a run unless the case routes it in. What a run starts
with and what it withholds:
[How runs are isolated](https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated).

- [ ] Anything the task needs is routed into the case explicitly: in the prompt body, in
      `context.add_dirs`, or written by `context.scaffold_script`.
- [ ] No `@path` mention is expanded into an attachment. A file the model must read needs `Read` in
      `allowed_tools` and a path that exists in the run.
- [ ] The environment is allowlisted. Anything the case needs beyond the basics and the provider
      auth variables is exported as `EVAL_<NAME>`; a key outside `EVAL_[A-Z0-9_]*` fails the run.
- [ ] The eval dir itself is hidden from the agent, so a case cannot read its own graders or its
      siblings. That is what makes the measurement honest; do not defeat it with `add_dirs`.
- [ ] Text a grader must match lives where the model will actually read it. A skill's hub file is
      loaded on invocation; a reference spoke is read only if the model chooses to. With the
      plugin copied outside any git repository, as [Worktree isolation](../SKILL.md#worktree-isolation)
      stages it, under the worktree root or on a `/run/user/<uid>` tmpfs, a run read, globbed and
      grepped that copy by absolute path, with or without a Bash grant; other copy locations are
      unmeasured. A pathless or workspace-relative lookup searches the empty workspace and finds
      nothing ([#12880](https://github.com/melodic-software/claude-code-plugins/issues/12880), Claude Code
      2.1.317, as of 2026-11-03; recheck when
      [How runs are isolated](https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated)
      changes what a run can read). Grade on terms the hub itself carries.
- [ ] A case whose skill must write under the workspace's `.claude/` is graded only on what the
      skill produces before that write, or recorded as unmeasured. Why the write is denied:
      [Protected paths](https://code.claude.com/docs/en/permission-modes#protected-paths) (the
      `dontAsk` row and the `permissions.allow` paragraph) with
      [Grant tools](https://code.claude.com/docs/en/plugin-evals#grant-tools).
- [ ] A case that tests settings seeds them in the workspace with `context.scaffold_script` and
      points the prompt at that scope. The gate fails a denied read of the run's own settings,
      because it can change what the skill reports.

## Graders

- [ ] Pair one **result** grader with one **process** grader per case: an outcome check (`regex`,
      `llm`, `file_exists`) plus a path check (`tool_used`, `tool_order`). That pairing is what
      separates "the answer was right" from "the plugin is why".
- [ ] Split by expectation. A mechanical expectation (a format, a required or forbidden string, a
      tool call, a created file) gets a deterministic grader; a holistic one (tone, completeness,
      judgment) gets an `llm` judge. Prefer a deterministic type (`regex`, `tool_used`,
      `tool_order`, `file_exists`) wherever one can decide the expectation, and grade long output
      with a `regex` over the file's contents rather than a judge. What each type costs and how a
      judge decides: [Grader types](https://code.claude.com/docs/en/plugin-evals#grader-types) and
      [Choose graders that give a stable signal](https://code.claude.com/docs/en/plugin-evals#choose-graders-that-give-a-stable-signal).
- [ ] A grader that cannot pass without the plugin (a `tool_used` on `tool: Skill`, or anything
      `arm: with-only`) is excluded from scoring in both arms and reported as an indicator. Use
      `arm: both` when the check must score in both arms, which a must-not-invoke check
      (`min: 0` **and** `max: 0`) requires.
- [ ] A prompt that starts with the skill's slash command loads the skill without a `Skill` tool
      call, so a `tool_used: Skill` grader fails and the validity gate marks the run INVALID. Drop
      that grader on slash-invoked cases, or phrase the prompt in natural language. Seen at Claude
      Code 2.1.289 on all 24 with-arm runs of two suites, 2026-10-04. Recheck trigger: a Claude
      Code release note touches slash-command skill loading or the `Skill` tool, or a kept trace
      of a slash-invoked case shows a `Skill` call; then re-run one such case with `--keep-temp`
      and restore the grader if the call appears.
- [ ] Drop any assertion that passes in both arms and measures nothing. A case at 1.00 on both sides
      is a passing case and a null measurement. Keep one only as a regression guard: tag it
      `regression-guard`, say so in its `description`, and pair it with a case a person judged
      hard, tagged `hard`, with the reason in its `description`.

| Type | Fields |
|---|---|
| `regex` | `pattern`, `flags`, `match`, `target` |
| `tool_used` | `tool`, `input_match`, `min`, `max` |
| `tool_order` | `before`, `after` |
| `file_exists` | `path`, `exists` |
| `llm` | `criteria`, `focus` |
| `baseline` | `baseline_file`, `criteria` |

- **Pointer**: when deciding what a grader passes on, a field's default, or how a judge votes,
  fetch [Grader types](https://code.claude.com/docs/en/plugin-evals#grader-types) live.
- **As of**: 2026-11-03
- **Recheck trigger**: that table adds or renames a type or a field, or changes when a type passes.

Pick the target for `regex.target` and `llm.focus` deliberately rather than relying on the default,
and check what that target holds before writing a pattern or a criterion against it.

- **Pointer**: when choosing a target, writing a pattern against one, or judging a long trace,
  fetch
  [What a grader can look at](https://code.claude.com/docs/en/plugin-evals#what-a-grader-can-look-at)
  live for what each target holds, the default target, and the judge's trace window.

## Mocks

- [ ] Each MCP tool the case's task reaches is mocked, unless the case deliberately runs a real
      server as the MCP row of [SKILL.md](../SKILL.md) allows. Where a mock file goes, what a
      missing one does, and what a real server needs:
      [Mock MCP servers](https://code.claude.com/docs/en/plugin-evals#mock-mcp-servers) and the
      `--mocks` rows of [Command options](https://code.claude.com/docs/en/plugin-evals#command-options).
- [ ] An agent mock with no committed `mocks/.replay/` recording is a reproducibility defect: the
      answer comes from a fresh model call every run, so the case cannot be compared with itself.
      Commit the recording with the rest of `mocks/`.

## Frontmatter bounds

The `prompt.md` key set, each key's default and bound, and the schema version are the CLI's,
read live; the validator's FAIL tier mirrors them in its own constants, so a change there is
re-derived in the validator too. The binary's own load-time messages, read 2026-09-12, showed
it refusing an unknown key, a non-positive `weight`, and a newer schema major; the validator
reports the same as FAIL.

- **Pointer**: when writing or checking a case's frontmatter, fetch
  [`prompt.md` fields](https://code.claude.com/docs/en/plugin-evals#prompt-md-fields) live.

Which grants need a sandbox backend is the CLI's rule too, and this checklist never lists the
tools.

- **Pointer**: when a case grants a tool outside the read-only set, fetch
  [Grant tools](https://code.claude.com/docs/en/plugin-evals#grant-tools) live for which grants
  run sandboxed and what each platform needs for a sandbox backend.

- [ ] `runs`, `max_turns`, and `timeout_seconds` are inside their bounds. Hitting `max_turns` is a
      run error, not a low score.
- [ ] `allowed_tools` requests only what the case needs. Read-only tools (the set in the
      validator's `READ_ONLY_TOOLS`, which mirrors the Grant tools pointer above) need no operator
      grant;
      anything else needs `--allow-tools`, and a grant that runs sandboxed also needs a sandbox
      backend on the machine (the Grant tools record above, in
      [Frontmatter bounds](#frontmatter-bounds); it has no heading of its own).
- [ ] `tags` are set when the suite will ever be filtered. A case runs if **any** of its tags match.

Run the static validator before every paid pass; it checks the bounds above with no model call.

## Calibration samples

What the hub's "Calibrating a judge" commands do with a case's `samples/<grader>.json`:

- `build` writes one case per sample into an empty plugin: the source case's prompt goes out
  unchanged, and an appended system prompt presents the sample as fixed test material for the agent
  to output byte for byte, even when wrong or incomplete, with no commentary, so the judge grades
  that sample as the answer to that question. No generated file carries the label; a must-pass and
  a must-fail case differ only in the sample text.
- `build` skips a grader that judges a file or mock calls, and prints one line for each empty or
  whitespace-only sample it skips: Claude Code answers an empty reply with an injected user turn,
  so it cannot be reproduced, and an empty answer is a deterministic failure that needs no judge.
- The appended prompt does not reach a `focus: trace` judge.
- `score`'s agreement leaves out a run whose reply was not the sample, and one with neither a kept
  trace nor judge evidence (also reported unchecked).

## Common mistakes

Check each of the next four against the two pointer records in [Graders](#graders) (they have no
heading of their own): the targets record and the grader-types record.

- `target: files` where a file's contents were meant.
- Assuming which target is the default.
- An inline flag group such as `(?i)` in a `regex` pattern.
- `file_exists` with the default `exists` in a suite where the model creates no file.
- A gated tool in `allowed_tools` with no matching `--allow-tools` grant. The tool is removed from
  the session and reported on stderr as `not granted`, and the case quietly measures a model without
  it.
- Relying on `allowed_tools` to keep a tool away from the model. A run can offer a tool the case
  does not list: in all 12 runs of one case (`mp-sung-line-template`, `allowed_tools: [Read, Glob,
  Grep]`) on Claude Code 2.1.317, the session was also offered `Skill`, `Task`, `TaskStop` and
  `ToolSearch`, and two runs called `Skill` with no denial. Which tools such a run is offered, and
  which of their calls run, is what harness-ops behavior-probes
  [record 21](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/behavior-probes/records.md#21-a-plugin-eval-case-is-offered-and-runs-tools-its-allowed_tools-leaves-out)
  records, from a live run of its
  [`plugin-eval/unlisted-tools-offered`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/harness-ops/skills/behavior-probes/cases/plugin-eval/unlisted-tools-offered/expect.json)
  probe on Claude Code 2.1.318; read the record for the outcome.
  When a case must not reach a tool, add a `tool_used` grader for it with `min: 0` and `max: 0`
  instead of trusting the list. When checking what `allowed_tools` is documented to allow,
  fetch [`prompt.md` fields](https://code.claude.com/docs/en/plugin-evals#prompt-md-fields) live.
  As of 2026-11-03. Recheck trigger: that probe reports `fail` on a rerun, record 21's recheck
  trigger fires, or that section changes what a run offers beyond the listed tools.
- Taking `claude plugin eval init --bare`'s scaffold as-is without checking which grader it
  writes. Replace a paid `llm` grader with a deterministic one wherever one can decide the case.
  When checking what the scaffold writes, fetch
  [Write a case manually](https://code.claude.com/docs/en/plugin-evals#write-a-case-manually)
  live.
