---
description: "Discovers this machine's facts and identity domains, stores them as a re-runnable profile, and reports drift between the stored profile and the host now. Read-only unless the operator confirms a write. Use when: 'machine profile', 'profile this machine', 'what does this host have configured', 'has this machine changed', 'diff my machine profile', 'which identity domains exist here', 'hand my machine facts to setup'. Never installs and never reapplies a stored value on its own."
argument-hint: "[profile | diff | explain <key> | apply --option <key>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Discover, store and diff machine facts and per-tree identity domains. Read-only by default.
  cadence: weekly
---

## Purpose

Record, once per machine, what the host has and which identity domains it holds, with the observation behind every value, so a plugin `setup` run starts from observed answers and a kept default says whether anyone looked. The profile drives setups; it never replaces their prerequisite logic. Design and rulings: `docs/specs/machine-profile-design.md`, placement in ADR 0041.

Everything here is read-only except two steps the operator confirms in that turn: `record --confirm` (writes the profile document) and `apply --confirm` (prints what to hand to each setup; it writes nothing itself).

## Actions

`<script>` is `bash "${CLAUDE_SKILL_DIR}/scripts/profile.sh"`. Every command that reads or writes the store takes `--data-dir "${CLAUDE_PLUGIN_DATA}"`.

- **profile** (default). Run `/claude-ops:prerequisites`, save its table to a scratch file, then run `<script> discover --prerequisites <file>` and print what it observed: machine facts, then each identity domain with its tree, git include, `gh` directory and verdicts. Offer to record it. On the operator's yes, run `<script> record --data-dir ... --confirm <saved discover output>`; without `--confirm` it validates and writes nothing.
- **diff**. `<script> diff --data-dir ... --prerequisites <file>` compares the stored document with fresh discovery. Empty output and exit 0 mean nothing changed: say so and ask nothing. Exit 4 lists each difference with both values and both `observed_by` entries. The store cannot tell a hand edit from a host change, so report the difference and do not attribute it.
- **explain** `<key>`. `<script> explain --data-dir ... <key>` prints the stored record and the command or path behind it.
- **apply** `--option <key>`. Run `diff` first and show it. Then `<script> apply --data-dir ... --option <key>` prints the plan. Only after the operator says yes in that turn, add `--confirm`. Setup skills are `disable-model-invocation: true`, so a `handoff` line is relayed for the operator to type as `/<plugin>:setup`; the model does not invoke it. An option recorded under a domain is a per-domain identity: the script reports a `conflict` and stops for it, and it is never put into the single `pluginConfigs` slot.

Exit codes: 0 ok, 1 refused, 2 usage or missing tool (`jq`), 3 no profile stored, 4 differences found.

## Where the profile lives

`${CLAUDE_PLUGIN_DATA}/machine-profile/profile.json`. The machine section is not project-keyed (it describes the host, the same for every project), which the design ratifies as a deviation from `docs/conventions/plugin-data-report-keying` rule 1; each domain is keyed by its tree root. A missing document reads as "no profile for this machine" and offers to produce one; there is no fallback path. The document is regenerable from the host, so uninstalling the plugin from its last scope costs a re-run, not data. It holds names, paths and observation commands, and discovery never reads a credential or a sensitive `userConfig` value. The writer is a backstop for hand-supplied records, not a secret detector: it refuses the key words and value shapes listed under Gotchas, so do not supply a secret that matches neither.

**Claim:** `${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/{id}/` and is deleted on uninstall from the last scope unless `--keep-data` is passed. **Basis:** [plugins reference](https://code.claude.com/docs/en/plugins-reference), Persistent data directory, as quoted in the keying convention (fetched 2026-08-12). **As of:** 2026-10-01. **Recheck:** the plugins reference changes the data directory formula or its uninstall behavior.

## Document shape and verdicts

Records live in `machine.facts`, `machine.options`, and per domain in `identity`, `facts` and `options`. Each record has `key`, `value`, `verdict`, and these by verdict:

| Verdict | Meaning | Required |
|---|---|---|
| `set` | a non-default value is in force | `observed_by`, `mode`, `supplied_by` |
| `default-verified` | unset; discovery looked | `observed_by`, `mode`, `observation` (including "found nothing") |
| `default-unexamined` | unset; nothing was looked at | `skipped_because`, and no `observed_by` |
| `blocked` | a guard prevents the change | `observed_by`, `mode`, `guard` with the operator command |

`mode` is `observed` or `reproduced`. A binary whose row in the prerequisites table names a `:setup check` is `reproduced`, because that setup is hidden and the profile cannot run its own check. A fact discovery measured directly (a binary present, a path, a core count) is recorded `set` with the source in `supplied_by`; absence is `default-verified`. There is no bare `keep`, and a value equal to its default is never written to mark it decided. `default-unexamined` becomes `default-verified` only through an observation, never through written rationale.

Discovery reads identity domains from the `includeIf "gitdir:..."` entries in `git config --list --show-origin`. It attaches a `gh` directory to a tree only when that tree's own `.envrc` exports a literal `GH_CONFIG_DIR`, which it reads as text and never evaluates; otherwise `gh_config_dir` is `default-unexamined` and the machine's directory is not copied to the tree.

**Claim:** `gh` takes its configuration directory from `GH_CONFIG_DIR`, then `$XDG_CONFIG_HOME/gh`, then `$AppData/GitHub CLI` on Windows, then `$HOME/.config/gh`, and reports no directory for the working directory. **Basis:** `gh help environment` on gh 2.98.0, run 2026-10-01. **As of:** 2026-10-01. **Recheck:** a gh release changes the `GH_CONFIG_DIR` lookup order in `gh help environment`.

**Claim:** `pluginConfigs` is read from user settings, `--settings` and managed settings only, and `claude plugin install --config` writes user settings whatever scope flag is given, so one slot serves the whole machine. **Basis:** facts 5 and 9 of `docs/conventions/hook-config-delivery` (Claude Code 2.1.283, 2026-09-27). **As of:** 2026-10-01. **Recheck:** the documented `pluginConfigs` read scopes change, or `--config` starts honoring a scope flag.

## Next

- A binary row is missing: /claude-ops:prerequisites
- The fleet's plugin versions, a different question: /claude-ops:plugins audit

## Gotchas

Binary facts come only from the prerequisites table. Without `--prerequisites`, discovery records `binaries` as `default-unexamined` and adds no probe of its own, so a `diff` run without the table reports the per-tool rows as removed.

The writer refuses a record whose key contains `token`, `secret`, `password`, `credential`, `api_key` or `private_key`, and a record whose value looks like a credential: a GitHub, AWS, Slack or `sk-` token, a JWT, a private-key block, or a URL with an embedded password. A key discovery derives from host text (a binary such as `docker-credential-pass`, an include path under a `token` directory) gets the first letter of each such word bracketed, as `binary.docker-[c]redential-pass`, so the profile still records it. `explain` needs the bracketed key, and a hand-supplied record keyed `api_token` is still refused.

`diff` compares facts and identity only. Option records are stored state that discovery does not observe, so a hand-edited or never-applied option does not show as drift.

`record` replaces the whole document, so options recorded earlier survive a re-record only when they are merged into the document first.

Discovery reads the effective user and system git configuration from a neutral directory, so the repository the session runs in does not add or hide a domain.

A read-only include file is detected with `test -w`; an immutable attribute on a file that still looks writable is not.

Do not reapply a stored value from a hook, a session start or a schedule. `apply` re-asserts a value only when the operator selects it in that run.
