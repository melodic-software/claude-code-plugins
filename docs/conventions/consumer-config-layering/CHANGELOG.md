# Consumer-Config Layering Convention — Changelog

Notable changes to the consumer-config layering contract. The contract is versioned by
`contract_version` (SemVer) and governs the layering axis only — layer set, precedence, override
semantics, and overlay naming. Per-concern keys and schema are versioned by their own owner docs and
change independently. A change to the precedence order or the meaning of a layer is a major bump;
adding an optional layer or relaxing a rule additively is a minor bump.

## 1.0 — 2026-07-20

Initial published contract, extracted from the tracked-rich-config seam in `docs/MIGRATION-PLAYBOOK.md`
so fleet audits have a Convention registry row to check. No rule changed in the extraction.

- Layer set and precedence: user-global → team → local overlay, resolved in that order.
- Override semantics: additive-preferred; per-key override is sanctioned for scalar and closed-list
  keys and must be declared; wholesale replacement of a base layer is forbidden.
- Overlay naming: `*.local.*`, with one recursive consumer `.gitignore` line covering flat,
  folder-form, and profiled surfaces alike.
- Resolution algorithm, including the repo-root anchoring rule and the per-layer gitignore verdicts.
- Deviations recorded as observed, not ratified.
