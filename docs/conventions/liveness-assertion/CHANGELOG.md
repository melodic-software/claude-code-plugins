# Changelog — liveness-assertion convention

Notable changes to the liveness-assertion contract (SemVer). Changing the core contract, a taxonomy
row's conformance bar, or an enforceability verdict is a major bump; additive guidance or new
instance rows is a minor bump; docs-only clarification is a patch.

## 1.0.0 — 2026-08-13

Initial published contract — peel 1 of
[#532](https://github.com/melodic-software/claude-code-plugins/issues/532) (docs-only; umbrella
stays open for enforcement peels).

- Core contract stated: a health, status, advisory, or gate surface must **fail loud** or route
  findings to an **agent-readable channel**; green-with-hidden-findings and healthy-while-dead are
  violations.
- Boundary stated against sibling umbrellas
  [#530](https://github.com/melodic-software/claude-code-plugins/issues/530) (signal absent) and
  [#531](https://github.com/melodic-software/claude-code-plugins/issues/531) (coupling axis); hook
  prerequisite silent-skip remains owned by `hook-observability` / `silent-skip-gate`.
- Surface taxonomy fixed: engine health-check, advisory lane, gate/classifier — with per-type
  conformance bars and self-test probe requirement for engines.
- Adopters/instances table seeded: `silent-skip-gate` and hygiene aggregator `--self-test` as
  conforming references; #510, #385/#376, #465/#499, #509 as tracked instances.
- Enforceability classified; peel 1 defers CI meta-check and engine self-test gates with event
  triggers.
- Convention registry row added in `PLUGIN-PHILOSOPHY.md`; Prerequisites section gains a pointer.
