# The bundled `design` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `visualization` plugin's `visualize` skill keeps its own record against
the same surface in its decision-matrix catalog.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| The commands table lists `/design` as a Skill: "Draft UI mockups, screen flows, landing pages, or posters as artboards on one canvas, published as an artifact that runs a research preview of Claude Design's editor". Where saving is enabled for the account the artboards are hand-editable and Save publishes a new version; otherwise the draft is view-plus-PNG/PDF-export. "Requires a session where artifacts are available and Claude Code v2.1.234 or later" | The `/design` row on <https://code.claude.com/docs/en/commands>; "Draft a design canvas" on <https://code.claude.com/docs/en/artifacts> | 2026-09-11 | Either page changes the description, the gate, or the version floor |
| Artifacts availability, which the canvas inherits: Pro, Max, Team, or Enterprise plan; a claude.ai login; the Anthropic API provider (not Bedrock, Google Cloud, or Foundry); no CMEK, HIPAA, or Zero Data Retention; CLI 2.1.183 or later or the desktop app; off by default in Agent SDK, GitHub Action, and MCP-server contexts | The Availability table on the artifacts page | 2026-09-11 | The table changes |
| The installed binary registers the canvas skill as **model-invocable and user-invocable**: menu line "Draft a design on a canvas Artifact, editable where saving is enabled (Claude Design preview)", description beginning "Create a design canvas", argument hint `[what to design]`, `userInvocable` on, no `disableModelInvocation`, subcommand dispatch on bare words only, enabled by a first-party-context check, a rollout flag that defaults on, and an Artifact tool whose schema carries `capabilities` | String search of the installed 2.1.263 binary; the skill is listed to the model with the canvas description in a first-party session on that build | 2026-09-11 | A release adds a model-invocation gate, changes the enablement check, or flips the flag default |
| A second bundled registration named `design` is a Claude Design hub with **model invocation disabled**: menu line "Work with Claude Design (claude.ai/design): create, import, export, sync, login", argument hint `[sync\|login\|consent\|revoke\|import\|export\|status\|<prompt>]`, enabled only behind an `allow_design_sync` setting, a policy gate, and a feature flag; a local `design consent \| revoke` command sits beside it | String search of the same binary | 2026-09-11 | The hub's gate or invocation flag changes, or the two registrations merge |
| The 2.1.285 binary resolves one bundled registration named `design`, **model invocation disabled** (`model_invocable` false), user-invocable, gated, with no resolved description. It supersedes the model-invocable row above for routing: the model never lists `design` and never invokes it, so this skill offers `/design` to the person instead. The extraction does not establish whether the canvas registration gained the gate or the hub now answers to the name | A binary extraction of the installed 2.1.285 build | 2026-09-29 | A release makes the `design` registration model-invocable, changes its gating, or splits or merges its registrations |
| Settings can remove the skill: `disableBundledSkills` turns off bundled skills, and a `skillOverrides` entry naming `design` hides it | The `disableBundledSkills` and `skillOverrides` rows on <https://code.claude.com/docs/en/settings-reference> | 2026-09-29 | Either setting is renamed or changes scope |
| No release note names a design-family surface, so no version floor beyond the docs' v2.1.234 is statable | <https://code.claude.com/docs/en/changelog>, newest entry 2.1.268 | 2026-09-11 | A changelog entry names `/design` or the hub |

The registration in the 2.1.251 binary (verified 2026-08-31) matches the canvas skill above except
for the rollout flag's default, which was off at v2.1.234 and is on at v2.1.263; the hub is the
design-sync family the registry records as a `defer` row.

## Why the verdict is complementary

`/design` drafts artboards on a persistent, versioned, shareable canvas that the user edits by
hand. This skill builds throwaway variants on the real stack or as a local HTML mockup, switchable
from a control bar, and captures only the winning-variant key. The canvas is the right shape when
the user wants to keep tweaking a layout; the mockup is right when the question is which
direction, answered and discarded.

## Presence and the offer

The model cannot check presence: a model-invocation-disabled skill never enters its listing. When
the intent selector lands on the HTML mockup substrate, build the mockup by default and give the
user the conditional sentence from the Boundary section ("If /design is available in your session
..."), with the lifecycle difference stated; the user checks their own session and runs
`/design <scope>` if they want the canvas.
