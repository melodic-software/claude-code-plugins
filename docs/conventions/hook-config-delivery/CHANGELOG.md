# Hook Config Delivery Convention — Changelog

Notable changes to the hook-config-delivery contract. Versioned by `contract_version` (SemVer). A
change to the decision rule or to a matrix row's verdict is a major bump; adding a channel, a fact,
or a recheck trigger additively is a minor bump. The version-pinned facts table is evidence, not
contract — refreshing a pin or recheck date without a verdict change is no bump.

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
