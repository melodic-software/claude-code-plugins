# Generated-code residue

## The pass

Goal: the listed code lines read like the surrounding codebase wrote them, and every residue kind
below that they still carry is named in the report.

- Delete first; rewrite only where behavior must survive.
- When removing a cast, catch or fallback forces a choice about what bad input does, the loud
  failure (a throw or a failed build) wins over the quiet wrong answer. That choice changes what
  bad input does, so in tidy-diff it always reaches the caller as a proposal.
- The room decides: the surrounding code's comment density, naming and error-handling idiom set
  the bar, and a project convention outranks a row below.
- In tidy-diff the pass covers the listed code lines only, under tidy-diff's posture: an edit that
  would change an output, an error, an order, which inputs a check accepts, or a public signature
  is a proposal, never an edit.
- Close with one read of the listed lines against every kind below, asking what would still make a
  reviewer suspect a model wrote them. Fix or propose what it finds, then read once more; what the
  second read finds is reported, and the pass ends there. Each kind still present after a proposal
  is named beside that proposal.

The **In tidy-diff** column says what the pass does with each finding:

- **pass 2**: pass 2 has already triaged the comment, since
  [triage.md](../../dissolve-comments/reference/triage.md) gives each comment kind below its class,
  and deleted it behind the COMMENT-ONLY proof or made it a proposal. This pass edits no comment;
  a comment pass 2 kept is named in the report beside pass 2's verdict, and a comment that an edit
  of this pass invalidates, or that the closing read flags, is a proposal.
- **pass 1 rule**: applied when pass 1's rule allows it (inside the listed lines, behavior
  unchanged); otherwise a proposal.
- **proposal**: reported with the residue kind and its fix; nothing is edited.
- **report**: named in the report for the owner the cell names; tidy-diff changes no test.

## Residue kinds

### Comments

One test covers every comment: **does it state something the code cannot?** A constraint, a unit,
a tradeoff, the bug it works around: keep. Everything else: delete. The classes that apply that
test live in [triage.md](../../dissolve-comments/reference/triage.md).

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Comment that narrates | `// increment the counter` above `count++`. `// Loop through each item`. `// Return the result`. | Delete. | pass 2 (class A) |
| Comment that talks to the reviewer | `// Updated to use the new API`. `// Removed the old implementation`. `// Now handles null`. `// NEW:`, `// Fixed:`. | Delete; its explanation belongs in the commit message. | pass 2 (class A); its explanation is noted for the commit message |
| Comment that lies | A comment describing behavior the code no longer has, a parameter that was removed, a step that moved elsewhere. | Delete or correct it. When editing any region, re-read every comment in it for one the edit invalidated. | pass 2 (class A, obsolete); a correction is a proposal |
| Section divider or numbered step | `// ===== Helpers =====`, `// Step 1: parse input`. | Delete the divider. Replace numbered steps with extracted functions bearing those names. | Divider: pass 2 (class A). Step comment: class B, so the extraction is a proposal |
| Docstring that restates the signature | `@param userId - the ID of the user`. | Document constraints, units, side effects and surprising behavior, or nothing. | pass 2 on a private member (class A or B); a public-API doc comment is exempt and never touched |
| Commented-out code and summary blocks | Commented-out code. File-level blocks that list everything the code below does. | Delete both. | pass 2 (class A) |

### Defensive theater

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Check against an impossible state | A null check on a value the type system, the constructor, or the three lines above already guarantee. `if (!user) return;` after a call that throws when user is missing. | Trust the invariant. Where it is not guaranteed, fix the type once instead of checking at every call site. | proposal |
| Catch theater | Catching only to log and rethrow unchanged. An empty catch. `catch (e) { console.error(e) }` that swallows the failure and continues as if it succeeded. | Handle the error once, at a real boundary, adding context, or do not catch it. | proposal |
| Silent fallback | `catch { return [] }`. `?? defaultValue` masking a failed fetch. A simpler backup code path for when the real one fails. | Let it fail loudly: the fallback keeps tests green while the primary path is broken. Where degraded behavior is an explicit product decision, make the degraded state visible to the user. | proposal |
| Validation at every layer | The same null-and-range check repeated in the handler, the service, and the helper. | Validate untrusted input once at the boundary, then pass the trusted value through. | proposal |
| Condition padding | `x !== null && x !== undefined && x !== ''` where one check suffices. `=== true` on a boolean. `a?.b?.c` chains on values guaranteed to exist. | Write the check the invariant needs. | proposal |

### Type escape hatches

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Cast that silences the compiler | `as any`, `as unknown as X`, `@ts-ignore`, a non-null `!` used to silence an error instead of fixing it. | Parse or validate at the boundary and let the correct type flow through. A cast stays only with a comment stating the invariant that makes it safe. | proposal; a cast with its invariant comment stays, and that comment is class C |

### Naming

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Generic name | `data`, `result`, `item`, `temp`, `handler`, `processData`. | Name the domain fact the value holds: `unpaidInvoices`, `retryDelayMs`. | proposal; tidy-diff renames nothing |
| Version-suffixed name | `fetchDataV2`, `handleClickNew`, `EnhancedButton`, `utils-new.ts`. | Replace the old implementation, update its callers, and take its name. Published public API (a package's exports, a served endpoint) keeps a deprecated alias for callers outside the repository. | proposal |

### Structure

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| One-call wrapper | A helper that only forwards its arguments to another function. | Inline it; extract again on a second caller or real logic to own. | pass 1 rule, when the wrapper and every caller sit in the listed lines and it is not public |
| Speculative flexibility | An options object with one caller passing one value. An interface with a single implementation. Config flags for scenarios the task doesn't have. | Build for the current caller; generalize on the second real use. | proposal |
| Duplicate helper | A reimplemented formatter, validator, or permission check that already exists in the repository. | Use the existing owner of that job. | pass 1 rule (reuse), when the existing helper behaves the same for every input the listed lines pass it |
| Unrequested compatibility shim | Deprecated aliases, re-exports, "keeping the old signature just in case" when every caller lives in this repository. | Update the callers instead. | proposal |
| Dead scaffolding | Helpers from an abandoned approach. Unused imports and variables. `TODO: implement error handling` stubs. | Delete everything the final approach does not use. | pass 1 rule for a private, unreferenced name whose removal runs no code (an import can run code on load); a `TODO` comment is pass 2; a stub is a proposal |

### Logging

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Debug leftover | `console.log('here')`, entry and exit logs (`entering processOrder`). | Delete. | proposal: removing a log changes output |
| Log ceremony | Emoji or celebration in log output: `console.log('✅ Successfully initialized!')`. | Log the facts an operator needs, in the repository's existing log style. | proposal: rewording a log changes output |

### Tests

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Test deleted or weakened to pass | An assertion deleted, skipped or weakened to make a run green. | Fix the implementation, or, when the contract changed, say so and update the test to assert the new contract. | report, for `/testing:test-value` |
| Tautological test | The test reproduces the implementation's calculation and compares the two. | Assert an independently known outcome, at the public boundary. | report, for `/testing:audit` |

### Scope

| Residue | Detection cue | Fix | In tidy-diff |
|---|---|---|---|
| Drive-by change | Reformatting, renaming, or refactoring code the task didn't touch. | Keep the patch minimal; propose unrelated cleanup as its own change. | proposal; the project's own rule on what one change may carry wins |
