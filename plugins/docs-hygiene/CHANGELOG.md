# Changelog — docs-hygiene plugin

## [0.9.0]

### Added

- **`rename-references` gains three container-position pattern forms (13–15), closing the gap
  that let six stale references survive three sweep passes (`#1283`).** Forms 1–12 assume the
  renamed token is a skill/mode identifier. When a CONTAINER renames — a plugin, a marketplace
  entry — the token also appears in positions none of them reach: as the argument to a
  management command (`/plugin install <old>@marketplace`, `/plugin configure <old>`), as a
  document title that IS the token (`# <old>`), and in possessive or appositive prose
  (`<old>'s effective configuration`, `the <old> plugin`). Form 1 cannot fire on the first
  shape because the slash anchors `plugin`, not `<old>`.

  Each new form is high-precision because the SURROUNDING SYNTAX admits only the naming sense:
  a management verb before the token, a `$`-anchored heading, the possessive clitic. That is
  what lets them stay Certain where bare-token Form 2 cannot be. Measured on the real fixture
  (the `re-anchor` → `discipline` rename, over that plugin's own tree): Form 2 matched **134**
  lines for **8** real defects; Forms 13–15 matched **9** — the 8 defects plus one frozen
  CHANGELOG-history line the existing "Frozen historical records" rule already excludes.

  Command-argument hits are called out as FUNCTIONAL breaks, not cosmetic ones: a reader
  following `/plugin install <old>@marketplace` gets `plugin-not-found`.

### Changed

- **`triage.md` records the collision class the English-verb blocklist cannot serve.** The
  blocklist holds tokens that are English verbs in general; it cannot cover a token that is a
  verb *in the consuming codebase*. Both branches fail there — omitted, every bare-token hit is
  rated Certain and the sweep proposes rewriting the verb uses; added, every hit lands ambiguous
  and the per-match confirmation rule turns a handful of defects into hundreds of prompts.
  Extending the blocklist swaps one unusable bucket for another; the remedy is position. The
  section routes to Forms 13–15 and carries the measured figures.
- **`patterns.md` Phase 6 now requires validating a new form on BOTH axes.** Recall alone is not
  evidence — Form 2 already has perfect recall on every form in the library and is still
  unusable when the token is a verb. A candidate is measured against the commit that FIXED the
  missed references (its removed lines are the defect set) for recall, and against the whole
  pre-fix tree for precision, reporting its hit count beside Form 2's on that same tree.
- **`audit.md`'s pattern-form breakdown** lists Forms 13–15 so an audit report accounts for
  every form the sweep runs.

## [0.8.7]

### Fixed

- `audit-derivability` fork-mechanism disambiguation now reads in one voice: the Hard Rules bullet
  adopts the "is the opposite" phrasing already used by the spot-test bullet, `context/rubric.md`,
  and `evals/evals.json`, replacing its divergent "is unrelated". The Gotchas self-grade bullet,
  previously the one bare "non-fork subagent" site, now names the Agent tool's `fork` subagent type
  as the forbidden mechanism — matching what `evals/evals.json` already grades on — without
  repeating the full `context: fork` explanation.

## [0.8.6]

### Fixed

- `audit-derivability` Hard Rules "never by a fork" now names the Agent tool's `fork` subagent
  type inline and distinguishes it from a skill's own `context: fork` frontmatter (which starts
  blank), matching the disambiguation already in the spot-test bullet — the Hard Rules section is
  now self-contained for a reader landing there first.

## [0.8.5]

### Fixed

- `audit-derivability` spot-test wording no longer inverts the fork mechanism: the contamination
  risk is attributed to the Agent tool's `fork` subagent type (which inherits the invoking
  conversation), not to a skill's own `context: fork` frontmatter (which starts blank with no
  conversation access). Corrected across SKILL.md, `context/rubric.md`, and `evals/evals.json`;
  the fresh-context non-fork recommendation is unchanged.

## [0.8.4]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.8.3]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.2] — 2026-07-21

### Fixed

- **`audit-noise`'s convention-roots scan no longer truncates a quoted
  `memory_dir`/`contract_dir` at an interior `#`, collapses interior
  whitespace, or leaves quotes unstripped.** The hand-rolled
  `${val%%#*}` + `${val//[[:space:]]/}` + ad hoc quote-peel in
  `scripts/lib/noise-shapes.sh`'s `audit_noise_convention_roots_pattern` is
  gone; resolution now routes through the shared `parse-concern-value.sh`
  helper (materialized from `lib/parse-concern-value.sh`), which resolves
  surrounding quotes and a comment-aware strip in the correct order and
  never mangles interior whitespace. Held behavior: trailing-slash
  normalization, and the `.`/`.work`/`docs/topics` default-root exclusions.

## [0.8.1] — 2026-07-21

### Added

