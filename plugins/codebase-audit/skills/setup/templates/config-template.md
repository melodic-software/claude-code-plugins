# codebase-audit configuration

Tracked audit-dimension configuration for the codebase-audit plugin. Each `##` section below is one
audit dimension. The four bundled dimensions (`documentation`, `configuration`, `code-quality`,
`architecture`) may be tuned or removed here; new `##` sections add custom dimensions. Personal
overlays go in `.claude/codebase-audit.local.md` (gitignored); a user-global base may live at
`~/.claude/codebase-audit.md`. Layers resolve user-global → this file → local overlay, additively.

Each dimension carries:

- **primary-sources** — glob patterns for files where factual claims live (docs, conventions,
  ADRs, status pages). Discovery reads these top-to-bottom and extracts claims.
- **verification-sources** — glob patterns for files where claims are verified against ground
  truth (build config, manifests, source, tests).
- **example-claims** — optional `{ claim, verify-via }` rows teaching the claim-extraction pass
  what drifts in THIS repo. The more concrete, the better the audit.

## documentation

**primary-sources:**

- `docs/**/*.md`
- `README.md`
- <!-- add agent-instruction files (AGENTS.md, CLAUDE.md), convention docs, ADR directories -->

**verification-sources:**

- <!-- build manifests, package manifests, lock files, test project files -->

**example-claims:**

- claim: "<!-- e.g. Doc lists tools 'A, B, C' — verify EACH against the package manifest -->"
  - verify-via: "<!-- e.g. Grep the package manifest for each tool; check for commented-out entries -->"

## configuration

**primary-sources:**

- <!-- build config, lint config, CI workflow files, git-hook config -->

**verification-sources:**

- <!-- the convention docs that describe those config files -->

**example-claims:**

- claim: "<!-- e.g. Doc claims 'warnings are errors globally' -->"
  - verify-via: "<!-- e.g. Read the build config; confirm property value + scope -->"

## code-quality

**primary-sources:**

- <!-- source roots: src/**, lib/**, packages/** -->

**verification-sources:**

- <!-- test roots + the convention docs that set the quality bar -->

**example-claims:**

- claim: "<!-- e.g. Library X has no test project despite non-trivial logic -->"
  - verify-via: "<!-- e.g. Glob the test root for a matching project; count public surface -->"

## architecture

**primary-sources:**

- <!-- dependency manifests, architecture docs, ADRs -->

**verification-sources:**

- <!-- analyzers, architecture tests, dependency-rule enforcement -->

**example-claims:**

- claim: "<!-- e.g. Doc claims 'Layer A depends on Layer B only' -->"
  - verify-via: "<!-- e.g. Read every Layer-A manifest; verify no other references -->"
