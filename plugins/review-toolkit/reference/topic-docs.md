# Topic-docs placement — where review findings land

How `/review-toolkit:quality-gate` and `/review-toolkit:code-review-fanout` resolve where review
reports land in a consuming repo. Both skills read this one document; neither bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

**Memory tier only, concern-scoped.** A review report's axis is the **branch**, not a topic, so
reports sit under the memory root's reserved `reviews/` name rather than inside a topic slice:

| Artifact | Location (default) |
|---|---|
| `quality-gate` findings | `.work/reviews/<branch-slug>/<UTC-timestamp>-<mode>.md` — never committed |
| `code-review-fanout` ranked reports | `.work/reviews/<branch-slug>/<UTC-timestamp>-<topic>.md` — never committed |

Reports are write-only process output; nothing downstream enforces against them, which is what makes
them memory-tier by the convention's placement question.

## Resolution (earlier wins)

1. `.claude/topic-docs.yaml` present → its `memory_dir`: `<memory_dir>/reviews/<branch-slug>/`.
2. A review-artifacts location declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it,
   and offer to persist it into the concern file (prose is an inference source, not the runtime
   authority).
3. The documented default: `.work/reviews/<branch-slug>/`.

Both skills review a git diff; with no git repo there is nothing to review, and the skills stop
before any write — the convention's no-project-root fallback surface never comes into play here.

## Branch slug and timestamps

- `<branch-slug>` — the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character
  replaced by `-`. This is the branch axis, deliberately distinct from the convention's topic-slug
  form: the mapping is lossy (`feature/foo` and `feature-foo` collide), which the fanout fix action
  compensates for with its `branch:` frontmatter check.
- Timestamps — ISO-basic UTC `YYYYMMDDTHHMMSSZ` (`date -u +%Y%m%dT%H%M%SZ`), colon-free and
  Windows-safe; lexical sort equals chronological sort.

## Runtime guards

- **Self-ignore guard:** the session's first memory-tier write verifies the **resolved memory
  root** (whatever `memory_dir` names — never a hardcoded `.work`) contains a `.gitignore` with
  `*`, creating it (announced) when absent — fresh clones heal on first write. Once per session,
  per the contract.
- No skill in this plugin ever edits the consumer's root `.gitignore`.

## Legacy grace — dual-read + old pins (`.claude/review/`)

This binding applies the contract's grace algorithm (the convention's "Deprecation and migration")
with slice axis = branch and legacy root = `.claude/review/`. The pre-convention default was
`.claude/review/<branch-slug>/`. During the deprecation window:

- **Short-circuit:** a populated resolved `<memory_dir>/reviews/<branch-slug>/` (default
  `.work/reviews/`) for the current branch proves the slice isn't pinned — skip the legacy probe.
- **Reads** (the fanout `fix` action, any report lookup): check the resolved
  `<memory_dir>/reviews/<branch-slug>/` first; when it holds no matching report and legacy
  `.claude/review/<branch-slug>/` does, read the legacy directory and emit the deprecation note.
- **Writes:** when the new home holds no reports for the current branch and legacy
  `.claude/review/<branch-slug>/` does, keep writing there (old pins — never split one branch's
  review history across roots) and emit the deprecation note with the guarded migration command:
  `mkdir -p <memory_dir>/reviews && mv .claude/review/<branch-slug> <memory_dir>/reviews/<branch-slug>`
  (substitute the resolved memory root — default `.work`).
  Fresh branches and fresh repos use the new home directly.
- **Sunset:** dual-read and the legacy fallback are removed at this plugin's next major version, no
  sooner than one minor release after this notice shipped.
