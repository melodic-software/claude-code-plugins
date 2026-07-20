# Convention config resolution

How `/source-control:commit`, `/source-control:pull-request`, and `/source-control:setup` resolve the
tracked commit-subject / PR-title convention. All three skills read this one document; none bakes its
own layering rules.

Implements the tracked-rich-config seam in
[`docs/MIGRATION-PLAYBOOK.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/MIGRATION-PLAYBOOK.md).

## The config surface

Markdown, one `## <key>` H2 per key, the value as the section body:

- `subject_pattern` — required; the literal keyword `Conventional Commits`, or an anchored regex
  (`^…`-style). Exactly one value, never a list and never a plain-language description — a convention
  with several accepted shapes is expressed as alternation inside the one regex
  (`^(?:feat|fix): .+|^[A-Z]+-\d+: .+`), which every consumer already evaluates correctly. A list form
  would need a serialization grammar and an any-matches rule that nothing here defines, and a reader
  handing a multi-line value straight to a matcher would reject valid subjects or build an invalid
  regex.
- `type_list` — the type vocabulary; meaningful only when `subject_pattern` is
  Conventional-Commits-shaped, omitted otherwise.
- `pr_title_pattern` — the PR-title shape, or the deferral marker spelled exactly
  `` Same as `subject_pattern`. `` (capital S, backticked key, trailing period). The match is literal:
  any other casing or punctuation is treated as a pattern in its own right.
- `trailer_policy` — the attribution-trailer template, or `none`. Absent means the `/commit` default
  trailer applies.

Absent sections are absent, never empty.

## The three layers

Resolve every read from the repo root — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`. A cwd-relative read from a nested directory finds
`<subdir>/.claude/source-control.md`, misses the repo-root config, and silently degrades.

Layer, in resolution order — a later layer refines an earlier one:

1. **`~/.claude/source-control.md`** — user-global. The operator's own preference, following them
   across repos and machines. Their home directory, not consumer repository data.
2. **`${REPO_ROOT}/.claude/source-control.md`** — team, tracked. The shared convention; the layer
   `/source-control:setup apply` writes by default.
3. **`${REPO_ROOT}/.claude/source-control.local.md`** — personal overlay, gitignored. A per-machine
   or per-operator deviation from team policy, never committed.

Each layer is optional, and **fall-through is per key, not per file**. A key absent from every layer
is unresolved even when some layer exists — a user-global file contributing only `trailer_policy`
leaves `subject_pattern` exactly as unresolved as no file at all. Each unresolved key falls through
independently to the repo's own `CLAUDE.md`/rules/commit-msg hook, then the bundled Conventional
Commits default. Never gate that fall-through on file presence.

## Merge semantics: per-key override

**A later layer replaces an earlier layer's value key by key, and never drops the base layer
wholesale.** A key absent from a later layer keeps the earlier layer's value.

This is a deliberate deviation from the seam's concatenating default, recorded rather than silent.
Concatenation is right for the first-party `security-guidance` precedent, whose layers are prose
blocks that genuinely accumulate. Every key here is a scalar or a closed list: two `subject_pattern`
regexes cannot concatenate into a third valid regex, and a concatenated `trailer_policy` would emit
two trailers. This is the seam's sanctioned per-key case.

Worked example — user-global sets `trailer_policy: none`, team sets `subject_pattern` to a
ticket-prefix regex and leaves `trailer_policy` unset, local overlay sets nothing: the effective
config is the team `subject_pattern` with the user-global `trailer_policy: none`.

**`type_list` is bound to the effective `subject_pattern`, not merged independently.** It is a
property of a Conventional-Commits-shaped pattern, so after the layers merge, an inherited
`type_list` is dropped whenever the *effective* `subject_pattern` is a custom regex — even when the
layer supplying that pattern said nothing about `type_list`. A user-global `Conventional Commits`
plus its type list, overridden by a team ticket-prefix regex, resolves to the team pattern with **no**
`type_list`; retaining it per key would leave `/commit` pre-checking against a vocabulary the
effective pattern does not use. The reverse also holds: an effective Conventional-Commits pattern with
no `type_list` in any layer resolves to the bundled 11-type list.

`pr_title_pattern` resolving to `Same as \`subject_pattern\`.` expands against the **effective**
`subject_pattern` after all three layers merge, not against the pattern in its own layer.

## Consumer `.gitignore`

The overlay convention needs one line in the consuming repo:

```gitignore
.claude/*.local.*
```

No skill in this plugin writes the consumer's root `.gitignore` — `/source-control:setup` recommends
the line and leaves the edit to the consumer.

## Failure modes

- **Team layer gitignored → hard STOP.** Teammates would never receive the shared convention.
  Surface the matching rule and stop; do not degrade silently.
- **Local overlay not ignored, or already tracked → FAIL, with different remediations.** The overlay
  is personal by contract; a committed one leaks a per-operator deviation into team history. A
  missing ignore rule is fixed by the `.gitignore` line; an already-tracked overlay is fixed by
  untracking it, since an ignore rule never applies to a file already in the index.
- **A layer is malformed** (a non-machine-checkable `subject_pattern`, an unparsable section) →
  surface the error, name the layer, and resolve as if that layer were absent. Unknown H2 sections
  are inert.
