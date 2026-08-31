# Permission Rule Hygiene Convention — Changelog

Notable changes to the permission-rule-hygiene convention. The convention states a principle and three
anti-patterns; it is enforced by `/claude-config:audit-permission-grants` (checks
P1/P2/P3), whose detector and criteria version independently of this document.

## 1.3.2 — 2026-08-31

Docs-only patch. The anti-pattern-3 bullet quoting the skills page's `allowed-tools` semantics now
cites the owning section by anchor and carries a re-verified date (2026-08-31) with a divergence
trigger, per the upstream-drift convention's four-part shape; the quoted spans themselves were
re-verified verbatim against a live raw-markdown fetch and are unchanged.

## 1.3.1 — 2026-08-28

Corrective patch: the principle, the three anti-patterns, and the correct pattern are all unchanged.
The enforcement sentence names its enforcer by public invocation instead of by a filesystem path
into another plugin's tree, and this file's own preamble stops naming a skill that does not exist.

- **The enforcement citation was a path an installed reader cannot resolve.** The opening section
  read "Enforced by the [`audit-permission-grants`](../../../plugins/claude-config/skills/audit-permission-grants)
  skill in the `claude-config` plugin". That link resolves only inside the marketplace checkout, and
  three plugin surfaces fetch this README over `raw.githubusercontent.com` at run time, so the
  enforcement route was unreachable exactly where the convention binds.
  [ADR 0018](../../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)
  makes the plugin the encapsulation boundary for citation: name the public invocation, never a path
  into another plugin's private tree. The sentence now reads
  "Enforced by `/claude-config:audit-permission-grants`", which resolves for an installed reader and
  drops the redundant plugin restatement the slash form already carries.
- **This changelog's preamble named `permission-hygiene`, a skill that no longer exists.** That was
  the skill's name when this convention shipped in
  [#175](https://github.com/melodic-software/claude-code-plugins/pull/175); the naming-grammar batch
  in [#371](https://github.com/melodic-software/claude-code-plugins/pull/371) renamed it to
  `audit-permission-grants` and this preamble was not carried along, so it has sent readers after
  nothing since. Same failure as the citation above, reached by rot rather than by form, and fixed
  the same way. Both found by the whole-repo extract-ssot sweep's encapsulation floor.

## 1.3 — 2026-08-17

- **Refreshed the auto-mode-default citation to the page's current wording.** The block-quoted
  "Starting August 14, 2026" passage is no longer present at the cited URL; the page now states a
  version floor (v2.1.228 on macOS/Linux/WSL, v2.1.233 on native Windows) plus the surviving
  one-time switch-prompt behavior, both quoted verbatim (fetched 2026-08-17). Substance of the
  convention unchanged. Known gap, recorded for a future revision: the convention reasons only
  about *loosening* (allow rules surviving auto mode) and says nothing about *tightening* —
  deny-rule durability across modes — which the `context-budget` design now depends on
  (shipped as `plugins/context-budget/`; its topic slice pruned per topic-docs, evidence
  retrievable via PR #2932's pre-prune SHA).

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
