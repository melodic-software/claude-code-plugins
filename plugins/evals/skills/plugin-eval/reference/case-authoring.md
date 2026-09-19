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

- [ ] With both files present, `prompt.md` frontmatter **overrides** the matching `case.yaml`
      fields, the `prompt.md` body is the prompt, and `graders/*.md` are appended after any
      `case.yaml` graders. Author one or the other per field; two sources for one value is how a
      suite starts measuring something nobody intended.
- [ ] `case.yaml` alone requires `schema_version` and `name`. It is also the only place
      `context.scaffold_script`, `context.history_file`, and `context.add_dirs` exist.

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
- [ ] Prefer the four deterministic types. `regex`, `tool_used`, `tool_order`, and `file_exists` are
      free and stable; `llm` and `baseline` each cost three judge calls per run and get noisy on long
      inputs. Grade long output with a `regex` over the file's contents rather than a judge.
- [ ] A grader that cannot pass without the plugin (a `tool_used` on `tool: Skill`, or anything
      `arm: with-only`) is excluded from scoring in both arms and reported as an indicator. Use
      `arm: both` when the check must score in both arms, which a must-not-invoke check
      (`min: 0` **and** `max: 0`) requires.
- [ ] Drop any assertion that passes in both arms and measures nothing. A case at 1.00 on both sides
      is a passing case and a null measurement.

| Type | Fields | Passes when |
|---|---|---|
| `regex` | `pattern`, `flags`, `match`, `target` | The JS regex is found in the target; `match: not_contains` requires absence, `match: "count:N"` exactly N |
| `tool_used` | `tool`, `input_match`, `min`, `max` | Matching calls fall in range; `min` defaults to 1 and `max` to unlimited |
| `tool_order` | `before`, `after` | Both were called and the first `before` precedes the first `after`; each is a tool name or `{tool, input_match}` |
| `file_exists` | `path`, `exists` | A file the model **created** during the run matches the glob. Scaffold output and edited files do not count |
| `llm` | `criteria`, `focus` | The judge votes PASS in at least 2 of 3. In the `.md` layout the body is the criteria |
| `baseline` | `baseline_file`, `criteria` | The judge finds the run at least as good as the reference `.jsonl` in the case dir |

Targets for `regex.target` and `llm.focus`: `last_message` (the default), `trace` (JSON per line,
where a judge sees only the first 12 and last 12 messages and quotes are JSON-escaped, so match
`\"`), `files` (the **list of created paths**, not their contents), `{ source: file, path: <p> }`
(the contents), and `mock_calls`.

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

| Fact | Basis and as-of | Recheck trigger, and what to do when it fires |
|---|---|---|
| The complete `prompt.md` frontmatter key set is `schema_version` (currently `"1.1"`), `name`, `description`, `tags`, `plugins`, `runs` (default 3, range 1 to 50), `expected_outcome`, `model`, `max_turns` (default 10, maximum 200), `timeout_seconds` (default 300, maximum 3600), `allowed_tools`, `append_system_prompt`, and `env`. An unknown key is an error (`prompt.md: unknown frontmatter key`), each grader type's option set is strict, `weight` must be positive, and a case whose `schema_version` major exceeds what the binary supports is refused | <https://code.claude.com/docs/en/plugin-evals> and the binary's own validator messages, verified 2026-09-12 | Recheck trigger: the page's frontmatter table gains or loses a key, or a bound changes. Then re-read the page, re-derive this row and the validator's FAIL tier together, and refresh this record with the outcome |

- [ ] `runs`, `max_turns`, and `timeout_seconds` are inside their bounds. Hitting `max_turns` is a
      run error, not a low score.
- [ ] `allowed_tools` requests only what the case needs. Read-only tools (`Read`, `Glob`, `Grep`,
      `NotebookRead`, `Skill`, `Agent`, `TodoWrite`, the `Task*` tools) need no operator grant;
      anything else needs `--allow-tools` and, for `Bash`, `Write`, or `Edit`, a sandbox backend.
- [ ] `tags` are set when the suite will ever be filtered. A case runs if **any** of its tags match.

Run the static validator before every paid pass; it checks the bounds above with no model call.

## Common mistakes

- `target: files` when the contents were meant. `files` is the list of created paths.
- Assuming `target` defaults to `trace`. It defaults to `last_message`.
- Inline `(?i)` in a pattern. Case-insensitivity is `flags: i`.
- `file_exists` in a read-only suite. Nothing is created, so the grader can never pass.
- A gated tool in `allowed_tools` with no matching `--allow-tools` grant. The tool is removed from
  the session and reported on stderr as `not granted`, and the case quietly measures a model without
  it.
- Taking `claude plugin eval init --bare`'s scaffold as-is: its default grader is `llm`, the paid
  type.
