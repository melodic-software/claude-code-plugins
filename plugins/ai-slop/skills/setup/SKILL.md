---
description: "Configure the ai-slop plugin for a consumer repository: exemption paths for documents that legitimately need em dashes, excluded paths, AI-vocabulary word-list tuning, and per-rule thresholds, written to the team layer .claude/ai-slop.json with the user's confirmation. Use when: 'set up ai-slop', 'configure slop detection', 'exempt this doc from the em-dash rule', 'tune the slop thresholds'."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

The ai-slop detector ships neutral defaults. A consumer repo declares its own exemptions and
tuning in `.claude/ai-slop.json`, resolved per the config-cascade convention: user-global
(`~/.claude/ai-slop.json`), team (`.claude/ai-slop.json`, tracked), local overlay
(`.claude/ai-slop.local.json`, gitignored). Later layers refine earlier ones per key.

## Keys

| Key | Type | Meaning |
|---|---|---|
| `excluded_paths` | glob list | Files the audit never scans |
| `em_dash_allowed_paths` | glob list | Documents exempt from the zero-tolerance em-dash rule |
| `vocab_add` | word list | Additions to the AI-vocabulary list |
| `vocab_remove` | word list | Removals from the AI-vocabulary list |
| `disabled_rules` | rule slugs | Rules the audit skips entirely (reported as disabled) |
| `thresholds` | map | Per-rule density thresholds: `ai_vocabulary`, `copulative_avoidance`, `rule_of_three` (matches per 1000 words; density rules also need at least 3 matches) |

## check (default — read-only)

Report the current state and change nothing:

1. Run the detector's `--show-config` (it names the layer supplying each value) or read the
   layers directly; report which layer wins each key and which layers are absent.
2. Flag drift: unknown keys, an em-dash threshold key (the rule is zero-tolerance by design —
   per-document exemption via `em_dash_allowed_paths` is the supported mechanism), globs that
   match nothing, or a `disabled_rules` slug that names no shipped rule.
3. End with what `apply` would change, if anything was flagged.

## apply

Everything `check` does, then the confirmed write:

1. Interview the user for what they want changed. For em-dash exemptions, ask for the documents
   that genuinely require em dashes; the default posture is that most work does not.
2. Write ONLY the team layer (`.claude/ai-slop.json`), showing the diff and getting explicit
   confirmation before writing. Never write the user-global or overlay layers on the user's
   behalf; name them as options the user edits themselves.
3. Re-run `--show-config` and report the new effective state.
