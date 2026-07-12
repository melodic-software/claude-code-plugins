---
name: setup
description: "Configure the skill-quality plugin for this repository: infer where this repo's skills live, confirm with the user, and persist the skills directory so `/skill-quality:skill-quality` runs deterministically. Use when: 'set up skill-quality', 'configure skill-quality', 'skill-quality setup', the check skill reports the skills directory is missing, or your skills live outside .claude/skills. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Settle the one variable the checker needs — the **skills directory** — so it never guesses a repo
layout (convention-resolution ladder). When your skills live at the conventional
`.claude/skills`, no configuration is needed and the checker just works; run this only when they live
elsewhere, or to confirm the resolved location.

## Task

1. **Detect the skills root.** In order:
   - If `${user_config.skills_root}` is already set, read it and report the current value.
   - Else check `${CLAUDE_PROJECT_DIR}/.claude/skills`. If it exists and holds skill subdirectories
     (each with a `SKILL.md`), that is the answer — the conventional default, nothing to persist.
   - Else search the repo for directories containing `*/SKILL.md` and propose the best candidate.
2. **Confirm with the user, one decision.** Present the detected or proposed root with a
   recommendation. Let the user accept, correct, or point at a different directory. Never resolve a
   non-default location the user did not confirm.
3. **Persist only a non-default location.** If the confirmed root is the conventional
   `.claude/skills`, persist nothing — the default already resolves there. Otherwise write it to the
   plugin's `skills_root` option so it survives updates. Both forms are valid:
   - **Plugin option (recommended).** In the consumer's project `settings.json`, set
     `pluginConfigs["skill-quality@melodic-software"].options.skills_root` to the confirmed path
     (relative to the project root). This is the same value the enable-time prompt writes.
   - **Environment override.** Alternatively, set `CHECK_SKILL_SKILLS_ROOT` in `settings.json` `env`
     — the script honors it directly and it is the simplest escape hatch for a one-off.
   Re-read `settings.json` before writing and edit the JSON in place (never add a `//` comment — it is
   strict JSON); if the plugin is not yet enabled, tell the user to enable it first so the
   registration key exists.
4. **Verify.** Run `/skill-quality:skill-quality check` (no skill name) against the confirmed root and
   confirm it enumerates the expected skills.

## Output

Report the resolved skills directory, whether anything was persisted (and where), and the count of
skills the checker will cover. If nothing needed persisting, say so — the default already works.
