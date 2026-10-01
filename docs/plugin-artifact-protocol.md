# Plugin lifecycle artifact protocol

Protocol version: 4

This protocol is the lifecycle interoperability profile for repo-facing plugins that participate in
discovery, planning, implementation, verification, or handoff. It owns the cross-plugin artifact
names, where they live, and producer/consumer behavior.

## Ownership and placement

Plugin `userConfig` is for personal, managed, or enable-time options. It is not a coordination surface
for repository artifacts.

Working artifacts live in the memory slice `<memory_dir>/<topic-slug>/`. `<memory_dir>` is `.work/`
unless the consumer's project instructions declare another root, and it is never committed. Durable
plans and specs live in the pull request body and the linked issue, not in committed files. An
explicit topic argument may select the slug, but cannot introduce a competing artifact root. Reject an
invalid root or slug rather than silently falling back to another location.

## Artifact kinds

Lifecycle plugins exchange these public artifacts under `<memory_dir>/<topic-slug>/`:

- `INDEX.md` (the reserved per-slice index), `EXPLORE.md`, `RESEARCH.md`, `<stage>-checklist.md`,
  `baselines/`, raw captures, and scratch. A topic slice is recursive: a decomposed slice holds child
  slices, and the same names are reserved at every depth. Entering a slice reads `INDEX.md` first; in
  an index-less leaf the sole artifact is the entry point.
- `PRD.md`, `PLAN.md`, `design/`, and distilled `verification/` manifests. Publish their durable
  content to the pull request body or the linked issue.
- Session handoffs and branch review reports are not part of a topic slice. Each lives in its own
  concern-scoped home under the memory root.

Each plugin remains horizontally decoupled: it may read artifacts by this public protocol, but it must not
import sibling plugin internals or assume another plugin is installed. Namespaced skill invocation is
optional and must degrade to a visible manual handoff when unavailable.

The canonical repository copy and every participating plugin's
`reference/artifact-protocol.md` copy must remain byte-identical. A breaking artifact-name, placement, or
producer/consumer change increments this protocol version and updates all copies and consumers together.

## Missing prerequisites

If an artifact is required, stop with a visible message naming the missing file and the skill that can
produce it. If an artifact is helpful but optional, continue and surface a warning. Do not silently fall
back to conversation memory when a fresh session is expected to resume from disk.
