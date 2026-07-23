# Config Cascade Convention — Changelog

Notable changes to the config-cascade contract. The contract is versioned by
`contract_version` (SemVer) and governs the layering axis only — layer set, precedence, override
semantics, and overlay naming. Per-concern keys and schema are versioned by their own owner docs and
change independently. A change to the precedence order or the meaning of a layer is a major bump;
adding an optional layer or relaxing a rule additively is a minor bump.

## Renamed — 2026-07-23

Folder + concept renamed `consumer-config-layering` → `config-cascade` (#1188). No contract change:
`contract_version` and every layer/precedence rule are unchanged — this is a name/path rename only,
so no version bump. The former clunky three-noun label is replaced by "cascade" (the established
CSS-cascade term for precedence-ordered resolution with override + ratified inversion). All live
references updated; historical topic docs and CHANGELOGs retain the former name as frozen record.

## 1.1 — 2026-07-20

Additive relaxation (minor bump): ratified a named exception class. Default precedence is unchanged for
every surface; the change carves out one surface class that may invert precedence direction on conflict.

- **Sanctioned exception class — policy-floor precedence inversion.** A surface whose team layer encodes
  a policy floor personal layers may extend or tighten but never weaken may invert precedence so the
  team layer wins a direct conflict, provided personal layers stay add/tighten-only and provenance is
  reported. Such a surface is conformant, not a tolerated deviation. `standards` is the exemplar; ruled
  in #649.

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
