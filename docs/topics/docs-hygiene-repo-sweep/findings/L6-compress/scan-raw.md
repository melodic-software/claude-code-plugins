| target | expected_yield_pct | classify | reason |
|---|---|---|---|
| `.claude/rules/vendor-docs-are-not-style.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `.claude/source-control.md` | 3-7% | UNCERTAIN | inline-code density 57/kw AND/OR cross-ref density 4/kw; flavor band narrow |
| `.github/pull_request_template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `AGENTS.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `CLAUDE.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `REVIEW.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `SECURITY.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/CATALOG-TAXONOMY.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/CATALOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/CI-RUNNER-ROUTING.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/CLOUD-FLEET-SETUP.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/CLOUD-SESSIONS.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/GLOSSARY.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/MIGRATION-PLAYBOOK.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/NATIVE-SURFACES.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/OFFICIAL-DOCS.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/PLUGIN-ARTIFACT-PROTOCOL.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/PLUGIN-PHILOSOPHY.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/SKILL-CHEAT-SHEET.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0002-default-on-ai-review-advisory-with-earned-promotion.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0003-verification-guards-earn-default-on-by-measured-precision.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0005-bound-instruction-surface-work-by-question-not-population.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0006-scope-model-doctrine-per-version-behind-a-promotion-gate.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0007-host-per-model-doctrine-outside-skill-private-surfaces.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0008-admit-only-present-text-defects-to-the-instruction-audit-catalog.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0009-report-the-permission-plane-as-in-effect-and-never-write-to-it.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0010-merge-findings-across-producers-and-mark-consumption-explicitly.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0011-resolve-routine-prerequisites-per-identity-declared-over-detected.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0012-dispatch-video-sources-through-a-static-adapter-registry.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0013-keep-storage-format-identifiers-stable-across-renames.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0014-resolve-seam-engine-plugin-canonical-and-adapters-consumer-first.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0016-source-skill-recommendation-from-the-catalog-not-the-listing.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/adr/0017-ship-the-product-code-lane-as-its-own-skill.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/ai-briefing-design.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/commit-convention/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/config-cascade/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/config-cascade/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/consumer-config-layering/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/detector-findings/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/detector-findings/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/ecosystem-commands/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/ecosystem-commands/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/finding-suppression/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/finding-suppression/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-budget/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-config-delivery/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-config-delivery/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-observability/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-precision/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-telemetry/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/hook-telemetry/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/invocation-mode/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/liveness-assertion/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/liveness-assertion/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/loop-lane/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/loop-lane/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/native-references/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/permission-rule-hygiene/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/permission-rule-hygiene/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/plugin-data-report-keying/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/plugin-data-report-keying/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/pr-body-convention/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/pre-pr-ordering/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/seam-phrasing/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/shell-test-helpers/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/standards/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/standards/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/standards/examples/worked-index.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/topic-docs/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/topic-docs/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/topic-docs/examples/worked-slice.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/tracker-reference-form/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/untrusted-content/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/upstream-drift/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/upstream-drift/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/conventions/windows-path-emit/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/extensibility-contract-smoke-tests.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/formatter-path-probes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/hook-migration-audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/knowledge-integration-design.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/agent-doc-register-detectors.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/agent-doc-surfaces.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/d1-model-already-knows-measurement.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/d1-model-already-knows-measurement/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/dead-code-detector-landscape.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/dead-code-lsp-viability.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/invocation-mode-doctrine-brief.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/specs/write-for-agents-brief.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-channel-adapters.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-escalation-observability.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-headless-agents.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-peer-frameworks.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-product-surface.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-routine-catalog.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-sandbox-bar.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/RESEARCH-telemetry-unification.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/design/design-threads.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/index.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ai-adoption-ladder/native-vs-hook-telemetry-audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/autonomy-ignition/PLAN.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/autonomy-ignition/design/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/commit-convention-well-known-path/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/article-sections.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/checks-and-sweep.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/coverage-matrix.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/official-corroboration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/proportionality-gate.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/rerun-contract.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/seam-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/setup-corpus-audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/context-engineering-claude-5/design/skill-inventory.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/audit-brief.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/codex-review.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/coverage-reconcile.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/disposition-review.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/dispositions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S1.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S10.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S11.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S12.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S13.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S14.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S2.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S3.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S4.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S5.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S6.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S7.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S8.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/findings/S9.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/repair-ledger.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fable-field-guide-audit/source-article.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `docs/topics/fresh-eyes-checkpoint-audit/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/fresh-eyes-checkpoint-audit/design/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/interview-batch-rounds/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ladder-climb-roadmap/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ladder-climb-roadmap/design/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/ladder-climb-roadmap/interview-checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/loop-engineering-codification/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/plugin-audit-port/PLAN.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/plugin-audit-port/design/design-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/topics/shadowed-skill-renames/PLAN.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/upstream/aihero-course.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/upstream/aihero-shipping-course.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/upstream/cursor-pstack.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/upstream/mattpocock-skills-v12-map.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `docs/upstream/mattpocock-skills.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/actionlint/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/actionlint/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/actionlint/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/adhd/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/adhd/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/adhd/skills/clarify/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/adhd/skills/shape/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/ai-briefing/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/ai-briefing/skills/generate/context/execution-flow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/evals/fixtures/archive-sample.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/evals/fixtures/candidate-items-sample.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/ai-briefing/skills/generate/evals/fixtures/open-window-sample.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/references/audience-defaults.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/references/build-pipeline.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/generate/references/slide-generation.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-briefing/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/ai-slop/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/ai-slop/skills/audit/context/persist-findings.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/evals/fixtures/em-dash-substitution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/evals/fixtures/fix-guarded-rewrite.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/ai-slop/skills/audit/evals/fixtures/knowledge-cutoff-prose.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/evals/fixtures/report-only.md` | 3-7% | UNCERTAIN | inline-code density 19/kw AND/OR cross-ref density 0/kw; flavor band narrow |
| `plugins/ai-slop/skills/audit/evals/fixtures/rubric-boundary.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/evals/fixtures/triads.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/reference/catalog.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/ai-slop/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/architecture/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/architecture/skills/improve/actions/deepening.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/research/deepening/dependencies.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/research/deepening/html-report.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/research/deepening/interface-design.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/research/deepening/scan-briefing.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/architecture/skills/improve/research/deepening/vocabulary.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/autonomous-pipeline-reminder.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/binding-seam.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails/admission-policy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails/isolation-ladder.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails/security-review.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails/verification-topology.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/guardrails/work-classes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/prerequisite-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/return-accounting.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/role-topology.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/advisory-cve-triage.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/backlog-readiness-check.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/ci-health-review.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/dependency-update-wave.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/doc-freshness-sweep.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/duplicate-detection-sweep.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/eng-metrics-digest.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/issue-triage-sweep.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/pr-queue-tending.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/routines/tech-debt-sweep.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/runner.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/runner/escalation.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/runner/lifecycle.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/runner/seams.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/runner/topology.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/telemetry.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/trigger-dispatch.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/reference/wiring-vs-advisor.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/autonomy/skills/setup/context/capture-slice.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/context/prerequisite-resolution-slice.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/context/trigger-dispatch-slice.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/scripts/fixtures/prerequisite-resolution-slice/slice-binding/envelope.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/scripts/fixtures/prerequisite-resolution/positive-verdict/repo/docs/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/ack-reply.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/ci-otlp-artifact.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/isolation-probe.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/return-capture.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/routine-definitions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/autonomy/skills/setup/templates/trigger-adapters.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bash-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bash-format/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bash-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/biome-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/biome-format/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/biome-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/bugs/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/reference/config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/skills/scan/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/bugs/skills/scan/context/findings-report.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/skills/scan/context/lenses.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/skills/scan/context/verification-gate.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/bugs/skills/write/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/bugs/skills/write/context/template.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/bugs/skills/write/evals/fixtures/pagination-correct-offset.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-automation-gaps/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-automation-gaps/context/gap-analysis.md` | 3-7% | UNCERTAIN | inline-code density 30/kw AND/OR cross-ref density 0/kw; flavor band narrow |
| `plugins/claude-config/skills/audit-automation-gaps/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-instructions/context/persist-findings.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/context/report-keying.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/description-restatement.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/frontmatter-emphasis.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/inline-fence-not-section.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/partial-overlap.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/protected-content.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/quoted-trigger-restatement.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/quoted-trigger.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/evals/fixtures/sibling-restatement.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/reference/conflict-criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-instructions/reference/criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-pass/reference/determinism-tiers.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/doctor-handoff.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/exclusion-set.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/finding-identity.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/report-location-and-schema.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/run-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/suppression.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-pass/reference/terms.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/claude-config/skills/audit-permission-grants/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-permission-grants/reference/criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-permission-state/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-permission-state/reference/criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit-prompting-postures/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit-prompting-postures/reference/postures.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/audit/context/procedures.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/context/validation-categories.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/reference/audit-checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/reference/known-issues.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/reference/required-permissions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/audit/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-config/skills/draft-auto-mode-rules/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-config/skills/unhobble/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-memory/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-memory/skills/audit/context/audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/context/fix.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/context/update.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/evals/fixtures/init-bloated-claude-md.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/reference/criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/audit/reference/official-guidance.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/stateless/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-memory/skills/stateless/context/desktop.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/stateless/context/disable.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/stateless/context/purge.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/stateless/context/status.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-memory/skills/stateless/reference/official-guidance.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-install-state/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/audit-install-state/reference/evidence-discipline.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-install-state/reference/name-schemes.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-install-state/reference/scope-and-handoffs.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-install-state/reference/surfaces.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-native-overlap/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/audit-performance/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/audit-performance/reference/known-performance-issues.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/audit-skill-visibility/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/audit-skill-visibility/reference/pair-cooccurrence.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/changelog/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/changelog/context/classification-rubric.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/changelog/context/read-actions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/changelog/context/repo-surfaces.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/inventory/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/inventory/reference/extraction.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/known-issues/context/action-check-all.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-create.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-list.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-quality.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-scan.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-search.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/action-status.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/issue-templates.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/output-templates.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/known-issues/context/registry-schema.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/lanes/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/lanes/context/config.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/lanes/context/refresh.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/lanes/context/restart-consumer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/morning-brief/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/observability/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/observability/context/data-sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/operator-setup-collector-daemon.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/operator-setup-emission-privacy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/operator-setup-retention.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/operator-setup.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/otel-pipeline.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/otel-queries.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/output-format.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/privacy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/observability/context/read-routing.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/plugins/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/claude-ops/skills/plugins/context/converge.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/plugins/context/gotchas.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/plugins/context/scope-semantics.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/plugins/context/sync.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/claude-ops/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/audit-comment-residue/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/audit-dead-code/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/audit-dead-code/context/adjudication.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/audit-dead-code/context/lanes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/batch-simplify/context/reference.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/batch-simplify/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/dissolve-comments/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/dissolve-comments/reference/dissolving-moves.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/dissolve-comments/reference/safety.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/dissolve-comments/reference/triage.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/tidy/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/code-tidying/skills/tidy/lanes/docs-prose.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/lanes/self-update.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/lanes/shell-tooling.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/reference/exclusions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/reference/scope-budget.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/reference/tidyings.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/templates/apps-lane.template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/templates/dependency-root-lane.template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/templates/host-wiring-lane.template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/code-tidying/skills/tidy/templates/polyglot-services-lane.template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/codebase-health/skills/audit/context/discovery-method.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/skills/audit/reference/audit-checklist.md` | 3-7% | UNCERTAIN | inline-code density 23/kw AND/OR cross-ref density 2/kw; flavor band narrow |
| `plugins/codebase-health/skills/audit/reference/category-playbook.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/skills/audit/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/codebase-health/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/codebase-health/skills/setup/templates/config-template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/skills/diagnose/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/computer-use/skills/diagnose/reference/failure-diagnostics.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/skills/diagnose/reference/screenshots-and-zoom.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/skills/diagnose/reference/windows-quirks.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/computer-use/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/context-budget/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-budget/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-budget/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/context-budget/skills/audit/reference/engine.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-budget/skills/audit/reference/report.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-budget/skills/audit/scripts/fixtures/context-sample.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-budget/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/context-guard/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-guard/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-guard/reference/cloud-headless-capture.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-guard/reference/reader-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context-guard/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/context7/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/skills/lookup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/context7/skills/lookup/context/cli.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/skills/lookup/context/lookup.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/skills/lookup/context/mcp.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/skills/lookup/context/update.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/context7/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/coupling/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/coupling/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/coupling/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/coupling/skills/reduce/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/coupling/skills/reduce/reference/coupling-model.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/coupling/skills/reduce/reference/ledger.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/coupling/skills/reduce/reference/remediations.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/debugging/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/debugging/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/debugging/skills/debug/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/debugging/skills/debug/reference/ecosystem-debugging.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/debugging/skills/debug/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/desktop-notification/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/desktop-notification/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/desktop-notification/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discipline/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discipline/context/re-anchor-audit-correct.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discipline/skills/do-your-research-deep/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/do-your-research/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/follow-our-standards/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/mind-your-maxims/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/pick-for-the-problem/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/point-dont-copy/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/reason-dont-recite/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/recheck-against-upstream-deep/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/recheck-against-upstream/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/reuse-or-replace/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/script-the-deterministic-work/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/scrutinize-dont-coast/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/sweep-all/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/tighten-your-output/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/use-your-skills/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discipline/skills/wait-what/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/agents/explorer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/agents/intent-tracer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/agents/researcher.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/reference/artifact-protocol.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/reference/parent-contract.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/blindspot/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/explore/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/explore/reference/dispatch.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/explore/reference/ecosystem-discovery.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/research-deep/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/research/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/research/context/artifact-shape.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/research/context/discipline.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/research/context/dispatch.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/research/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/research/context/source-categories.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/trace-intent/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/discovery/skills/trace-intent/context/artifact-shape.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/trace-intent/context/dispatch.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/trace-intent/context/evidence-categories.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/discovery/skills/trace-intent/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/disk-hygiene/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/disk-hygiene/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/disk-hygiene/skills/clean/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/disk-hygiene/skills/clean/reference/safety-model.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/disk-hygiene/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/context/clean-tree-fallback.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/context/derivability-route-followups.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-derivability/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-derivability/context/rubric.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-derivability/evals/fixtures/decision-rationale.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-derivability/evals/fixtures/derivable-with-source/runtime-settings.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/legit-optouts.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/negation-shapes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/negation-trigger-fence.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/recall-paraphrases.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/context/details.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/context/queries.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/context/scratch-notes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/healthy-skill/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/healthy-skill/reference/redlining-rules.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/mixed-instructions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/compress/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/compress/context/fan-out-orchestration.md` | 3-7% | UNCERTAIN | inline-code density 24/kw AND/OR cross-ref density 2/kw; flavor band narrow |
| `plugins/docs-hygiene/skills/compress/context/flavor-vs-content-matrix.md` | 3-7% | UNCERTAIN | inline-code density 25/kw AND/OR cross-ref density 5/kw; flavor band narrow |
| `plugins/docs-hygiene/skills/compress/context/integration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/compress/context/semantic-diff-prompt.md` | 3-7% | UNCERTAIN | inline-code density 33/kw AND/OR cross-ref density 7/kw; flavor band narrow |
| `plugins/docs-hygiene/skills/compress/context/target-types.md` | ≤3% | SKIP | author-time-disciplined; signal 4 cite; empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/audit-fixture-dir/lean.md` | ≤3% | SKIP | author-time-disciplined; signal 4 cite; empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/audit-fixture-dir/mixed.md` | 3-7% | UNCERTAIN | inline-code density 72/kw AND/OR cross-ref density 0/kw; flavor band narrow |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/audit-fixture-dir/verbose.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/terse-agent.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/verbose-onboarding-snippet.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/docs-hygiene/skills/extract-ssot/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/extract-ssot/actions/batch.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/actions/identify.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/actions/verify.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/anti-patterns.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/citation-form.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/decision-framework.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/execution-checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/lessons.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/rename-references/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/rename-references/context/apply.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/rename-references/context/audit-modes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/rename-references/context/audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/rename-references/context/patterns.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/rename-references/context/triage.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/write-for-agents/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/write-for-agents/evals/fixtures/draft-rule.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/write-for-agents/reference/agent-doc-surfaces.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/write-for-humans/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/docs-hygiene/skills/write-for-humans/reference/sentence-rules.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/docs-hygiene/skills/write-for-humans/reference/sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/skills/curate-language/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/domain-driven-design/skills/curate-language/context/glossary-contract.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/skills/curate-language/evals/fixtures/billing-terms.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/skills/curate-language/evals/fixtures/context-map.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/skills/curate-language/evals/fixtures/custom-terms.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/domain-driven-design/skills/curate-language/evals/fixtures/support-terms.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/dometrain/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/dometrain/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/dometrain/skills/grounding/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/dometrain/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/dometrain/skills/sync/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/dometrain/skills/sync/context/update.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/explain/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/education/skills/quiz-me/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/education/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/education/skills/teach/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/education/skills/teach/context/assessment.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/teach/context/exercises.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/teach/context/glossary.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/teach/context/lessons.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/teach/context/mission.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/education/skills/teach/context/resources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/eol-normalizer/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/eol-normalizer/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/eol-normalizer/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/evals/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/evals/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/evals/skills/design/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/evals/skills/methodology/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/evals/skills/methodology/reference/eval-design.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/evals/skills/methodology/reference/grading.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/evals/skills/methodology/reference/recipes.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/evals/skills/methodology/reference/success-criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/event-storming/skills/methodology/reference/big-picture-workshop.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/design-level.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/glossary-and-tools.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/notation-and-building-blocks.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/patterns-and-anti-patterns.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/process-modeling.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/methodology/reference/remote-eventstorming.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/simulation/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/event-storming/skills/simulation/evals/fixtures/big-picture-board-export.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/simulation/reference/agentic-simulation.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/simulation/reference/iteration-workflow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/simulation/reference/miro-integration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/event-storming/skills/simulation/reference/simulation-evaluation.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/skills/firecrawl/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/firecrawl/skills/firecrawl/context/commands.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/skills/firecrawl/context/configuration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/firecrawl/skills/update/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/firecrawl/skills/update/UPSTREAM.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/firecrawl/skills/update/context/update-flow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/areas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/browser-automation.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/change-routing.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/conventions-file.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/method-ladder.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/recipes/actions-policy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/recipes/billing.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/recipes/rulesets-repo-drift.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/reference/recipes/security-posture.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/github/skills/advise/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/github/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/github/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/go-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/go-format/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/go-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/guardrails/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/guardrails/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/guardrails/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/implementation/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/agents/implementer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/agents/phase-verifier.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/reference/artifact-protocol.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/skills/implement-dispatch/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/implementation/skills/implement/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/implementation/skills/implement/context/bugfix.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/skills/implement/context/feature.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/skills/implement/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/implementation/skills/implement/context/refactor.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/reference/config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/skills/find/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/improvement/skills/find/context/ci-health.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/skills/find/context/hotspots.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/skills/find/context/ranking.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/skills/find/context/unattended.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/improvement/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/instruction-placement/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/context/corpus.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/context/findings-artifact.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/context/routing-rubric.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/context/verified-mechanics.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/evals/adherence-results.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/instruction-placement/skills/audit/context/gotchas.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/audit/context/routing-out.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/audit/evals/fixtures/bloated-agents.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/audit/evals/fixtures/contributing-with-conventions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/check/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/instruction-placement/skills/delta/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/instruction-placement/skills/realign/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/instruction-placement/skills/realign/context/apply-recipes.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/instruction-placement/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/kindle-dedrm/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/skills/manage/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/kindle-dedrm/skills/manage/references/sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/skills/manage/references/troubleshooting.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/skills/manage/references/versions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/skills/manage/references/workflow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/kindle-dedrm/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/reference/citation-shape.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/reference/ingest-deferred-decisions.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/book-distill/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/book-distill/context/templates.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/book-distill/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/course-digest/context/multimodal-evaluation.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/context/storage-schema.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/context/workflow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/reference/adapters/discovery-checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/reference/adapters/dometrain.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/reference/adapters/teachable.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/reference/analysis-template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/reference/screenshot-strategy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/course-digest/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/docpage-digest/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/docpage-digest/context/pipeline-hardening.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/docpage-digest/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/map-corpus/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/map-corpus/discovery/link-map-format.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/map-corpus/extraction/node-manifest-format.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/map-corpus/verification/inventory-format.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/video-digest/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/knowledge/skills/video-digest/context/companion-primary-sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/output-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/quality-gates.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/synthesis-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/watch-pipeline.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/watch-queue.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/context/workflow.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/extraction/liveness/LIVENESS.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/reference/sources/x.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/reference/sources/youtube.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/companion-source-brief.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/deck-inventory.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/queue.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/readme-journey.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/recommendations/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/recommendations/interview.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/recommendations/menu.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/recommendations/questions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/recommendations/takeaways.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/research-cluster.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/synthesis-item.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/knowledge/skills/video-digest/templates/watch-checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/machine-health/skills/audit/TODO.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/linux/NOT_IMPLEMENTED.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/macos/NOT_IMPLEMENTED.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/approvals.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/catalog-overlay.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/correlation-rules.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/discovery-guide.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/output-schema.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/remediation-philosophy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/report-template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/severity-rubric.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/shared/testing.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/windows/check-catalog.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/windows/elevation-matrix.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/references/windows/remediation-policy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/scripts/linux/NOT_IMPLEMENTED.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/scripts/macos/NOT_IMPLEMENTED.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/tests/fixtures/windows/Environment/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/audit/tests/fixtures/windows/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/machine-health/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/markdown-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/markdown-format/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/markdown-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mcp-tools/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mcp-tools/skills/audit/evals/fixtures/meta-annotations.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/evals/fixtures/server-with-resource.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/evals/fixtures/tools-with-defects.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/evals/fixtures/well-designed-tool.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/reference/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mcp-tools/skills/audit/reference/server-discovery.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/miro/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/miro/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/miro/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mutation-testing/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mutation-testing/skills/audit/context/persist-findings.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/audit/context/suppression.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/principles/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mutation-testing/skills/principles/reference/metrics.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/principles/reference/operators-and-states.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/principles/reference/scaling-and-suppression.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/principles/reference/theory.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/principles/reference/tooling.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/mutation-testing/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/mutation-testing/skills/setup/templates/config-template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/naming/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/naming/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/naming/skills/name-it-better/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/naming/skills/name-it-better/context/sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/context/findings-artifact.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/context/product-code-lane.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/context/scrutiny-method.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/reference/artifact-protocol.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/reference/consumer-config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/overengineering/skills/audit/context/report-template.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/skills/audit/context/surface-walk.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/skills/delta/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/overengineering/skills/delta/context/recurring-wiring.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/overengineering/skills/realign/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/reference/artifact-protocol.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/reference/standards-contract.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/audit-answers/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/brainstorm/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/design-handoff/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/design-handoff/evals/fixtures/design-threads-all-resolved.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/design-handoff/evals/fixtures/design-threads-single-gap.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/design-handoff/evals/fixtures/design-threads-unresolved-gap.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/design/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/devils-advocate/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/draft-goal-condition/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/interview/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/interview/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/context/loop.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/context/session-config.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/evals/fixtures/auto-guard-residue/codebase-survey.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/evals/fixtures/auto-guard-residue/task-context.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/evals/fixtures/lock-stop-on-gap/codebase-survey.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/evals/fixtures/lock-stop-on-gap/task-context.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/interview/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/plan/context/plan-reviewer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/context/plan-template.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/context/research-iterate.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/context/stress-test-triggers.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/context/tag-decisions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/plan/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/prd/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/prd/context/templates.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/questionnaire/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/questionnaire/templates/questionnaire.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/wayfind/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/planning/skills/wayfind/context/map-anatomy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/planning/skills/wayfind/context/tracker-mechanics.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/reference/model-adaptation/opus-4-8.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/reference/model-adaptation/opus-5.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/reference/model-adaptation/sonnet-5.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/playbooks/skills/boris/reference/advanced.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/automation.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/playbooks/skills/boris/reference/autonomy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/context-engineering.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/customization.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/favorites.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/foundations.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/loops.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/orchestration.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/unknowns.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/workflows.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/boris/reference/worktrees.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/playbooks/skills/fable-5/context/calibration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/communication.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/context-economy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/debugging.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/execution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/orchestration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/planning.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/problem-framing.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/reasoning-moves.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/recovery.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/trust-and-authority.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/fable-5/context/verification.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/skill-authoring/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/playbooks/skills/skill-authoring/reference/precompute-context.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/skill-authoring/reference/verification-loops-in-skills.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playbooks/skills/update/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/playwright/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/playwright/skills/playwright/actions/update.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/commands.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/e2e-orchestrator-recipe.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/network-mocking.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/running-code.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/sessions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/snapshots-and-refs.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/storage-and-auth.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/test-generation.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/tracing-and-video.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/playwright/reference/windows-quirks.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/playwright/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/plugin-quality/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/README.md` | 3-7% | UNCERTAIN | inline-code density 44/kw AND/OR cross-ref density 5/kw; flavor band narrow |
| `plugins/plugin-quality/agents/auditor.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/reference/config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/plugin-quality/skills/audit/references/component-types/agent.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/skills/audit/references/component-types/command.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/skills/audit/references/component-types/config.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/skills/audit/references/component-types/hook.md` | 3-7% | UNCERTAIN | inline-code density 19/kw AND/OR cross-ref density 3/kw; flavor band narrow |
| `plugins/plugin-quality/skills/audit/references/component-types/skill.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/plugin-quality/skills/audit/references/recurring-concerns.md` | 3-7% | UNCERTAIN | inline-code density 11/kw AND/OR cross-ref density 0/kw; flavor band narrow |
| `plugins/plugin-quality/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/powershell-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/powershell-format/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/powershell-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/prototype/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/prototype/README.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/prototype/context/discipline.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/prototype/skills/explore-directions/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/prototype/skills/pressure-test/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/rate-limit-guard/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/rate-limit-guard/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/rate-limit-guard/bench/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/rate-limit-guard/reference/reader-contract.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/rate-limit-guard/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/repo-fleet-hygiene/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-fleet-hygiene/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-fleet-hygiene/skills/apply/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/repo-fleet-hygiene/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/repo-fleet-hygiene/skills/audit/reference/confidence-model.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-fleet-hygiene/skills/audit/reference/official-sources.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-fleet-hygiene/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/repo-hygiene/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/repo-hygiene/skills/clean/context/action-router.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/context/clean-batch.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/context/git-branch-cleanup.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/context/git-tree-reset-batch.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/context/git-tree-reset.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/context/preflight.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/reference/cleanup-config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/reference/ecosystems.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/clean/reference/invocation-forms.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/repo-hygiene/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/review/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/architecture-guardian.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/ci-log-auditor.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/code-reviewer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/doc-drift-detector.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/ecosystem-specialist.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/agents/security-reviewer.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/context/severity.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/reference/standards-contract.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/code-review/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/review/skills/fanout/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/review/skills/fanout/context/default-mode.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/fanout/context/findings-normalization.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/fanout/context/fix-pass-mode.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/fanout/context/leaf-roster.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/fanout/context/run-everything-mode.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/review/skills/quality-gate/context/architecture.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/close-out.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/code.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/criteria.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/downstream.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/per-slice.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/pr.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/restatement.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/security.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/self.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/quality-gate/context/spec.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/review/skills/security-review/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/review/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/ruff-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ruff-format/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/ruff-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/output-styles/brain-fried.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/gather.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/observer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/off-thread-work.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/save-point.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/structure.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/clean-stop/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/continue-in-background/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/find-handoff/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/handoff/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/handoff/context/gotchas.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/keep-going/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/orchestrate/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/orchestrate/context/gotchas.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/orchestrate/context/sources.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/orient/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/reanchor/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/reconcile/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/retro/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/retro/context/codify.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/retro/context/quick.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/retro/context/session.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/retro/context/trends.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/retro/reference/ecosystem-improvement-catalog.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/running-retro/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/running-retro/context/checkpoint.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/show-options/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/show-options/context/buckets.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/show-options/context/candidate-ladder.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/session-flow/skills/workflow/context/continuation.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/context/philosophy.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/context/pre-pr.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/context/spec-first.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/context/steps.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/context/wrap-up.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/session-flow/skills/workflow/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/skill-quality/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/skill-quality/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/skill-quality/skills/check/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/skill-quality/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/agents/object-writer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/action-routing.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/ai-tools.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/artifact-persistence.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/audit-checklist.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/beyond-books.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/book-references.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/box-model.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/songwriting/context/pat-pattison/research/brainstorm.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/bridge.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/cliche.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/co-writing.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/coaching-protocol.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/daily-practice.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/demo-review.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/exercises.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/five-compositional-elements.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/form.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/fragment-development.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/hook.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/idea-to-title.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/line-brainstorm.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/line-edit-rubric.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/lyric-melodic-roadmaps.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/metaphor.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/meter.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/mosaic-rhyme.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/object-writing.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/phrasing.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/point-of-view.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/process.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/prosody.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/repetition.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/response-filter.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-dictionary-practice.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-fundamentals.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-generation.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-sonic-bonding.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-spotlight-connection.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-strategy.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-types.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/rhyme-worksheets.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/section-building.md` | 3-7% | UNCERTAIN | inline-code density 31/kw AND/OR cross-ref density 2/kw; flavor band narrow |
| `plugins/songwriting/context/pat-pattison/research/song-forms-examples.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/song-forms.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/stable-unstable-meta.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/title-game.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/variations.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/verse-development.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/voiceprint.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/workflows.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/research/worksheets.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/audit-checklist-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/brainstorm-opener.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/bridge-writing-prompt.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/co-write-session-opener.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/demo-review-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/diagnose-section-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/fragment-development-prompt.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/idea-to-title-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/line-brainstorm-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/metaphor-collision-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/metaphor-recipe-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/object-writing-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/title-game-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/title-generation-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/variations-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/context/pat-pattison/templates/worksheet-prompt.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/co-write/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/diagnose/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/metaphor/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/meter-prosody/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/object-writing/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/practice/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/rhyme/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/song-form/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/suno/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/songwriting/skills/suno/context/advanced.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/genre-taxonomy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/lyrics.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/power-tips.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/research-recipes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/studio.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/style.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/tips.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/troubleshoot.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/v55-features.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/voices.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/context/workflow-recipes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/reference/suno-drift-audit-ledger.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/ambient.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/classical.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/edm.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/folk.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/hip-hop.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/jazz.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/lofi.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/metal.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/pop.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/rnb.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/rock.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/suno/templates/trap.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/songwriting/skills/workflow/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/reference/config-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/reference/review-discipline.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/reference/worktree-root-convention.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-loop/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/babysit-loop/reference/no-progress-detector.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-loop/reference/pre-escalation-dispatch.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-loop/reference/telemetry-upsert.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/babysit-prs/reference/autopilot.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/cadence.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/feedback.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/freshness.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/guard-contract.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/independent-resolution.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/loop.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/orchestration.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/review-trigger.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/runbook-cycle.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/safety.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/stuck-checks.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/babysit-prs/reference/worktrees.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/.claude/source-control.local.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/.claude/source-control.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/commit/reference/exec-bit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/reference/format-check.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/reference/pathspec-commits.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/commit/reference/staging-preconditions.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/.claude/source-control.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/pull-request/evals/fixtures/ci-status-security-fail.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/evals/fixtures/source-control-required-none.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/evals/fixtures/source-control-required-related.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/reference/create.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/reference/merge.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/reference/monitor.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/reference/prep.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/reference/readiness.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/pull-request/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/resolve-conflicts/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/setup/.claude/source-control.local.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/setup/.claude/source-control.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/setup/reference/apply-convention.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/worktree/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/source-control/skills/worktree/context/audit.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/worktree/context/cleanup.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/worktree/context/create.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/worktree/context/status.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/source-control/skills/worktree/fixtures/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/tdd/skills/principles/reference/anti-patterns-khorikov.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/classical-vs-london-khorikov.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/code-coverage-khorikov.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/four-pillars-khorikov.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/integration-testing-khorikov.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/methodology-beck.md` | 5-15% | COMPRESS | verbose-prose baseline; expected flavor cuts on filler/hedging/articles |
| `plugins/tdd/skills/principles/reference/money-example-beck.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/observable-behavior-khorikov.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/refactoring-under-test.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/test-design.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/test-doubles.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/testable-architecture-khorikov.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/testing-styles-khorikov.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/tdd/skills/principles/reference/xunit-example-beck.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/audit/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/testing/skills/diagnose/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/testing/skills/diagnose/context/investigate.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/diagnose/context/loop.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/plan/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/testing/skills/run-e2e/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/testing/skills/run-e2e/context/e2e-config.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/run-e2e/context/e2e.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/run-e2e/context/non-ui.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/write/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/testing/skills/write/context/organize.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/testing/skills/write/context/write.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/reference/resolution-ladder.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/toolchain/skills/check/context/bash.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/dotnet.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/go.md` | ≤3% | SKIP | flavor-token density 4/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/powershell.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/python.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/sarif.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/check/context/typescript.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/toolchain/skills/lint/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/toolchain/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/typos-format/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/typos-format/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/typos-format/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/verification/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/reference/artifact-protocol.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/confirm/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/verification/skills/confirm/context/fix.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/confirm/context/outcome.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/confirm/context/refactor.md` | ≤3% | SKIP | flavor-token density 3/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/measure/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/verification/skills/measure/context/metrics.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/measure/context/performance.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/verification/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/visualization/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/visualization/README.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/visualization/skills/visualize/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/visualization/skills/visualize/context/decision-matrix.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/wizard/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/wizard/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/wizard/skills/generate/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/agent-brief.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/ai-disclaimer.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/capability-tier-labels.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/dogfood-filing.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/escalation-marker.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/execution-shape.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/issue-conventions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/item-content-trust.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/label-taxonomy.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/permission-preflight.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/pipeline-shape.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/standing-item-preconditions.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/topic-docs.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/tracker-seam.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/reference/work-class-labels.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/attend-queue/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/decompose/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/onboard-adapter/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/onboard-adapter/reference/adapter-spec.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/onboard-adapter/reference/live-exploration.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/scan-todos/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/setup/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/setup/reference/capability-tier-axis-migration.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/setup/reference/capability-tier-backfill.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/setup/reference/overlay-ignore-probes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/setup/reference/providers.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/ship/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/track/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/track/actions/add.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/audit.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/done.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/due.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/list.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/recheck.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/search.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/start.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/track/actions/stats.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/triage/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/work-loop/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/skills/work-loop/reference/invocation-argv.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/work-loop/reference/mode-drain.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/work-loop/reference/mode-standing.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/skills/work/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/work-items/templates/checklist.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/CONTRACT.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/gitea/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/github/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/jira/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/linear/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/linear/schema-check/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/work-items/tools/work-item-tracker/adapters/local-markdown/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/x/CHANGELOG.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/x/README.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `plugins/x/skills/read/SKILL.md` | ≤3% | SKIP | author-time-disciplined path (signal 1); empirical baseline 3/3 reverted; use `--force` only for targeted sub-3% diff |
| `plugins/x/skills/read/context/failure-modes.md` | ≤3% | SKIP | flavor-token density 0/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `prompts/cloud-bootstrap-rollout.md` | ≤3% | SKIP | flavor-token density 2/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |
| `prompts/loops/loop-lane-prompts.md` | ≤3% | SKIP | flavor-token density 1/kw < 5; disciplined-by-authorship; empirical baseline 9/9 reverted at 0.02-0.4% |

Total: 1280 skips, 10 compress-recommended, 12 uncertain
