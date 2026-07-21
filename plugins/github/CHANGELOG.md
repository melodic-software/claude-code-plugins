# Changelog

All notable changes to the `github` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
