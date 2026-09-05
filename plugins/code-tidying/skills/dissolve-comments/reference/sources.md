# Sources

The doctrine this skill enforces, with what each source contributes. Read the whole passage before
citing any of them: two of these were misread from a fragment during authoring, and a quoted rule is
not a scoped rule.

- [Fowler, Comments smell, Refactoring 2nd ed. excerpt](https://www.informit.com/articles/article.aspx?p=2952392&seqNum=24),
  "refactor the code so that any comment becomes superfluous".
- [Fowler, refactoring catalog](https://refactoring.com/catalog/), the named dissolving moves.
- [Ousterhout ⇄ Martin debate](https://github.com/johnousterhout/aposd-vs-clean-code), the
  jointly-signed floor ("implementation code only needs comments when the code is nonobvious") and
  the class-C boundary. Martin's "comments are always failures" is his alone and is not built on.
- [Google eng-practices, comments explain *why*, not *what*](https://google.github.io/eng-practices/review/reviewer/looking-for.html).
- [Anthropic prompting best practices, Overeagerness](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices),
  "Only add comments where the logic isn't self-evident". That sentence sits inside
  anti-overengineering guidance whose sibling bullets say "Don't add features, refactor code, or
  make 'improvements' beyond what was asked" and "Don't create helpers, utilities, or abstractions
  for one-time operations". It authorizes the *removal* half of this skill and constrains the
  *refactoring* half. It is not blanket authority for either.
- [Ousterhout, A Philosophy of Software Design §12.6](https://web.stanford.edu/~ouster/cgi-bin/aposd2ndEdExtract.pdf),
  the author-published rebuttal to "comments are always failures", and the 10-100x
  missing-versus-incorrect cost asymmetry behind this skill's conservative tie-break.
- [Kernighan & Pike, The Practice of Programming §1.6](https://archive.org/details/practiceofprogra0000kern),
  "Don't comment bad code, rewrite it", and the counterweight that comments legitimately "collect
  into one place information that is spread through the source".
- [Henney, Comment Only What The Code Cannot Say, ACCU Overload 28(157)](https://accu.org/journals/overload/28/157/henney_2796/),
  the stricter test (what the code *cannot* say, not merely what it does not say) and the second
  verb: a failing comment is "removed **or rewritten**". The class-C line budget rests on that verb.
- [Wayne, The Myth of Self-Documenting Code](https://buttondown.com/hillelwayne/archive/the-myth-of-self-documenting-code/),
  the negative-information and operational-information categories no encapsulated unit's code can carry.
- [Google Testing on the Toilet, To Comment or Not to Comment?](https://testing.googleblog.com/2017/07/code-health-to-comment-or-not-to-comment.html),
  the four-move dissolve ladder and the four keep-cases, stated as an operational checklist.
- Abdelsalam, Peitek, Bergum, Apel, *The Effect of Comments on Program Comprehension: An Eye-tracking
  Study*, Empirical Software Engineering, [doi:10.1007/s10664-025-10721-2](https://doi.org/10.1007/s10664-025-10721-2):
  comments moved comprehension performance from a 30% decrease to a 34% increase depending on the
  snippet, with no population-level effect. No blanket policy in either direction is empirically
  licensed, which is why every treatment here is per comment.

Ranking and census sources are listed in [tooling.md](tooling.md) and in the header of
`${CLAUDE_PLUGIN_ROOT}/scripts/rank-comment-targets.py`.
