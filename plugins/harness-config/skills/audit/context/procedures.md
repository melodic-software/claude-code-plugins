# audit: procedures & fix policy

Operational recipes the SKILL.md phases point to: how to inspect `settings.local.json` without leaking
secrets (Phase 1), and which findings the skill may auto-fix vs which need judgment (Phase 5).

## Reading settings.local.json safely

Treat the file as secret-bearing regardless of deny rules. Run `check-structure.sh` first;
supplemental jq: below.

The safety here is *what gets emitted*, not what gets opened. `check-structure.sh` is safe because it
emits counts and never values. The `cat … | jq` recipes below emit values, and a project whose
settings carry a `Read(./.claude/settings.local.json)` deny may block them. That is the correct
outcome. Do not route around the block with an interpreter one-liner
(`python -c`, `node -e`) to dump content the sanctioned script will not emit. See "Scope of a Read
deny" in [reference/required-permissions.md](../reference/required-permissions.md); that file's
"Relation to the standards permission floor" says why the deny is a project's choice, not part of the
baseline.

- **Pointer**: when deciding which commands a `Read` deny blocks, fetch
  [permissions: read and edit](https://code.claude.com/docs/en/permissions#read-and-edit) live.

**Counts are not guaranteed.** Where the project also enables the sandbox, a `Read` deny on the file
can block `check-structure.sh` too. The script distinguishes that case: it reports
`Readable: no` with a `not inspectable` note rather than `Valid JSON: no`, and does not fail the run.
Treat that output as the answer. Record the file as not inspectable under the project's own
configuration, carry that into the report, and do not escalate to another reader to get the counts
anyway. A `Present: yes` / `Readable: no` pair is a correct result, not a broken audit.

- **Pointer**: when deciding whether the sandbox blocks the script, fetch
  [sandboxing: how sandboxing relates to permissions and permission modes](https://code.claude.com/docs/en/sandboxing#how-sandboxing-relates-to-permissions-and-permission-modes)
  live.

```bash
# Key inventory (no values)
cat .claude/settings.local.json | tr -d '\r' | jq 'keys'

# Permission count
cat .claude/settings.local.json | tr -d '\r' | jq '{
  env_keys: (.env | keys),
  allow_count: (.permissions.allow // [] | length),
  deny_count: (.permissions.deny // [] | length),
  ask_count: (.permissions.ask // [] | length),
  plugin_count: (.enabledPlugins // {} | length)
}'

# Check for deny rules (should NOT be here per bug #8961)
cat .claude/settings.local.json | tr -d '\r' | jq '.permissions.deny // empty'
```

## Phase 5: fixes the skill can apply

| Category | Auto-fixable | Requires judgment |
| --- | --- | --- |
| Add `$schema` | Yes | No |
| Add missing baseline deny rules | No | Yes (see below) |
| Move deny rules from local to project | Yes | No |
| Add new settings from docs | No | Yes (evaluate relevance) |
| Restructure permissions | No | Yes (evaluate scope) |
| Fix MCP server config | No | Yes (may need env vars) |
| Remove orphan plugins (`false`) | Yes (`scripts/fix-plugin-drift.sh --yes`), unless a lower-precedence scope holds `true` for the key or cannot be read | Yes, for a removal the script moved to manual review |
| New upstream plugins | No (report only; nothing adds a key) | Yes (whether to enable, disable, or leave the key absent) |
| Disabled dependency of an enabled plugin | No | Yes (enable the dependency, or disable the plugins that need it) |
| Remove orphan plugins (`true`) | No | Yes (user enabled a now-removed plugin, so investigate intent) |
| Rename plugins (heuristic match) | No | Yes (verify upstream rename, update key, preserve `enabled` value) |

Each approved edit to `settings.json` or `settings.local.json` goes through the
built-in `update-config` skill when it resolves in this session, and directly when it does not
(`.mcp.json` is always edited directly), except orphan-`false` plugin removal, which stays on
`scripts/fix-plugin-drift.sh --yes` for its lower-precedence-scope check. In auto mode the user's
explicit approval of a fix is the consent for it. When the classifier refuses an operation, such as
writing the team suppression record or re-running `scripts/audit-engine.sh` for the after-fix
summary, the fallback is the operator applying the edit or running the re-run and pasting the output
back; never retry around the refusal. The probe record of which operations were refused is in
[SKILL.md](../SKILL.md) "Refusals in auto mode".

- **Pointer**: when deciding what the classifier blocks, fetch
  [permission modes: what the classifier blocks by default](https://code.claude.com/docs/en/permission-modes#what-the-classifier-blocks-by-default)
  live.

**The judgment on a baseline deny addition, stated.** Two things have to be checked before the rule is
added, and neither is mechanical:

1. **Is the family already covered?** A **live** `PreToolUse` hook on the tool surface that pattern
   defends may already block it, in which case the finding is `info` rather than `error` and the rule
   is redundant. See [required-permissions.md](../reference/required-permissions.md) "Narrowing the
   baseline", whose three preconditions govern: installed and enabled is not enough (a
   hook-suppression lever can switch hooks off; read the levers from
   [validation-categories.md](validation-categories.md) Category D, and which
   `strictPluginOnlyCustomization` values cover hooks from
   [settings reference: strictPluginOnlyCustomization](https://code.claude.com/docs/en/settings-reference#strictpluginonlycustomization)
   live), a `Bash` hook does not cover the `Read`-pattern family, and one command family's coverage says
   nothing about another's. **The inventory half is a lookup**: Phase 1.0's
   `scripts/check-hook-coverage.sh` enumerates settings-declared *and* plugin-declared hooks,
   resolving each enabled plugin through the installed-plugin registry. What stays a judgment is
   whether an enumerated hook covers *this* family, and where that script exited 1, the sources it
   names as unenumerated remain a question, not an absence.
2. **Would the addition suppress a gate the project built on purpose?** Check whether a deny over a
   family a project hook escalates to an *ask* would replace that prompt with an outright block, so
   the human loses the approve/reject decision. That is fail-closed: a workflow regression, not a
   security one. See "Interaction with hook-based gates" in the same file. Whether a hook's outcome
   survives a deny or ask rule is read from
   [permissions: precedence among rules, hooks, and mods](https://code.claude.com/docs/en/permissions#precedence-among-rules-hooks-and-mods)
   live.

*Moving* an existing deny rule from local to project stays mechanical, since it is bug #8961 placement,
not a policy change.

## The findings artifact and the suppression record

`audit-engine.sh --out <file>` writes every finding as a row in the identity shape the sibling
`audit-pass` skill hashes: `identity.check`, `identity.claim`, and `identity.sites` (each a
`surface` plus a versioned `anchor/v1`), with `finding_id` derived from them, plus `severity`,
`detail`, `lane` (`harness-config/audit`) and `tier` (`derived` for engine rows). Persist it in the
topic's memory slice (default `.work/harness-config-audit/findings.json`), never in the tree the
audit scans. A judgment finding the model adds takes the same shape with `"tier": "judged"`; derive
its anchor and id with the engine's `anchor` and `finding-id` subcommands rather than by hand, so
two runs agree on the identity.

The same identity keys the consumer's suppression record, layered per the config-cascade
convention. The engine reads the team layer (the `suppressions` mapping of
`<home>/harness-config.yaml`, `<home>` being the convention home the repository binds, default
`docs/conventions`), the user-global layer, and the personal override, and lists each in
`suppressions.layers` with the file read and its state; every applied entry names its layer and
file. Only the team layer suppresses, a personal-only entry is reported as `personal-only, not
applied`, and an entry whose constituents do not hash to its key, or that lacks a required key, is
reported `malformed` and never suppresses. The `--table` output prints a `suppress:` line under every
finding with the id, surface, and anchor, so an operator who decides to keep a finding copies that
into a stanza with a `reason` and a `date` instead of deriving anything. This is the declared route
for session posture; nothing about the session's environment is read to decide which rows apply.
