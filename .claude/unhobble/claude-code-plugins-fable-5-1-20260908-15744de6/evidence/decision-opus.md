# Unhobble run decisions (independent agent: Opus 5)

Experiment: `claude-code-plugins-fable-5-1-20260908-15744de6`. Operator standing instruction:
accept/resolve where consensus research from authoritative sources backs it; where evidence is
thin or inference-only, prefer reversibility and contract intactness, and say so.

---

## D1. User-scope opt-in

**VERDICT: No. Do not ablate user scope this run, and do not ablate the 73 plugins via the
project-scope `false` overlay either; record all 73 as confounds. The overlay IS the correct
mechanism for a future plugin ablation, but it is gated on a Phase 1 classification pass that has
not run.**

CONFIDENCE: **high** (not opting user scope in) / **medium-high** (overlay is the right future
mechanism).

EVIDENCE

- Contract, `SKILL.md` "Scope and safety rails": user-global surfaces "are included only when the
  operator explicitly opts in per phase-1 prompt, never by default." No opt-in was given.
- D1 finding 3 + consensus row: a real user's `~/.claude/settings.json` never reaches a cloud
  session (code.claude.com/docs/en/cloud-environments "What carries over";
  code.claude.com/docs/en/settings "Settings in cloud sessions"). The in-container
  `~/.claude/settings.json` is environment-synthesized by the snapshot plus
  `.claude/cloud-bootstrap.sh`, not a human's standing instruction. Ablating it measures the
  provisioning layer, not the operator's instruction surface.
- D1 finding 3 + D3 findings 1.1/1.3/1.4: every session gets a fresh VM; the only persisted
  filesystem is the setup-script snapshot (~7-day expiry). A user-scope edit made in this session
  is **self-reverting** at the next session, so it cannot hold across an observe window measured in
  days. It buys no durable arm.
- Contract Phase 1: classification is required for "**every surface the strip plan will touch**
  ... and project-enabled plugins alike." No per-plugin classification exists for the 73. The
  manifest records only names (`confounds[0].with_hooks`, 20 entries). Per the task's own rule,
  unclassifiable plugins stay kept.
- Contract Phase 2 plugin rule: a plugin with any `policy` surface alongside behavioral components
  is **hybrid, kept whole**. Every one of the 20 hook-wiring plugins wires at least one gate-shaped
  hook, so the prior for each is "hybrid → keep whole", with only per-hook kill switches available.
  Named policy keeps the task lists (guardrails, source-control, rate-limit-guard) and the
  deterministic tooling lane (actionlint, bash-format, biome-format, eol-normalizer, go-format,
  markdown-format, powershell-format, ruff-format, typos-format) all fall on the keep side of that
  rule on the evidence available; the remaining eight (autonomy, claude-ops, context-budget,
  context-guard, desktop-notification, disk-hygiene, instruction-placement, session-flow) cannot be
  classified from the memos or the manifest and therefore stay kept pending the pass.
- The overlay mechanism is real and durable: `scripts/check-plugin-catalog-enablement.sh` header —
  "A key set to `false` PASSES. An explicit `false` is a recorded decision"; and
  `.claude/cloud-bootstrap.sh` (~line 205) computes its install set as fleet overlaid with
  `.claude/settings.json`, selecting `.value == true`, "so a repo entry set to false opts out of a
  fleet entry." Committed, it survives every fresh VM. This is the contract's own Phase 2 spelling
  ("disable the ones classified `behavioral` **for this project**").
