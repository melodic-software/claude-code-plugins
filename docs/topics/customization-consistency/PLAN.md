# Customization consistency — consolidation of config, persistence, and setup conventions

## Brief

### TLDR

Unify how plugins express consumer-facing configuration: natural-language convention docs with
progressive disclosure (pointers from AGENTS.md/CLAUDE.md) replace dedicated config files where the
content is prose-expressible; a shared retired-convention detection/cleanup mechanism (folded into
the existing setup check/apply contract) replaces the eight bespoke migration implementations; and
four of the twelve verified cross-plugin drift classes get fixed (the rest are explicitly out of
scope below). Grounded in the full-fleet inventory at
`.work/customization-consistency-inventory/INVENTORY.md` (memory tier; regenerate via
`/discovery:explore` if absent).

### Goal

1. **Phase 1 — drift fixes** (no doctrine change): converge the recommended gitignore line on
   config-cascade's recursive form; codify drop-`apply` for nothing-to-write setups and fix the
   no-op-apply holdouts; converge tracked-file verification depth (check-ignore + ls-files); move
   the duplicated ~120-word setup paragraph to a single owned source.
2. **Phase 2 — doctrine amendment + migration**:
   - Amend `docs/conventions/config-cascade/`, `docs/PLUGIN-PHILOSOPHY.md`,
     `docs/MIGRATION-PLAYBOOK.md`; record the doctrine amendment in one ADR.
   - New expression doctrine: consumer conventions live as **natural-language docs at the
     consumer's convention home** (e.g. `docs/conventions/<topic>/`), discovered once at setup.
     AGENTS.md (or CLAUDE.md) carries only content needed in effectively every conversation plus a
     single standing index/pointer line; that pointer line **is** the persisted convention-home
     binding (no separate binding file). Structured data (yaml/json) stays structured where it is
     the right tool; policy-floor config and all mutable state keep dedicated files.
   - Root-file shape: downstream repo's choice, setup discovers and guides once; recommended
     guidance is AGENTS.md-canonical with a pure `@AGENTS.md` CLAUDE.md shim (generalizes
     instruction-placement's existing shape), never forced.
   - Convention-resolution ladder amendment: convention doc → infer house style from repo evidence
     → ask → plugin default, with gated infer-and-persist so discovery happens once.
   - Shared retired-convention mechanism (**decided 2026-09-01**, unanimous blind-validator
     ranking + user approval; full record in
     `.work/customization-consistency/mechanism-candidates/VALIDATION.md`): the approved hybrid —
     per-plugin append-only `retirements.yaml` (CI schema-validated) + one shared deterministic
     `lib/check-retirements.sh` synced byte-identical via the existing state-key.sh
     sync-and-registry mechanism; detection as one fixed step in setup `check`, per-item gated
     cleanup in `apply`, model carries judgment-bearing migrate content. Plus: one eval case per
     retirement record (detect-hit + clean path); a runtime fleet-sweep lane in claude-config's
     audit-pass globbing installed plugins' `retirements.yaml` (covers setup-never-re-run);
     archived/report-only demotion for old records. Deferred until proven needed: CI-aggregated
     fleet registry (uninstalled-plugin orphan coverage).

### Constraints

- Amendments to existing owner docs, never a parallel second way (config-cascade conformance table
  must be updated in the same change as any surface it describes).
- Consumer repos vary (docs folder name/layout, existing conventions): every placement is
  discovered or asked once at setup and persisted; nothing hardcodes `docs/conventions/`.
- Convention prose parsed from consumer repos is untrusted input (education:teach precedent).
- No new setup verb: migration lives inside check/apply. Setups with nothing to write are
  check-only (no no-op apply).
- The retired-convention registry (whatever shape wins) ships inside plugins, never in consumer
  repos.
- Per-surface migration calls apply the locked criterion — amended 2026-09-01 at plan approval
  (DA C2, user-approved): TEAM-SHARED prose config → convention doc; per-operator-keyed
  surfaces, structured data, policy-floor config, and all state STAY files. They are Phase 2
  execution decisions per plugin PR, not pre-enumerated here.

### Acceptance criteria

- Phase 1: zero remaining occurrences of the narrow gitignore recommendation forms; zero no-op
  `apply` actions; all tracked-file setups verify with check-ignore + ls-files; the shared setup
  paragraph has exactly one owning source.
- Phase 2: the three owner docs + ADR land before any surface migrates; a migrated surface's old
  file is detected by its plugin's setup `check` and cleaned by gated `apply`; skills resolve the
  convention home from the AGENTS.md pointer line and fall back down the ladder when absent.
- Execution contract (bulk work): one PR per drift-fix class (Phase 1); Phase 2: one doctrine PR,
  one mechanism PR, one conversion PR per bespoke-migration plugin, then one PR per migrated
  surface. Per-unit loop: edit → `skill-quality:check` (and toolchain checks) → close.

### Captured assumptions

- INVENTORY.md's counts (51 setup skills, 12 inconsistencies, 8 bespoke migrations, ~20 config
  surfaces) are accurate as of 2026-08-31.
