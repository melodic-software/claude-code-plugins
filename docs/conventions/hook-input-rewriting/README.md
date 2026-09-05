# Hook input rewriting — deny or ask, never a silent rewrite

Owner doc for what a `PreToolUse` hook may do to a tool call it disagrees with. The
[plugin philosophy](../../PLUGIN-PHILOSOPHY.md) owns the posture rule — an advisory hook is a nudge,
a guard must not block legitimate work — and [hook precision](../hook-precision/README.md) owns
what a hook matches. This doc owns the one question those two leave open: when a hook can see both
that a call is wrong and what the right call would be, is it allowed to substitute the right one?

It is not. The rule is one line, and the rest of this doc is why.

## The rule

**A `PreToolUse` hook denies or asks. It never pairs `allow` with `updatedInput`.**

A `PreToolUse` hook's decision-control fields are `permissionDecision` (`allow`, `deny`, `ask`),
`permissionDecisionReason`, `updatedInput`, and `additionalContext` (verified against
[the hooks reference](https://code.claude.com/docs/en/hooks), 2026-09-04). Three of them are
uncontroversial. `updatedInput` is the one that lets a hook rewrite the call, and its only
sanctioned pairing here is with `"ask"`.

The concrete case this rule was written against: a commit guard that can tell a non-canonical
`git commit -m "…"` from the canonical form, and could simply substitute the canonical one. It
would work. It is still refused.

## Why

**Principle of least astonishment.** A silent rewrite means the command that ran is not the command
anyone wrote. The agent's transcript records one call, the shell ran another, and nothing in
between says so. The next debugging session starts from a false premise, and the person debugging
it has no reason to suspect the hook — a rewritten call looks exactly like a call that was never
inspected. A denial is legible: the call did not run, and the reason says why.

**`updatedInput` replaces the ENTIRE input object, not the field you meant.** A hook returning it
hands back a whole tool input, and a field the hook did not think to carry forward is a field the
tool no longer receives. This is the failure mode that gets worse as the tool's schema grows,
because the hook was written against the schema of the day it shipped.

**Permission rules are re-evaluated against the HOOK's version, not the user's.** The rewritten
input is what the permission layer then judges. A rewrite that widens a call — even accidentally,
even while narrowing the part the hook cared about — is a rewrite that can clear rules the original
call would have tripped. A guard that can launder a call past the permission layer is not a guard.

## The sanctioned escape hatch

`updatedInput` paired with `"ask"`. The modified input is surfaced for confirmation before it runs,
which restores everything the silent form removes: the person sees the substitution, the transcript
records that a substitution was offered, and the permission re-evaluation happens against something
a human has actually looked at.

Use it when the hook genuinely knows the right call and the correction is worth the interruption. A
hook that would rather not interrupt should deny and say what to do instead: a denial's reason
reaches Claude as the blocking explanation — by the JSON field, or by stderr on an `exit 2`, which
route identically — so the agent can reissue the call itself. That is what makes "deny with
instructions" a complete answer rather than a dead end, and it is why no hook here needs to rewrite
a call to get the right one run.

## Boundary

- **Not about `PostToolUse`.** A `PostToolUse` hook that reformats a file it just observed being
  written is a deterministic transform on an artifact, not a rewrite of a call — that is the
  formatter plugins' whole job and it is unaffected.
- **Not about `additionalContext`.** Adding text for the model to read changes no call and is
  governed by [hook observability](../hook-observability/README.md).
- **Not a claim that `updatedInput` is broken.** It is a documented field with a real use; this doc
  narrows WHEN this marketplace reaches for it, and pairs it with `ask` when it does.
- **Not a substitute for precision.** A hook that rewrites because its match is too broad has a
  precision defect, not a rewriting question. Fix the match.

## Conformance

Today every `PreToolUse` hook in this marketplace conforms, and none emits `updatedInput` at all:
the guards deny (`exit 2` or a JSON `deny`, which route identically — Claude sees the stderr message
as the denial reason), and the two that ask emit `"ask"` with no rewrite. `block-noncanonical-commit`
is the conforming instance of the motivating case: it can identify the canonical form and it denies
with instructions rather than substituting it.

A hook that adds `updatedInput` must pair it with `"ask"` and say in its own header comment why the
interruption is warranted.
