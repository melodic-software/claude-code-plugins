# The native `security-review` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| We treat the native `/security-review` as a developer's single pass over their current branch, with no target this lane could hand it, so this lane never routes a PR to it; what it diffs against and what it needs are read from its row | Pointer: the `/security-review` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | The row gains a Skill label, a flag, or a target argument |
| The installed binary still registers it as plugin-backed, not as a bundled skill: `pluginName:"security-review", pluginCommand:"security-review"`, description "Complete a security review of the pending changes on the current branch", and the prompt refuses to run outside a git repository | String search of the installed 2.1.263 binary | 2026-09-11 | An extraction reports the name under bundled skills, or the commands row gains a Skill label |
| It is one layer of a defense-in-depth stack that also holds a deep-scan plugin and managed products; a request for a deeper or continuous scan routes to those layers, never to this lane. Which layers exist and their plan tiers are read live | Pointer: [claude-security: how the plugin fits with other security tools](https://code.claude.com/docs/en/claude-security#how-the-plugin-fits-with-other-security-tools) | 2026-10-11 | The table adds, removes, or re-tiers a layer |
| It is unusable in CI, so this skill is the CI path | Pointer: the opening paragraph under the title of [SKILL.md](../SKILL.md#ci-security-review-reviewsecurity-review) carries that record with its own pointer and recheck trigger; not repeated here | 2026-10-11 | That paragraph moves out from under the title, or stops carrying its own pointer and trigger |

On 2026-09-11 the commands page gave the command no Skill label, so nothing on it contradicted the
binary's plugin-backed registration, and the binary's description is what a 2.1.263 session
listed for the command. The registry row keeps `plugin-backed-builtin`, the class the binary
reports.

## Why the verdict is complementary

This skill is the security logic the `claude-security-review` reusable workflow runs in CI, with
the wrapper owning posting and this skill owning what to hunt for. The native command is a local
single pass a developer runs on a branch before pushing, and it cannot run under the Actions
checkout at all. Neither wraps the other. The Claude Security plugin and the managed products are
further surfaces this lane does not wrap either: a request for a deep scan or repository
monitoring routes to them, not here.

## Presence

The native command is gated by its backing plugin's availability, `skillOverrides`, the host
surface, and the environment. Nothing in this lane depends on it: the CI wrapper never invokes it.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, whose
`plugin_backed` map reports `{"security-review": "security-review"}` with the name in neither the
built-in commands nor the bundled skills. This record re-verifies the plugin-backed registration
on the installed 2.1.263 binary by string search and reads the two pages named above, all on
2026-09-11.
