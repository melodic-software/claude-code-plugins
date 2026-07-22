# Changelog

All notable changes to the `autonomy` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

Versions 0.1.0–0.7.0 predate this file (introduced with 0.7.1); their history lives in the
merged work-package PRs (#333, #343, #356, #372, #377, #600, #676).

## [0.9.0]

### Changed

- **Credential-probe validation is now deny-by-default against a configured `--credential-roots`
  allowlist.** The security-binding checker no longer recognizes a probed host-credential path by
  static structural shape. A static checker cannot know an org's real credential locations, and for
  any open-ended structural recognizer an adversary can craft a plausible-but-invented path (an
  invented home user, a mount that need not exist) whose failing read proves nothing while real host
  credentials stay readable. A filesystem credential entry now counts as credential-absence evidence
  only when its recorded host-side expansion resolves — lexically, `..`-safe, filesystem-independent —
  under one of the operator-configured trusted roots passed via the new `--credential-roots
  <path,path,...>` flag, mirroring the `--egress-hosts` seam; with no roots configured, every
  filesystem credential entry is untrusted and the level fails closed. Membership under a configured
  root is the sole test, so the previously non-converging location enumeration is dissolved. A
  cloud-metadata-endpoint route and a well-known credential env token remain bounded closed sets that
  need no allowlist, and the expansion-coherence guard is retained. The egress-side seam is unchanged.

## [0.8.0]

### Added

- **Instruction-provenance clause added to the routines contract.** A new normative clause in
  `reference/routines.md` fixes that a routine's instruction content lives in a
  version-controlled, reviewable artifact and the stored prompt is a thin pointer to it;
  pasted-prose prompts are non-compliant, retaining no history and drifting invisibly against
  the repository state each run executes on. The clause is surface-agnostic — its rationale is
  that a scheduling surface holding the prompt centrally exposes no prompt history, diff, or
  rollback, so behavior change is auditable only where the pointed-to artifact is versioned.
  Surface-class mappings (a cloud scheduling surface → a skill committed to a selected
  repository's skills directory; a desktop scheduling surface → a per-task instruction
  file under the deployment's version-controlled dotfiles) appear only as illustrative
  deployment-owned bindings, consistent with the contract's Hosting stance.

## [0.7.4]

### Changed

- **Boris-intent attribution seams marked across the guardrail contract.** Three surgical
  attributions distinguish this contract's own instantiation from the source playbook's posture,
  closing UNMARKED-EXTENSION seams a Boris-intent audit found (zero violations, three seams). The
  guardrail hub now states that the step-4 sentence it quotes verbatim is the playbook's while the
  five-class taxonomy, blocking knobs, and promotion predicates are this contract's mechanism; the
  security-review leaf marks review-as-merge-gate (the `blocking` knob) as this contract's own
  layer over the playbook's advisory-review-feeding-a-human-merge posture; and the work-classes
  leaf attributes the numeric-predicate promotion/demotion apparatus as this contract's
  quantification of the playbook's qualitative "earned widespread trust" bar. Documentation only —
  no contract semantics change.

## [0.7.3]

### Added

- **Security-binding golden suite is graded (`#662`).** A table-driven runner
  (`check-security-binding.fixtures.test.mjs` + its co-located expectations manifest) runs
  every fixture under `evals/fixtures/security-binding/` through
  `check-security-binding.mjs` and asserts exit code + defect-naming findings: 109 fixtures
  (14 pass-expected, 95 reject-expected), zero quarantined, with the fixtures' 67 probe
  transcripts enumerated as suite inputs. Self-policing in both directions — an ungraded
  new fixture, an unlisted transcript, or a manifest entry whose file vanished all fail the
  suite, and the repo's orphaned-fixture gate no longer grandfathers the set.

## [0.7.2]

### Changed

- **Pillar 3 reconciled with the audited native-surface reality (`#351` audit).** The
  causal-tree contract now states explicitly that `traceparent` propagation binds
  CONTRACT-AUTHORED emissions, and that a native agent surface ignoring inbound context (a
  default surface may, honoring it only behind an opt-in) does not break the tree — its
  session emissions attach query-side through the Pillar 2 join attribute, and relying on
  direct native span joining is a recorded migration trigger, not an assumption. The CI
  OTLP template's trace-context-injection section carries the same surface-specific caveat
  plus the `OTEL_RESOURCE_ATTRIBUTES` injection the setup flow already wires. No emission
  or checker behavior changes.

## [0.7.1]

### Added

- **D1 deferral sweep — every out-of-package note from the WP1–WP7 design rounds now has a
  durable trigger record (`#353`).** The README roadmap gains the fleet guardrail
  materializations, fleet routine stand-up + existing-scheduler reconciliation,
  vendor-binding capability templates, and cost-enforcement rows; the trigger register gains
  the second-binding-consumer cross-repo drift check; `reference/return-accounting.md`
  records the per-work-class precision-graduation deferral beside its band-stability rule.
  Documentation only — no contract semantics change.