- But the outcome of `true` at user + `false` at project is **inference, not documentation** (D1
  Unverified #1: no page states that pair), and mid-session enablement changes are unverified
  (D1 Unverified #3; `docs/CLOUD-SESSIONS.md` ~line 286 records the registry is built at process
  start and not re-read). Thin evidence → keep the contract intact.

WHAT WOULD CHANGE THIS VERDICT

1. A completed per-plugin classification pass (hooks.json + README per plugin) plus an official doc
   or an empirical check confirming project `false` beats user `true` — then disable the
   behavioral-classified subset via the committed overlay.
2. Operator explicitly opting user scope in at the Phase 1 prompt, accepting that the strip must be
   re-applied every session and that the arm measures provisioning, not instructions.

PHASE 2 MECHANICAL STEPS (D1)

1. Touch **no** plugin enablement: `.claude/settings.json#enabledPlugins` stays `{fleet: true,
   playgrounds: false}`. Do not edit `~/.claude/settings.json`.
2. Leave `manifest.scope.user_global_surfaces = false`; append to `scope.user_global_note`: "Opt-in
   declined for this run; user-scope edits do not survive a fresh VM, and no classification pass
   exists for the 73."
3. Promote the confound to a first-class experiment limitation: in `confounds[0]`, add
   `"classification_pass": "required before any of these may be stripped"` and
   `"durable_mechanism": ".claude/settings.json enabledPlugins <id>: false (committed; bootstrap
   honors settings-wins; catalog-enablement gate passes on an explicit false, keys must stay byte-
   sorted)"`.
4. After the strip, in the fresh session, run `/context` and `claude plugin list --json` and record
   what actually loaded in the manifest (D1 option F). Do not call any arm "stripped" on intent.

---

## D2. The four convention units

**VERDICT: Strip (a) "Validate a change" and (c) `pr-body-contract.md`; keep (b) "Open a pull
request as a draft" and (d) `ruff-pin.md`.**

CONFIDENCE: **high** for (a) and (d); **medium-high** for (b); **medium** for (c).

EVIDENCE

- (a) **strip.** D2 §4(a): `scripts/affected-tests.sh` is run by `ci.yml` job `test-linux`, which is
  in `ci-status.needs`, the single required check — a **gating** oracle. `README.md` "Validate a
  change" owns the full contract and survives the strip; the script self-documents (`--explain`,
  "FAIL LOUD, NOT OPEN"). D2 §3.5 Gate 0: no class (cost is wall clock). This is the exact
  derivable-with-a-live-oracle shape the experiment exists to measure.
- (c) **strip.** D2 §4(c): the `pr-contract` composite leaves an advisory comment plus a
  `needs-issue-linkage` label within one CI run — a real, fast correction signal the bare model
  receives. The section list survives in `.claude/source-control.md`
  (`pr_body_required_sections`), which is **not** in the strip plan, so the strip tests whether the
  model finds the surviving owner. Gate 0 is contested-weak: by the rubric's own "recognition is by
  consequence, not by phrasing" (`plugins/instruction-placement/context/routing-rubric.md` line
  ~42), a removable comment and a removable label is a bounded, reversible consequence.
