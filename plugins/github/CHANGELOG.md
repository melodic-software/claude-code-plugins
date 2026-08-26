# Changelog

All notable changes to the `github` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.8]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Install`. The
  generated table itself is unchanged; a `## Configuration` heading was added above it. Docs-hygiene
  sweep, L8-write-for-humans.

## [0.3.7]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.3.6]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** The README's "No endpoint tables,
  no scope lists, no prices" cadence flattened to a single plain enumeration; all
  three denied items stay asserted. The read-only contract enumeration also stays:
  it defines the actual guarantee.

## [0.3.5]

### Changed

- **Instruction-surface de-slop (#2891, github cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.3.4]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.3.3]

### Fixed

- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against (#3111).
  Two upstream links that pointed at empty backward-compatibility anchors on the settings page
  were repointed at the headings that hold the content.

## [0.3.2]

### Changed

- **Explicit `disable-model-invocation` on `advise` and `audit` (#2968).** Both skills now state the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.3.1]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.0]

### Changed

- **`/github:setup apply` now states the two state-assessing clauses the setup contract requires of
  it.** The skill said `apply` "never blindly rewrites" and carried an idempotency check, but
  neither of the contract's specific guarantees had a line to cite: nothing preserved keys in an
  existing `routing.yaml` that the schema does not recognize, and nothing said a recognized value
  the current version cannot reconcile is reported rather than converged. Both are now explicit and
  scoped to `routing.yaml`, which is the only file `apply` merges — `conventions.md` is a prose stub
  already governed by never-overwrite, so a preserve-keys guarantee about it would say nothing. An
  unrecognized key may be a consumer extension or a newer version's, and an unreconcilable value
  quietly rewritten is config loss the consumer discovers only when routing misbehaves.

## [0.1.0]

### Added

- Published to the marketplace catalog (`category: operations`) after clearing the per-plugin
  migration gate and the plugin-acceptance security review (record in the playbook's
  security-review section — no hooks/MCP/bin; egress limited to the consumer's own `gh` auth,
  official-docs runtime fetches, and the opt-in confirm-gated browser-automation offer; ingested
  GitHub content treated as untrusted data).

- Walking skeleton: the `audit` skill end-to-end — area router (`reference/areas.md`, every
  coverage-matrix area), generic method ladder (`reference/method-ladder.md`: `gh` native →
  `gh api` REST → GraphQL → UI-only detection → guided manual + deep link, with fetch-integrity,
  403/404 disambiguation, plan/SKU honest degradation, and org-scale scoping rules), and the
  read-only contract stated in write-capability terms.
- Plugin manifest, README (verb contract including the `advise` verb declaration), and drafted
  `audit` eval cases.
- Consumer config surface: `reference/change-routing.md` (`routing.yaml` schema
  `contract_version` 1.0.0 — scope blocks, per-key override layering, policy-floor inversion on
  write-posture keys, target-resolution rule) and `reference/conventions-file.md` (concatenating
  prose conventions audits compare against).
- The `setup` skill (user-invoked only): `check` verifies `gh`, auth, credential-modality
  picture, and per-layer config verdicts; `apply` writes `.claude/github/` config idempotently
  via interview. Drafted `setup` eval cases.
- The `advise` skill: forward-looking guidance and hand-holding grounded in live `gh` state and
  freshly fetched official docs, proactive in-session suggestions (offered, never acted on), and
  a declared routing boundary against `audit` in both skill descriptions. Drafted `advise` eval
  cases.
- The `--apply` resolution flow in `reference/change-routing.md` (scope+target resolved first —
  org/enterprise targets asked, never silently inferred; then `propose` / `guided-apply` with
  per-step confirms, doc provenance, and post-write read-back / `handoff`; unconfigured →
  `propose`), wired into both `audit` and `advise`.
- The browser-automation offer for UI-only surfaces: `reference/browser-automation.md`
  (presence gates for claude-in-chrome and the `playwright` plugin, claude-in-chrome-first
  preference order, never-auto-fire rule, confirm-gate offer template naming surface + action +
  doc provenance + authenticated-session fact, post-write read-back verification, guided-manual
  deep-link fallback), the `offer_browser_automation` plugin setting (boolean, default `true`,
  advisory gate layered under the per-action confirm), and the method ladder's UI-only rung now
  citing the reference. Gate value surfaced in `audit` and `advise` prose via
  `${user_config.offer_browser_automation}`.
- Evals and QA surface: completed eval suites for all three skills (trigger routing, happy path,
  refusal branches, and both anti-pattern contracts — injected instructions in fetched GitHub
  content cause no write/browser/routing action; browser automation is offered and confirm-gated,
  never auto-fired), schema-validated. Committed contract test `github.test.sh` (runs under the
  repo's plugin-test runner) durably enforcing the zero-vendored-knowledge sweeps (no endpoints,
  no scope names in shipped prose, no prices), the agnosticism sweep, the area-coverage oracle
  (canonical area-key fixture diffed against `reference/areas.md`), and the recipe non-hollow
  contract (six sections plus a ≥10-question checklist per recipe).
- Primary-tier method recipes under `reference/recipes/` — `billing.md`,
  `security-posture.md` (authentication, advanced security, GitHub Apps, OAuth app policy,
  PATs), `rulesets-repo-drift.md`, `actions-policy.md`. Each carries a credential-and-gate
  preflight, a curated audit-question checklist, cost-control levers or posture heuristics, a
  drift-comparison procedure against declared conventions, dated re-verify-live caveats, and
  stable official-doc entry pointers — zero vendored endpoints, scopes, or prices (mechanics
  resolve at runtime via the method ladder). `reference/areas.md` primary rows link their
  recipes.
