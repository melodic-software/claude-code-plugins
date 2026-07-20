# Convention config resolution

How `/source-control:commit`, `/source-control:pull-request`, and `/source-control:setup` resolve the
tracked commit-subject / PR-title convention. All three skills read this one document; none bakes its
own layering rules.

Implements the tracked-rich-config seam in
[`docs/MIGRATION-PLAYBOOK.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/MIGRATION-PLAYBOOK.md).

## The config surface

Markdown, one `## <key>` H2 per key, the value as the section body:

- `subject_pattern` — required; the literal keyword `Conventional Commits`, or an anchored regex
  (`^…`-style), or an any-of list of anchored regexes. Never a plain-language description.
- `type_list` — the type vocabulary; meaningful only when `subject_pattern` is
  Conventional-Commits-shaped, omitted otherwise.
- `pr_title_pattern` — the PR-title shape, or the literal `Same as \`subject_pattern\`.`
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

Each layer is optional. All three absent → this rung yields nothing and resolution falls through to
the repo's own `CLAUDE.md`/rules/commit-msg hook, then the bundled Conventional Commits default.

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
- **Local overlay NOT gitignored → warn.** The overlay is personal by contract; a tracked one leaks
  a per-operator deviation into team history. Recommend the `.gitignore` line.
- **A layer is malformed** (a non-machine-checkable `subject_pattern`, an unparsable section) →
  surface the error, name the layer, and resolve as if that layer were absent. Unknown H2 sections
  are inert.
