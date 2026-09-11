# The bundled `design` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The `visualization` plugin's `visualize` skill keeps its own record against
the same surface in its decision-matrix catalog.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| The commands table lists `/design` as a Skill: "Draft UI mockups, screen flows, landing pages, or posters as artboards on one canvas, published as an artifact that runs a research preview of Claude Design's editor". Where saving is enabled for the account the artboards are hand-editable and Save publishes a new version; otherwise the draft is view-plus-PNG/PDF-export. "Requires a session where artifacts are available and Claude Code v2.1.234 or later" | The `/design` row on <https://code.claude.com/docs/en/commands>; "Draft a design canvas" on <https://code.claude.com/docs/en/artifacts> shows the user running `/design <brief>` | 2026-09-11 | Either page changes the description, the gate, or the version floor |
| Artifacts availability, which `/design` inherits: Pro, Max, Team, or Enterprise plan; a claude.ai login; the Anthropic API provider (not Bedrock, Google Cloud, or Foundry); no CMEK, HIPAA, or Zero Data Retention; CLI 2.1.183 or later or the desktop app; off by default in Agent SDK, GitHub Action, and MCP-server contexts | The Availability table on the artifacts page | 2026-09-11 | The table changes |
| The installed binary registers `design` as a Claude Design hub with **model invocation disabled** and user invocation on: menu line "Work with Claude Design (claude.ai/design): create, import, export, sync, login"; description "Hub for Claude Design (claude.ai/design): routes `sync`/`login` to their dedicated commands and maps `import`/`export`/`status`/free-form prompts to the native tool. Always fetches the live Claude Design instructions rather than shipping a vendored copy"; argument hint `[sync\|login\|consent\|revoke\|import\|export\|status\|<prompt>]`; enabled only behind an `allow_design_sync` setting, a policy gate, and a feature flag. A local `design consent \| revoke` command sits beside it | String search of the installed 2.1.263 binary (`disableModelInvocation:!0`, `userInvocable:!0`, `isEnabled:()=>nSe()` where `nSe` tests `allow_design_sync` and two further gates) | 2026-09-11 | A release changes `disableModelInvocation`, the gate, or the subcommand set, or a release note first names the skill (none through 2.1.268) |
| Consequence: the model cannot invoke the skill and a user-invocable-only skill is hidden from the model's skill list, so presence cannot be read from the listing | The `skillOverrides` value table on <https://code.claude.com/docs/en/skills> ("user-invocable-only: hidden from Claude, visible in the `/` menu") describes the same visibility class | 2026-09-11 | Model invocation is re-enabled, or the listing shows user-invocable-only skills |

The registration in the 2.1.251 binary (verified 2026-08-31) described a design canvas with no
model-invocation gate; the 2.1.263 registration is the hub above with the gate on. The registry
row's trigger, a change in bundled-skill invocability or the commands reference naming the skill,
has fired on both counts, and this record replaces the earlier one.

## Why the verdict is complementary

`/design` drafts artboards on a persistent, versioned, shareable canvas that the user edits by
hand. This skill builds throwaway variants on the real stack or as a local HTML mockup, switchable
from a control bar, and captures only the winning-variant key. The canvas is the right shape when
the user wants to keep tweaking a layout; the mockup is right when the question is which
direction, answered and discarded.

## Presence and the offer

The model never invokes `design` and never asserts it is present. When the Artifact tool resolves
in the session (the same gates the canvas inherits) and the intent selector lands on the HTML
mockup substrate, name `/design <brief>` once as a user-run alternative, with the lifecycle
difference stated, and build the mockup unless the user picks the canvas. A user who reports no
such command has a session without it; drop the offer for the rest of the session.
