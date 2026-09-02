# Config Cascade Convention — Changelog

Notable changes to the config-cascade contract. The contract is versioned by
`contract_version` (SemVer) and governs the layering axis (layer set, precedence, override
semantics, overlay naming) and, from 1.2, expression form (dedicated file vs convention doc bound
by a pointer line). Per-concern keys and schema are versioned by their own owner docs and
change independently. A change to the precedence order or the meaning of a layer is a major bump;
adding an optional layer or relaxing a rule additively is a minor bump.

## 1.2 — 2026-09-01

- **Expression doctrine (additive, minor).** A second sanctioned expression form joins the
  dedicated file: team-shared prose configuration is expressed as a natural-language convention
  doc at the consumer's convention home, bound by a single pointer line in a marked machine-owned
  region of the root instruction file (the line is the binding; no binding file). Per-operator-
  keyed, structured, policy-floor, and state surfaces stay files. Defines pointer-line rules
  (the file that owns the discovered marked region is canonical; AGENTS.md wins only when both
  files carry a region; a pure `@AGENTS.md` CLAUDE.md shim is not consulted; duplicate and
  missing-target handling as ask-don't-infer FAILs; branch-scoped binding), root-file shape as
  the downstream repo's call, the WARN-visible dual-read deprecation window, the migrated-surface
  overlay WARN, and the machine-scope exclusion. No layer, precedence, or overlay-naming rule
  changes. Ratified by ADR 0018; the Implementers table gains a per-row expression note that each
  migration PR fills.
- **Overlay spelling drift closed.** Every setup recommends the recursive line; the section now
  records the convergence and the two deliberate exceptions.

## Implementers table — 2026-08-28

- **Two rows cited another plugin's skill internals by path.** The `ai-slop` row resolved its
  cascade "in `skills/audit/scripts/detect.sh`" and assigned key ownership to "the plugin's
  `skills/setup/SKILL.md`"; the `testing` (`run-e2e`) row owned its keys at
  `run-e2e/context/e2e-config.md`. All three are plugin-relative paths that resolve against nothing
  from this file, and five plugin surfaces fetch this README over `raw.githubusercontent.com` at run
  time, where the paths are not on disk at all.
  [ADR 0018](../../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)
  makes the plugin the encapsulation boundary for citation: name the public invocation, never a path
  into another plugin's private tree. The rows now read `/ai-slop:audit`, `/ai-slop:setup`, and
  `/testing:run-e2e`. No contract rule change and no layer, precedence, or override semantics
  change — no version bump. Found by the whole-repo extract-ssot sweep's encapsulation floor.

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
