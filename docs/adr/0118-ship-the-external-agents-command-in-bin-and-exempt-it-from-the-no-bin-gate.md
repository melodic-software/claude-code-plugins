# Ship the external-agents command in bin/ and exempt it from the no-bin gate

- Status: accepted
- Date: 2026-11-21
- Supersedes in part: [ADR 0021](0021-reject-the-three-unused-official-plugin-components.md), its
  `bin/` verdict, for the external-agents plugin only
- Refs: [#17954](https://github.com/melodic-software/claude-code-plugins/pull/17954); owner interview
  of 2026-11-21 (Q61, Q62: "go w/ recomendations");
  [ADR 0117](0117-replace-the-official-codex-plugin-with-one-external-agents-plugin-and-a-skill-per-cli.md)

## Context

Council runs each member from a script, and `review:brief-reviewer` has no Skill tool, so neither
can invoke a skill. Before this change, council reached Codex by locating the official plugin's
install path and running its private script. ADR 0021 rejected `bin/` marketplace-wide. Its recheck
trigger was a script the consumer runs as a bare command. Council, the skills and a person at a
shell now all run `external-agents` that way, so the trigger has fired.
`scripts/check-plugin-manifest-presence.sh` rule 3 fails any plugin with a top-level `bin/`,
because claude.ai organization plugin sync rejects one (#5850).

## Decision

1. **`plugins/external-agents/bin/external-agents` is the plugin's one public command**, on the
   Bash `PATH` while the plugin is enabled. Council's adapter runs `external-agents review <provider>`
   and the skills run the same command. Nothing outside the plugin names its scripts or install path.
2. **The no-bin gate exempts this plugin by name.** Rule 3 skips `external-agents` only. Its test
   proves every other plugin's `bin/` still fails.
3. **Organization sync skips external-agents.** The rest of the marketplace still syncs. The
   plugin drives local CLIs, so it has nothing to do on claude.ai.
4. **A missing command is a skipped member, never a failure or a fallback answer.** When
   `external-agents` is not on `PATH` (plugin disabled, or `PATH` delivery failed), council prints
   `skipped (external-agents not enabled)`.

## Considered options

- **A council skill member, run from the main thread (design T1 option B).** Rejected by the owner
  (Q62): it loads the skill once per member, and the output shape then depends on the model.
- **Invoke the script by `${CLAUDE_PLUGIN_ROOT}` path from council.** Rejected: council would have
  to find another plugin's install path, the coupling this change removes.
- **Keep ADR 0021's marketplace-wide rejection.** Rejected: its recheck trigger fired, and no
  `scripts/` path lets a script in another plugin call this one without that lookup.

## Consequences

- The exemption is one named plugin. Any other plugin that wants `bin/` needs its own record.
- `PATH` delivery is per session and can fail silently
  ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066)). When it
  fails, council's Codex member reports skipped instead of running.
- The component-stances table in `docs/plugin-philosophy.md` keeps `bin/` at Decline, with this
  plugin named as the exception.

## Revisit triggers

- claude.ai organization sync accepts a plugin with a top-level `bin/`, so the exemption can become
  the rule.
- A script can invoke a skill, or `review:brief-reviewer` gains the Skill tool.
- A second plugin needs a bare command on `PATH`.
