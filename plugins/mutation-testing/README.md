# mutation-testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow. It measures whether a test
suite can actually *detect* faults, not merely *execute* code. Three skills, one concern: proving the
tests are checking something.

| Skill | What it does |
|---|---|
| `/mutation-testing:principles` | Knowledge router. Mutant states, operator catalogs, mutation score vs covered-code score vs test strength vs MSI, the oracle gap, equivalent mutants, arid nodes, and why not to gate on the score. Five reference spokes load on demand; a quick decision guide answers the common questions with no file load. |
| `/mutation-testing:setup` | Verify and configure. Detect the ecosystem, confirm the mutation tool is installed and drives the project's test runner, measure the baseline suite, settle the diff target and operator set, write the tracked config and an empty arid-node suppression record. `check` inspects read-only; `apply` interviews and writes. |
| `/mutation-testing:audit` | Diff-scoped mutation analysis, read-only with respect to tracked source. At most one mutant per changed line, executed against the cached covering tests, always reverted. Survivor triage is delegated to a fresh-context reviewer; the report ranks files by oracle gap and hands survivors to the test-authoring lane. `--persist-findings` additionally writes the survivors into the memory tier as a findings file the `review:fanout` `fix` action consumes, after proving that destination outside tracked space, by probing the checkout that governs it or by establishing from two independent signals that none does. |

## Why this exists

Coverage tells you a line **executed**. It cannot tell you the line was **checked**. A file at 95%
coverage and 40% covered-code mutation score has tests that run the code and assert almost nothing
about it, and a coverage report will call that file healthy.

## Works in any repo

- **Reads your conventions, assumes none.** Ecosystem, test runner, source roots, and diff target
  come from your own project. Detected from what exists, confirmed with you at setup, then recorded
  in a tracked config file so runs are deterministic.
- **Cross-plugin refs degrade gracefully.** Test authoring defers to `/testing:write` when the
  `testing` plugin is installed and hands the survivor list back otherwise; failing-suite diagnosis
  routes to `/testing:diagnose` when installed and to the project's own test command otherwise;
  test-design questions route to `/tdd:principles` when installed and to the project's own guidance
  otherwise. No step blocks on a missing plugin.
- **Self-contained.** Operator catalogs, metric formulas, the scaling protocol, and the manual
  fallback for languages with no tool ship inside the plugin and are referenced via
  `${CLAUDE_PLUGIN_ROOT}`.

## What it deliberately does not do

- **No score gate.** The config has no threshold field. A mutation score has a permanent, unknowable
  ceiling below 100% because equivalent mutants cannot all be removed, and every point is
  purchasable by suppressing a mutant, so a gate selects for suppression over testing. Report the
  number; rank by the gap; let the surviving mutants be the finding.
- **No whole-repo nightly ratchet.** Diff-scoped, at most one mutant per changed line. The
  un-scoped, un-suppressed, gated shape is the one that kept this technique unused for three
  decades.
- **No test authoring.** `audit` never both creates a gap and closes it.
- **No mutation left behind.** Every mutant is reverted on every exit path; a run that cannot restore
  the tree reports that as its headline finding.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install mutation-testing@melodic-software
```

## Configuration

`/mutation-testing:setup apply` writes two tracked files in the consuming repo:

- `.claude/mutation-testing.md`. Tool, invocation command, diff target, mutate globs, operator set,
  timeout, measured baseline suite time, optional mutant cap.
- `.claude/mutation-testing-arid.md`, the arid-node suppression record, shaped by the marketplace's
  finding-suppression convention: a mapping keyed by a derived `finding_id`, every entry carrying all
  five required keys (`check`, `claim`, `sites`, `reason`, `date`) with the id derived from its own
  constituents. An entry missing any of them is malformed and does not suppress.

They are kept separate deliberately: a config diff reads as a policy change, a suppression diff reads
as an accepted finding. **Their layering also differs.** The config layers per the config-cascade
convention (user-global → team → `.local.md` overlay, later wins). The suppression record sits in the
cascade's policy-floor precedence-inversion class: on a conflict the **team** layer wins, and a
personal-layer entry for an id the team layer does not carry **does not suppress at all**. It is
reported `personal-only, not applied`. A personal layer is a draft surface there, so one developer
cannot hide a finding the team never accepted.

This plugin declares no `userConfig` options.

## Sources

The reference material is distilled from primary sources, fetched 2026-08-10:

- [Stryker. Mutant states and metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/),
  [Stryker.NET configuration](https://stryker-mutator.io/docs/stryker-net/configuration/),
  [StrykerJS incremental](https://stryker-mutator.io/docs/stryker-js/incremental/)
- [PIT](https://pitest.org/) and its [mutation operators](https://pitest.org/quickstart/mutators/)
- [Infection. MSI](https://infection.github.io/guide/)
- Petrović & Ivanković, *State of Mutation Testing at Google*, ICSE-SEIP 2018
  (<https://dl.acm.org/doi/10.1145/3183519.3183521>)
- Petrović, Ivanković, Fraser & Just, *Practical Mutation Testing at Scale*
  (<https://arxiv.org/abs/2102.11378>)
- Jia & Harman, *An Analysis and Survey of the Development of Mutation Testing*, IEEE TSE 37(5), 2011
  (<https://dl.acm.org/doi/10.1109/TSE.2010.62>)
- Ojdanic et al., *Mind the Gap: The Difference Between Coverage and Mutation Score Can Guide Testing
  Efforts* (<https://arxiv.org/abs/2309.02395>)
- DeMillo, Lipton & Sayward, *Hints on Test Data Selection*, IEEE Computer, 1978

## License

MIT (SPDX-License-Identifier: MIT).
