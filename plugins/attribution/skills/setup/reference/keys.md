# Attribution config keys

## The form

Write block style. Quote a value that starts with `*`, `&`, `!`, `|`, `>`, `{` or `[`, that holds a
`:` followed by a space, or that holds a `#` after a space: the detectors name a file outside their
YAML subset on stderr and read none of it.

```yaml
excluded_paths:
  - docs/legacy/**
budgets:
  searches_per_candidate: 3
  fetches_per_candidate: 5
  corpus_fetch_ceiling: 200
separation:
  min_containment: 0.3
  min_span_words: 15
stamp_expiry_days: 180
trigger_less_stamp_check: false
judge_samples: 3
gates:
  fix_precision_bar: 0.95
  report_recall_floor: 0.8
  min_n_per_class: 10
accuracy:
  nomination_passes: 2
  judge_lens_diversity: true
  review_agents: 1
  deep_research_on_exhaustion: false
```

- **`excluded_paths`**: categorical exclusions, glob-matched against repo-relative paths. This
  is where a repository declines a whole class of surface, never an individual passage someone
  wanted kept.
- **`budgets`**: per-candidate caps and the corpus ceiling. These bound runaway loops rather
  than save money: fetches are cheap and judge sampling is the cost center.
- **`separation`**: the deterministic rule's two constants. The rule fires on containment at or
  above `min_containment` **or** a matched span at or above `min_span_words`, after
  quote-stripping. Raising both narrows what can become fix-eligible.
- **`stamp_expiry_days`**: the verification-stamp window.
- **`trigger_less_stamp_check`**: off by default. See below.
- **`judge_samples`**: panel size, floor 3 for anything that could become fix-eligible.
- **`gates`**: bind fix-mode eligibility and release readiness only. **They never filter what
  the report shows.** Lowering a gate does not hide findings and raising one does not surface
  more; that separation is deliberate.
- **`accuracy`**: the verification-depth dials. `judge_samples` is not one of them (`SKILL.md`, "The keys").

## The test-fixture exclusion

With no layer setting `excluded_paths`, its bundled default declines test-fixture trees:

```yaml
excluded_paths:
  - "**/fixtures/**"
  - "**/__fixtures__/**"
  - "**/testdata/**"
```

The default is matched below the scan target and never declines a named file, so a run aimed at
a fixture tree, or given a fixture file, reads it. A layer that sets `excluded_paths` replaces
the default whole: keep these globs in its list to keep declining the trees, or set `[]` to scan
them.

**This belongs in config and nowhere else.** An unconditional exclusion inside `list-corpus.sh`
would decline the fixtures under the eval harness, leaving the eval author reading prose instead
of results. As a default value, a normal run declines the trees and says so, while the harness
lifts it and the fixtures report their real findings.

## Enabling the trigger-less-stamp check

Off by default, deliberately. It flags a dated stamp whose surface states no recheck trigger,
and it is coarse by design: it asks whether the whole file states a trigger anywhere, so one
trigger clears every stamp in that file.

Enable it only when the repository's stamp forms are uniform enough to be found reliably.
Measure before enabling, never after, with the `--trigger-less` run `SKILL.md` names.

Read two numbers from that run. If `counts.declined` is a large share of `counts.candidates`,
the repository's stamps are not uniformly greppable and enabling the check converts signal into
noise. If the trigger-less findings are dominated by files that plainly do state a trigger in
wording the check does not recognize, the same conclusion follows. Leave it off and say why.
