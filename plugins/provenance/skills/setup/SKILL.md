---
description: "Set up and maintain this repository's provenance configuration: `.claude/provenance.json` across the config cascade's three layers. Manages the categorical exclusions (including the eval-fixture tree, which is a config entry by design and never a rule in a script), the per-candidate and corpus fetch budgets, the separation-rule constants, the stamp expiry window, the accuracy dials for nomination passes and judge sampling, and the fix-eligibility gates. Enables the off-by-default trigger-less-stamp check for a repository whose stamp forms are uniform enough to greppably support it. Use when: 'set up provenance', 'configure provenance', 'exclude a path from the provenance audit', 'change the stamp expiry window', 'the provenance audit flags too much', 'turn on the trigger-less stamp check', or after installing the plugin. Writes only the consuming repository's own config file, never source."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/list-corpus.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh:*)", "Bash(git:*)", "Bash(jq:*)", "Bash(grep:*)"]
shell: bash
---

## Pre-computed context

Repository root: !`git rev-parse --show-toplevel 2>/dev/null || echo "not a git repository"`
Team config present: !`test -f "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/provenance.json" && echo yes || echo no`

## Why this skill is human-invoked

`disable-model-invocation: true` under the setup contract: a setup skill is named `setup` and is
explicit and repeatable. Config decides what the audit is allowed to ignore, so the model
proposing its own exclusions would let a run quiet its own findings. Every write here is a
deliberate human choice.

## Action router

| Argument | Action |
|---|---|
| *(empty)* or `check` | **Read-only.** Report the effective config, which layer supplies each value, and what a proposed change would alter. Writes nothing |
| `apply` | Write the agreed keys to `.claude/provenance.json` in the team layer, or the local overlay when the user asks for that layer |

`check` is the default and never writes. `apply` writes only after the user has seen a `check`
report naming every key it will change and the layer it will change it in. On a first run in a
repository with no config, `check` interviews for the initial keys and reports the file it would
write; `apply` writes it.

`apply` is a per-key edit, never a regenerated file. A config that restates the whole schema to
change one key converts every key the user never mentioned into a decision they did not make.

## The three layers

Per the config-cascade convention, resolved in this order, each optional, a later layer refining
an earlier one:

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/provenance.json` | the operator, across every repo |
| 2 | team | `<repo>/.claude/provenance.json` | the repository, tracked |
| 3 | local overlay | `<repo>/.claude/provenance.local.json` | one operator in one repo, gitignored |

All three absent is a valid state: the bundled defaults apply. Merge is **per-key override** —
a later layer replaces a value key by key, and a key absent from a later layer keeps the earlier
value. Never write a layer that restates the whole config to change one key; that turns every
key the overlay does not mention into an accidental decision.

To report the effective values and their supplying layer, run the detectors' own
`--show-config`, which is the authority rather than reading the files by hand:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/list-corpus.sh" --show-config
"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh" --show-config
```

## The keys

```json
{
  "excluded_paths": ["docs/legacy/**"],
  "budgets": {
    "searches_per_candidate": 3,
    "fetches_per_candidate": 5,
    "corpus_fetch_ceiling": 200
  },
  "separation": { "min_containment": 0.3, "min_span_words": 15 },
  "stamp_expiry_days": 180,
  "trigger_less_stamp_check": false,
  "judge_samples": 3,
  "gates": {
    "fix_precision_bar": 0.95,
    "report_recall_floor": 0.8,
    "min_n_per_class": 10
  },
  "accuracy": {
    "nomination_passes": 2,
    "judge_lens_diversity": true,
    "review_agents": 1,
    "deep_research_on_exhaustion": false
  }
}
```

- **`excluded_paths`** — categorical exclusions, glob-matched against repo-relative paths. This
  is where a repository declines a whole class of surface, never an individual passage someone
  wanted kept.
- **`budgets`** — per-candidate caps and the corpus ceiling. These bound runaway loops rather
  than save money: fetches are cheap and judge sampling is the cost center.
- **`separation`** — the deterministic rule's two constants. The rule fires on containment at or
  above `min_containment` **or** a matched span at or above `min_span_words`, after
  quote-stripping. Raising both narrows what can become fix-eligible.
- **`stamp_expiry_days`** — the verification-stamp window.
- **`trigger_less_stamp_check`** — off by default; see below.
- **`judge_samples`** — panel size, floor 3 for anything that could become fix-eligible.
- **`gates`** — bind fix-mode eligibility and release readiness only. **They never filter what
  the report shows.** Lowering a gate does not hide findings and raising one does not surface
  more; that separation is deliberate.
- **`accuracy`** — the verification-depth dials. `judge_samples` is deliberately a TOP-LEVEL key
  and not one of these; reject an `accuracy.judge_samples` loudly rather than writing it, since
  a misplaced key there would be a silent no-op that quietly halves the panel.

Reject any key not in this schema rather than writing it through. A typo that lands in the file
reads as a setting and behaves as nothing.

## The eval-fixture exclusion

A repository that runs this plugin's own eval harness lists the fixture tree in
`excluded_paths`:

```json
{ "excluded_paths": ["**/provenance/skills/audit/evals/fixtures/**"] }
```

**This belongs in config and nowhere else.** An unconditional exclusion inside `list-corpus.sh`
would decline the fixtures under the eval harness's own config isolation, leaving the eval
author reading prose instead of results. As a config entry, a normal run declines the tree and
says so, while the harness lifts the config layer and the fixtures report their real findings.
If someone proposes moving this into the script, that is the reason not to.

## Enabling the trigger-less-stamp check

Off by default, deliberately. It flags a dated stamp whose surface states no recheck trigger,
and it is coarse by design: it asks whether the whole file states a trigger anywhere, so one
trigger clears every stamp in that file.

Enable it only when the repository's stamp forms are uniform enough to be found reliably.
Measure before enabling, never after:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-stamps.sh" --trigger-less
```

Read two numbers from that run. If `counts.declined` is a large share of `counts.candidates`,
the repository's stamps are not uniformly greppable and enabling the check converts signal into
noise. If the trigger-less findings are dominated by files that plainly do state a trigger in
wording the check does not recognize, the same conclusion follows. Leave it off and say why.

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
  An unconditional exclusion would decline the fixtures under the eval harness's own config
  isolation, leaving the eval author reading prose instead of results.

## What this skill does NOT do

- **Does not edit source.** The only file it writes is the consuming repository's own config.
- **Does not add per-instance suppressions.** There is no per-finding keep in this schema by
  design; a passage-level exception is the operator's, through the finding-suppression
  convention.
- **Does not weaken a shipped default to quiet a corpus.** A repository's deliberate structure
  is config in that repository, never a change to what the plugin ships.
- **Does not run the audit.** `/provenance:audit` owns that.