- **`audit-noise` gates its five in-page NOISE shapes behind a whole-page
  existence pre-check** (#505). Before line-level classification, the skill
  now asks whether a reader with repository search could derive the page's
  content from the code itself; a FAIL is a deletion candidate (recommend
  relocate-then-delete, never auto-delete) and skips the in-page tier table.
  Decisions, domain language, thin navigation, and policy/wiring pages always
  pass admission. Reuses `/docs-hygiene:audit-derivability`'s rubric by
  reference for contested calls (optional namespaced skill invocation,
  degrading to the admission question standalone when unavailable). Ships as
  a portable-baseline default; a consuming repo's own declared
  documentation-existence convention overrides it via
  `/re-anchor:follow-our-standards`'s resolution ladder. Read-only, matching
  the skill's existing contract.

## [0.8.0] — 2026-07-20

### Added

- `/docs-hygiene:audit-derivability` — a read-only, document-level worth
  classifier. It asks whether a whole documentation file earns its existence:
  could a fresh agent re-derive the document's conclusions by natively exploring
  the code, config, metadata, and structure? Verdicts weigh four factors
  together (derivability, re-derivation cost, drift risk, fact ownership) and
  never derivability alone — `delete`, `convert-to-pointer`,
  `keep-as-derivation-cache` (which demotes when it carries no drift-control
  condition), or `keep-owns-facts` (rationale, decisions, constraints, and
  external facts are non-derivable). Audience-aware (agent-facing surfaces get
  the full axe; human-facing docs clear a higher bar), and load-bearing or
  contested deletions are confirmed by a fresh-context, non-fork spot-test that
  has not seen the document. Distinct axis from the siblings, which trim
  *inside* a document worth keeping.

## [0.7.1] — 2026-07-20

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0] — 2026-07-18

Changed:

- `/docs-hygiene:compress`: `markdownlint-cli2` absence is now classified
  required-for-correctness — the skill stops at the entry point with an install
  remediation instead of treating a missing ship gate like a lint failure
  (prerequisite-visibility wave).
- README gains a Requirements section declaring the runtime (Bash/git/jq
  ambient, Git Bash on native Windows), the compress-only `markdownlint-cli2`
  requirement with its absence behavior, and the optional `caveman` backend.

## [0.6.0] — 2026-07-17

Changed:

- Renamed the `declutter` skill → `audit-noise` (breaking). Update any
  `/docs-hygiene:declutter` invocations to `/docs-hygiene:audit-noise`; the
  plugin ID (`docs-hygiene`) is unchanged, only the skill's leaf name moved.
  The skill is a read-only classifier — per the marketplace naming grammar
  `audit` = read-only report — and "declutter" remains a description trigger
  word. The detect-script env vars moved with it:
  `DECLUTTER_REPO_ROOT` → `AUDIT_NOISE_REPO_ROOT`.

## [0.5.0] — 2026-07-15

Changed:

- Renamed the `encapsulation-audit` skill → `audit-encapsulation`. Update any
  `/docs-hygiene:encapsulation-audit` invocations to `/docs-hygiene:audit-encapsulation`; the plugin ID
  (`docs-hygiene`) is unchanged, only the skill's leaf name moved.

## [0.4.0] — 2026-07-15

Added:

- Self-contained, bundled eval fixtures: compress's `audit-classification-table`
  case (`evals/fixtures/audit-fixture-dir/`) and declutter's
  `opt-out-and-section-exemptions-respected` case
  (`evals/fixtures/legit-optouts.md`) — both previously unfalsifiable prose
  prompts referencing nonexistent files.
- The "add an eval case" clause, re-added to the two Gotchas/Recheck-trigger
  bullets in rename-references/SKILL.md.

## [0.3.0] — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0) in the declutter
ghost-ref detector:

- Concrete `docs/topics/<slug>/` contract-slice paths are ghost-ref
  candidates alongside `.work/<slug>/` memory slices — contract slices
  are pruned before merge, so a durable doc citing one breaks.
- Any `.claude/notes/` citation is a ghost-ref candidate, placeholder
  form included — the location is retired under the convention.
- The exemption widens from the bare `.work/<slug>` / `.work/<sub-slug>`
  / `.work/<TS>` tokens to the convention's citable surfaces:
  angle-bracket slot variables under `.work/` and `docs/topics/`, the
  reserved concern-scoped roots `.work/handoffs/` and `.work/reviews/`,
  and the tracked concern file `.claude/topic-docs.yaml`.
- Exemptions apply per matched path, not per line: the detector scans
  each candidate path individually, so a convention token (placeholder,
  bare concern root, concern file) no longer masks a concrete ghost ref
  sharing its line.
- The concern-root exemption narrows to the bare roots: `.work/handoffs/`
  and `.work/reviews/` are exempt only with nothing concrete after them
  (or an angle-bracket placeholder child) — a concrete child such as
  `.work/reviews/pr-123-auth/20260101T000000Z-self.md` flags.
- Candidate slugs accept a digit-leading first character, matching the
  convention's `[a-z0-9-]` slug spec and its recommended date-suffixed
  slugs (`docs/topics/2026-migration/PLAN.md` flags).
- The `.claude/topic-docs.yaml` exemption clause is removed: the concern
  file matches no ghost-ref pattern, so under the per-path model it
  passes naturally instead of exempting whole lines.
- The ghost-ref block short-circuits: a literal prefilter on `.work/`,
  `docs/topics/`, and `.claude/notes/` gates the scan, which stops at
  the first flagged path.
