# Permission Rule Hygiene Convention — Changelog

Notable changes to the permission-rule-hygiene convention. The convention states a principle and three
anti-patterns; it is enforced by the `claude-config` plugin's `permission-hygiene` skill (checks
P1/P2/P3), whose detector and criteria version independently of this document.

## 1.2 — 2026-07-26

- **Corrected the known gap: plugin `bin/` delivery is unreliable, not absent.** 1.1 read the gap as
  categorical non-delivery on Windows / Git Bash; that came from sampling only degraded sessions. A
  local shell-snapshot survey found the delivering `export PATH=` line present in some sessions and
  missing in others on the same machine, including sessions carrying the surveyed plugin's own
  `bin/`. The section now states the per-session mechanism and cites both the local corpus (#843) and
  the upstream mechanism report. The operational guidance is unchanged and firmer: an intermittent
  capability still cannot carry a permission story, so invoke by bundled path.
- **Replaced "expect the call to reach the classifier on every invocation" with the mode-dependent
  truth.** An uncovered `bash <path> …` call is decided by the permission mode, not the allow rule: a
  prompting mode issues a per-call prompt, while auto mode routes it to the classifier, which may
  approve or deny without prompting. Helper authors are told to design for both rather than document
  a prompt that some sessions never issue.

## 1.1 — 2026-07-24

- Added "Known gap — step 1's plugin `bin/` is not delivered on Windows / Git Bash": the measured
  behavior, its harness-wide scope, the two consequences for helper authors, why a `~/.local/bin`
  shim and an `env.PATH` settings entry are not substitutes, and the one untested candidate
  (leading-wildcard rule) with the two specific unknowns that gate it.

## 1.0 — 2026-07-14

Initial published convention.

- Principle: the operative allow-rule for a guarded code-execution helper must be a narrow,
  machine-independent, bare-command rule the operator adds to user-global settings.
- Anti-pattern 1 — interpreter-wildcard / blanket allow rules dropped in auto mode.
- Anti-pattern 2 — hardcoded absolute machine/user paths (Bash rules match literally, no expansion).
- Anti-pattern 3 — assuming a skill or plugin can self-grant an auto-mode-gated action class.
- Correct pattern: bare command on the Bash tool PATH (pre-plugin PATH shim, post-migration plugin
  `bin/`) allowed narrowly by bare name, with an operator-setup boundary note.
