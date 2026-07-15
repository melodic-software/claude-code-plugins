# Audit Discovery Guide

A guide for what kinds of claims to look for in each dimension. The primary method is always
**exhaustive claim verification**: read every line, extract factual claims, verify each one. This
guide helps you recognize claims you might otherwise skip.

The four bundled dimensions (documentation / configuration / code-quality / architecture) are
universal. Per-dimension `primary-sources`, `verification-sources`, and `example-claims` for THIS
repo come from the resolved audit config (`.claude/codebase-health.md` and its overlays).

## Documentation Claims to Verify

When reading a doc file, these are claim TYPES that commonly drift:

- **File/directory references** — "see `<path>`", "in `<module>`" → does that file/directory exist?
- **Package/tool names** — "uses tool X for Y" → is it in the package manifest? Commented out or
  active? Referenced by any project? **Check EVERY tool in a bullet list, not just some** — verify
  all entries individually.
- **Ranges and counts** — "rules `<PREFIX>NNN-<PREFIX>MMM`", "N categories", "M libraries" → count
  actual items.
- **Dependency claims** — "Layer A → Layer B only", "Module X has ZERO deps" → read the actual
  build manifest.
- **Convention descriptions** — "each module exposes `<pattern>`" → does the actual code follow this
  pattern?
- **Tool/installation claims** — "Tool X installed" → run the equivalent `<ecosystem> list` or
  check.
- **Suppression claims** — "Rule X is suppressed globally" → read the actual disabled-rules list in
  build config, check ALL entries not just the first.
- **Test class/location claims** — "Test class T in project P" → grep for the class, check what
  project it's in.
- **Status claims** — "Steps 1-2 implemented, 3-6 planned" → check if any "planned" items are
  actually done.
- **API surface claims** — "Type T has methods M1, M2, M3" → verify each method actually exists in
  source. Method-level claims are high-risk because methods get renamed, removed, or never
  implemented while docs persist.

## Configuration Claims to Verify

- **Every documented setting** vs actual file content — don't just spot-check, compare line by line.
- **Undocumented settings** — settings in config files no doc mentions.
- **Cross-file consistency** — does lint config match the convention narrative? Does build config
  match the build-config narrative?
- **Section scoping** — config files with sectioned scope (e.g. `.editorconfig` `[*.cs]`) can break
  scope unexpectedly.
- **Suppression rationale** — are suppressions documented and justified?

## Code Quality to Check

- **SOLID violations** — SRP, OCP, DIP especially (concrete deps, god classes).
- **DRY violations** — duplicated logic across 3+ files.
- **Missing test coverage** — non-trivial libraries without test projects.
- **Assertion library consistency** — all test projects using the same library?
- **Pattern compliance** — do implementations match documented conventions?

## Architecture to Check

- **Dependency direction** — read build-manifest files, verify against documented rules.
- **Enforcement gaps** — rules in docs that could be analyzers or tests but aren't.
- **Naming conventions** — interfaces, namespaces, test classes following docs.
- **Analyzer coverage** — help-link URLs valid? identifier range consistent across all docs?
