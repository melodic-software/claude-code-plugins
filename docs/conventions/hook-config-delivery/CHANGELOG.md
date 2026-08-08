# Hook Config Delivery Convention — Changelog

Notable changes to the hook-config-delivery contract. Versioned by `contract_version` (SemVer). A
change to the decision rule or to a matrix row's verdict is a major bump; adding a channel, a fact,
or a recheck trigger additively is a minor bump. The version-pinned facts table is evidence, not
contract — refreshing a pin or recheck date without a verdict change is no bump.

## 1.2.0 — 2026-07-31

Additive channel: **G. Operator-side arm record** (#1784) — an operator-side helper writes a
per-session record under the plugin's install-anchored data directory and the session carries only a
random record id through a `userConfig` string option; the hook treats the env-delivered id as a
capability pointer (shape-validated, anchored-store lookup, first-session claim, TTL, terminal
consumption), never authority. Closes channel F's `--settings` residual for per-session values.
Decision rule 3 gains the F+G pairing for per-session safety-critical values; no existing row's
verdict changes. Shipped exemplar: the autonomy lane-stop gate (0.12.0) armed by the claude-ops
lane launcher (0.26.0). Adopters table gains the autonomy row.

## 1.1.0 — 2026-07-27

No verdict change: the Recheck-triggers section cites the
[upstream-drift convention](../upstream-drift/README.md) (#1638), the new owner of the
stamp-and-trigger discipline this doc already practiced, and gains an additive sixth trigger
covering facts 7–8 (body substitution and sensitive-value storage), which previously had no
event naming their recheck.

## 1.0 — 2026-07-24

Initial published contract, codifying the channel decision matrix from the userConfig→hook delivery
program (verification probe of 2026-07-23 on Claude Code 2.1.218; docs re-fetched 2026-07-24).
Supersedes the proposal draft in issue #1182, which becomes the adoption/tracking pointer.

- Channels A–F characterized, including the shipped direct-settings-read channel (F) that
  disk-hygiene 0.9.0 (#1242) introduced, superseding the earlier SessionStart-file design for that
  plugin.
- Decision rule: skill-hooks → C/F; safety-critical optional-with-default → F (never B — the unset
  case is repo-tamperable via `env`; never bare argv — the hook drops); non-safety → B with
  in-script default; sensitive → B/C only.
- Meta-rule: prefer the most tamper-resistant channel that reliably delivers; argv's exclusion is
  pinned to the unimplemented upstream `default` (#46477) and carries a recheck trigger, not
  permanence.
- Enforcement: `scripts/check-hook-userconfig-argv.sh` CI gate (bare `${user_config.*}` in any
  plugin hook config fails; allowlist reserved for a proven channel D).
- Open gap recorded: G-required (channel D's no-unset-case premise, unprobed).
