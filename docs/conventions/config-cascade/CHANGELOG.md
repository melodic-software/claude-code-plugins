# Config Cascade Convention — Changelog

Notable changes to the config-cascade contract. The contract is versioned by
`contract_version` (SemVer) and governs the layering axis only — layer set, precedence, override
semantics, and overlay naming. Per-concern keys and schema are versioned by their own owner docs and
change independently. A change to the precedence order or the meaning of a layer is a major bump;
adding an optional layer or relaxing a rule additively is a minor bump.

## Implementers table — 2026-08-23

- **`work-items` overlay allowlist.** The personal overlay may refine linear and
  gitea `auth_env` alongside the original jira auth identity keys. The
  Implementers-table wording now matches the seam allowlist so a Linear or Gitea
  user can discover the personal configuration the contract already intended
  (#3132).

## Implementers table — 2026-08-19

- **`ai-slop` row added.** The surface implemented the full three-layer cascade from its first
  release and was never tabled, so the table under-reported a conforming surface rather than an
  open gap. Found by a verifier while checking an unrelated exploration: the plugin registered its
  Wikipedia source with `upstream-drift` but was invisible to this table, the same
  shape-implemented-registration-missed defect in two conventions at once. Records the two
  list keys that replace rather than merge (`vocab_add` / `vocab_remove`), and that no key is
  policy-floor class.

## Implementers table — 2026-08-18

- **`work-items` row (#2941).** Flipped from observed deviation (single-layer, CWD-to-root climb) to
  declared: team + gitignored local overlay at the repo root (ADR 0015), per-key allowlisted overlay
  merge (deny-by-default), deliberately no user-global layer, anchored at the repo root with the climb
  removed. Location precedent: `standards` (layers outside `.claude/`). Includes a declared narrow
  exception to the no-plugin-writes-gitignore rule: the root-level overlay is outside the
  `.claude/**/*.local.*` one-liner, so `/work-items:setup apply` appends its line, announced. No
  contract rule change — no version bump.

## Renamed — 2026-07-23

Folder + concept renamed `consumer-config-layering` → `config-cascade` (#1188). No contract change:
`contract_version` and every layer/precedence rule are unchanged — this is a name/path rename only,
so no version bump. The former clunky three-noun label is replaced by "cascade" (the established
CSS-cascade term for precedence-ordered resolution with override + ratified inversion). All live
references updated; historical topic docs and CHANGELOGs retain the former name as frozen record.

## Implementers table — 2026-08-12

- **`code-tidying` row (#723).** Recorded the declared deviation: no user-global or `*.local.*`
  overlay; team layer over bundled default, with personal variation limited to lane names the team
  does not track (uncommitted team-path lane file never added to the index). No contract rule change

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