- (b) **keep.** D2 §4(b): **no oracle at all** — no CI job, no hook, no skill default. A violation
  is silent and self-inflicted CI spend, and this is a cloud session that opens PRs. Gate 0 is
  contested toward `external-publication` (the rubric's literal example is "opening PRs"), which
  means that under contract Phase 4 step 4 it would be **restored regardless of the ledger** as a
  register hold. Stripping it therefore purchases cost with no evidentiary return. Thin/contested
  evidence → keep.
- (d) **keep.** D2 §3.3, `docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook": "a hook with a
  behavioral purpose but a non-derivable ground-truth oracle ... is a keep, not an ablation
  candidate." D2 §4(d): `scripts/run-ruff.sh` exits 2 on drift but **127/SKIP when the pin is
  unavailable** (fail-open), CI's only ruff lane covers one subtree
  (`plugins/source-control/skills/babysit-prs/**`), and nothing detects a local bare `ruff`. A bare
  model typing `ruff check` gets a clean-looking wrong answer with no error. The pin fact (a
  release moving rules into defaults) is machine ground truth no model can know unaided.
- Cross-check on the carve-out the keeps rest on: D2 §1.8 and the consensus table record that
  "team conventions in git" is **not** an officially stated exemption from the cut test — the
  repo's own `criteria.md` line 1887 concedes it. So (b) and (d) are kept on their own evidence
  (no oracle; non-derivable oracle), not on the convention class alone. (a) and (c) are stripped
  precisely because the convention label was doing the work for them.

WHAT WOULD CHANGE THIS VERDICT

1. (b): a detector landing (a `source-control` skill default or a CI check that flags a non-draft
   new PR) would make it strippable with a real feedback loop; or an adjudication that a reversible
   publication-cost rule is outside `external-publication`.
2. (c): evidence that the `pr-contract` composite at SHA `5776760…` actually **gates** rather than
   advises on body/linkage (D2 Unverified #2) would flip it to keep, since the gate would then
   already carry the correction and the strip would measure nothing new.
3. (d): a repo-wide, fail-closed ruff lane in `ci.yml` would remove the non-derivable-oracle carve-
   out and make it strippable.

---

## D3. Where experiment state lives

**VERDICT: Split. Keep `${CLAUDE_PLUGIN_DATA}/unhobble/<id>/` as the contract-canonical home, and
commit a durable mirror on the experiment branch at `docs/topics/unhobble-fable-5-1/` —
`stumbles.md` (the primary ledger) and `manifest-mirror.json` (identity by `origin_url` + `branch` +
`base_commit`, absolute path replaced by the literal token `${CLAUDE_PROJECT_DIR}`). `backups/`
never leaves the plugin data dir.**

CONFIDENCE: **medium-high**.

EVIDENCE

- Durability is not optional here: D3 findings 1.1/1.3/1.4 (fresh VM per session; reclaim restores
  conversation history, not disk; the only persisted filesystem is the post-setup-script snapshot,
  ~7-day expiry) and the repo's own **normative** matrix, `docs/conventions/topic-docs/README.md`
  "Visibility across execution contexts": cloud clone sees `${CLAUDE_PLUGIN_DATA}` as **invisible**
  and carries "pushed commits only". `SKILL.md` Phase 3 calls `stumbles.md` "the experiment's
  entire evidentiary output"; option (i) makes that output depend on an ungated manual hand-carry,
  twice per session, over days.
- Committing is unaddressed, not forbidden: D3 finding 4 — `SKILL.md` "What this skill does NOT do"
  lists four items, none about state location. Keeping the plugin-data dir canonical means no
  contract clause is bent; the mirror is an additive deviation, recorded in the manifest.
- `docs/topics/<slug>/` is the repo's **contract tier** — "Committed on the task branch only;
  pruned before merge" (`docs/conventions/topic-docs/README.md`), with a documented prune-with-
  pointer lifecycle. It is deliberately **not** the memory tier (`.work/`, self-ignoring, lost to a
  reclaimed container — `.gitignore` carries `.work/`), which is the tier that would lose the
  ledger. `scripts/docs-only-paths.txt` describes this exact prefix as "Operator precedent-
  codification & session working docs."
- **Changelog-parity clearance:** `scripts/check-changelog-parity.sh` case arms are `plugins/*/*`
  and `docs/conventions/*/CHANGELOG.md`. `docs/topics/` matches neither, so no version bump and no
  release entry is demanded per state write. State under `plugins/claude-config/` would demand both
  (D3 finding 5.2) — that path is rejected on this ground.
- **Friction F1 (machine-specific-paths gate vs the recorded absolute worktree path):** resolved by
  keeping the absolute path only in the plugin-data manifest, which is never committed, and
  tokenizing it in the mirror. No ci.yml exception-list edit is needed. Identity still holds:
  `origin_url` + `branch` + `base_commit` identify the checkout, and the canonical manifest the
  later phases verify against is still the plugin-data one.
- **Friction F2 (gitleaks vs `backups/`):** does not bite this run — the confirmed strip plan
  modifies **no** non-tracked file (`strip_whole`, `trim` and `regenerate` are all tracked paths;
  every `settings.json` surface is `action: keep`), so `backups/` is empty. The rule stands anyway:
  `backups/` stays out of git, since it would hold `.claude/settings.local.json`-class content the
  repo gitignores.
- **Friction F3 (Phase 2 already commits):** an advantage, not a cost. The branch is already the
  carrier for the stripped surfaces; the mirror rides the same flow, and D3 finding 3.4
  (`instruction-placement`, `overengineering`) establishes the repo's pattern that anything which
  must survive a reclaimed container becomes a tracked file.
- Gate profile accepted for the mirror: always-on markdownlint, typos, editorconfig and gitleaks
  still run on `docs/topics/**` (D3 5.1). `stumbles.md` must be ATX-headed, dash-bulleted, final-
  newline; the mirror JSON 2-space indented with a final newline. The em-dash gate is an allowlist
  and `docs/topics/` is not on it (D3 5.3), so free prose there is unenforced.

WHAT WOULD CHANGE THIS VERDICT

1. An empirical sentinel check (D3 U1: write a file under `~/.claude/plugins/data/`, look for
   it next session) showing the plugin data dir **does** survive reclaim for this environment —
   then option (i) alone suffices and the mirror becomes optional.
2. The operator electing to run observe from a durable local checkout, which moves the durability
   problem out of scope (and pins later phases to that machine's path, per F1).

PHASE 2 MECHANICAL STEPS (D3)

1. `mkdir -p docs/topics/unhobble-fable-5-1/`.
2. Write `docs/topics/unhobble-fable-5-1/manifest-mirror.json`: a copy of `manifest.json` with
   `checkout.worktree_path` set to the literal string `${CLAUDE_PROJECT_DIR}` and a new
   `"mirror_note"` stating that the canonical manifest with the resolved absolute path lives at
   `${CLAUDE_PLUGIN_DATA}/unhobble/claude-code-plugins-fable-5-1-20260908-15744de6/manifest.json`
   and that this mirror exists because a cloud clone cannot see that directory.
3. Write `docs/topics/unhobble-fable-5-1/stumbles.md` with the Phase 3 header row
   (`| Date | Task | What happened | Expected | Suspected missing instruction | Severity |`) and a
   one-paragraph preamble naming the experiment id and branch. This tracked file is the **primary**
   ledger; the plugin-data copy is derived.
4. Add to the canonical `manifest.json` a `"state_location_deviation"` object recording: the mirror
   path, the reason (cloud ephemerality; `topic-docs` visibility matrix), that `backups/` is
   excluded from the mirror, and that the mirror is contract-tier and pruned before merge.
5. Include both files in the Phase 2 commit (`experiment: strip instruction surfaces for unhobble
   baseline`) and push to `claude/unhobble-config-oe7yfx`.
6. At the start of every later session: `git pull`, then rehydrate
   `${CLAUDE_PLUGIN_DATA}/unhobble/<id>/` from the mirror (restoring the absolute
   `checkout.worktree_path` for the current checkout) before running any phase command.
7. At Phase 4 close: fold the ledger's conclusions into the restoring commits, then prune
   `docs/topics/unhobble-fable-5-1/` per the contract tier's prune-with-pointer lifecycle before
   merge.

---

## D4. Sanity check of the default strip plan

**VERDICT: Three class/flag changes — `rule-ruff-pin` becomes a ground-truth-oracle keep (drop
`operator_optional_strip`), `agents-draft-pr` gains a contested `external-publication` register-
class candidate and drops `operator_optional_strip` for this run, and `rule-pr-body-contract` is
stripped under a **named register hold** rather than as a plain convention strip. No other unit's
class changes.**

CONFIDENCE: **medium-high**.

EVIDENCE

- `rule-ruff-pin` — manifest has `class: convention, action: keep, operator_optional_strip: true`,
  reason "Repo tooling convention". The memo shows it is stronger than that: D2 §3.3's ground-
  truth-oracle carve-out (`docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook") plus D2 §4(d)'s
  fail-open wrapper, single-subtree CI lane, and non-derivable pin fact make it a **keep on the
  rule, not a keep the operator may casually override**. Change: keep `class: convention`, set
  `"operator_optional_strip": false`, and add `"keep_basis": "ground-truth-oracle carve-out
  (PLUGIN-PHILOSOPHY 'Classifying a hook'); run-ruff.sh is fail-open outside one subtree"`.
- `agents-draft-pr` — manifest has `class: convention, operator_optional_strip: true`. D2 §3 Gate 0
  determination records it as **contested `external-publication`** (the rubric's literal example is
  "opening PRs"; `plugins/instruction-placement/context/routing-rubric.md` line ~38). Under
  contract Phase 4 step 4 that class is restored regardless of the ledger. Change: add
  `"register_class_candidate": "external-publication (contested; rubric example vs reversible
  consequence)"` and set `"operator_optional_strip": false` for this run, with the reason recorded
  as "no oracle exists (D2 §4(b)) and a Gate 0 candidate returns on a register hold, so the strip
  buys cost without evidence."
- `rule-pr-body-contract` — manifest has `class: convention, action: keep,
  operator_optional_strip: true`. D2 §3 records it as **contested-weak `external-publication`**.
  Per D1/D2 the strip is elected (D2 above), so the manifest must carry the hold rather than
  strip it silently as a convention. Change: `action: strip`, `mechanism: git rm`, `restore: git`,
  plus `"register_class_candidate": "external-publication (contested, weak)"` and
  `"phase4_precommit": "register hold — restored at Phase 4 regardless of ledger rows if the
  contested reading is adopted; not counted in the ledger's defence tally"`.
- `agents-validate` — **no class change.** It stays `convention`; only `action` flips from `keep`
  to `strip` via the existing `operator_optional_strip` flag (D2 above). Gate 0: no class.
- Units the memos do not touch (`rule-vendor-docs`, `rule-catalog-taxonomy`, `rule-hook-budget`,
  `rule-worktree-base-ref`, `rule-skill-bodies`, the four `nested-*`, every `settings-*`,
  `plugin-fleet`, `plugin-playgrounds`, `plugin-config-files`) are **not re-litigated** and stand
  as the manifest classifies them. `nested-model-adaptation` (policy / `legal-compliance`) and
  `settings-permissions-deny` (policy / `secret-handling`) already carry their register classes
  correctly.

WHAT WOULD CHANGE THIS VERDICT

1. An adjudication (an added register entry, or a rubric amendment) placing a reversible
   publication-cost rule definitively inside or outside `external-publication` — that settles
   `agents-draft-pr` and `rule-pr-body-contract` in one move and removes both hedges.
2. Reading the `ci-workflows` `pr-contract` composite at SHA `5776760…` and finding the
   body/linkage half gating — `rule-pr-body-contract` then reverts to `action: keep`.
