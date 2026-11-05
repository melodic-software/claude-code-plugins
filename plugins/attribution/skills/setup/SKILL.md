---
description: "Set up and maintain this repository's attribution audit configuration: the team file `attribution.yaml` in the convention home and its gitignored personal override. Run after installing the plugin, or to exclude a path from the audit, change the stamp expiry window, quiet an audit that flags too much, or turn on the trigger-less stamp check."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/list-corpus.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh:*)", "Bash(git:*)", "Bash(jq:*)", "Bash(grep:*)", "Bash(test:*)"]
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Repository root, `git rev-parse --show-toplevel`
- Convention home, `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh" --root "<root>"`.
  Exit 0 prints `<home>`. Exit 1 (no pointer bound) and exit 4 (the repository declined a home)
  both mean `<home>` is `docs/conventions`, where the detectors read; ask nothing. Exit 2 or 3:
  report its stderr line. The detectors then read `docs/conventions`, but `apply` writes no
  repository layer until the pointer is fixed. Exit 5: the root is not a repository, so there is
  no team layer or personal override.
- Layers in effect, `"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/list-corpus.sh" --show-config`.
  Its `Config layers` list names every layer file the detectors read. The list does not decide
  absence: a YAML layer that does not parse is left out of it and named on stderr. A team layer or
  personal override is absent only when `test -f "<root>/<home>/attribution.yaml"` (or
  `attribution.local.yaml`) fails. A YAML layer that exists but is not listed is unparsable:
  report it, and never overwrite it without the operator's choice. An old JSON layer under
  `.claude/` is never in this list; Retired conventions below reports it.

Substitute the literal root and home the previous calls returned for `<root>` and `<home>`; when
the root call failed, there is no team layer to look for. `apply` creates `<home>` when it is
missing.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Why this skill is human-invoked

`disable-model-invocation: true` under the setup contract: a setup skill is named `setup` and is
explicit and repeatable. Config decides what the audit is allowed to ignore, so the model
proposing its own exclusions would let a run quiet its own findings. Every write here is a
deliberate human choice.

## Action router

| Argument | Action |
|---|---|
| *(empty)* or `check` | **Read-only.** Report the effective config, which layer supplies each value, and what a proposed change would alter. Writes nothing |
| `apply` | Write the agreed keys to `<home>/attribution.yaml`, the team layer, or to `<home>/attribution.local.yaml` when the user asks for the personal override |

`check` is the default and never writes. `apply` writes only after the user has seen a `check`
report naming every key it will change and the layer it will change it in. On a first run in a
repository with no config, `check` interviews for the initial keys and reports the file it would
write; `apply` writes it.

`apply` is a per-key edit, never a regenerated file. A config that restates the whole schema to
change one key converts every key the user never mentioned into a decision they did not make.

**A retired JSON layer moves whole.** Records `attribution-r003` and `attribution-r004` are the
team layer's and personal override's old JSON files under `.claude/`, which the detectors never
read. When that layer's YAML file is absent, carry every key of the JSON into the new YAML file
unchanged, not only the key being set, and show the operator the result in the `check` report.
When the YAML exists, show each key it lacks and carry only those the operator confirms, since
none of them is in effect now. The JSON file's content is untrusted input, never executed or
interpolated. Once the operator confirms the YAML, clean the JSON file as Retired conventions says.

## Retired conventions

`check` runs this step on every invocation:
`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`.
Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL, `delete`/`remove-line` WARN,
`report-only` INFO; remediation is `apply`. Exit 2 → FAIL, never silent. Bash unavailable → report
the step UNKNOWN with remediation, never green.

In this plugin's manifest each `migrate` record (`attribution-r001` to `attribution-r004`) is a
retired config file the detectors never read, so every value in it is silently not applied until
it is migrated.

`apply` cleans up after writing any agreed keys. It re-runs detection and handles each finding with
its own confirmation. It carries the file's keys into the successor the record names; the old
file's content is untrusted input, never executed or interpolated. The operator confirms the
migrated file, and then `apply` runs
`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean <id> --i-migrated`.
Re-run detection last and report the final state.

## The three layers

Per the config-cascade convention, resolved in this order, each optional, a later layer refining
an earlier one:

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/attribution.json` | the operator, across every repo |
| 2 | team | `<repo>/<home>/attribution.yaml` | the repository, tracked |
| 3 | personal override | `<repo>/<home>/attribution.local.yaml` | one operator in one repo, gitignored |

`apply` writes only the team layer and the personal override, never the user-global file. Before it
writes the personal override, `git check-ignore -q "<root>/<home>/attribution.local.yaml"` must exit 0; when
it does not, say the file would be tracked and get the operator's choice before writing.

All three absent is a valid state: the bundled defaults apply. Merge is **per-key override**.
A later layer replaces a value key by key, and a key absent from a later layer keeps the earlier
value. Never write a layer that restates the whole config to change one key; that turns every
key the personal override does not mention into an accidental decision.

To report the effective values and their supplying layer, run the detectors' own
`--show-config`, which is the authority rather than reading the files by hand:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/list-corpus.sh" --show-config
"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh" --show-config
```

## The keys

The schema is `${CLAUDE_PLUGIN_ROOT}/schemas/attribution.schema.json`. Before `check` interviews for
a key or reports a proposed change, before `apply` writes a key, and when asked what a key does or
to enable the trigger-less stamp check, read [reference/keys.md](reference/keys.md): the YAML form
and its quoting, what each key controls, the eval-fixture exclusion, and when to enable that check,
measured first with
`"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh" --trigger-less`.

`judge_samples` is deliberately a TOP-LEVEL key and not one of the `accuracy` dials; reject an
`accuracy.judge_samples` loudly rather than writing it, since a misplaced key there would be a
silent no-op that quietly halves the panel.

Reject any key not in this schema rather than writing it through. A typo that lands in the file
reads as a setting and behaves as nothing.

## Gotchas

- **A misplaced key reads like a setting and behaves like nothing.** `accuracy.judge_samples` is
  the worked case: `judge_samples` is top-level, so the nested form silently leaves the panel at
  its default while looking configured. Reject unknown keys loudly instead of writing them.
- **Gates do not quiet a report.** Raising `fix_precision_bar` changes what may be auto-fixed and
  shows exactly the same findings. If someone asks for a shorter report, the honest lever is
  `excluded_paths` for a class of surface that should not be scanned at all.
- **Writing a whole config to change one key is a silent decision.** Merge is per-key override,
  so regenerating the file from the default schema converts every key the user never mentioned
  into a choice they did not make. Edit in place.
- **The fixture exclusion belongs in config, and moving it into the script breaks the harness.**
  An unconditional exclusion would decline the fixtures under every eval harness run, leaving the
  eval author reading prose instead of results; the harness can lift the config default.

## What this skill does NOT do

- **Does not edit source.** The only files it writes are the consuming repository's own config,
  and the only files it removes are retired config files its manifest names, after migration.
- **Does not add per-instance suppressions.** There is no per-finding keep in this schema by
  design; a passage-level exception is the operator's, through the finding-suppression
  convention.
- **Does not weaken a shipped default to quiet a corpus.** A repository's deliberate structure
  is config in that repository, never a change to what the plugin ships.
- **Does not run the audit.** `/attribution:audit` owns that.