- instruction-placement's AGENTS.md + shim machinery is reusable as the guidance shape.

### Out of scope

- Config/state mixture cleanups ranked in INVENTORY §3 (records.json, rules-index block, etc.) —
  separate effort.
- The undocumented seventh persistence tier (forge state) — needs its own convention doc, separate
  effort.
- PD keying convergence (INVENTORY §6 item 8) — candidate for a later drift-fix class.
- Remaining INVENTORY §6 drift items not covered by the four Phase 1 classes: item 1 (gitignore
  posture split), 6 (install subaction naming), 7 (per-surface cascade semantics), 9 (config file
  location outliers), 10 (github setup frontmatter), 11 (operator-decision durability), 12
  (ai-briefing phantom overlay) — file as follow-up work items at Phase 1 close.
- Third-party plugins (caveman, codex).

### Deferred questions

- Q9 | Retired-conventions mechanism implementation | arbiter: USER-RESERVED — RESOLVED
  2026-09-01: hybrid on Candidate B approved by user after unanimous blind-validator ranking (see
  Goal, Phase 2, and `.work/customization-consistency/mechanism-candidates/VALIDATION.md`).

## Plan

Design inputs: `design/design-resolution.md` (tournament outcome),
`.work/customization-consistency/mechanism-candidates/candidate-b.md` (mechanism spec),
`VALIDATION.md` (hybrid amendments). Standards grounding: the three owner docs
(config-cascade, PLUGIN-PHILOSOPHY, MIGRATION-PLAYBOOK) are themselves the governing standards
for every phase and were read during discovery; no separate `.claude/standards.yaml` index exists
in this repo.

Program shape: this topic spans multiple PRs. PLAN.md + topic slice ride a
`chore/customization-consistency` branch; each phase gets its own PR branch off `main`, and this
file's phase tags advance as phase PRs merge.

### Phase 1a: Gitignore-line convergence [DOING]

Converge every setup skill's recommended consumer gitignore line on config-cascade's mandated
recursive form (`.claude/**/*.local.*`). Edit the setups INVENTORY §6.2 names: codebase-health,
mutation-testing, toolchain, ai-briefing, and source-control's appended line; sweep all 51 setups
for stragglers (`grep -rn "\.local\." plugins/*/skills/setup/`), fixing narrow/bespoke spellings.
Owner-doc side: config-cascade's closing section already mandates the form — cite it from each
setup instead of restating where the setup text allows. Known narrow spellings to catch:
`.claude/<name>.local.*` forms, toolchain's `.claude/ecosystems/*.local.*`, ai-briefing's
`.claude/ai-briefing/**/*.local.*`, source-control's appended line. Legitimate survivors (never
"fix"): overlay-file path names in prose (`.claude/ai-slop.local.json` etc.), native
`.claude/settings.local.json` references, claude-config's quote of the narrow form as a negative
example.

**Sanity Check:** first work item builds the class list — enumerate every setup file containing a
gitignore-recommendation context (`grep -rln "gitignore" plugins/*/skills/setup/`) into the PR
body as a checkbox inventory; after the fix, every file on that list recommends only the
recursive form (`grep -l '\.claude/\*\*/\*\.local\.\*'` matches each), and a repo-wide grep for
each known narrow spelling above inside a recommendation context returns only the documented
negative-example lines (enumerated in the PR body).

