---
bump: minor
---

### Fixed

- `tidy` no longer describes the PR body as fixed to `Summary` and `Test plan`; it hands `/source-control:pull-request create` the facts and that skill writes the body from the repo's configured sections.

### Added

- `audit-comment-residue` reports a new Tier 2 shape, `unjustified-workaround`: a comment that names a workaround and gives neither a link (a URL, an issue or PR number, an RFC) nor a removal condition (`until`, `remove when`, `once ... ships`). A link or condition on any line of the same comment run justifies the run, and a workaround comment's own issue reference is no longer reported as `ticket-pr-residue`.
- `audit-comment-residue` and `dissolve-comments` take `--added-since <base>`, which limits the run to comments on lines the branch adds against the merge base of `<base>` and `HEAD`. The ranges come from the new read-only `scripts/added-lines.sh`.
- `dissolve-comments` has a `report` token that applies nothing and asks nothing: every treatment is a proposal, a constraint comment gets a regression-test or lint-rule proposal, and lint-rule proposals are written as a findings file under `<memory_dir>/comment-pass/<branch-slug>/` for `/review:audit-enforceability`.
- `dissolve-comments` lists each workaround comment it removes or proposes to remove as open root-cause work, in every mode.

### Changed

- **`aggressive` keeps two more kinds of comment.** A comment on behavior a dependency, platform, vendor service or protocol forces, and a comment whose issue or RFC link explains a constraint, now survive `aggressive` within `class_c_max_lines`. Before, `aggressive` deleted another system's limit or an upstream's behavior as rationale. A survivor that names a workaround still needs a link or removal condition. `strip` is unchanged.
- tidy's #14 example workaround comment carries a removal condition, so it no longer reads as an unjustified workaround.
- **`dissolve-comments` re-checks a kept claim against the code.** Before a constraint, warning, contract or thread-safety comment is kept, step 5 reads the code it describes; a claim the code now contradicts is obsolete (class A) and is deleted or proposed under the mode's class-A rule. A claim the code cannot settle goes to `/discovery:trace-intent` when it is among the available skills; one still open is reported as unverified and then goes through the class-C criteria like any other comment.
