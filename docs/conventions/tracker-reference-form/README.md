# Tracker reference form — what a code comment may say about an issue

Owner doc for how a tracker reference is written inside a **code comment**. The rule is enforced
in CI by the `comment-hygiene` composite action, which this repository consumes from
`melodic-software/ci-workflows` at a SHA pinned in
[`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml). That pin is the version of the
policy in force; this doc describes its shape, and the action remains the source of truth.

The reason this convention needs a written home: **the lane cannot be run locally.** The action is
not vendored here, so no local command reproduces it, and a violation is discoverable only after
pushing. Authors need the shape up front rather than from a red lane.

## The shape

Use the **bare parenthesised form** — `(#1491)` — to attach an issue number to a comment. It is
not a tracker reference by the policy's definition and is used throughout this repository.

These forms are rejected in a scanned file's comments:

| Rejected | Example |
| --- | --- |
| `owner/repo#N` | `melodic-software/ci-workflows#12` |
| `PR #N` | `PR #3011` |
| `GH-N` | `GH-45` |
| A closing keyword plus a number | `fixes #12`, `resolves #42`, `closed #7` |
| `issue` / `issues` / `tracked` plus a number, `#` optional | `issue 88`, `tracked #3` |
| The internal marker | `cc-issue` |

The intent behind the list: outstanding work belongs in the tracker, where it stays current, rather
than in a comment that no process revisits.

## Where it applies

Only to an allowlist of code extensions — at the pinned version: `.cs`, `.ts`, `.tsx`, `.js`,
`.jsx`, `.mjs`, `.cjs`, `.mts`, `.cts`, `.py`, `.sh`, `.ps1`, `.razor`, `.cshtml`.

**Markdown and YAML are not scanned**, which explains apparent counterexamples in the tree: a
`PR #N` in a workflow comment and an `owner/repo#N` in `dependabot.yml` both sit outside the
allowlist and pass. Do not read those as evidence the rule is lax — read them as evidence the rule
is scoped. A skill's `SKILL.md` is likewise outside it.

One path is excluded by configuration rather than by extension: `code-tidying`'s
`audit-comment-residue` scripts, because that skill is itself a comment linter and its fixtures must
contain the banned markers as test corpus.

## What this convention is not

- Not a commit-message or PR-title rule. Those are [`commit-convention`](../commit-convention/README.md);
  a PR body may reference issues freely, and the linkage gate in fact requires a closing keyword there.
- Not a ban on issue numbers in comments. The bare `(#N)` form exists precisely so a comment can cite
  its origin.
- Not locally enforceable. Check the form by reading it before pushing; there is no local command.

## Conformance

Comments added to scanned files use the bare form. When adding a reference, grep the change for the
rejected shapes first — cheaper than a CI round trip on a lane that only runs remotely.
