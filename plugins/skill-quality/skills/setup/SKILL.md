---
description: "Verify where this repository's skills live for skill-quality — the resolved skills_root — and explain how to change the personal skills_root option through Claude Code. Use when: 'set up skill-quality', 'configure skill-quality', or the checker reports a missing skills directory. Actions: check (read-only verification, default) | apply (route a skills_root change once you've chosen a location). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` resolves and verifies the
skills root, `apply` resolves what it found. `skills_root` is a personal `userConfig` scalar owned by
Claude Code's native configuration surface — Claude Code prompts for it when the plugin is enabled,
stores non-sensitive options in user settings, and ignores project/local `pluginConfigs` entries on
current releases (≥ 2.1.207). This skill never writes it; `apply` verifies and routes.

Official contract (verified 2026-07-18):
<https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
reconfiguration guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

Read the rendered `${user_config.skills_root}` value — never inspect or edit settings files or
`pluginConfigs` directly. Resolve the candidate root, verify it, and report PASS/FAIL/INFO with one
remediation per FAIL. Do not modify anything.

1. **Resolve the root** in order: configured `skills_root`; else `${CLAUDE_PROJECT_DIR}/.claude/skills`;
   else repository directories containing child `SKILL.md` files. Report which rung resolved (INFO when
   the zero-config default `.claude/skills` applies).
2. **Verify** the resolved root exists and enumerates skills (child `SKILL.md` files). PASS with the
   directory and skill count; FAIL when it is absent or empty, with the resolution result in the
   remediation line — never claim success for a missing directory.

## `apply` (idempotent)

Run `check`, then resolve what it found. This skill has no legitimate write of its own — `skills_root`
lives in Claude Code's native config surface, which setup must not hand-edit — so `apply` is
verify-and-route:

- **Skills not found / wrong root (FAIL):** if the skills live somewhere other than the resolved root,
  the personal `skills_root` should point there. Reconfigure through the path below, then rerun `check`.
- **Reconfiguring the personal option:** `/plugin configure skill-quality@<marketplace>` (interactive, any time).
  Headless: rerun the install with the new value —
  `claude plugin install skill-quality@<marketplace> -s <scope> --config skills_root=<dir>`. Against
  an already-installed plugin it prints `already installed` and still writes the value, verified on
  Claude Code 2.1.240 for a non-sensitive option at `user` scope; a `sensitive` option, and
  `project`/`local` scope, were not covered, so re-verify before relying on it there. Do **not**
  uninstall to reconfigure: that drops this plugin's entire stored `pluginConfigs` entry, resetting
  every option in the README's Options reference table to its manifest default. `-s` defaults to
  `user`, so pass the scope `claude plugin list` reports for this plugin, and run from that
  project's directory for a `project`/`local` scope, or the write lands at a scope that does not
  load. This skill never writes user settings or `pluginConfigs`.
- **One-run override (no persistence):** for a single run against a different root, the checker also
  honors the `CHECK_SKILL_SKILLS_ROOT` environment variable; do not persist that variable on the user's
  behalf.

After any reconfiguration, rerun `check` **in a fresh session** and verify by invoking
`/skill-quality:check` via the Skill tool — without turning setup into the full quality audit. The
fresh session is not optional: the rendered `${user_config.skills_root}` is injected when this skill
loads, so a same-session rerun still resolves the OLD root and would report a correct write as a
failure. Re-running `apply` when the root resolves and enumerates changes nothing and reports
"already configured".

## What this skill does NOT do

- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Persist the `CHECK_SKILL_SKILLS_ROOT` environment override.
- Perform the full skill-quality audit, or invent organization-specific paths, IDs, or env-var prefixes.
