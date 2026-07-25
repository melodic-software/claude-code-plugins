# Triage — 3-Bucket Classifier

After running the pattern library from `patterns.md`, every match goes into one of three buckets. Triage logic is the difference between mass-mangling prose and a clean rename.

## Bucket 1: Certain (auto-apply candidate)

Match patterns where the rename intent is unambiguous regardless of surrounding context.

**Bucket criteria:**

- Form 1: slash-prefixed token (`\B/<old>\b`) — slash-tokens are skill names by convention; token in `<old>` position is virtually never an English word with a leading slash
- Form 3: path references (`context/<old>.md`, `skills/<old>/`, and a container-root segment
  ending in the token, `plugins/<old>`) — paths are inherently specific
- Form 8: frontmatter glob set (`{a,b,<old>,c}`) — brace enumeration is a glob construct, not English prose
- Forms 13–15 (container-position) — but ONLY the alternatives their own form rates Certain.
  Form 13's management-verb alternative, a Form 14 title in a container-owned file with an
  uncommon token, a Form 14 manifest/catalog `name` declaration (exempt from the scope rule), and
  Form 15 where the token is not a common noun. The demoted alternatives land in Bucket 2 or
  Bucket 3 below; `patterns.md` "Phase 0" carries the per-alternative table

**User flow:** present count and 1-2 example matches via `AskUserQuestion`. Two options: "auto-apply N matches" or "review one-by-one." Default: auto-apply.

**Why default-apply:** these forms have near-zero false-positive rate empirically. Treating them as ambiguous burdens the user without value.

## Bucket 2: Chain-context (review-recommended)

Match patterns where rename intent is highly likely given surrounding context, but verification is cheap and the cost of a wrong rename in chain prose is high (workflow documentation drift).

**Bucket criteria:**

- Form 4: chain prose forward (`(?:→|->|,| and ) <old>`) — plausibly a rename target if neighbors are also identifiers
- Form 5: chain prose backward (`<old> (?:→|->|,| and )`) — same
- Form 6: numbered table row (`| <N>. <old> |`) — workflow step tables
- Form 7: frontmatter chain string — when token appears alongside other workflow tokens
- Form 9: PascalCase comma-list — comma-separated capitalized identifiers
- Form 10: cross-skill mode reference (`/<other-skill> <old>`) — references to a mode of another skill
- Form 13's **bare qualified-id** alternative (`<old>@<slug>`, no management verb in front) — the
  shape cannot separate a marketplace-qualified id from a dotless email address, and Certain
  auto-applies, so this is where it belongs. `patterns.md` "Form 13" owns the rationale and the
  promotion test

**Refinement — neighbor-aware classification:**

For chain forms (4, 5, 6, 9), check whether at least one neighboring token (within 5 chars before or after the separator) matches a known skill or command name in the consuming repository (e.g., `name:` frontmatter across `.claude/skills/*/SKILL.md`, installed plugin skill listings). If yes, promote confidence — these are workflow chain references, near-certain rename targets. If no, demote to ambiguous.

**Form 13's qualified-id alternative uses its OWN promotion test, not the one above.** It has no
separator and no chain neighbors, so the 5-char skill-name check does not apply to it. Promote it
to Certain only on the single per-occurrence signal `patterns.md` "Form 13" names — the occurrence
IS a key in an `enabledPlugins` / `pluginConfigs` map. A management verb elsewhere on the LINE does
not promote it: the verb may govern a different plugin entirely, and one that governs this
occurrence is already Certain under the management-verb alternative. **A failed promotion leaves it at
Chain-context; it does NOT fall through to Ambiguous** the way a chain form does. Chain-context is
this alternative's floor, because the form is high-recall and its risk is auto-application, not
misclassification.

**User flow:** present matches in groups of up to 10 with 2-line context per match. Three options via `AskUserQuestion`: "auto-apply all", "review one-by-one", "skip bucket".

**Why not auto-apply:** chain prose appears in user-facing documentation (CLAUDE.md, AGENTS.md, README files). A wrong rename in a workflow diagram is loud and embarrassing. The cost of one round of confirmation is much lower than the cost of breaking the diagram.

## Bucket 3: Ambiguous (mandatory per-match confirmation)

Match patterns where the token is a common English word AND surrounding context doesn't strongly disambiguate. These are the highest false-positive vector.

**Bucket criteria:**

- Forms **14 and 15** (container-position) when the matching form's own scope rules demote it — a
  Form 14 title match outside a container-owned file or with a common-word token, a Form 15
  possessive where `<old>` is a common noun. Span-precedence attributes the occurrence to that
  form; it does NOT override the form's demotion (`patterns.md` "Phase 0"). A Form 14
  manifest/catalog `name` declaration is NOT demoted here — the scope rule and the common-word
  rule both exempt it, because the key is the registration rather than evidence of one.
  **Form 13 is deliberately absent:** its demoted alternative lands in Bucket 2, not here
