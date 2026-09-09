# ai-slop plugin scope

## Brief

### TLDR

- The ai-slop plugin runs both detection layers, detector and full judgment rubric, on every repo-wide audit; nothing is budgeted away.
- Em dashes are not this repo's house style. The em-dash rule is re-enabled and the corpus purge tracked by #2891 continues.
- Ten plugin defects observed during the 2026-09-08 audit run are fixed in this branch and the plugin version is bumped.
- This branch de-slops the ai-slop plugin's own tree completely plus the four filler hits elsewhere; the rest of the corpus lands as per-plugin tranches under #2891.
- One umbrella issue tracks the plugin defects; the corpus decisions are recorded on #2891.

### Goal

The plugin that ships the em-dash rule passes its own audit, its detector and emit scripts produce a findings file that is correct when the corpus is scanned in chunks, its rubric layer has a defined and resumable execution shape, and this repository's config stops overriding the plugin's headline rule for a reason that was volume rather than style.

### Constraints

- Vendored upstream material under `plugins/*/skills/*/vendor/**` and the eval fixtures under `plugins/ai-slop/skills/audit/evals/fixtures/**` stay excluded from the audit. Every other tracked markdown file is in scope.
- The curly-quote and emoji rules stay disabled in this repository. Each cites a specific owner ruling, not volume.
- Every file edit under `plugins/ai-slop/` requires a version bump and a CHANGELOG entry per the changelog-parity gate.
- Prose rewrites go through the rewrite guide and a fresh-context semantic-diff verification per file. Meaning is preserved over style.
- No rewrite of vendored content.

### Acceptance criteria

- `.claude/ai-slop.json` no longer lists `rule-em-dash` in `disabled_rules`, no longer lists `catalog.md` in `excluded_paths`, and its comment states the current rule and its reason rather than a volume measurement.
- The audit skill's pre-computed context shows `disabled_rules` and `rule_allowed_paths` for any config that sets them.
- `emit-findings.sh` accepts the output of several chunked `detect.sh` runs and emits per-rule counts equal to the sum over chunks, and a rule reports "no rows" only when every chunk reported zero findings.
- The findings file's Surfaces section names every rule the config disabled.
- A double-quoted span that wraps across a soft line break is exempt from wording rules on both lines.
- The default vocabulary no longer fires on the noun "underscore" in a doc about naming conventions.
- Summary rows report declined counts split by cause (code fence or marker, quotation, config) alongside the total.
- The audit skill states how the rubric pass fans out (batch size, subagent per batch, where partial results persist) so an interrupted repo-wide run resumes from the last completed batch.
- The plugin README names `/ai-slop:audit` as the invocation and says a bare `/ai-slop` is not a command.
- The persist doc tells the operator to create the self-ignore guard file with the Write tool because shell redirects into the checkout are blocked.
- `detect.test.sh` covers the wrapped-quote exemption, the multi-chunk aggregation, and the split declined counts, and passes.
- After the fixes, a detector run over the full target set records the em-dash baseline, and the findings file is re-emitted from that run.
- Every detector and rubric finding under `plugins/ai-slop/` is fixed, suppressed with a reason, or reverted with a reason, and the three `in order to` hits outside the plugin are rewritten.
- IF the post-fix detector run fails or times out, THEN the config change still lands and the issue states the baseline as unmeasured.
- WHILE a plugin's tranche is unmerged, its findings stay on the #2891 checklist and are not re-filed.
- One issue exists in melodic-software/claude-code-plugins carrying the ten defects as checkboxes, labelled `priority: needs-triage` and `work-class: scoped`; the pull request for this branch closes it.
- A comment on #2891 records the three corpus decisions, the measured baseline, and the per-plugin tranche plan.

### Captured assumptions

- The rubric findings gathered during the audit run remain valid after the detector fixes, because none of the ten defects changes what the rubric reads. Revisit if a fix changes the prose extraction the rubric subagents were given.
- "seam" keeps a use only where the surrounding text defines it as a term of art (Feathers-style code seams, the songwriting author seam). Revisit if the sweep finds the definition itself is the only use.
- Unwanted-behaviour and state-driven coverage were examined: both criteria above came from that check.

### Scope change (2026-09-09)

The maintainer reversed the tranche decision after the first pull request opened: the whole corpus purge (#2891) lands in this one branch and pull request, every plugin touched gets its version bump and changelog entry here, and the purge list declares every cleaned path. Worst-first order holds (instruction surfaces, then the rest), and each area is committed as it closes so progress is never stranded. `docs/adr/**` and `docs/upstream/**` stay untouched per the purge list's own header: decision records are a historical account and upstream text is not this repo's prose.

### Out-of-scope

- Rewriting `docs/adr/**` and `docs/upstream/**`, and any vendored tree.
- A `rubric_terms_of_art` config key. The repo decided to sweep the jargon rather than allowlist it.
- A bare `/ai-slop` command alias. Plugin commands are namespaced, so the fix is documentation.
- Re-enabling the curly-quote or emoji rules.

### Deferred questions

- None.

## Plan

(empty; populated by /planning:plan)
