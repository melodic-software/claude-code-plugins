# Changelog — liveness-assertion convention

Notable changes to the liveness-assertion contract (SemVer). Changing the core contract, a taxonomy
row's conformance bar, or an enforceability verdict is a major bump; additive guidance or new
instance rows is a minor bump; docs-only clarification is a patch.

## 1.1.0 — 2026-08-28

Additive, minor — a new instance row. The core contract, every taxonomy row's conformance bar, and
the enforceability verdict are unchanged.

- **`loop-lane-floor-drift-gate` tabled as conforming under Gate / classifier.** It is the
  adopt-on-touch case the convention describes: the surface it replaced was a sentence in
  `docs/conventions/loop-lane/README.md` §6 asserting that fleet audits checked per-consumer
  conformance, while nothing checked it and three consumers had already drifted. The replacement
  states its taxonomy row in its own header and fails loud on every input it cannot resolve rather
  than reporting a comparison it did not make. Its registry is bounded by a repo-wide scan, because
  a hand-maintained list of what to check is itself a surface that can go green over a copy nobody
  added to it.

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
