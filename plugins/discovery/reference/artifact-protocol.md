# Plugin lifecycle artifact protocol

Protocol version: 2

This protocol is the lifecycle interoperability profile for repo-facing plugins that participate in
discovery, planning, implementation, verification, or handoff. The marketplace-wide topic-docs convention
owns placement, tiers, resolution, slug rules, runtime guards, and lifecycle:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
This profile owns only the cross-plugin artifact names and producer/consumer behavior.

## Ownership and resolution

Plugin `userConfig` is for personal, managed, or enable-time options. It is not a coordination surface
for repository artifacts. The tracked `.claude/topic-docs.yaml` concern file is the runtime authority;
consumer project instructions are an inference source when that file is absent.

Resolve the memory and contract slices through the topic-docs convention and the current plugin's
`reference/topic-docs.md` binding. An explicit topic argument may select the slug, but cannot introduce a
competing artifact root. The same slug names the topic in both tiers. Reject invalid roots or slugs using
the convention's guards rather than silently falling back to another location.

## Artifact kinds

Lifecycle plugins exchange these public artifacts:

- Memory tier: `EXPLORE.md`, `RESEARCH.md`, `<stage>-checklist.md`, `baselines/`, raw captures, and
  scratch under `<memory_dir>/<topic-slug>/`.
- Contract tier: `PRD.md`, `PLAN.md`, `design/`, and distilled `verification/` manifests under
  `<contract_dir>/<topic-slug>/` when `contract_tier: branch`.
- In `contract_tier: local`, contract kinds join the memory slice with the same relative layout.
- Session handoffs and branch review reports use the concern-scoped homes defined by topic-docs, not a
  topic slice.

Each plugin remains horizontally decoupled: it may read artifacts by this public protocol, but it must not
import sibling plugin internals or assume another plugin is installed. Namespaced skill invocation is
optional and must degrade to a visible manual handoff when unavailable.

The canonical repository copy and every participating plugin's
`reference/artifact-protocol.md` copy must remain byte-identical. A breaking artifact-name or
producer/consumer change increments this protocol version and updates all copies and consumers together.
Placement changes belong to the versioned topic-docs convention, not this profile.

## Missing prerequisites

If an artifact is required, stop with a visible message naming the missing file and the skill that can
produce it. If an artifact is helpful but optional, continue and surface a warning. Do not silently fall
back to conversation memory when a fresh session is expected to resume from disk.
