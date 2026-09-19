# Tiers and the form table

A tier answers one question: inside this set of paths, which shapes of reference
may be rewritten when the file they name is renamed?

Print the table below before presenting any plan. An operator approving a rename
is approving what happens to every citation of it, and the tier is what decides
that.

## The three forms

| Form | Rewrites | Leaves alone |
|---|---|---|
| `all` | every shape: markdown links, backtick paths, absolute URLs, table cells, key lines, running prose, and unambiguous bare stems | nothing |
| `links-and-paths` | markdown links, backtick paths, and absolute URLs | running prose and bare stems, so the narrative reads as it was written |
| `none` | nothing | everything; sites are listed and never touched |

A file belongs to the declared tier whose matching pathspec has the most path
segments, ties going to the earlier entry. A file no tier claims belongs to the
implicit `current` tier, whose form is `all`. A tree that declares no tier at all
therefore still gets every reference repointed, which is the right default for a
repository with no historical record to protect.

## Why a historical tier keeps its links

A decision record, a specification, or an upstream note is evidence of what was
decided and when. Rewriting its prose edits the record. Leaving its links broken
makes the record unusable. `links-and-paths` is the split that keeps both: the
sentence stays as written, and the link it carries still resolves.

## Why a released tier is frozen by default

A published changelog entry is a statement about a version that already shipped.
Editing one changes what the project said about a release after the fact, and
some repositories gate exactly that. The default is `none`, and the plan lists
every frozen site so a maintainer who does want one changed can do it
deliberately, declare it, and say so.

## Bare stems and the review action

A bare stem is the file's name with no extension, matched only where the
surrounding characters are not name characters. Two rules keep it safe:

- Maps apply longest old name first, and the anchor consumes the surrounding
  character, so a rename of `catalog` can never reach inside `catalog-taxonomy`.
- A stem that is one dictionary-shaped word (no hyphen, no digit) is marked
  `review` rather than `edit`, because such a stem also appears as an ordinary
  English word in prose that has nothing to do with the file.

A `review` site is never written by the realign. Escalate it singly, with its
line, and let the operator say whether it names the file.

## Generated files

A path the concern file lists as generated is never text-edited, whatever tier
claims it. Its sites are marked `regenerate`, and the realign runs the declared
command after the move. A generated record often stores a sorted sample or a
derived index, so a substitution that looks correct leaves a stale value no
reader would notice.

## Per-site exclusions

`sweep_exclude_sites` carries `path:literal` pairs the sweep marks `skip`. It is
the reproducible form of a hand decision: a line whose text matches an old name
by accident, in a file whose real references still need rewriting. Excluding the
whole file by path would hide those too.
