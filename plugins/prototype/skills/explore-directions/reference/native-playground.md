# The marketplace `playground` plugin: verification record

Detail behind the playground Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part record: the claim, the basis it rests on, the date
it was checked (left empty on pointer rows), and the event that makes it worth checking again.
Nothing here asserts the plugin is installed in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `playground` is a first-party marketplace plugin in `anthropics/claude-plugins-official`, not a bundled Claude Code surface | The upstream repository at commit `ed404106fcd80ba98ecb7c851e531dcb626d13b7` (HEAD of main, re-verified by fetch) | 2026-09-01 | The default branch moves past that commit with changes under `plugins/playground`, or the plugin is renamed, removed, or absorbed into the CLI as a bundled skill |
| Its `playground` skill is where this skill routes an ask to explore a parameter space and hand back a prompt (the routing rule below); what its page holds and which asks it targets are read upstream, not here | Pointer: when deciding whether an ask is the playground's, fetch [the upstream `playground` skill's `SKILL.md` at that commit](https://github.com/anthropics/claude-plugins-official/blob/ed404106fcd80ba98ecb7c851e531dcb626d13b7/plugins/playground/skills/playground/SKILL.md) live |  |  |
| The `playgrounds` wrapper plugin in this marketplace declares the cross-marketplace dependency and carries the install uplift, so the route has a landing surface where the wrapper is installed | The wrapper's manifest (it names `playground` as a dependency) and its `use` skill in this marketplace | 2026-09-29 | The wrapper is renamed or removed, or drops the dependency |

## Why the verdict is complementary

Both render a browser page with switchable controls. A playground explores an arbitrary parameter
space and hands the chosen settings back as a prompt. This skill varies the user's own UI in a
local mockup by default (or on its real stack on request) so one direction can be picked and the
rest discarded; its output is
a winning-variant key and notes, not a prompt. Explorer-shaped asks route out; "what should this
page look like" stays here.

## Presence

A marketplace plugin resolves only where it is installed and enabled. The routing states what to do
when the `playground` skill or the wrapper resolves, and says the capability exists as an
installable plugin when neither does.

## Boundary with this skill

Both produce a browser page with controls that change what is shown, so an ask to "try options
visually" can mean either:

- **`playground` (marketplace plugin, first-party, from `anthropics/claude-plugins-official`).** Its
  `playground` skill builds an interactive parameter explorer whose output returns to the
  conversation as a prompt.
- **This skill (marketplace plugin).** Switchable UI variants of the user's own project (a local
  mockup in the app's own look by default, or its real header, data, and routes on request); the
  winning-variant key is kept and the rest is thrown away.

**Routing.** When the ask is to explore a parameter space and hand back a prompt, route it to the
`playground` skill when that plugin is enabled, or to `/playgrounds:use` when that wrapper is
enabled. When neither is, say the capability exists as an installable plugin and do not build an
imitation. Keep questions about how the user's own screen should be laid out here.

**Mutation gate.** A playground writes its own page; this skill never builds one on its behalf.
Routing ends the turn: no offer to write the explorer as a plain task or a one-off page either,
since that is the imitation the routing rule declines.

**Availability is never assumed.** The plugin is present only where it is installed from its
marketplace; this section states what to do when it resolves, never that it is present. The
four-part records live in this file.
