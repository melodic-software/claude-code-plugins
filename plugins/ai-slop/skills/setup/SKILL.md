---
description: "Configure the ai-slop plugin for a consumer repository: exemption paths for documents that legitimately need em dashes, excluded paths, AI-vocabulary word-list tuning, and per-rule thresholds, written to the team layer docs/conventions/ai-slop.yaml with the user's confirmation. Use when: 'set up ai-slop', 'configure slop detection', 'exempt this doc from the em-dash rule', 'tune the slop thresholds'."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s config resolve ran at load time. The detector's `--show-config` output below names the
layer supplying each effective value; `(detector unavailable)` means it did not run:

!`"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/detect.sh" --show-config 2>/dev/null || echo "(detector unavailable)"`

When it reads `(detector unavailable)` or `[shell command execution disabled by policy]`, run the
detector's `--show-config` via Bash or read the three layers directly.

## Purpose

The ai-slop detector ships neutral defaults. A consumer repo declares its own exemptions and
tuning in `<home>/ai-slop.yaml`, resolved per the config-cascade convention: team
(`<home>/ai-slop.yaml`, tracked) and personal overlay (`<home>/ai-slop.local.yaml`, gitignored),
where `<home>` is the convention home the repository binds in its instruction file
(`docs/conventions` by default). The file is validated by the plugin's
`schemas/ai-slop.schema.json`. Later layers refine earlier ones per key.

A repository that still keeps the older JSON files (the same names with a `.json` extension, in
`.claude/`) is read from them only while the YAML beside them is absent. `apply` writes the YAML:
when the repository has the JSON team file and no YAML, offer to carry its values into
`<home>/ai-slop.yaml` (the JSON `_comment` text becomes YAML comments) and leave the JSON file
for the repository to delete.

## Keys

| Key | Type | Meaning |
|---|---|---|
| `excluded_paths` | glob list | Files the audit never scans |
| `em_dash_allowed_paths` | glob list | Documents exempt from the zero-tolerance em-dash rule |
| `vocab_add` | word list | Additions to the AI-vocabulary list |
| `vocab_remove` | word list | Removals from the AI-vocabulary list |
| `phrase_add` | ERE fragment list | Additions to the model-era phrase roster (`rule-model-era-phrases`); whole fragments, spaces allowed, apostrophes spelled `.` |
| `phrase_remove` | ERE fragment list | Removals from the shipped phrase roster, matched verbatim against the shipped fragments |
| `disabled_rules` | rule slugs | Rules the audit skips entirely (reported as disabled) |
| `thresholds` | map | Per-rule density thresholds: `ai_vocabulary`, `copulative_avoidance` (matches per 1000 words; density rules also need at least 3 matches) |
| `rule_allowed_paths` | map of rule slug to glob list | Files that decline that one rule |

Record the rationale for a choice as a YAML comment above the key: a config that disables a rule
without recording why is the drift this skill exists to catch. A legacy JSON file carries it as a
`_comment` string key, which is not drift, so do not flag it as an unknown key.

## check (default, read-only)

Report the current state and change nothing:

1. Read the pre-computed `--show-config` output (it names the layer supplying each value), or read
   the layers directly when it is unavailable; report which layer wins each key and which layers are
   absent.
2. Flag drift: unknown keys, an em-dash threshold key (the rule is zero-tolerance by design, and
   per-document exemption via `em_dash_allowed_paths` is the supported mechanism), globs that
   match nothing, a `disabled_rules` slug that names no shipped rule, a `phrase_add` fragment
   that is not a valid ERE (the detector skips it with a stderr note; surface it here as
   drift), or a `phrase_remove` fragment matching no shipped phrase.
3. End with what `apply` would change, if anything was flagged.

## apply

Everything `check` does, then the confirmed write:

1. Interview the user for what they want changed. For em-dash exemptions, ask for the documents
   that genuinely require em dashes; the default posture is that most work does not.
2. Write ONLY the team layer (`<home>/ai-slop.yaml`), showing the diff and getting explicit
   confirmation before writing. Never write the personal overlay on the user's behalf; name it
   as an option the user edits themselves.
3. Re-run `--show-config` via Bash (the pre-computed output predates the write) and report the
   new effective state. Then run the tracked-file pair on
   the written team file: `git check-ignore -v <home>/ai-slop.yaml` reports no match (a match is
   FAIL with the pattern) AND `git ls-files --error-unmatch <home>/ai-slop.yaml` exits 0
   (non-zero right after a fresh write means "written but untracked: commit it to share with the
   team", never success).
