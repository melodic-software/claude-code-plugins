# Abstract provider details in skills behind the consumer's conventions and adapters

- Status: accepted
- Date: 2026-10-10
- Supersedes: the GitHub-only rulings recorded on closed issues
  [#441](https://github.com/melodic-software/claude-code-plugins/issues/441) and
  [#416](https://github.com/melodic-software/claude-code-plugins/issues/416) (no ADR held them)

## Context

Two earlier rulings, both closed as not planned in August 2026, accepted GitHub-only behavior in
skills meant to be generic:

- **#441** ruled that `source-control`'s `pull-request` and `babysit-prs` stay GitHub-only "as
  declared", because building a forge seam ahead of any non-GitHub consumer was speculative. Reopen
  trigger: a real GitLab, Bitbucket or Azure DevOps consumer asks.
- **#416** left `/planning:wayfind` and the `/planning:plan` tracker-write template calling `gh`
  directly instead of the work-item-tracker seam, deferred until wayfind was staffed for seam
  adoption.

Neither trigger has fired. The user's standing rule now overrides both: provider details (GitHub, a
tracker, a CI system) in any skill are implementation details, and belong behind the consumer's
conventions, policies and adapters. That reverses recorded rulings, so it is recorded here rather
than applied silently.

The evidence is a read-only audit of `main` on 2026-10-10 (`melodic-software/knowledge-corpus`
PR #36, `.work/youtube-watch/new-skills-v1-3-brings-pr-implement-spec-BsJGo1wFTvQ/deep-dive/verify/R-C-provider-coupling.md`):

- **Trackers have a seam; forges do not.** The work-item-tracker seam
  (`plugins/work-items/tools/work-item-tracker/CONTRACT.md`, adapters for github, gitea, jira,
  linear and local-markdown) covers coordination verbs. Pull requests, CI checks, reviews and merges
  have no abstraction; `source-control` owns them and is GitHub-specific throughout.
- **Generic skills call `gh` directly for forge and tracker work**: wayfind and the plan template,
  `review:explain-change` and `quality-gate` (pr, close-out), `improvement:improve`,
  `session-flow:clean-stop` and its `tidy_work.py`.
- **The change-to-item link text is GitHub's grammar everywhere.** `Closes #N` and a branch pattern
  capturing "the numeric GitHub issue number" are written into work-items and
  `source-control:pull-request`, though the link depends on the tracker (a Jira key is not `#N`).
- **The portability lint already holds the detector.** `scripts/check-skill-portability.sh` with
  `scripts/skill-portability-tokens.txt` carries a staged, commented-out `gh` class, to be enabled
  "once the seam-routing members land".

## Decision

**Provider details in skills are implementation details, always.** A skill names the operation the
consumer needs (open a draft change request, read the head's CI status, link a change to its work
item). The provider's commands, API fields and grammar sit behind the owner of that operation, and
the consumer's conventions, policies and adapter binding select the provider.

**Contain the coupling now; do not build a full forge seam yet.** Containment has three parts, each
tracked by its own issue:

1. **Generic skills hand provider work to its owner.** Forge work (change requests, CI, reviews,
   merges) goes to `/source-control:pull-request` actions; tracker work goes to the work-item-tracker
   seam or its adapter. A generic skill does not name `gh`. Tracked in
   [#6936](https://github.com/melodic-software/claude-code-plugins/issues/6936).
2. **The tracker adapter owns the change-to-item link text and the branch item-ID pattern.**
   `Closes #N` on GitHub, an issue key on Jira: skills ask the bound adapter instead of hardcoding
   either. Tracked in
   [#6937](https://github.com/melodic-software/claude-code-plugins/issues/6937).
3. **`source-control` uses neutral operation wording, with GitHub commands under
   `reference/providers/github/`.** Skill bodies say what is done; the provider reference says how
   GitHub does it. Behavior does not change. Tracked in
   [#6941](https://github.com/melodic-software/claude-code-plugins/issues/6941).

**A full forge seam waits for a named second-forge user.** A dispatcher, verb-per-script adapters
and a conformance suite for forges, mirroring the tracker seam, are built only when a named
consumer needs `source-control` on a forge other than GitHub. Its contract is then scoped from that
forge's actual API.

**Enabling the staged `gh` portability lint rule is a separate decision**, made at the end
of #6941 with its own justification: who the rule blocks and what they do with its output. This ADR
does not turn it on.

**Declared-provider surfaces stay as they are.** A plugin or skill whose purpose is one provider
(the `github` plugin, `repo-fleet-hygiene`, the CI review lanes a GitHub workflow invokes, adapter
files) is not a generic skill and keeps its provider details.

## Alternatives considered

- **Keep the #441 and #416 rulings and apply the rule only to new skills.** Rejected: existing
  generic skills would keep hardcoding GitHub, and every new skill would copy their precedent.
- **Build the full forge seam now.** Rejected for now: with one forge in use, the contract would be
  shaped by GitHub alone and frozen while the PR surface is still changing. The tracker seam earned
  its contract across several adapters and a conformance suite; a forge seam needs at least one real
  second forge to do the same.
- **A `forge` key in `.claude/source-control.md` selecting a provider reference set.** Deferred: it
  selects between nothing until a second provider reference set exists. It is the first step of the
  full seam, under the same trigger.

## Consequences

- #441 and #416 stay closed; this record replaces their rulings. Their reopen triggers no longer
  gate the containment work above.
- The containment work is ordered: #6936 and #6937 first, then #6941, which rewrites
  `source-control` after the pull-request edits land.
- A non-GitHub tracker gets correct change links once #6937 lands, without a forge seam.
- A non-GitHub forge is still unsupported after containment, but adding it becomes adding a provider
  reference set and one code module, not editing every generic skill.
- Reviewers apply the rule to new skill text now: a generic skill that names `gh` or GitHub grammar
  is a finding, unless it sits behind the owner of the operation or in a declared-provider surface.
