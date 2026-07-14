# Plugin artifact protocol

Protocol version: 1

This protocol is the shared artifact contract for repo-facing plugins that participate in a discovery,
planning, implementation, or handoff lifecycle.

## Ownership

Plugin `userConfig` is for personal, managed, or enable-time plugin options. It is not the coordination
surface for tracked repository artifacts. Repo-shared artifact locations belong to the consuming
repository's own documented convention (`CLAUDE.md`, `AGENTS.md`, `.claude/rules`, or a repo-owned config
file). When no convention exists, these plugins use `.work/<topic-slug>/`.

## Resolution

Resolve artifact destinations in this order:

1. Explicit invocation arguments: `--artifacts-dir <repo-relative-base>` selects the base directory and
   `--topic <slug>` selects the topic. Either argument may be supplied independently.
2. A consuming-repo convention declared in `CLAUDE.md`, `AGENTS.md`, or `.claude/rules`.
3. The default `.work/<topic-slug>/` directory at the repository root.

The resolved topic root is `<artifact-base>/<topic-slug>/`. Reject bases that are absolute paths,
contain a `..` segment, or escape the repository root after normalization. Topic slugs are lowercase
kebab-case, at most 40 characters, and derived from the task, plan title, or current branch name when not
supplied. If derivation is ambiguous, ask instead of selecting an unrelated branch-derived name.

## Layout

Discovery, planning, and implementation plugins may write different artifact types, but they share the
same topic root:

- `.work/<topic-slug>/EXPLORE.md`
- `.work/<topic-slug>/RESEARCH.md`
- `.work/<topic-slug>/PRD.md`
- `.work/<topic-slug>/PLAN.md`
- `.work/<topic-slug>/design/`
- `.work/<topic-slug>/baselines/`
- `.work/<topic-slug>/verify/`

Each plugin remains horizontally decoupled: it may read artifacts by this public protocol, but it must not
import sibling plugin internals or assume another plugin is installed. Namespaced skill invocation is
optional and must degrade to a visible manual handoff when unavailable.

The distributable copy at each participating plugin's `reference/artifact-protocol.md` must match this
contract. A breaking layout or resolution change increments the protocol version and requires all copies
and consumers to change together.

## Missing prerequisites

If an artifact is required, stop with a visible message naming the missing file and the skill that can
produce it. If an artifact is helpful but optional, continue and surface a warning. Do not silently fall
back to conversation memory when a fresh session is expected to resume from disk.
