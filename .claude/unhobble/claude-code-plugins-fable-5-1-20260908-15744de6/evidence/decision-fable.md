# Unhobble decisions (agent: Fable, independent)

Experiment `claude-code-plugins-fable-5-1-20260908-15744de6`, branch `claude/unhobble-config-oe7yfx`,
HEAD c41c6422. Default strip plan in the manifest is accepted as-is except where D4 flags it.
Evidence tags: D1/D2/D3 = memo finding numbers; repo paths are relative to `<worktree>`.

## D1. User-scope opt-in

**VERDICT:** Do not opt user scope in. The project-scope `enabledPlugins: false` overlay IS a
contract-consistent Phase 2 mechanism, but this run disables zero plugins through it: all 20
hook-wiring plugins classify as keep, and the 53 skill-only plugins need a classification pass first.

**CONFIDENCE:** high on "do not opt in" and on the 20-plugin classification; medium on whether a project
`false` would even take effect in-cloud (rests on D1 Unverified #1 plus a bootstrap gap found below).

**EVIDENCE**

- The in-container `~/.claude/settings.json` is environment-synthesized, not a human's standing
  instructions: D1 §3 (cloud-environments "fresh VM", "user-scoped enabledPlugins ... not read"),
  D1 §4 (`docs/CLOUD-SESSIONS.md` ~372-388; `.claude/cloud-bootstrap.sh` 205-210). Ablating it measures
  provisioning, not instructions, and edits there do not survive reclaim (D3 §1.3-1.4, U1/U2).
- Project `false` is documented per-project opt-out: D1 §2 (plugins-reference "Synced plugins";
  "`enabledPlugins` still honors project and local settings"). The catalog gate passes an explicit `false`
  (`scripts/check-plugin-catalog-enablement.sh` header: "A key set to `false` PASSES"; keys must stay byte-sorted).
  This is exactly the contract's Phase 2 "disable the ones classified behavioral for this project"
  (SKILL.md Phase 2, plugins bullet), so it stays inside project scope.
- Gap that caps confidence: the bootstrap's overlay only drives INSTALLS (`cloud-bootstrap.sh` ~236-241,
  `select(.value == true)`); the snapshot has already installed and enabled all 73 at user scope, and the
  only uninstall path (~340-360) is the same-version refresh. So a project `false` on a fleet-enabled
  plugin leaves user `true` in place and relies on Claude Code precedence (project over user), which no
  doc states for this exact pair (D1 Unverified #1). Registry is built at process start and not re-read
  (`docs/CLOUD-SESSIONS.md` 287), so any effect lands in the next session only (D1 Unverified #3).
- Classification of the 20 hook plugins, from `plugins/<name>/hooks/hooks.json` + hook headers, against
  `docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook" (782-815):
  - policy / keep whole: `guardrails` (secret-pattern, hardcoded-path, block-no-verify, block-dangerous-git
    = secret-handling / irreversible-action; cli-flag-verify, skill-reference-verify, stale-path-verify are
    the rubric's named ground-truth-oracle keeps), `source-control` (pr-body-linkage-gate, worktree gates),
    `disk-hygiene` (destructive_guard = irreversible-action), `context-budget` (settings_write_ask =
    agent-authority), `instruction-placement` (index-drift: machine oracle; manifest already depends on it
    staying green), `actionlint` (relays measured linter findings = policy per rubric example).
  - notification/infra, no model payload / keep: `claude-ops` (audit emitters, event log; default off),
    `desktop-notification`, `rate-limit-guard`, `session-flow` (observer-arm; default off),
    `autonomy` (lane-stop-gate; default OFF, honored from user/managed settings only, so inert here).
  - deterministic-transform tooling / keep (operator's formatter carve-out): `bash-format`, `biome-format`,
    `go-format`, `markdown-format`, `powershell-format`, `ruff-format`, `typos-format`, `eol-normalizer`.
  - hybrid / keep whole, record `unstripped-hybrid-hook`: `context-guard`. zone-crossing-inject carries a
    measured zone (oracle) plus an inline counter-steer prose payload into model context
    (`hooks/zone-crossing-inject.sh` header lines 5-20 = behavioral surface); zone-gate is advisory-inert
    by default. Its only kill switch `context_guard_hooks_enabled` is a master switch for all three hooks
    and lives in `pluginConfigs`, which project settings cannot set (D1 §2), so no project-scope partial strip exists.
- 53 skill-only plugins: neither memo classifies them; descriptions load per turn (D1 §2, skills page) but
  bodies only on invocation, and `skillListingBudgetFraction: 0.05` already caps the listing. Per the task
  rule, no strip without a classification pass. Note `claude-config` must stay enabled regardless: it hosts
  `/claude-config:unhobble` for Phases 3-4. Candidates the pass should look at first, on their own
  descriptions: `discipline`, `playbooks`, `adhd`, `education` (pure coaching / doctrine); not stripped now.

**WHAT WOULD CHANGE THIS VERDICT**

1. A doc sentence or an in-cloud `claude plugin list --json` reading in a fresh session proving project
   `false` beats user `true` for a snapshot-installed plugin; then option C becomes operable and the
   classification pass can strip skill-only behavioral plugins.
2. The operator declaring the cloud-synthesized user file in scope as an environment surface (a different
   experiment than the contract's; would need its own manifest entries).

**PHASE 2 MECHANICAL STEPS (D1)**

1. Add to `manifest.json` a `user_scope_plugins` block: per-plugin `class` and `action: keep` for the 20
   above, `context-guard` with `unstripped-hybrid-hook`, and the 53 skill-only ids as
   `classification: pending`. No edit to `.claude/settings.json#enabledPlugins` this run.
2. In the first bare session, run `claude plugin list --json` and `/context`; append the loaded set to the
   manifest as `bare_session_loaded` (D1 option F) so the observe phase knows its confounds.

## D2. The four convention units

**VERDICT:** Strip (a) "Validate a change" and (c) `pr-body-contract.md`; keep (b) "Open a PR as a draft"
and (d) `ruff-pin.md`.

**CONFIDENCE:** high for (a) and (d); medium for (b) and (c) (Gate 0 class contested, D2 Unverified #1).

**EVIDENCE**

- The consensus row is the cut test with no exception (D2 consensus table rows 1, 3): the "conventions are
  exempt" reading is repo-only and the repo's own `criteria.md` 1887 concedes it appears on no official
  page. So the experiment, not the class label, decides; strip where a live oracle catches the miss and
  keep where the miss is silent or matches a keep rubric.
- (a) strip: gating oracle `scripts/affected-tests.sh` runs in `ci.yml` `test-linux` under `ci-status`
  (D2 §4a); the script fails loud on a zero-suite mapping itself; README "Validate a change" owns the
  contract. Gate 0: none. Suppressed only while the PR is a draft, which the flip-to-ready resolves.
- (c) strip: four surviving oracles: the user-scope `source-control` hook
  `plugins/source-control/hooks/pr-body-linkage-gate.sh` blocks a bare `gh pr create` whose body misses
  the keyword or any of the four sections (header lines 12-25); `.claude/source-control.md`
  `pr_body_required_sections`; the `/source-control:pull-request` pre-create gate; and the CI composite's
  advisory comment + label (D2 §4c). Gate 0 contested-weak (D2 §3.5); handled at Phase 4 below.
- (b) keep: no oracle of any kind (D2 §4b: no CI job, no hook, no skill default); a miss is silent spend
  on the test and two AI-review lanes; `external-publication` names "opening PRs" literally
  (`plugins/instruction-placement/context/routing-rubric.md` 38). Thin evidence, so prefer the reversible,
  contract-intact default (kept).
- (d) keep: non-derivable ground-truth carve-out (`docs/PLUGIN-PHILOSOPHY.md` 801-805, D2 §3.3): a bare
  `ruff` returns a clean-looking wrong answer; `scripts/run-ruff.sh` exits 2/127 only when invoked; CI lint
  is one subtree and fail-open (D2 §4d). Path-scoped to `**/*.py`, so its context cost is near zero and a
  strip measures little.
- Phase 4 for (c): restore on two same-cause ledger rows as usual; if the readd pass affirms
  `external-publication` for it, restore as a register hold instead (register README line 56), never left
  deleted on silence. Always-loaded count after this plan: 50 - 6 - 25 = 19 lines.

**WHAT WOULD CHANGE THIS VERDICT**

1. A stated adjudication (rubric or register) that reversible publication-cost rules are inside
   `external-publication`: then (c) is stripped only under a pre-declared register hold, and (b) may be
   stripped under the same hold (D2 option 5).
2. Evidence the `source-control` hook is not loaded in the bare session (D1 confound reading): (c) then
   loses its in-session oracle and should stay kept.

## D3. Where the state lives

**VERDICT:** Canonical location stays the plugin data dir per the contract; a durable mirror of
`manifest.json` and `stumbles.md` is committed on the experiment branch at
`docs/topics/unhobble-fable-5-1/`, synced each session; `backups/` never leaves the plugin data dir.

**CONFIDENCE:** high that hand-carry alone is unsafe; medium-high on the path choice.

**EVIDENCE**

- The state must outlive the VM and the observe phase is days of sessions (SKILL.md Phase 3). Data dir is
  lost at reclaim: D3 §1.1-1.4 (fresh VM, only conversation history restored, cache is the setup-script
  snapshot), repo-normative matrix D3 §3.2 (`${CLAUDE_PLUGIN_DATA}` "invisible" to a cloud clone), sibling
  precedent D3 §3.4 ("reclaimed container ... kept — it is tracked"). Only U1 is inference; a sentinel
  under `~/.claude/plugins/data/` in the next session settles it.
- `docs/topics/<slug>/` is the named contract tier: "committed on the task branch only; pruned before
  merge" (`docs/conventions/topic-docs/README.md` 65, 656-679); sole entry in `scripts/docs-only-paths.txt`;
  not gitignored (D3 §5.5); outside the changelog-parity arms `plugins/*/*` and
  `docs/conventions/*/CHANGELOG.md` (`scripts/check-changelog-parity.sh` 480, 484), so no version bump per
  ledger write (D3 §5.2). Committing is unaddressed, not forbidden, by the contract (D3 §4).
- Frictions: F1 absolute worktree path vs the machine-specific-paths gate (`ci.yml` 486-507, exclude list is
  hand-maintained); F2 `backups/` vs gitleaks; F3 Phase 2 already commits to the branch. A fourth found here:
  `scripts/check-contract-slice-prune.sh --check-diff` (`ci.yml` 982) red-lines any PR whose diff adds a
  path under `docs/topics/` until the prune commit. That is the convention's designed state and is the
  gate guaranteeing run state never reaches `main`.
- F2 dissolves for this run: no non-tracked file is modified (settings hooks kept, no `enabledPlugins`
  edit per D1), so `backups/` is empty; the data dir currently holds `backups/`, `manifest.json`, `stumbles.md`.

**WHAT WOULD CHANGE THIS VERDICT**

1. The sentinel survives into the next session (U1 false): the mirror becomes optional insurance.
2. A later phase must edit an untracked settings file: `backups/` then stays data-dir-only and the
   manifest records the backup as non-durable (operator hand-carry for that one artifact).

**PHASE 2 MECHANICAL STEPS (D3)**

1. `mkdir -p docs/topics/unhobble-fable-5-1/`; copy `manifest.json` and `stumbles.md` there. In the committed
   copy drop `checkout.worktree_path` (keep `origin_url`, `branch`, `base_commit`); add
   `state_location: {canonical: "${CLAUDE_PLUGIN_DATA}/unhobble/<id>/", durable_mirror:
   "docs/topics/unhobble-fable-5-1/", deviation: "committed copy omits the absolute worktree path;
   sync re-derives it"}` to both copies. Ensure final newline and a valid table for markdownlint/editorconfig;
   typos will spell-check ledger prose.
2. Commit separately from the strip commit: `experiment: carry unhobble state on the branch`. Push.
3. Session-start sync (every fresh session): `mkdir -p "$CLAUDE_PLUGIN_DATA/unhobble/<id>"`, copy both files
   in, `jq --arg p "$(git rev-parse --show-toplevel)" '.checkout.worktree_path=$p'` into the data-dir copy;
   the contract's identity check then compares as written. Session-end: copy `stumbles.md` and
   `manifest.json` (minus the path) back, commit, push.
4. Phase 4 close: final commit prunes `docs/topics/unhobble-fable-5-1/` with the pre-prune SHA named in the
   PR body (topic-docs lifecycle step 4); the contract-slice gate goes green; `backups/` needs no action.

## D4. Sanity check of the default plan

**VERDICT:** No class changes to any strip/trim/regenerate unit; four annotations to the manifest.

**CONFIDENCE:** high.

**EVIDENCE**

- `agents-draft-pr` (b): add `register_class_contested: external-publication` (D2 §3.5; rubric line 38).
  Kept, so no Phase 2 effect, but Phase 4 must not treat a future strip of it as silence-deletable.
- `rule-pr-body-contract` (c): same annotation, marked weaker; add `surviving_oracles` naming the
  source-control hook, `.claude/source-control.md`, and the CI composite (D2 §4c), since that is why it may
  be stripped at all.
- `rule-ruff-pin` (d): reason should cite the ground-truth-oracle carve-out (PLUGIN-PHILOSOPHY 801-805)
  rather than only "tooling convention"; class stays `convention`, `operator_optional_strip` may stay but
  the carve-out makes a strip low-value.
- Manifest `strip_plan_summary` counts: recompute `always_loaded_lines_after` to 19 for this plan and add a
  `user_scope_plugins` block (D1 step 1). `ephemeral_note` is superseded by `state_location` (D3).
- Units checked and unchanged: `rule-worktree-base-ref` (consequence is a reviewable settings key, git
  history is the oracle; no Gate 0 class), `nested-autonomy` (CI typos gate is the oracle; it is a
  contributor workaround, not a rail), `rule-vendor-docs`, `rule-catalog-taxonomy`, `rule-hook-budget`
  (pointer-only; owner docs stay), `rule-skill-bodies` and `nested-provenance` trims (residues kept),
  `nested-model-adaptation` (legal-compliance hold, correct), `settings-permissions-deny` (secret-handling).

**WHAT WOULD CHANGE THIS VERDICT**

1. A Gate 0 adjudication for (b)/(c) (see D2): the annotations become `register_class`.
2. The bare-session load reading shows the `source-control` hook absent: (c) moves back to keep.
