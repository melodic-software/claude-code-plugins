# Changelog — docs-hygiene plugin

## [0.9.0]

### Fixed

- **Precedence no longer launders a demotion into a Certain rating.** The dedup rule said a
  deduplicated line "enters the Certain bucket" unconditionally, which contradicted Form 14's
  scope rule demoting out-of-scope title matches to Ambiguous — and made eval 11's own
  expectation unachievable. A deduplicated line now enters **the owning form's bucket after its
  scope rules apply**. Precedence decides WHICH form owns a line, never how safely it is rated.
- **Apply mode terminates under container-rename mode.** `apply.md` Phase 6 completed only at
  `count == 0`, but the residue the mode rule deliberately leaves unrenamed still matches the
  token forever, so Outcome B looped indefinitely. Phase 6 now evaluates the ACTIONABLE count —
  the survey after precedence and mode — and reports residue in the hand-off summary.
- **`--include-bare-token` is registered where flags are parsed.** Phase 0b named it as the way
  to inspect suppressed residue, but it appeared in neither `SKILL.md`'s `argument-hint` nor
  `audit-modes.md`'s override table, whose contract errors on unknown flags — so the only
  documented path to the residue failed. Registered in both, audit-mode only, always Ambiguous.
- **Coverage keys on the CAPTURED token span, not the whole match span.** A match usually spans
  more than the token: Form 13's two alternatives span `/plugin install <old>@` and
  `<old>@acme-tools`, which overlap without either containing the other — so the whole-span
  coverage test kept both and scheduled two Edits on one token, the second failing because the
  first already rewrote it. Everything outside the captured `<old>` is context, not the thing
  being replaced.
- **Form 14 recognizes Setext titles.** A README may underline its title instead of using `#`.
  Both render as the primary heading, so missing the Setext shape left a container's own title
  with only a Form 2 hit — excluded by container mode — and the rename could report completion
  with the landing-page title stale.
- **Form 15's appositive accepts sentence-initial `The`.** Container prose routinely opens a
  sentence with "The `<old>` plugin ships…"; a lowercase-only `the` missed it, leaving the token
  with only a suppressed Form 2 hit. Only the article is case-flexible — the token stays
  case-sensitive, per `#1394`.
- **The survey emits one record per OCCURRENCE, not per line.** The span-dedup rule had no spans
  to compare: Grep's content mode returns matching lines and `--column` reports only the first
  match on a line, so a line-shaped record silently degraded the rule back to line-keyed dedup
  and restored the false completion it was written to prevent. Phase 2 now re-scans each returned
  line for every occurrence and emits `{file, line, start, end, pattern_form, snippet}`.
- **Form 13 matches the `marketplace` subcommand shape.** A marketplace's name sits after
  `/plugin marketplace add|update`, not directly after `/plugin` — so renaming a marketplace
  matched no position-anchored form, container mode suppressed its Form 2 hits as residue, and
  the sweep could report zero actionable stragglers while executable install instructions stayed
  stale.
- **The bare qualified-id alternative is Chain-context, not Certain.** Excluding dots is
  necessary but not sufficient — a dotless address is still an address, and this tree contains
  `auth_email: "a@b"` and `user.email t@t`, which containers named `a` or `t` would match and
  auto-rewrite. The management-verb alternative keeps Certain because its verb anchors it; the
  unanchored one is promoted only when a neighbor confirms it.
- **Form 14 recognizes JSON name declarations.** When the manifest or catalog is JSON the
  declaration is `"name": "<old>"` — quoted key, indented, trailing comma — which the
  column-zero YAML alternative reaches not at all. No other container-position form reached it
  either, so container mode reduced the container's own REGISTERED name to excluded residue and
  the sweep could report zero actionable stragglers with the registration stale. The Form 14
  scope rule is now explicitly scoped to the TITLE alternatives: a manifest or catalog `name`
  declaration is exempt from it and from the common-word demotion, because the key is the
  registration rather than evidence of one — without that exemption a repository-root catalog
  entry demotes to Ambiguous and the defect survives the fix.
