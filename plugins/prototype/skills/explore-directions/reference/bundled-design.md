# The bundled `design` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `visualization` plugin's `visualize` skill keeps its own record against
the same surface in its decision-matrix catalog.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/design` drafts a hand-editable design canvas published as an Artifact, and is gated. What it drafts, how the person edits and exports it, and its gates are read live, not from this row | Pointer: when offering `/design` or answering what it produces or requires, fetch [Artifacts: Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas) and its parent [Start from a Slides, Design, or Docs template](https://code.claude.com/docs/en/artifacts#start-from-a-slides-design-or-docs-template) live | 2026-10-11 | Either section changes what `/design` drafts, its gate, or its version floor |
| The canvas inherits every artifacts availability condition; this skill never lists them | Pointer: when deciding whether the canvas can be offered, fetch [Artifacts: Availability](https://code.claude.com/docs/en/artifacts#availability) live | 2026-10-11 | The Availability table adds, drops or changes a row |
| History: the 2.1.263 binary carried two `design` registrations, a model-invocable canvas skill and a model-invocation-disabled Claude Design hub, each behind its own enablement gates | Probe: the `design` and `design-sync` records in `docs/native-surfaces/records.json` (string search of the installed 2.1.263 binary) | 2026-09-11 | Superseded by the next row; kept as history |
| The 2.1.285 binary resolves one bundled `design` registration, model-invocation-disabled, user-invocable and gated. It supersedes the history row for routing: the model never lists or invokes `design`, so this skill offers `/design` to the person instead. It is a user-only design-Artifact creator, not the hub (the hub's text now belongs to the separate `ClaudeDesign` tool); its identity string, which the offer quotes, is held in the probe record | Probe: the `design` records in `docs/native-surfaces/records.json` (binary extraction of the installed 2.1.285 build, 2026-09-29, plus a targeted string search of the same binary, 2026-09-30) | 2026-09-30 | A release makes the `design` registration model-invocable, changes its description (the identity string the offer quotes), changes its gating, or splits or merges its registrations |
| Settings can remove the skill | Pointer: when a person asks how to turn `/design` off, fetch [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills) and [`skillOverrides`](https://code.claude.com/docs/en/settings-reference#skilloverrides) live | 2026-10-11 | Either setting is renamed or changes what it removes |
| No release note names a design-family surface, so the only version floor is the one the first row's pointer reads | Probe: the changelog cross-check in the `design` records of `docs/native-surfaces/records.json` | 2026-09-11 | A changelog entry names `/design` or the hub |

Earlier probe history (verified 2026-08-31): the 2.1.251 binary carried the same canvas
registration as the history row, with its rollout flag defaulting off at v2.1.234 and on at
v2.1.263; the hub is the design-sync family the registry records as a `defer` row in the
`design-sync` records of `docs/native-surfaces/records.json` (recheck when those records change
disposition or a release note first names a design-family surface).

## Why the verdict is complementary

`/design` drafts a persistent, shareable canvas that the user edits by hand. This skill builds throwaway variants on the real stack or as a local HTML mockup, switchable
from a control bar, and captures only the winning-variant key. The canvas is the right shape when
the user wants to keep tweaking a layout; the mockup is right when the question is which
direction, answered and discarded.

## Presence and the offer

The model cannot check presence: a model-invocation-disabled skill never enters its listing. When
the intent selector lands on the HTML mockup substrate, build the mockup by default and give the
user the conditional sentence from the Boundary section ("If /design is available in your session
..."), with the lifecycle difference stated; the user checks their own session and runs
`/design <scope>` if they want the canvas.
