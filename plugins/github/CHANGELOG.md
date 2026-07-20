# Changelog

All notable changes to the `github` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

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
