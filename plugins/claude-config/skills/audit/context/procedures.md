# audit: procedures & fix policy

Operational recipes the SKILL.md phases point to: how to inspect `settings.local.json` without leaking
secrets (Phase 1), and which findings the skill may auto-fix vs which need judgment (Phase 5).

## Reading settings.local.json safely

Treat the file as secret-bearing regardless of deny rules. Run `check-structure.sh` first;
supplemental jq: below.

The safety here is *what gets emitted*, not what gets opened. `check-structure.sh` opens the file from
inside a subprocess, which a `Read(...)` deny does not cover. It is safe because it emits counts and
never values. The `cat … | jq` recipes below go the other way: `cat` is a file command Claude Code
recognizes in Bash, so a project carrying the baseline `Read(./.claude/settings.local.json)` deny will
block them. That is the correct outcome. Do not route around it with an interpreter one-liner
(`python -c`, `node -e`) to dump content the sanctioned script will not emit. See "Scope of a Read
deny" in [reference/required-permissions.md](../reference/required-permissions.md).

**Counts are not guaranteed.** Where the project also enables the sandbox, the baseline `Read` deny
merges into the sandbox filesystem boundary and the OS blocks `check-structure.sh` and its `tr`/`jq`
children too, and the subprocess route closes. The script distinguishes that case: it reports
`Readable: no` with a `not inspectable` note rather than `Valid JSON: no`, and does not fail the run.
Treat that output as the answer. Record the file as not inspectable under the project's own
configuration, carry that into the report, and do not escalate to another reader to get the counts
anyway. A `Present: yes` / `Readable: no` pair is a correct result, not a broken audit.

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
| Remove orphan plugins (`false`) | Yes (`scripts/fix-plugin-drift.sh --yes`) | No |
| Add new upstream plugins as `false` | Yes (`scripts/fix-plugin-drift.sh --yes`) | No |
| Remove orphan plugins (`true`) | No | Yes (user enabled a now-removed plugin, so investigate intent) |
| Rename plugins (heuristic match) | No | Yes (verify upstream rename, update key, preserve `enabled` value) |

**The judgment on a baseline deny addition, stated.** Two things have to be checked before the rule is
added, and neither is mechanical:

1. **Is the family already covered?** A **live** `PreToolUse` hook on the tool surface that pattern
   defends may already block it, in which case the finding is `info` rather than `error` and the rule
   is redundant. See [required-permissions.md](../reference/required-permissions.md) "Narrowing the
   baseline", whose three preconditions govern: installed and enabled is not enough (`disableAllHooks`
   and the managed `allowManagedHooksOnly` / `strictPluginOnlyCustomization` levers switch hooks off),
   a `Bash` hook does not cover the `Read`-pattern family, and one command family's coverage says
   nothing about another's. **The inventory half is a lookup**: Phase 1.0's
   `scripts/check-hook-coverage.sh` enumerates settings-declared *and* plugin-declared hooks,
   resolving each enabled plugin through the installed-plugin registry. What stays a judgment is
   whether an enumerated hook covers *this* family, and where that script exited 1, the sources it
   names as unenumerated remain a question, not an absence.
2. **Would the addition suppress a gate the project built on purpose?** Deny and ask rules are
   evaluated regardless of what a `PreToolUse` hook returns, so adding a deny over a family a project
   hook escalates to an *ask* replaces the prompt with an outright block and the human loses the
   approve/reject decision. Fail-closed, so not a security regression but a workflow regression. See
   "Interaction with hook-based gates" in the same file. (A hook that blocks by `exit 2` short-circuits
   before permission rules, so nothing is suppressed there.)

*Moving* an existing deny rule from local to project stays mechanical, since it is bug #8961 placement,
not a policy change. That is why the two rows are graded differently.

## The findings artifact and the suppression record

`audit-engine.sh --out <file>` writes every finding as a row in the identity shape the sibling
`audit-pass` skill hashes: `identity.check`, `identity.claim`, and `identity.sites` (each a
`surface` plus a versioned `anchor/v1`), with `finding_id` derived from them, plus `severity`,
`detail`, `lane` (`claude-config/audit`) and `tier` (`derived` for engine rows). Persist it in the
topic's memory slice (default `.work/claude-config-audit/findings.json`), never in the tree the
audit scans. A judgment finding the model adds takes the same shape with `"tier": "judged"`; derive
its anchor and id with the engine's `anchor` and `finding-id` subcommands rather than by hand, so
two runs agree on the identity.

The same identity keys the consumer's suppression record, `.claude/audit-pass.md`, layered per the
config-cascade convention. The engine reads the team layer, the user-global layer, and the local
overlay; only the team layer suppresses, a personal-only entry is reported as `personal-only, not
applied`, and an entry whose constituents do not hash to its key, or that lacks a required key, is
reported `malformed` and never suppresses. The `--table` output prints a `suppress:` line under every
finding with the id, surface, and anchor, so an operator who decides to keep a finding copies that
into a stanza with a `reason` and a `date` instead of deriving anything. This is the declared route
for session posture; nothing about the session's environment is read to decide which rows apply.
