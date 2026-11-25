# Keep a role chain's standing rules in one gitignored file the resume loads first

- Status: accepted
- Date: 2026-11-22
- Related: [ADR 0115](0115-write-handoff-shape-4-with-binding-sections-first-and-a-tool-owned-byte-budget.md)
  (decision 2 stands),
  [#17277](https://github.com/melodic-software/claude-code-plugins/issues/17277) (the need),
  [#18140](https://github.com/melodic-software/claude-code-plugins/issues/18140) (part 1, this
  change)

## Context

A handoff audit on 2026-11-18 found a GitHub monitor chain at hop 136 writing handoff files of
about 285 KB. That is 11 times the 24,600-byte handoff-file cap and past the Read tool's page size.
Its rules alone hold a median of about 88 KB. Its state is standing memory for an ongoing role,
not a snapshot of one phase, so the fit that moves movable sections cannot help: rules are
binding and never move (ADR 0115 decision 2).

## Decision

The owner chose option (b) on 2026-11-22 ("Go with recommendations", recorded on #18140).

1. **One standing-rules file per role chain.** `save_point.py new --standing-rules` marks a
   shape-4 chain as a role chain through the `standing_rules` frontmatter key, which every later
   hop carries. `fill` writes Current rules and Standing preferences to
   `archive/<chain-root-stem>/standing-rules.md`, beside the chain's archive files in the same
   gitignored memory tier.
2. **The handoff file keeps a pointer in place.** Each of the two sections stays in its binding
   position, holding one `- Standing rules: <file>#<section>` line. Section order, ids, rewrite in
   place and `retire` are unchanged.
3. **The resume loads the rules first.** The directive reads `Read @<standing-rules file> then
   @<handoff file>, …`, and tells the reader to page the standing-rules file when it is over one Read
   page.
4. **No rule is lost silently.** `new` copies the predecessor's rules into the new archive file as
   before, so each archive file keeps a frozen copy of them. `validate` checks carried rules against
   that copy and reads an older handoff file's rules from its successor's archive file, since each `fill`
   rewrites the shared file.

## Alternatives considered

- **(a) A committed per-role instruction file.** It would publish role rules in a public
  repository and needs a path decision. Not chosen.
- **(c) Let Current rules overflow behind a pointer.** That reverses ADR 0115 decision 2. Not
  chosen.

## Consequences

- A role chain's handoff file drops by the size of its rules. A goal section that is itself past the
  cap still has to shrink through `retire` or by codifying amendments as rules.
- The resume loads two files. The standing-rules file can still pass one Read page, and its
  directive then says to page it.
- `read --section` on a pointer reads the file as it is now, the tip's rules, not an older hop's.
- A role chain cannot fork: `fill` and `amend` refuse a hop when another session's handoff follows
  the same predecessor, since both would rewrite the one file.
- Whether this passes the parent issue's gates (the headless resume eval and a before-and-after on
  real sessions) is left to the rest of #17277.
