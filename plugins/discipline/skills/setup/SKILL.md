---
name: setup
description: "Validate the discipline plugin's configuration — the posture-batch overlay and do-your-research-deep's verification depth — and explain how to change it through Claude Code's plugin configuration prompt. Use when: 'set up discipline', 'configure discipline', 'discipline setup', 'is discipline configured', 'set up re-anchor', 'configure re-anchor', 're-anchor setup', 'is re-anchor configured', 'what's in my posture batch', 'what's my deep-research depth', or you want to adjust which correctors the batch runs or how deeply the research fan-out verifies. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Variables

Batch exclude: `${user_config.batch_exclude}`
Batch promote: `${user_config.batch_promote}`
Batch demote: `${user_config.batch_demote}`
Deep-research verification depth: `${user_config.research_deep_verification}`

## Purpose

Report discipline's effective configuration without editing Claude Code settings.
The plugin's whole configuration surface is native `userConfig`: three
`sweep-all` batch-overlay options (`batch_exclude` / `batch_promote` /
`batch_demote`) plus `do-your-research-deep`'s verification-depth default
(`research_deep_verification`). Claude Code prompts for them when the plugin is
enabled, stores non-sensitive options in user settings, and ignores `pluginConfigs`
entries in project and local settings on current releases (>= 2.1.207).

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's
entire configuration surface is native `userConfig`, so `check` (the default and only
action) verifies and reports, and reconfiguration routes through Claude Code's native
flow — an `apply` here would have nothing to write except the `pluginConfigs` setup
must never touch. Non-interactive: report and recommend; never block on a question.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

## `check` (read-only, the only action)

1. Read the four rendered `${user_config.…}` values from the Variables block
   above (the three `batch_*` overlay options and `research_deep_verification`). Do
   not inspect or edit `settings.json`, `settings.local.json`, managed settings, or
   `pluginConfigs` directly.
2. **Empty or unexpanded is unset.** An option the user never configured does not
   reliably render empty — the literal `${user_config.…}` token can survive (a
   zero-config or headless install). Treat BOTH an empty value AND a surviving
   literal placeholder as unset (the key's own default applies); never read the
   literal token as a value.
3. For each set batch option, split on commas and report the parsed corrector names,
   and the net effect: `batch_exclude` drops those correctors from the batch,
   `batch_promote` runs those situational correctors every session, `batch_demote`
   gates those core correctors on relevance. With all three unset, report that the
   batch runs the tiers exactly as the correctors declare them.
4. **Validate the batch names against what is installed.** Glob the sibling corrector
   directories under this plugin's `skills/` and, for each name in an overlay, report:
   - a name that matches no installed corrector — FAIL (typo or removed corrector);
     remediation: fix the value via the plugin configuration prompt;
   - the same name in `batch_exclude` and in `batch_promote`/`batch_demote` —
     contradictory; report it;
   - a `batch_promote` naming an already-core corrector, or a `batch_demote` naming
     an already-situational one (read its `metadata.discipline-batch`) — a no-op; INFO.
5. **Report the deep-research verification depth.** `research_deep_verification` sets
   `do-your-research-deep`'s default depth. Report the effective value: `tiered`
   (fan subagents out only over load-bearing items) or `full` (subagent-verify every
   item). An unset value, a surviving literal placeholder, OR any unrecognized string
   (not exactly `tiered` or `full`) all resolve to the `tiered` default — report an
   unrecognized value as a WARN (typo; remediation: fix it via the plugin
   configuration prompt) that still falls back to tiered, never a hard failure. Note
   that an invocation argument to `do-your-research-deep` overrides this default per
   invocation.
6. **Full-batch prerequisite.** INFO: the batch's mid-session pass dispatches
   conversation-inheriting fork subagents, which need fork-spawning enabled
   (`CLAUDE_CODE_FORK_SUBAGENT`, which a server-side staged rollout can also enable —
   <https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation>).
   `sweep-all` preflights this itself and degrades when the fan-out cannot inherit —
   that runbook owns the behavior; report the prerequisite here only so an unavailable
   fan-out reads as expected rather than as a misconfiguration, and do not restate what
   the degraded pass does.
7. To change or clear any value, direct the user to Claude Code's plugin configuration
   prompt for `discipline` (interactive `/plugin configure discipline` any time;
   headless `--config` applies only on a fresh install — uninstall then reinstall to
   reconfigure). Claude Code owns persistence. Do not hand-edit any `pluginConfigs` key.

## Gotchas

- **No `apply`.** The only thing an apply could write is `pluginConfigs`, which the
  setup contract forbids a skill from touching. Reconfiguration is the native
  `/plugin configure discipline` flow.
- **Unexpanded token is not a value.** A surviving literal `${user_config.…}` means
  unset (the key's default applies) — parsing it as a corrector name or a depth value
  is the failure this check exists to prevent.
