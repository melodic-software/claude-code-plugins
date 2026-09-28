# Changelog for the Config Cascade Convention

Notable changes to the config-cascade contract. The contract is versioned by
`contract_version` (SemVer) and governs the layering axis (layer set, precedence, override
semantics, overlay naming) and, from 1.2, expression form (dedicated file vs convention doc bound
by a pointer line). Per-concern keys and schema are versioned by their own owner docs and
change independently. A change to the precedence order or the meaning of a layer is a major bump;
adding an optional layer or relaxing a rule additively is a minor bump.

## Implementers table, 2026-09-28 (architecture readers)

- **`architecture` is also read by `/architecture:map-containers`.** `architecture_dir` still has
  no default. `diagram_dialect.system` stays owned by authoring-formats. No `contract_version`
  bump: layering is unchanged.

## Deviations and Implementers table, 2026-09-28 (gitignore)

- **gitignore postures declared, not converged (#3573).** Recommend stays the
  default. Two consumer-root appends are sanctioned exceptions (`source-control`
  recursive overlay line; `work-items` ADR 0015 overlay line). Own-ignore-file
  inside a plugin-owned directory is a different file. No `contract_version`
  bump: the layering rules are unchanged; the no-plugin-writes sentence now
  names the exceptions it already described in Overlay spelling drift.

## Consumer gotchas tier, 2026-09-28

- **Ratified `consumer-gotchas.md` (#3547).** Documents the concatenating cascade tier for
  consumer-contributed skill gotchas (local config vs upstream issues). No `contract_version` bump:
  additive guidance sibling to the core contract; participating plugins wire readers per plugin.

## Deviations and Implementers table, 2026-09-28

- **Semantics-at-a-glance index (#3575).** A who-wins / merge-form table sits above
  Implementers so an operator can see later-wins, policy-floor inversion,
  `code-tidying`'s no-overlay residual, and `repo-fleet-hygiene`'s reversed
  ladder without reading every conformance cell. Engines stay per-surface.
  No `contract_version` bump: no layering rule changed.
- **Location outliers ruled (#3577).** `standards` layer location outside `.claude/`
  (default `docs/standards/`) is ratified, the axis #649 left open. `work-items`
  recurring schedule stays at `.github/recurring-schedule.json` (team-only, no
  overlay). `songwriting` prompt-template overrides stay at
  `songwriting/templates/pat-pattison/` (team-only, not a cascade). Relocating any
  of the three under `.claude/` was rejected. The `work-items` binding at repo
  root was already ADR 0015. No contract rule change, so no version bump.
- **`code-metrics` `.claude/code-metrics.yaml` (#3847).** The table gains the surface the plugin already ships: all three layers, per-key override, keys owned by `plugins/code-metrics/reference/config.md`. No contract rule change, so no version bump.
- **`source-control` `branch_issue_pattern` fail-closed stop declared (#4673).** The Declared list
  gains the surface's divergence from rule 4 (degrade soft on a malformed layer): a layer whose
  `## branch_issue_pattern` section exists but yields no usable pattern stops resolution with no
  issue number, because the value feeds a `Closes #N` line and a lower source's number could close
  the wrong issue. The row's conformance cell names the exception. The near-miss-heading stop that
  shipped in #4581 was that divergence already, undeclared. No contract rule change, so no version
  bump.

## Implementers table, 2026-09-08

- **`architecture` and `authoring-formats` C4 dialect surfaces (#3910).** The two rows no longer
  sit as unexplained opposites on mermaid fitness. Each points at the mapping in its owner doc
  (`plugins/architecture/reference/config.md`, `docs/conventions/authoring-formats/README.md`):
  `landscape_dialect` is the landscape `/architecture:map-landscape` emits, and
  `diagram_dialect.system` is the opt-in container view `/planning:design` emits. Defaults and
  allowed values are unchanged. No contract rule change, so no version bump.

## Implementers table, 2026-09-02

- **`ai-briefing` team-only, no local overlay (#3580).** The surface no longer recommends a
  `.claude/ai-briefing/**/*.local.*` gitignore line. The implementers row and declared-deviation
  text now record team-only with no local overlay. Named profile selection is profile selection,
  not a `*.local.*` cascade layer. `sources.md`, optional `audience.md`, and optional
  `brand.json` are profile files in the selected team directory, not personal overlays. No
  contract rule change, so no version bump.

## [1.2] - 2026-09-01

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

## Implementers table, 2026-08-28

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
  change, so no version bump. Found by the whole-repo extract-ssot sweep's encapsulation floor.

## Implementers table, 2026-08-23

- **`work-items` overlay allowlist.** The personal overlay may refine linear and
  gitea `auth_env` alongside the original jira auth identity keys. The
  Implementers-table wording now matches the overlay allowlist so a Linear or Gitea
  user can discover the personal configuration the contract already intended
  (#3132).

## Implementers table, 2026-08-19

- **`ai-slop` row added.** The surface implemented the full three-layer cascade from its first
  release and was never tabled, so the table under-reported a conforming surface rather than an
  open gap. Found by a verifier while checking an unrelated exploration: the plugin registered its
  Wikipedia source with `upstream-drift` but was invisible to this table, the same
  shape-implemented-registration-missed defect in two conventions at once. Records the two
  list keys that replace rather than merge (`vocab_add` / `vocab_remove`), and that no key is
  policy-floor class.

## Implementers table, 2026-08-18

- **`work-items` row (#2941).** Flipped from observed deviation (single-layer, CWD-to-root climb) to
  declared: team + gitignored local overlay at the repo root (ADR 0015), per-key allowlisted overlay
  merge (deny-by-default), deliberately no user-global layer, anchored at the repo root with the climb
  removed. Location precedent: `standards` (layers outside `.claude/`). Includes a declared narrow
  exception to the no-plugin-writes-gitignore rule: the root-level overlay is outside the
  `.claude/**/*.local.*` one-liner, so `/work-items:setup apply` appends its line, announced. No
  contract rule change, so no version bump.

## Renamed, 2026-07-23

Folder + concept renamed `consumer-config-layering` → `config-cascade` (#1188). No contract change:
`contract_version` and every layer/precedence rule are unchanged. This is a name/path rename only,
so no version bump. The former clunky three-noun label is replaced by "cascade" (the established
CSS-cascade term for precedence-ordered resolution with override + ratified inversion). All live
references updated; historical topic docs and CHANGELOGs retain the former name as frozen record.

## Implementers table, 2026-08-12

- **`code-tidying` row (#723).** Recorded the declared deviation: no user-global or `*.local.*`
  overlay; team layer over bundled default, with personal variation limited to lane names the team
  does not track (uncommitted team-path lane file never added to the index). No contract rule change

## [1.1] - 2026-07-20

Additive relaxation (minor bump): ratified a named exception class. Default precedence is unchanged for
every surface; the change carves out one surface class that may invert precedence direction on conflict.

- **Sanctioned exception class: policy-floor precedence inversion.** A surface whose team layer encodes
  a policy floor personal layers may extend or tighten but never weaken may invert precedence so the
  team layer wins a direct conflict, provided personal layers stay add/tighten-only and provenance is
  reported. Such a surface is conformant, not a tolerated deviation. `standards` is the exemplar; ruled
  in #649.

## [1.0] - 2026-07-20

Initial published contract, extracted from the tracked-rich-config section in `docs/migration-playbook.md`
so fleet audits have a Convention registry row to check. No rule changed in the extraction.

- Layer set and precedence: user-global → team → local overlay, resolved in that order.
- Override semantics: additive-preferred; per-key override is sanctioned for scalar and closed-list
  keys and must be declared; wholesale replacement of a base layer is forbidden.
- Overlay naming: `*.local.*`, with one recursive consumer `.gitignore` line covering flat,
  folder-form, and profiled surfaces alike.
- Resolution algorithm, including the repo-root anchoring rule and the per-layer gitignore verdicts.
- Deviations recorded as observed, not ratified.