- **Form 3 keeps terminal container directory paths actionable.** Every earlier path alternative
  requires something AFTER the token — an extension, a trailing slash, a known subdirectory — so
  a catalog's `"source": "./plugins/<old>"` and a README link `[…](plugins/<old>)` reached none
  of them, and apply mode could complete with the marketplace pointing at a vanished directory.
  The new alternative anchors on a bounded container-root segment and excludes an adjacent
  hyphen at both ends.
- **The survey enables multiline for Form 14's Setext alternative.** Phase 2 listed
  `multiline: true` for Form 7 only. The Setext pattern contains a literal `\n`, which ripgrep's
  single-line default REJECTS outright rather than under-matching, so the form was not
  executable through the documented pipeline at all.
- **Form 13's Chain-context demotion is stated consistently across files.** The precedence rule
  enumerated only Certain and Ambiguous, and `triage.md`'s Chain-context criteria never listed
  Form 13 — so the classifier apply mode follows flattened the demotion back to Certain and
  would still auto-rewrite a dotless address. Precedence now carries a per-alternative bucket
  table, container mode defers to it, and `triage.md` registers the alternative in Bucket 2 with
  its own promotion test and a Chain-context floor.
- **Form 14 matches TOML manifest declarations.** TOML delimits with `=`, so `name = "<old>"` in
  `pyproject.toml` or `Cargo.toml` reached neither the YAML nor the JSON alternative — while the
  mode ladder already names `pyproject.toml` as evidence for selecting CONTAINER mode. The skill
  therefore routed such a package into the mode that suppresses bare-token residue while being
  unable to match the one declaration that mode makes load-bearing.
- **Form 14 matches a catalog KEYED by the container, and YAML declarations at any indentation.**
  The mode ladder names both catalog shapes — a manifest's `name`/`id` field or a key in a
  registry catalog — but only the field shape had a pattern, and the YAML alternative was anchored
  at column zero so a nested manifest entry missed. Both selected container mode while their own
  registration stayed excluded residue. The key-position alternative requires the value to OPEN an
  object or array, and is Ambiguous outside a manifest or catalog unconditionally: `"<key>": {` is
  the commonest line shape in JSON (569 in this repository alone), so the file condition is what
  keeps it from becoming a mass-rewrite vector. A YAML block-mapping catalog key stays a
  documented gap: it opens with nothing, so the only pattern reaching it would match every nested
  YAML key.
- **The survey enumerates every token span INSIDE each match.** Form 7's pattern swallows a whole
  frontmatter field and its greedy prefix binds the capture to one occurrence, so
  `description: "first <old> and then <old>"` produced a single match for two references — and no
  cursor advance recovers the other, since re-matching from inside the field cannot reproduce the
  `description:` prefix. The whole-pattern match now establishes THAT a form applies and over what
  extent; the token spans within it are the references.
- **Form 14 accepts closed ATX headings.** `# <old> #` is valid ATX and its entire content is
  still the token, but the anchor rejected the trailing hash run, leaving the title as Form 2
  residue. The run is decoration, not reference: only the token span is replaced.
- **The default hand-off discloses confirmed skips.** Phase 7 required reporting them; the success
  template at the bottom of `apply.md` listed only the residue count, so a normal run said "0
  actionable stragglers" without disclosing that occurrences were preserved by request.
- **The rescan cursor advances to the end of the captured token, not the end of the match.**
  Forms 3, 13, 15 and both delimiter-anchored Form 14 alternatives CONSUME a trailing delimiter
  rather than asserting it, because ripgrep's default engine rejects look-around — and that
  delimiter is often the LEADING one the next occurrence needs. On
  `{"name":"<old>","id":"<old>"}` a global rescan therefore emitted only the first declaration
  and the second survived as suppressed residue. Fixed once in the survey rather than in each
  regex; dropping the terminator is not an option, since without it the qualified-id form matches
  inside an email domain again.
- **Skip spans are remapped as edits apply.** A span recorded before Phase 5 does not survive the
  edit: `<old>` and `<new>` differ in length, so rewriting an accepted occurrence shifts every
  later occurrence on that line and the stored skip no longer subtracts — the non-terminating
  loop again, defeated by the bookkeeping added to close it. Each Edit now shifts the later
  stored spans on its line by the delta, and a carried snippet catches any mismatch.
