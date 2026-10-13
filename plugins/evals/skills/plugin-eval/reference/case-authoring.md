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
- [Common mistakes](#common-mistakes)

## Layout

```text
<plugin-root>/evals/            default eval dir; manifest experimental.evals overrides it
  <case-name>/
    prompt.md                   frontmatter plus the prompt body
    case.yaml                   alternative or companion; schema_version and name required
    graders/<grader-name>.md    one grader per file; the name is the filename minus .md
  mocks/<server>/<tool>.md      MCP tool answers
  mocks/.replay/                recorded agent-mock responses; commit these
  results/<timestamp>/          written by a run; gitignore it
```

- [ ] The eval dir sits under the plugin root, or the manifest's `experimental.evals` key points at
      it. A path target writes results under the plugin; a named installed plugin writes them under
      the current directory.
- [ ] Each case is a directory with `prompt.md`, `case.yaml`, or both. A loose file is not a case.
- [ ] Grader names are unique within the case. Duplicates are rejected at load, which exits 1 and
      looks exactly like a failing case.

## Precedence

- [ ] Which file wins when both are present, what `case.yaml` requires, and which fields exist
      only there: [case.yaml fields](https://code.claude.com/docs/en/plugin-evals#case-yaml-fields),
      as of 2026-10-07. Recheck trigger: that section's precedence sentence or its only-in-`case.yaml`
      table changes.
- [ ] Author one or the other per field; two sources for one value is how a suite starts
      measuring something nobody intended.

## The workspace starts empty

Every run gets a throwaway home, cwd, and config, so nothing on the authoring machine is present
unless the case routes it in explicitly.

- [ ] Anything the task needs is in the prompt body, in `context.add_dirs` (read-only), or written
      by `context.scaffold_script`, which runs only under `--scaffold`, as you, outside the sandbox.
- [ ] No `@path` mention is expanded into an attachment. A file the model must read needs `Read` in
      `allowed_tools` and a path that exists in the run.
- [ ] The environment is allowlisted. Anything the case needs beyond the basics and the provider
      auth variables is exported as `EVAL_<NAME>`; a key outside `EVAL_[A-Z0-9_]*` fails the run.
- [ ] The eval dir itself is hidden from the agent, so a case cannot read its own graders or its
      siblings. That is what makes the measurement honest; do not defeat it with `add_dirs`.
- [ ] Text a grader must match lives where the model will actually read it. A skill's hub file is
      loaded on invocation; a reference spoke is read only if the model chooses to, and a `Read`
      outside the empty workspace can be denied. Grade on terms the hub itself carries.

## Graders

- [ ] Pair one **result** grader with one **process** grader per case: an outcome check (`regex`,
      `llm`, `file_exists`) plus a path check (`tool_used`, `tool_order`). That pairing is what
      separates "the answer was right" from "the plugin is why".
- [ ] Split by expectation. A mechanical expectation (a format, a required or forbidden string, a
      tool call, a created file) gets a deterministic grader; a holistic one (tone, completeness,
      judgment) gets an `llm` judge. Prefer the four deterministic types. `regex`, `tool_used`, `tool_order`, and `file_exists` are
      free and stable; `llm` and `baseline` each cost three judge calls per run and get noisy on long
      inputs. Grade long output with a `regex` over the file's contents rather than a judge.
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

| Type | Fields | Passes when |
|---|---|---|
| `regex` | `pattern`, `flags`, `match`, `target` | The JS regex is found in the target; `match: not_contains` requires absence, `match: "count:N"` exactly N |
| `tool_used` | `tool`, `input_match`, `min`, `max` | Matching calls fall in range; the range defaults are in the `tool_used` row of [Grader types](https://code.claude.com/docs/en/plugin-evals#grader-types), as of 2026-10-11. Recheck trigger: that row or the grader's fields change |
| `tool_order` | `before`, `after` | The `tool_order` row of [Grader types](https://code.claude.com/docs/en/plugin-evals#grader-types), as of 2026-10-07. Recheck trigger: that row or the grader's fields change |
| `file_exists` | `path`, `exists` | The `file_exists` row of [Grader types](https://code.claude.com/docs/en/plugin-evals#grader-types), as of 2026-10-07. Recheck trigger: that row or the grader's fields change. Scaffold output and files the model only edits do not count |
| `llm` | `criteria`, `focus` | The judge votes PASS in at least 2 of 3. In the `.md` layout the body is the criteria |
| `baseline` | `baseline_file`, `criteria` | The judge finds the run at least as good as the reference `.jsonl` in the case dir |

Targets for `regex.target` and `llm.focus`: `last_message`, `trace` (JSON per line, where quotes
are JSON-escaped, so match `\"`), `files` (the **list of created paths**, not their contents),
`{ source: file, path: <p> }` (the contents), and `mock_calls`. Pick the target explicitly rather
than relying on the default, and assume a judge given `trace` sees only part of a long one.

- **Pointer**: when choosing a target, or judging a long trace, fetch
  [What a grader can look at](https://code.claude.com/docs/en/plugin-evals#what-a-grader-can-look-at)
  live for the default target and the judge's trace window.
- **As of**: 2026-10-11
- **Recheck trigger**: that section adds or renames a target, changes the default, or changes how
  much of a trace the judge reads.

## Mocks

- [ ] MCP tools are mocked by default from `evals/mocks/<server>/<tool>.md`. A mock file both answers
      the tool and grants it; its absence removes the tool rather than failing the call, which reads
      as the model choosing not to use it.
- [ ] A real server needs `--allow-real-servers` or `--mocks off`, plus an
      `--allow-tools "mcp__plugin_<plugin>_<server>__*"` grant, and runs as you, outside the sandbox.
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
- **As of**: 2026-10-11
- **Recheck trigger**: that section gains or loses a key, a default or bound changes, or the
  binary's validator rejects a case the static validator passed. Then re-derive the validator's
  FAIL tier with it.

Which grants need a sandbox backend is the CLI's rule too, and this checklist never lists the
tools.

- **Pointer**: when a case grants a tool outside the read-only set, fetch
  [Grant tools](https://code.claude.com/docs/en/plugin-evals#grant-tools) live for which grants
  run sandboxed and what each platform needs for a sandbox backend.
- **As of**: 2026-10-11
- **Recheck trigger**: that section changes which grants run under the sandbox or what a platform
  needs for the backend, or a run is refused for a grant that section does not name.

- [ ] `runs`, `max_turns`, and `timeout_seconds` are inside their bounds. Hitting `max_turns` is a
      run error, not a low score.
- [ ] `allowed_tools` requests only what the case needs. Read-only tools (the set in the
      validator's `READ_ONLY_TOOLS`, which mirrors the Grant tools pointer above) need no operator
      grant;
      anything else needs `--allow-tools`, and a grant that runs sandboxed also needs a sandbox
      backend on the machine (the Grant tools record above, in
      [Frontmatter bounds](#frontmatter-bounds); it has no heading of its own. As of 2026-10-11.
      Recheck trigger: that record moves or stops naming the backend).
- [ ] `tags` are set when the suite will ever be filtered. A case runs if **any** of its tags match.

Run the static validator before every paid pass; it checks the bounds above with no model call.

## Common mistakes

- `target: files` when the contents were meant. `files` is the list of created paths.
- Assuming `target` defaults to `trace`. It does not; read the default at the targets
  record's pointer in [Graders](#graders) (the record has no heading of its own). As of 2026-10-11.
  Recheck trigger: that record moves or its pointer stops covering the default target.
- Inline `(?i)` in a pattern. Case-insensitivity is `flags: i`.
- `file_exists` with the default `exists` in a read-only suite. Nothing is created, so the grader
  can never pass.
- A gated tool in `allowed_tools` with no matching `--allow-tools` grant. The tool is removed from
  the session and reported on stderr as `not granted`, and the case quietly measures a model without
  it.
- Taking `claude plugin eval init --bare`'s scaffold as-is without checking which grader it
  writes. Replace a paid `llm` grader with a deterministic one wherever one can decide the case.
  When checking what the scaffold writes, fetch
  [Write a case manually](https://code.claude.com/docs/en/plugin-evals#write-a-case-manually)
  live. As of 2026-10-11. Recheck trigger: that section changes what `init --bare` writes.
