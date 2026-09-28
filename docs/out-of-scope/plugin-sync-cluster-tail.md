# Plugin-sync cluster operator-gated tail

Recorded park for
[#4186](https://github.com/melodic-software/claude-code-plugins/issues/4186),
the operator-gated remainder of the claude-ops plugin-sync cluster (#3688
follow-ups, post-wipe tracking).

**Decision.** This marketplace checkout has no remaining easy gated item from
that list. Every row below is either another repository, an upstream
marketplace, user-scope settings, or a structural change gated on a
ci-workflows release. Do not implement any of them from this repo. Do not
open cross-repo fleet PRs from this change.

## Adjacent drift list

| Id | Item | Owner | Disposition |
|---|---|---|---|
| (a) | `claude-code-account-rotation` SessionStart hook + marketplace via standards sync | `melodic-software/standards` (and possibly github-iac) | Park. Cross-repo fleet; unprobed whether already tracked. |
| (b) | ci-workflows `release.yml` error text points at a file that exists | `melodic-software/ci-workflows` | Park. Mechanical wording, wrong checkout. |
| (c) | ci-workflows README version line (`v0.7.0`) | `melodic-software/ci-workflows` | Park. Wrong checkout. |
| (d) | standards managed-files-guard README acceptance bullet naming `dependabot[bot]` | `melodic-software/standards` | Park. Wrong checkout. |
| (e) | github-iac `.github/dependabot.yml` ignore widened to `melodic-software/ci-workflows/*` | `melodic-software/github-iac` | Park. Wrong checkout. |
| (f) | ci-workflows #590 header sentence on consumer repins | `melodic-software/ci-workflows` | Park. Wrong checkout. |
| (g) | claude-bot plugin SessionEnd hook path | `claude-community` marketplace (upstream) | Park. Not this marketplace; disable-or-file is an operator action on the installed plugin. |

## Waiting on a ci-workflows release

| Item | Disposition |
|---|---|
| Structural managed-files-guard fix: move `actions/checkout` into the composite action and drop the step from the standards component | Park. Operator-gated on a ci-workflows release; not this checkout. |

## Operator-only

| Item | Disposition |
|---|---|
| Add `"Bash(gh pr merge *)"` beside the other `gh pr` rules in `~/.claude/settings.json` | Park. User-scope config; a session cannot add it (classifier denies self-modification). Fresh-host settings seeding, not a marketplace PR. |

## In-repo remainder of #3835

The last open thread the tracking issue named in this marketplace is #3835
(orphan-sweep observation). That probe is recorded separately; it is not an
item on the list above.

- **Claim:** no #4186 item is implementable in `melodic-software/claude-code-plugins`;
  the tail stays parked in its owning repos until an operator go there.
- **Basis:** #4186 body (items a–g, managed-files-guard, operator settings);
  each owner column is a repository or surface this checkout does not write.
  The shipper skip list names cross-repo fleet as out of scope.
- **As of:** 2026-09-28.
- **Recheck:** an operator go that names a specific owning repository and a
  branch in that repository, or #3835 closing with an observed sweep.