### Phase 1b: Drop no-op apply [DOING]

Conformance fix to EXISTING doctrine — PLUGIN-PHILOSOPHY already states the "Check-only
carve-out" (line ~469: no `apply` where there is nothing it could conformingly write). No owner-doc
edit in this phase. Remove the no-op `apply` actions from the holdouts (INVENTORY §6.3:
claude-ops, skill-quality, context-budget, repo-hygiene, session-flow), citing the carve-out, and
normalize their check output text.

**Sanity Check:** for each of the five named holdout setup SKILL.md files, no `apply` action
section remains (`grep -n "^### .*apply\|action: apply" plugins/<p>/skills/setup/SKILL.md` empty
per holdout) and each cites the check-only carve-out
(`grep -l "[Cc]heck-only carve-out" <the five files>` returns all five).

### Phase 1c: Tracked-file verification depth [DOING]

Bring every setup that writes tracked consumer files up to the full verification pair
(`git check-ignore` AND `git ls-files`) that bugs/improvement/mutation-testing already use.
Fix INVENTORY §6.4 names: code-tidying, codebase-health, toolchain, repo-fleet-hygiene; sweep the
rest of the 51 for the same gap. Class definition matters: only setups that WRITE tracked
consumer files owe the pair; setups using check-ignore solely to verify an overlay IS ignored are
correct without ls-files and are excluded.

**Sanity Check:** first work item enumerates the tracked-file-writing setups into the PR body as
a checkbox inventory (with exclusions listed + one-line reason each); after the fix, every file
on that inventory contains both `check-ignore` and `ls-files`
(`grep -rln "check-ignore" plugins/*/skills/setup/ --include='*.md' | xargs -r grep -L "ls-files"`
returns only the documented exclusions; evals fixtures excluded from the sweep).

### Phase 1d: Setup-prose SSOT [DOING]

Move the ~120-word `--config`/CC-version setup paragraph (duplicated with drift across ~25
skills, INVENTORY §6.5) to one owned source — PINNED (DA M2): a NEW spoke under
`docs/conventions/` (not an existing owner doc, which would void Phase 1 ∥ 2a disjointness) —
and replace each copy with the canonical short form + citation. 1d carries no forward
references; Phase 2b later ADDS the conditional detection-step sentence + retired-conventions
citation to that spoke (one-file edit — the point of the seam).

**Sanity Check:** baseline first work item records the current count
(`grep -rln "2\.1\.240" plugins/*/skills/setup/SKILL.md | wc -l` — 28 at plan time); after the
fix that same grep returns 0 in setup SKILL.md bodies (the marker survives only in the single
owning source), and the owning source is cited by every replacement
(`grep -rln '<owner doc path>' plugins/*/skills/setup/ | wc -l` equals the baseline count ±
documented exceptions listed in the PR body).

### Phase 2a: Doctrine PR [DOING]