- **The JSON declaration is delimiter-anchored, not whole-line-anchored.** A minified or compact
  manifest — `{"name":"<old>","version":"1"}` — is perfectly valid and still selects container
  mode by filesystem evidence, but a `^…$` anchor required the field to occupy the whole line and
  left the registration unmatched. Now uses the same `(^|[{,])` / `(,|}|$)` delimiters as the
  key-position shape; precision on this repository is unchanged. The YAML and TOML alternatives
  keep their end-of-line anchor deliberately, being line-oriented grammars for the shapes
  manifests actually use.
- **The mode-ladder lead-in no longer says "stop at the first rule that fires".** The conflict
  rule added below the list said to collect rules 2–4 in full and compare; the sentence
  introducing the list still said the opposite, so the contradiction stood in one file.
- **A confirmed skip no longer blocks completion.** The actionable count excluded the container
  mode's residue but not the matches a user declined at Phase 4, so a deliberate "skip this"
  re-entered Outcome B on every re-sweep and the only exits were rewriting a known false positive
  or aborting — the same non-terminating loop the residue rule closes, reached through the other
  door. The allowlist change above made it routine rather than rare by demoting Forms 4–12 to
  per-match prompts. Skips are now recorded by occurrence span, subtracted from the count, scoped
  to the sweep that asked, and reported on their own hand-off line: residue was never proposed, a
  skip was proposed and declined.
- **The catalog key anchors on the JSON delimiter, not the line start.** `^\s*` reached only the
  pretty-printed shape where the key sits alone on a line — not the compact
  `plugins: { "<old>": { … } }` that the form's own motivating example uses. The anchor is now
  `(^|[{,])`: a JSON key follows a line start, an opening brace, or a comma, and nothing else.
- **Container mode's Certain rule is enforced as an allowlist over forms.** It was applied only to
  the bare-token residue, leaving Forms 8 and 12 — both Certain by default — on the auto-apply
  path: renaming a `context` plugin would rewrite the unrelated dotted key `context.timeout` and a
  `{a,context,b}` glob. Forms 1, 3 and 13–15 are the whole eligible set; every other form demotes
  to Ambiguous, reported per match rather than folded into the aggregate.
- **The survey rescans multiline matches as blocks.** Per-occurrence records were extracted by
  re-running each form's pattern against a single returned line, which reproduces nothing for
  Form 7 and Form 14's Setext alternative — so no record was emitted and the reference vanished
  between survey and triage, silently, on the two forms added because their references were being
  missed.
- **Form 14's declaration alternatives accept `id`, not only `name` and `title`.** The mode ladder
  already selects container mode on `<old>` appearing as the `name`/`id` field of a manifest, so a
  manifest identifying the container by `id` routed into the mode that suppresses bare-token
  residue while its `id` declaration stayed unmatched and excluded. The manifest/catalog condition
  on the declaration exemption is what keeps the widened key set safe — `id="$1"` is ordinary
  shell assignment syntax — so outside a manifest an `id` match takes the scope rule and the
  common-word demotion.
