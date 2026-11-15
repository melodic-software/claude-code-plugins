# Switch plugin sets by profile and gate optional calls on enabled skills

- Status: accepted
- Date: 2026-11-15
- Refs: [#16428](https://github.com/melodic-software/claude-code-plugins/issues/16428),
  [#16430](https://github.com/melodic-software/claude-code-plugins/issues/16430); owner decisions
  of 2026-11-15 (design rounds Q55 to Q70 and the plan approval, relayed by the control-hub session)

## Context

Every enabled plugin adds its skills to the listing each session carries, and a session doing one
kind of work needs a fraction of them. Claude Code has no on/off set for plugins
([#6462](https://github.com/melodic-software/claude-code-plugins/issues/6462) left one unbuilt), and
the `core` bundle tried to stand in for one by declaring a fixed list as dependencies. A profile
leaves a plugin installed and switches it off, so a gate that asked whether a plugin is installed
could send a call to a skill that is not there. Hooks that every session runs live in skill plugins,
so switching such a plugin off for a session also switched off its session-wide hooks.

## Decision

1. **Profile file format.** One YAML file per profile, in the subset `lib/yaml-subset.mjs` parses,
   with the keys `description`, `plugins`, `optional`, `remove`, `exclude` and `hide_skills`. Every
   plugin id is `name@marketplace`, shipped files included. The plugin-profiles plugin owns the
   grammar and the files; no other file lists a profile's members.
2. **Profile homes.** Three levels: shipped in the plugin's `profiles/`; the user's
   `~/.claude/plugin-profiles/`; the repository's `<convention home>/plugin-profiles/`. The user
   level departs from [ADR 0075](0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
   fix 9, which retired user-global files into `userConfig`: a profile is authored data a person
   edits and shares as a file, not a setting value.
3. **Extend rule.** A same-named file at a higher level extends the one below it: members = lower ∪
   `plugins` − `remove`; `exclude`, `optional` and `hide_skills` are unioned. An `exclude` naming an
   always-on member is rejected.
4. **Marketplace governance.** A profile writes `enabledPlugins` entries only for plugins of the
   marketplaces its ids (and the always-on profile's) name. Plugins of any other marketplace are
   left as they are and listed as left alone.
5. **Hook units.** Session-wide hooks move into two hook-only plugins, `session-telemetry` and
   `plugin-diagnostics`. The rule they follow is the hook-unit rule in
   [`docs/review/hooks.md`](../review/hooks.md): a hook unit depends on nothing of another plugin.
   Whether harness-ops declares `session-telemetry` as a dependency is open with the owner.
6. **`core` is removed** in the same release that ships plugin-profiles; the always-on profile
   replaces its list.
7. **Optional calls gate on enabled.** The
   [seam-phrasing contract](../contracts/seam-phrasing/README.md#the-shape) gate asks whether the
   target skill is among the available skills (its plugin enabled), not whether the plugin is
   installed, and every gate site says "enabled".

### Probe record (Claude Code 2.1.325, 2026-11-15)

Throwaway marketplace in an isolated `CLAUDE_CONFIG_DIR` for the plugin probes.

| Probe | Result | Evidence |
|---|---|---|
| `sync-keeps-false` | yes | sync treats `enabledPlugins: false` as the persistent opt-out (`plugins/harness-ops/skills/plugins/context/sync-install-enable.md:72-73`); install of an installed plugin only reports it (next row) |
| `install-idempotent` | yes | CLI docs: "already installed at that scope ... exit code is 0" ([CLI reference](https://code.claude.com/docs/en/plugins/cli-reference), read 2026-11-15) |
| `resume-keeps-settings` | no | `claude -p --settings <file>` saw the file's env value; `claude -p --resume <id>` without the flag printed none |
| `reload-removes-skills` | no | owner's live probe on 2.1.325 (interview F23): skills stayed listed after the reload |
| `reload-from-turn-complete` | yes | owner's live probe on 2.1.325 (interview F23): counts moved 85/330 to 84/329 from a `turn.complete` hook |
| `surface-vars` | partial | `CLAUDE_CODE_ENTRYPOINT=cli` observed in a CLI session; cloud sets `CLAUDE_CODE_REMOTE=true` (env-vars docs); Desktop and VS Code values UNVERIFIED (variable undocumented); Desktop WSL loads no plugins |
| `default-on-existing-users` | no | a plugin added to the marketplace with `defaultEnabled: true` was not installed by `marketplace update` |
| `deps-enable-from-settings` | yes, on update | updating a plugin that gained a dependency installed it and wrote it `true` at user scope; a dependency set `false` stops the dependent loading: `Dependency "pb@probe-mkt" is disabled — enable it or remove the dependency` |

## Considered options

- **Keep `core` as the on/off mechanism.** Rejected: a dependency list cannot switch plugins off,
  and every change to it is a release of a plugin that ships nothing.
- **Profiles as `userConfig` values** (ADR 0075 fix 9 as written). Rejected for the user level: a
  list of plugin ids per profile is a file a person writes and copies, not a scalar option.
- **Bare plugin names in profile files.** Rejected: the same name can exist in two marketplaces, and
  governance needs the marketplace on every id.
- **Keep the "installed" gate.** Rejected: under profiles an installed plugin is often off, and the
  gate then names a skill the session cannot call.
- **Leave session-wide hooks in their skill plugins.** Rejected: a profile that switches the skill
  plugin off would also switch off telemetry and health notices every session needs.

## Consequences

- The profile file format, the three homes and the ids are a published contract; changing a key or
  a home is a migration for every user profile.
- A handoff written where `/plugin-profiles:profile status` is available carries the restore entry
  that skill prints; without it, the handoff has no profile entry.
- A gated call in a session whose profile switched the target's plugin off takes its fallback.
- Users of `core` move to the always-on profile when they update.

## Revisit triggers

- Claude Code ships a native plugin-set feature; the profile engine maps onto it or retires.
- A probe row above reads differently on a later Claude Code version.
- The owner decides the harness-ops dependency question.