- Form 2: bare token (`\b<old>\b`) when `<old>` is in the English-verb blocklist — and, under
  container-rename mode, the bare-token residue is excluded from Certain entirely rather than
  bucketed here per match (`patterns.md` "Phase 0b")
- Form 4/5/6/9 (chain forms) when no neighbor is a known skill name (failed promotion check above)
- Form 7: frontmatter chain string when token appears alone in description without other workflow tokens

**English-verb blocklist** (force ambiguous regardless of pattern position):

```text
confirm, test, review, fix, clean, build, lint, verify, plan, explore,
research, implement, retro, render, view, list, run, sort, filter, group,
merge, split, drop, pop, push, get, set, post, delete, put, head, body,
link, work, stop, start, pause, resume, log, watch, monitor, check,
validate, audit, compare, debug, trace, profile, scan, search, find,
load, save, copy, move, write, read, parse, render, print, format,
```

(Extend as new collisions surface.)

**Verb-sense collision the blocklist cannot serve.** The blocklist is a static list of tokens
that are English verbs *in general*. It cannot cover a token that is a verb **in the consuming
codebase** — a coined or hyphenated term the project uses verbally hundreds of times. Both
branches fail for such a token:

- **Absent from the blocklist** → every bare-token hit is rated Certain, so the sweep proposes
  rewriting the verb uses.
- **Added to the blocklist** → every hit lands ambiguous, and the per-match rule below turns a
  handful of real defects into hundreds of confirmation prompts.

Extending the blocklist is therefore the WRONG remedy here; it swaps one unusable bucket for
another. The remedy is position: `patterns.md` Forms 13–15 anchor on syntax that only the
container sense can occupy (argument-to-a-management-command, a heading that IS the token, the
possessive clitic), so they stay Certain regardless of blocklist membership.

Measured on the `re-anchor` → `discipline` rename, over that plugin's own tree: Form 2 matched
134 lines for 8 real defects; Forms 13–15 matched 9. Reach for a position-anchored form before
reaching for the blocklist.

**Position-anchoring alone does not finish the job.** Forms 13–15 resolve only the lines they
match; the remaining bare-token lines still reach Form 2 and take its Certain default. What
removes them is `patterns.md` "Phase 0b — container-rename mode": when the renamed thing is a
container, bare-token position carries no signal at all, so the residue is excluded from Certain
and reported as an aggregate rather than as prompts. Mode is decided by WHAT is being renamed,
which is why it works where the blocklist cannot — it does not depend on anyone having listed
the token in advance.

**User flow:** present each match individually via `AskUserQuestion` with 3 lines of surrounding context. Three options per match: "rename this", "skip this", "skip remaining ambiguous". Always one-by-one — batched confirmation defeats the safety purpose.

**Why per-match:** "the user just renamed the `confirm` skill" does NOT mean every English use of "confirm" should be replaced. The incident that motivated this skill contained dozens of legitimate "confirm" verb uses (research vocabulary, user-confirmation prompts, domain logic) that MUST be preserved. Per-match confirmation lets the user catch each.

## Special case: Rename-documenting plan docs

Auto-exclude any match in the active plan/work-notes documents that document THIS rename (a plan file, migration notes, a changelog entry drafted for the rename) from ALL buckets. Those documents *document the rename*; both old and new names appear by design in scope tables, success criteria, and decision logs.

Identify these documents from conversation context and the consuming repository's work-notes conventions (its CLAUDE.md / rules). When in doubt, exclude the file that documents the rename and report it in the Excluded row so the user can widen scope deliberately.

## Special case: Frozen historical records

Auto-exclude archived/completed work notes and frozen records of past work (finished plan documents, past changelog entries, retired design notes) — they are a frozen-in-time record of finished work. If the consuming repository marks work-notes status in frontmatter or by directory convention, use that signal; otherwise treat clearly-archived paths as frozen.

## Special case: Memory entries

Claude Code auto-memory entries at `~/.claude/projects/*/memory/*.md` and `MEMORY.md` indices describe past renames as part of the user's institutional knowledge. They are intentionally append-only historical record.

Auto-exclude all memory paths from sweeps. If user explicitly wants to rename within memory (rare), they must opt in: `/rename-references <old> to <new> --include-memory`.

## Reporting bucket counts

After triage, present a summary before any Edit calls:

```text
Rename: <old> → <new>
Sweep results across <N> tracked files:

| Bucket          | Count | Default action       |
|-----------------|-------|----------------------|
| Certain         | <X>   | Auto-apply           |
| Chain-context   | <Y>   | Review-recommended   |
| Ambiguous       | <Z>   | Per-match confirm    |
| Excluded        | <W>   | Skipped (plan-docs/historical/memory) |

Proceed?
```

Use `AskUserQuestion` to gate the proceed/abort decision.