- **Qualified-id promotion binds to the occurrence, not the line.** "A management verb somewhere
  on the line" promoted an unrelated dotless address to Certain — `/plugin install foo@acme;
  email t@t` — undoing the demotion. A verb that governs the occurrence is already Certain under
  the management-verb alternative, so the line-level check added no recall and only laundered.
  The sole promotion signal is now structural and per-occurrence: the occurrence IS a key in an
  `enabledPlugins` / `pluginConfigs` map.
- **The mode ladder collects conflicting evidence instead of taking first-match.** Renaming the
  `/test` action while an unrelated manifest declares `name = "test"` fired the manifest rule for
  container and never inspected the `/test` invocations — container mode then suppressed exactly
  the actionable bare references and the rename falsely completed. Only the explicit override
  short-circuits; the filesystem, manifest and invocation rules are now collected in full and
  compared, and disagreement routes to the ask rather than to the earliest rule.
- **A raw `rg` fallback needs `--hidden`.** Container manifests live in dot-directories
  (`.claude-plugin/`), which bare `rg` skips — so the two alternatives above would return zero on
  exactly the files they exist to reach. The Grep tool and `git grep` need no flag; the
  cross-platform note now says so.
- **`--container` / `--identifier` are registered.** The Phase 0b ladder advertised them as the
  correction mechanism when evidence picks the wrong mode, but they appeared in no flag contract,
  and unknown flags are rejected — so the documented override could not be honored.
- **Forms 13 and 15 no longer match inside a hyphenated superstring.** Container IDs are
  kebab-case, but a word boundary counts a hyphen as a boundary — so renaming `guard` matched
  `context-guard@marketplace`, and renaming `context` matched `/plugin configure context-guard`.
  On Certain-rated forms that silently auto-rewrites a DIFFERENT plugin's identifier. Both ends
  of both forms now exclude an adjacent `-`. Verified against a marketplace where 32 plugin names
  are hyphenated.
- **Span coverage collapses COEQUAL matches, not only weaker ones.** Two alternatives of the same
  form can hit one occurrence — `/plugin install <old>@marketplace` matches both of Form 13's.
  Left uncollapsed the count doubles and Phase 5 schedules two targeted Edits, the second failing
  because the first already rewrote the token. Keep one per `<old>` span, widest first, earlier
  form on a tie.
- **Eval 9 no longer contradicts the span rule it predates.** It still required deduplication by
  `(file, line)` and dropping the bare-token duplicate for the whole line — so a correct
  span-based implementation would FAIL it while the line-based behavior that can falsely declare
  completion was rewarded. Rewritten around `(file, line, start, end)`.
- **Container-rename mode has a concrete selection ladder.** The mode was defined by what is
  being renamed, but nothing said how to determine that — Phase 1 resolves only the two strings,
  so an invocation like `/rename-references re-anchor to discipline` left the mode undetermined.
  Both defaults are costly: identifier mode on a container restores the Form 2 flood, container
  mode on an identifier suppresses genuinely actionable bare references. Resolution now runs an
  evidence ladder — explicit override, then a container-shaped directory with a manifest, then
  the manifest/catalog `name` field, then namespaced-invocation shape — and **asks** when none
  fires. Inferring from the token's shape is explicitly banned (hyphenation and word-likeness are
  uncorrelated with what the thing is), and the resolved mode plus the rule that fired are
  reported so a reader can see which applied. Resolved in Phase 1 by both audit and apply, before
  anything depends on it.
- **Every site stating a changed rule now agrees.** This skill states the same contract across
  `SKILL.md`, five `context/` files, and `evals/evals.json`, so a rule changed in one place left
  the others asserting its opposite. `SKILL.md` still gated the re-sweep on `count == 0` in two
  places (the always-loaded surface — that alone would have shipped the non-terminating loop the
  `apply.md` fix was meant to close), an eval still asserted the raw count and would have failed
  against the corrected skill, `triage.md`'s bucket criteria never learned that Forms 13–15 can
  be demoted, and `audit.md` defined Certain without the scope qualifier. All reconciled.
- **`patterns.md` "Phase 6" now requires that reconciliation.** After changing a rule, grep the
  whole skill directory for the claim just changed and fix every hit, evals included — an eval
  asserting superseded behavior is worse than a stale sentence, because it fails against the
  corrected skill and reads as a regression.
- **Deduplication keys on the occurrence SPAN, not the line.** A line can carry two independent
  references — `Use <old> via /plugin install <old>@marketplace`. Collapsing by `(file, line)`
  dropped the bare one, and because Phase 5 replaces a single span at a time, the survivor was
  then reclassified as residue, excluded by container mode, and the re-sweep declared completion
  with a live stale reference still in the file. A weaker match is now suppressed only when its
  span is COVERED BY a more-specific match's span.
- **Form 13's boundary uses no look-around.** The natural way to exclude a trailing dot is a
  negative lookahead, but ripgrep's default engine — the one this skill instructs — rejects
  look-around without `-P/--pcre2`, and `patterns.md`'s own cross-platform note already bans
  lookbehinds for the same class of reason. The form now CONSUMES a terminator,
  `([^\w.@-]|$)`, the same shape Forms 4 and 5 use.
- **`--include-bare-token` no longer over-promises on Orphans.** The override table said it
  applied to all sub-modes, but Orphans sweeps only Forms 1 and 3 and so has no bare-token
  residue to surface — the flag silently returned the default result there. Scoped explicitly,
  and reported as not-applicable rather than silently ignored.
- **Both Phase 7 hand-off templates carry the residue count.** The actionable-count rule
  promised users an aggregate, but neither success template had a field for it and the default
  hand-off still said `0 stragglers` — so the fix prevented the loop while hiding the number it
  committed to. Emitted only under container-rename mode and only when non-zero.
- **Form 13's qualified-id form no longer matches email addresses.** `<old>@[\w.-]+` has no
  management verb anchoring it, so for a container named `info`/`admin`/`support` it matched
  contact addresses on a Certain-rated form — a silent auto-rewrite. A marketplace slug is
  kebab-case with no dots while an email domain carries a TLD dot, so the form now accepts
  `[\w-]` with a `(?![\w.-])` lookahead. Verified: `info@acme-tools` matches;
  `info@acmetools.com` and `info@example.co.uk` do not.

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

- **Container-rename mode (`patterns.md` Phase 0b) — the rule that actually removes the prompt
  flood.** Precedence (below) resolves only lines the container forms ALSO matched: 8 of Form 2's
  134 on the measured fixture. The other 126 are ordinary verb uses no container form touches,
  and they fall through to Form 2's Certain default. The sweep now declares a MODE at Phase 0
  from what is being renamed. For a container — a plugin, a marketplace entry, a package — the
  renamed thing is a proper name, so a bare-token occurrence is evidence of nothing; the residue
  is excluded from Certain **regardless of blocklist membership** and reported as one aggregate
  count, surfaced only behind an explicit widen and then as Ambiguous. Mode is a property of what
  is being renamed, which is why it works where the static blocklist cannot: it does not depend
  on anyone having listed the token in advance. Fixture result with mode + precedence: 8 Certain
  findings, 126 reported-not-proposed, 0 confirmation prompts.

- **Form 14 is scoped to container-owned documents.** "A heading that IS the token can only be
  naming it" holds for a coined or hyphenated name and FAILS for an ordinary-word one — verified
  against this repository: renaming a `testing` plugin matches `README.md:86` (`### Testing`, a
  marketplace category heading) and renaming `architecture` matches `plugins/miro/README.md:39`
  (`## Architecture`, an unrelated design section). Under precedence a false Certain there is
  worse than a plain Form 2 hit, because it discards the safer classification. A title match is
  Certain only in plausibly container-owned files, and always Ambiguous when the token is a
  common English word.

- **Container-position precedence, without which the new forms only ADD hits.** Forms 13–15 are
  strictly more specific than Form 2 — every line they match, Form 2 matches too. The sweep now
  deduplicates by `(file, line)` after collecting and before triage: a container-position match
  takes the Certain path and its bare-token duplicate for that line is dropped as the same
  reference seen through a weaker lens, not a second finding. Only lines the container forms did
  NOT match fall through to Form 2's blocklist rule. The audit report carries the superseded
  count so the suppression is visible rather than inferred. This is what makes position an actual
  remedy for the verb collision instead of an additional lens over an unchanged prompt flood.

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
- **`audit.md`'s pattern-form breakdown** lists Forms 13–15 and the superseded-hit count, and its
  Survey phase applies the precedence dedup before triage runs.
- **Form 14 accepts single-quoted YAML** (`name: '<old>'`) alongside bare and double-quoted
  values, with the quotes required to PAIR — a naive `["']?` would match the invalid `"<old>'`.
- **Form 15 allows the token to be inline code** before the possessive clitic, which in markdown
  is the common case rather than the exception: the literal `<old>'s` sequence never appears when
  the token is a code span, so without this the form missed its own motivating example.

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
