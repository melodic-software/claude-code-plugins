# Tidyings taxonomy

Three sections: Beck's 15 named tidyings (the canonical list from *Tidy First?*, 2024), the Fowler "Composing Methods" subset most applicable to Boy Scout passes, and prose tidyings for the documentation/skill surface.

Total entries: 15 + 5 + 6 = **26 named tidyings**.

Each entry follows the same shape: name, when-to-apply, when-NOT-to-apply, 1-line example.

---

## Section 1 — Beck's 15 tidyings (from *Tidy First?*, 2024)

Beck's framing: small, named refactorings nobody could hate on. Structural-only. Each targets a specific reading-experience defect. **Apply liberally; commit atomically.**

### #1 — Guard Clauses

- **When to apply:** a method's happy path is buried inside nested `if`/`else`. Replace with early-return guards at the top.
- **When NOT to apply:** the nested branches each have meaningful logic worth preserving as separate methods (that's Extract Method, not Guard Clause). Also when the language doesn't support early return cleanly.
- **Example:** `if (x != null) { if (x.IsValid) { ... } }` → `if (x is null || !x.IsValid) return; ...`

### #2 — Dead Code

- **When to apply:** code that no longer has any callers or any path of execution that reaches it. Static analyzers (Roslyn, ruff F841, biome unused-import) often surface candidates.
- **When NOT to apply:** the "dead" code is reflectively invoked, used by source generators, or referenced by string name in DI/serialization. Verify before deletion.
- **Example:** `private static string FormatLegacy(...)` no longer called after a public API consolidated → delete.

### #3 — Normalize Symmetries

- **When to apply:** two parallel constructs that do "the same thing" are written in two different ways without semantic justification. Make them look the same.
- **When NOT to apply:** the asymmetry is intentional (e.g., one variant has additional safety checks the other doesn't need).
- **Example:** half the validation methods return a result type, half throw exceptions → align them on the result type (only when the exception variants are not load-bearing).

### #4 — New Interface, Old Implementation

- **When to apply:** **ONLY when the new interface has zero existing consumers.** Add a new abstraction layer over an existing implementation without changing the implementation. Tidy the call sites later.
- **When NOT to apply:** existing consumers exist that would need to migrate. That's not a tidying — that's a migration with breaking-change risk. **Treat as behavioral.**
- **Example:** wrapping a static helper class behind an injectable interface, when no one currently calls the static directly. If anyone calls it directly today, this is migration work; defer.

### #5 — Reading Order

- **When to apply:** members of a file/class/module appear in an order that doesn't match the order a reader needs to encounter them in to understand the file. Reorder so the public API reads top-to-bottom; private helpers go below the methods that call them.
- **When NOT to apply:** the existing order matches a strong external or project convention (e.g., minimal-API ordering by route, or an alphabetical-by-default rule).
- **Example:** in a service-registration extensions file, the public `AddXService` is at the bottom, private `ConfigureY` helpers above it → flip the order.

### #6 — Cohesion Order

- **When to apply:** members operating on the same concern are scattered. Group them: constructor → state → operations on that state → operations on derived state.
- **When NOT to apply:** the existing grouping reflects a different valid axis (e.g., grouped by interface implementation rather than by data they touch).
- **Example:** `OrderService` has `ValidateAddress`, `ValidateLineItems`, `ApplyDiscount`, `ValidatePayment` mixed with persistence methods → group all the validators together.

### #7 — Move Declaration and Initialization Together

- **When to apply:** a variable is declared near the top of a method and assigned much later. Move the declaration to where it's first used.
- **When NOT to apply:** language constraints force an early declaration (rare in C# / TS / Python; common in C).
- **Example:** `string result; ... 30 lines ... result = ComputeIt();` → `string result = ComputeIt();`

### #8 — Explaining Variables

- **When to apply:** a sub-expression in a long expression is hard to name in isolation but is doing meaningful work. Extract it into a named local.
- **When NOT to apply:** the expression is short, the name would be redundant (`int total = a + b;` is not an improvement when `a + b` is used inline once).
- **Example:** `if (order.LineItems.Where(x => x.Quantity > 0).Sum(x => x.Price * x.Quantity) > customer.CreditLimit)` → extract `var orderTotal = ...; if (orderTotal > customer.CreditLimit)`.

### #9 — Explaining Constants

- **When to apply:** a magic number or magic string appears inline with no clue what it represents. Replace with a named constant.
- **When NOT to apply:** the literal is self-documenting in context (`for (int i = 0; ...)` doesn't need `const int Zero = 0;`).
- **Example:** `if (status == 7)` → `if (status == OrderStatus.Cancelled)`.

### #10 — Explicit Parameters

- **When to apply:** a method takes a "context" or "options" object whose fields are mostly unused, and the caller would benefit from the actual parameters being explicit.
- **When NOT to apply:** the options object is genuinely a coherent value with many fields, or it's a public API where breaking the signature is behavioral.
- **Example:** `void Process(ProcessOptions opts)` where every caller only sets `opts.Timeout` → `void Process(TimeSpan timeout)`.

### #11 — Chunk Statements

- **When to apply:** a long method has logical "stages" mashed together with no separation. Insert blank lines between stages. (Not Extract Method — that's #12. Just visual chunking.)
- **When NOT to apply:** the method is already chunked, or it's short enough that chunking would be overkill.
- **Example:** a 40-line setup method with no blank lines → insert blank lines between "build context", "validate", "execute", "log".

### #12 — Extract Helper

- **When to apply:** a chunk from #11 (or a duplicated chunk across two methods) deserves to be its own named method.
- **When NOT to apply:** the chunk is only used once and naming it adds noise without aiding comprehension. Or: extracting it would force complex parameter passing that obscures the original method.
- **Example:** two different endpoint handlers each have a 12-line "build error response" block → extract `private static IResult ToErrorResponse(Result result)`.

### #13 — One Pile

- **When to apply:** code that should logically be in one place (one file, one class, one section) is split across multiple locations for no semantic reason.
- **When NOT to apply:** the split is intentional (separate files for build performance, separate classes for layering / testability).
- **Example:** `OrderValidationRules.cs` and `OrderValidationHelpers.cs` both contain Order validation utilities with overlapping concerns → consolidate.

### #14 — Explaining Comments

- **When to apply:** code does something non-obvious (a workaround for a bug, a subtle invariant, a constraint from outside the code). Add a brief `// Why:` comment.
- **When NOT to apply:** the code is self-explanatory and the comment would just restate it. Only comment *why*, never *what*.
- **Example:** `// Workaround: the IDE locks analyzer DLLs; output to bin/cli/ when not building inside it`.

### #15 — Delete Redundant Comments

- **When to apply:** a comment restates what the code obviously says, or describes behavior the code no longer has.
- **When NOT to apply:** the comment is non-obvious context (the kind #14 produces). Be conservative — when uncertain, leave the comment.
- **Example:** `// Increment counter` above `counter++;` → delete the comment.

---

## Section 2 — Fowler "Composing Methods" subset (from *Refactoring*, 2nd ed., 2018)

These overlap somewhat with Beck's list but predate it. Use Fowler's framing when discussing with colleagues outside the Beck terminology; use the Beck name internally if they have one. Skip subjective Fowler refactorings (Replace Conditional with Polymorphism, Replace Type Code with Class) — design judgments, not tidyings.

### F-1 — Extract Method

- **When to apply:** same as Beck #12 (Extract Helper). Fowler's name is more widely recognized; either label works.
- **When NOT to apply:** same as Beck #12.
- **Example:** see Beck #12.

### F-2 — Inline Method

- **When to apply:** a method's body is just as clear as its name. Inline it at the call site, then delete the method.
- **When NOT to apply:** the method is called from multiple sites; inlining duplicates code (negative tidy).
- **Example:** `private bool IsValidNonEmpty(string s) => !string.IsNullOrEmpty(s);` called once → inline.

### F-3 — Rename Variable / Method / Class

- **When to apply:** a name no longer matches what the symbol actually does, or fails the "fits-in-head" test for a new reader.
- **When NOT to apply:** the symbol is part of a public API. Renaming is then behavioral (every caller must change).
- **Example:** `private static List<X> ProcessThem(List<X> items)` → `private static List<X> NormalizeWhitespace(List<X> items)`.

### F-4 — Extract Variable

- **When to apply:** same as Beck #8 (Explaining Variables). Fowler's name is also widely used.
- **When NOT to apply:** same as Beck #8.
- **Example:** see Beck #8.

### F-5 — Replace Magic Number with Symbolic Constant

- **When to apply:** same as Beck #9 (Explaining Constants), specifically for numeric literals.
- **When NOT to apply:** same as Beck #9.
- **Example:** see Beck #9.

---

## Section 3 — Prose tidyings (documentation / skill surface)

Beck-style structural improvements applied to the prose surface — skill bodies, lane files, documentation. No established names in the broader literature; named here for discoverability.

### P-1 — Dead-link removal

- **When to apply:** a markdown link `[text](path)` points at a file or section that no longer exists.
- **When NOT to apply:** the link is intentionally aspirational (e.g., pointing at a planned doc) — but in that case, mark it explicitly with surrounding text. Bare broken links are dead.
- **Example:** `see [the cleanup skill](../cleanup/SKILL.md)` after that skill was renamed → fix or delete.

### P-2 — Stale cross-reference repair

- **When to apply:** a reference to a file path, function name, env var, or skill name that has changed. The reference still resolves to *something* but no longer to the right thing.
- **When NOT to apply:** the reference is in a quoted historical passage (e.g., a retro post-mortem citing what *was* true at the time).
- **Example:** a doc references `.claude/rules/worktree-setup.md` after that file moved to `.claude/rules/worktree/worktree-setup.md`.

### P-3 — Redundant-paragraph dedup

- **When to apply:** two skills (or two sections within one doc) explain the same concept with overlapping but not identical prose. Move the canonical explanation to one place; reference it from the other.
- **When NOT to apply:** the two explanations are intentionally tailored to different audiences (e.g., a quick summary for one skill's users vs. the deep-dive for the canonical doc).
- **Example:** "what the pre-push branch-name check does" appears in three rule files → keep the canonical one, replace the others with a reference link.

### P-4 — Reading-order improvements (in prose)

- **When to apply:** same as Beck #5, applied to documentation. Readers should encounter "what is this" before "how to use it" before "advanced gotchas".
- **When NOT to apply:** the existing order matches a deliberate inverted pyramid (most important info first; details below). That's also a valid order.
- **Example:** a SKILL.md whose "Gotchas" section appears before "Workflow" → move Gotchas to the bottom.

### P-5 — Explaining-comments insertion (in code-shaped prose)

- **When to apply:** a CLI command, config snippet, or code example in markdown does something non-obvious. Add a one-line `# explains the next line` comment.
- **When NOT to apply:** the snippet is self-explanatory. Don't pad code blocks with restating-comments.
- **Example:** `npx markdownlint-cli2 "**/*.md"` → add `# Lint all markdown files (matches CI)`.

### P-6 — Delete-redundant-comments (in prose)

- **When to apply:** a paragraph in a doc restates the section heading or repeats information already given. Delete it.
- **When NOT to apply:** the paragraph is a deliberate "TL;DR" summary providing genuine value to skimmers.
- **Example:** a section titled "## Workflow" whose first paragraph reads "This section describes the workflow." → delete the paragraph.

---

## Quick reference — commit-type defaults

| Tidying group | Default Conventional Commits type for code lanes | For prose lanes |
|---|---|---|
| Beck #1-#15 | `refactor:` | n/a (Beck targets code) |
| Fowler F-1 to F-5 | `refactor:` | n/a |
| P-1 to P-6 | n/a | `docs:` (prose lanes) or `chore(tidy):` (self-update) |

Each lane's own `## Conventional Commits type` section overrides this if it specifies otherwise.