Amend the three owner docs + ADR (Brief § Goal 2). config-cascade: new expression doctrine
section (natural-language convention docs at the consumer's discovered convention home;
AGENTS.md/CLAUDE.md carry only every-conversation content + the single index/pointer line, which
IS the persisted binding; structured data stays structured; policy-floor + state keep files);
root-file guidance (AGENTS.md-canonical, pure `@AGENTS.md` shim, downstream's call);
MIGRATION-PLAYBOOK: convention-resolution ladder amendment (convention doc → infer house style →
ask → default, gated infer-and-persist) + retired-conventions mechanism seam; PLUGIN-PHILOSOPHY:
ownership-table row + drop-apply rule (ratifies 1b) + retirement-declaration requirement. One ADR
records the doctrine amendment (hard to reverse, surprising, real trade-off — tournament record
cited). Update config-cascade's conformance table in the same PR.

Stress-test-mandated doctrine content (must be in the 2a text, not discovered mid-2d):

- **Dual-read deprecation window (DA C1):** a migrated skill that finds the retired path present
  treats it as WARN + reads it as authority (or at minimum inference evidence) until cleaned —
  covers consumers who update plugins without re-running setup, including the PowerShell-only ×
  never-re-run intersection (DA H4). Window end condition stated in the ADR.
- **Cascade layering story for convention docs (DA C2):** RESOLVED 2026-09-01 (user-approved,
  option b): per-operator-keyed surfaces stay files; only team-shared prose config migrates.
  2a's doctrine text states this criterion amendment; a migrated (team-shared) surface has no
  overlay channel, and setup `check` WARNs on any pre-existing overlay file rather than
  silently ignoring it.
- **Pointer-line robustness (DA H2/M4/M5):** the pointer line lives in a marked machine-owned
  region (rules-index-block precedent); both-files (AGENTS.md + CLAUDE.md) precedence and
  duplicate handling defined; resolver treats "pointer absent but previously-known home exists"
  and "pointer target directory missing" as ask-don't-infer FAIL, never silent rebind; binding
  is branch-scoped content (divergent branches may re-ask).

**Sanity Check:** `ls docs/adr/ | grep -i "convention"` hits the new ADR;
`grep -n "convention home\|@AGENTS.md" docs/conventions/config-cascade/README.md` hits, and
`grep -n "retirements\.yaml" docs/MIGRATION-PLAYBOOK.md docs/PLUGIN-PHILOSOPHY.md` hits in both
(distinctive new marker; the bare word "retire" pre-exists in both docs).

### Phase 2b: Mechanism PR [DOING]

Implement the approved hybrid per the committed spec (`design/mechanism-spec.md` +
`design/mechanism-validation.md` — graduated from .work, now the normative contract):

1. `retirements.yaml` schema (append-only records: id/retired/plugin_version/kind/path/match/
   content_match/action/successor/note + demotion field) — validation wired into the
   `scripts/validate-plugin-contracts.mjs` walk (it takes no manifest argument; extend
   `scripts/validate-plugin-contracts.test.sh` with retirement-manifest fixtures, valid +
   malformed).
2. `check-retirements.sh` — detection TSV, exit 0/1/2, `--clean <id>`, `--i-migrated`;
   `.test.sh` coverage. Canonical home pinned per the state-key precedent:
   `plugins/claude-config/lib/check-retirements.sh`, synced byte-identical into consuming
   plugins via `scripts/cross-plugin-source-registry.txt` + a sync script. Contract hardening
   (DA H3/M3/L2): line-kind matching strips `\r` (or `\r?$`) with CRLF test fixtures; Windows
   lock failure during `--clean` = exit 2 + documented re-run, never partial-silent; the two
   fixed setup lines are CONDITIONAL ("when the plugin ships retirements.yaml" — exit 2 on a
   missing manifest stays loud for manifest-shipping plugins only); validator enumerates the
   legal edits to an append-only record (demotion flip, defect fix) so append-only is
   machine-checked.
3. Owner doc `docs/conventions/retired-conventions/README.md` + convention-registry row — the
   canonical home of the two fixed setup lines (per mechanism-spec; the Phase 1d paragraph CITES
   this doc, it does not own the mechanism text).
4. Setup-contract wiring: fixed detection step lands via the Phase 1d owned paragraph citing the
   owner doc; CI check that a plugin with a manifest invokes the helper (bidirectional).
5. Runtime fleet-sweep lane in claude-config audit-pass globbing installed plugins'
   `retirements.yaml` (no generator, no committed aggregate); repeated-decline routes through
   the existing finding-suppression convention (per mechanism-spec).
6. Eval-case requirement: one eval per retirement record (detect-hit + clean path) — validator
   FAILURE, not warning (per mechanism-validation hybrid item 2).
7. AGENTS.md pointer-line grammar: small tested helper (resolve-convention-home), landed here —
   not improvised in the 2d pilot — honoring the untrusted-input constraint.

Pre-flight consumer check (first work item): grep for anything already parsing
`retirements.yaml`/`check-retirements` names (expected zero — new contract; verified zero at
plan time).

**Sanity Check:** `bash plugins/claude-config/lib/check-retirements.sh --help` exits 0; its
`.test.sh` exits 0; `bash scripts/validate-plugin-contracts.test.sh` exits 0 with the new
fixtures present (and fails when the malformed fixture is marked expected-pass); registry row
present (`grep check-retirements scripts/cross-plugin-source-registry.txt`); owner doc exists
(`test -f docs/conventions/retired-conventions/README.md`).

### Phase 2c: Bespoke-migration conversion PRs [DOING]

Honest scope (DA H1): most of the 8 bespoke migrations are NOT expressible in the approved
schema — context-guard/rate-limit-guard target machine-scope (`~/.claude/...`) surfaces,
machine-health probes a legacy home-dir root, work-items' are forge-label backfills, guardrails
is provisioning, planning/review are version-delta. The clean historical conversion is
source-control's SSOT retirement; the mechanism's value rests on 2d + future retirements.
Work items: (a) convert source-control; (b) record one-line stays-bespoke rationale in each
excluded skill; (c) dedupe the context-guard/rate-limit-guard twin detection via the existing
sync-registry (kills their documented prose drift without forcing them into the schema);
(d) RESOLVED 2026-09-01 (user-approved, option b): no `scope` field — the schema stays
repo-only and the 2a ADR records the machine-scope exclusion; the twins' drift fix is item (c).

**Sanity Check:** per converted plugin, `retirements.yaml` validates in CI and the old bespoke
detection prose is deleted (`grep -n "shim-revision\|legacy" <plugin setup>` only in the
rationale line or gone); per skipped plugin, the rationale line exists.

### Phase 2d: Surface-migration PRs [TODO]

Apply the amended criterion per surface (TEAM-SHARED prose config → consumer convention doc +
AGENTS.md pointer discipline; per-operator-keyed / structured / policy-floor / state stays).
Consequence of the D1 decision: `testing` e2e is per-operator-keyed and STAYS a file — it drops
out of 2d entirely. Pilot: `plugin-quality` (`.claude/plugin-quality.md`, team-shared repo-map
prose, single reading plugin → consumer convention doc, retirement record added, setup discovers
convention home per doctrine). After pilot verified in a real consumer repo: evaluate the next
candidates one PR each (codebase-health.md, improvement.md, tidy-lanes; topic-docs.yaml is
structured and stays) — each PR makes its own keep/migrate call against the amended criterion
and records it in the PR body.

Pre-flight consumer check (FIRST work item of EVERY 2d surface PR): repo-wide grep for the old
path across ALL plugins, docs, tests, and workflows — config-cascade's conformance table
describes every surface (Brief constraint: table updates in the same change); enumerate every
hit in the PR body.

Pilot hardening (DA M1 — the pilot must sample the risks it licenses): the test consumer repo
has a POPULATED pre-existing AGENTS.md, a pre-existing `.claude/plugin-quality.local.md` overlay
file (check must WARN on it per the D1 decision, never silently ignore), and the verification
includes an update-without-re-setup simulation (new plugin version active, setup not re-run →
dual-read window must carry the old values, WARN visible). Rich-prose surfaces (tidy-lanes
per-section merge, codebase-health empty-list opt-out) are a SECOND pilot tier, not ordinary
post-pilot serial work.

**Sanity Check (pilot):** in that consumer repo, `/plugin-quality:setup check` reports the
retired file when present; `apply` migrates the team content into the convention doc, writes/uses
the AGENTS.md pointer line (via the 2b resolve-convention-home helper), deletes the old file,
and WARNs on the leftover overlay; re-run `check` is clean except the overlay WARN; the
update-without-re-setup sim shows old values still honored + WARN; REPO-WIDE old-path grep
(`grep -rn "\.claude/plugin-quality\.md" .` across the marketplace repo) returns only
retirement-record, conformance-table, and negative-example references, each enumerated in the
PR body.

## Blast radius

HIGH — new enforcement/convention mechanism constraining all future plugin work, CI machinery,
~30+ files across 25+ plugins in Phase 1 alone. Mitigations: docs/skills are git-revertable, no
consumer-repo runtime breakage until Phase 2d, phased PRs each revertable along one axis, the
mechanism design already survived a 3-candidate/3-blind-validator tournament.

## Stress-test summary

Two-stage. (1) Fresh-context plan reviewer: 13 findings (3 CRITICAL — broken 1a/1d sanity
greps, mechanism spec stranded in gitignored .work; 5 IMPORTANT; 5 SUGGESTION), all verified
and applied. (2) Devils-advocate: 2 CRITICAL / 4 HIGH / 5 MEDIUM / 3 LOW, all repo-verified;
applied as doctrine additions (dual-read window, pointer-line robustness rules), 2b contract
hardening (CRLF, locks, conditional invocation, append-only enumeration), honest 2c rescope,
pilot hardening, 1d pinning. Two findings escalate to user decisions (Open questions). Accepted
residuals recorded: eval-gate may discourage declarations (DA L1, watch), four Phase-1 release
waves over the same files (DA L3), uninstalled-plugin orphans deferred (consciously, per Q9
hybrid). Assumptions that survived attack: INVENTORY ground truth, sync-registry precedent,
jq-free flat-YAML choice, untrusted-prose posture, phased-PR blast containment.

## Execution shape

Sequential within Phase 1 (1a→1d: the four classes overlap on the same ~25–51 setup SKILL.md
files; parallel editing risks concurrent-edit races). Phase 2: 2a → 2b (doctrine before
mechanism; 1d gates 2b's wiring) → then 2c PRs parallel-safe (disjoint plugin dirs, fan-out
sub-agents allowed, scope-fenced per plugin) and 2d pilot-then-serial. Phase 1 may run in
parallel with 2a (disjoint: setups vs owner docs; 1b/1d touch PLUGIN-PHILOSOPHY-adjacent text —
2a lands the ratifying prose, so land 1b text as behavior-only and let 2a own doctrine wording).

| Phase | Surface | Basis |
|---|---|---|
| 1a–1d | main session or single worker each | judgment-light sweeps; same-file overlap forbids fan-out inside a class |
| 2a | main session | doctrine wording, high judgment |
| 2b | main session (scripts+tests), worker for fixtures | new contract, test-driven |
| 2c | fan-out sub-agents, one per plugin | disjoint dirs, mechanical conversion |
| 2d | main session per surface | per-surface keep/migrate judgment |

Sequential fallback: any scope-fence violation or race → collapse to sequential per-class order
above.

## Open questions

None. The two DA escalations were decided at plan approval (2026-09-01, user chose the
recommended option for both):

1. **Cascade layering (DA C2) → option b:** per-operator-keyed surfaces stay files; only
   team-shared prose config migrates. Criterion amended in Constraints; pilot switched from
   testing e2e (per-operator) to plugin-quality (team-shared).
2. **Machine-scope schema field (DA H1) → option b:** schema stays repo-only; the 2a ADR
   records the machine-scope exclusion; context-guard/rate-limit-guard twin drift is fixed via
   the sync-registry dedup (2c item c).

## Handoff to implementation

### User-approval gates

- Phase 2d: each post-pilot surface migration's keep/migrate call is surfaced in its PR, and the
  pilot's consumer-repo verification result is shown before further surfaces migrate.
- Any mid-flight change to the approved mechanism contract (schema fields, helper exit codes)
  re-opens Q9 — stop and ask.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Phase-1 classes sequential; 2c fan-out per plugin; ordering 2a→2b→2c/2d.
- [EXEC-SHAPE] Phase 1d's owned paragraph is also 2b's wiring point (one seam, two phases).
- [FALLBACK — confirm or override] If the pilot (testing e2e) fails consumer-repo verification,
  halt 2d, keep remaining surfaces as files, and record the outcome in the ADR as a bounded
  experiment rather than rolling doctrine back wholesale.

### Mechanical work

Commit per phase-PR; `skill-quality:check` + repo lint (markdownlint, editorconfig-checker,
shellcheck for the helper) on every touched skill; PLAN.md phase tags advance per merged PR;
scope-change notes dated in this file.
