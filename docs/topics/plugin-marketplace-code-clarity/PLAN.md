# plugin-marketplace-code-clarity

## Brief

### TLDR

A new skill in the `code-tidying` plugin that enforces self-describing, expressive code
over agent-written changes: a three-way comment triage that deletes zero-information
comments, dissolves code-expressible comments through behavior-preserving refactoring and
then deletes them, and keeps only terse, load-bearing comments carrying information code
cannot express. Doctrine is grounded in a verified research pass over the canonical
sources (Martin, Fowler, Ousterhout + the aposd-vs-clean-code debate, McConnell, Google
eng-practices, Anthropic's prompting guidance); every decision below survived a
two-validator adversarial audit.

### Goal

Ship one user-invocable, edit-applying skill in `plugins/code-tidying` that, when run,
makes the target code more expressive and removes every comment that does not earn its
keep — the enforcement counterpart to the read-only `audit-comment-residue` classifier.

### Decisions (locked)

1. **Primary use case:** agent-written code before commit. On invocation the skill
   enforces; it is a tidy-after-generation pass, never a generation-time comment ban.
2. **Shape:** one skill hosting an explicit three-way triage per comment:
   - **Class A — zero/negative information** (restates code, obsolete, commented-out):
     delete outright, near-mechanically.
   - **Class B — information the code could carry:** refactor until the comment is
     superfluous (Extract Function, Extract Variable, Change Function Declaration /
     rename, Replace Magic Literal, Introduce Assertion), then delete.
   - **Class C — information code cannot express:** survives only if load-bearing at the
     point of reading (a future editor risks a bug or misuse without it). Terse is the
     default posture, not a hard line cap.
3. **Doctrine floor:** the jointly-signed debate line — implementation code only needs
   comments when the code is nonobvious — plus Anthropic's "only add comments where the
   logic isn't self-evident."
4. **Justification routing:** rationale/justification defaults to routing out of code
   (commit message, PR, ADR); a terse in-code why is legitimate. Before any deletion is
   final, stripped narrative is staged as a proposed commit-message block in the skill's
   output (or handed to `/source-control:commit`) — text is never silently destroyed.
5. **Class-B safety gate:** tests gate application (lint is supplementary — it cannot
   attest behavior preservation). The skill must discover a runnable test command
   covering the touched code; otherwise class-B changes are proposed, never applied.
   Class-A deletions apply without that gate.
6. **Scope of a run:** uncommitted diff by default; optional explicit file/dir target.
7. **Doc comments:** public-API doc comments (docstrings, C# XML docs, JSDoc on exported
   surfaces) are exempt — never touched. Private/internal doc comments are triaged under
   class C — an explicit choice of the Martin pole for internal interfaces, not a side
   effect.
8. **Sanctioned exceptions (never touched):** legal/license headers, machine-read
   directives (lint pragmas, region markers, shebangs), `TODO(#issue)` markers tracking
   real work, and an opt-out marker (mirroring `audit-comment-residue`'s
   `comment-residue-ignore` convention).
9. **File scope:** code files only, language-agnostic; markdown excluded
   (`docs-hygiene` territory). Plus the plugin's standard path-exclusion tier mirroring
   `tidy`'s `exclusions.md`: `.claude/settings*`, hooks, `.github/workflows/**`,
   lint/enforcement config are never edited autonomously.
10. **Never flags missing comments** — the add-side belongs to `tidy` #14.
11. **Name:** `dissolve-comments` (`/code-tidying:dissolve-comments`) — picked by the
    user from a blind three-lens `/naming:name-it-better` shortlist (all three lenses
    independently derived it). Criteria honored: semantically correct, explicit over
    implicit — a dissolved comment's information passes into the code before the husk
    is removed.
12. **Safety tiers (operating modes):** the risk that behavior-preserving refactors
    still break something is managed as layers, not a single gate, without hamstringing
    the default:
    - **`safe` mode (explicit argument):** comment removals only — class-A deletions
      apply; nothing that changes code structure is applied (class-B treatments are
      emitted as proposals). For consuming codebases whose guardrails are unknown.
    - **Default mode:** the full contract as decided — class A applies; class B applies
      behind the tests gate (decision 5), else proposed. This remains the primary,
      expected mode: consumers with tests, audits, and quality checks in place get the
      whole enforcement pass.
    - **Never, in any mode:** applying a class-B refactor with no discovered test net,
      or touching exempt/excluded surfaces (decisions 7-9).

### Constraints

- Fences hold: `audit-comment-residue` remains the read-only residue classifier;
  `tidy` keeps its lane/PR machinery (#14/#15); `docs-hygiene` owns markdown;
  `batch-simplify` owns windowed batch sweeps. The new skill's description must carry
  explicit skip-when fences naming these.
- Class-B edits are behavior-preserving refactorings only; no semantic changes.
- No component may recommend generation-time comment bans (comments are useful model
  context at generation time; the research's comments-as-model-context finding).

### Acceptance criteria

- Running the skill on a diff containing class-A comments removes them without touching
  surrounding code.
- Running it on a class-B comment with a discoverable test net produces the named
  refactoring, a passing test run, and the comment's deletion; without a test net it
  produces a proposal, no applied class-B edit.
- Class-C comments passing the earn-its-keep test, public-API doc comments, sanctioned
  exceptions, and excluded paths emerge untouched from any run.
- Stripped narrative appears in the skill's output as a proposed commit-message block
  whenever a justification comment is removed.
- The skill passes `/skill-quality:check` and its description carries the skip-when
  fences.

### Captured assumptions

- Agent over-commenting is dominated by class A and cheap class B (research-backed:
  practitioner consensus + vendor guidance), so the enforcement posture is safe given
  the class-C keep rules.
- The consuming repos' test conventions are discoverable enough for the class-B gate;
  where they are not, propose-only is an acceptable degradation.

### Out-of-scope

- Flagging or adding missing comments (Ousterhout direction; `tidy` #14 owns adding).
- Markdown/prose comment hygiene.
- Editing public-API doc comments in any way.
- Batch/branch-window sweeps (`batch-simplify` composes instead).
- Any change to the existing sibling skills beyond cross-referencing fences.

### Deferred questions

None. (Q16, the final name, was USER-RESERVED and resolved 2026-08-17: the user picked
`dissolve-comments` from the naming shortlist — recorded in decision 11.)

## Plan

*(Empty — `/planning:plan` fills this section.)*
