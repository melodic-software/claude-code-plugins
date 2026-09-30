# sonnet-5-5-adoption

## Brief

### TLDR

Act on the verified digest of the claude.dev post "Building with Claude Sonnet 5.5" (2026-09-28),
limited to what only that post drives. Everything the Sonnet 5.5 prompting guide drives belongs to
the `feat/sonnet-5-5-prompting-digest` branch; this branch turns three stale restated facts into
doc pointers and fixes the usage-limit reset checker now, closes out the digest slice, and adds
the post's own records after that branch merges. The blog extractor ships in that branch's PR.

### Goal

Remove the repo's stale Sonnet 5.5 facts that only this post surfaced, fix the one tooling defect
with a known fix, and record the post as a source, without colliding with the peer branches that
own the guide-driven changes.

### Constraints

- Files are owned by source article. This branch edits only blog-only paths; the Prompting Sonnet
  5.5 branch owns the Sonnet 5.5 chapter, fable-5 routing and evals, audit-instructions and
  prompting-postures rows, the plugin-philosophy tier table, the loop-lane README tier row, agent
  effort pins, verification skills, and docpage-digest `SKILL.md`, profile and
  `dual-verification.md` (pending its Q37). Its PR merges first; this branch rebases once. (Q17)
- The ten relayed standing rules apply (Q19): self-contained interview questions; no copied
  upstream content in repo files (own words, a link to the exact section, a date and a recheck
  trigger; look sources up live); official Anthropic defaults with configurable overrides; source precedence on
  conflicts (prompting guide for model behavior, Claude Code docs for Claude Code handling), every
  conflict written down; verification by gates, not prose; medium effort floor for code-changing
  work; current-model list; fix known issues now, else file; one PR with a parent issue closing
  sub-issues; coordinate across sessions by message.
- Pointers go to the latest main doc pages, never a single blog release post; a note records
  where later blog posts should be correlated. (Q12) Exception: this post's own provenance record
  and queue entry link the post, since it is their subject. (Q22)
- Links only: where a repo file needs an upstream fact, it keeps a one-line topic pointer to the
  exact doc section with a check date and a recheck trigger, and no values, lists or quotes; any
  exception needs the user's explicit yes. (Q29) This includes this post's own provenance record
  and queue entry: what was decided and changed, phrased without upstream values, plus links,
  dates and recheck triggers. (Q31)
- Outward actions (push, PR creation, issue creation) wait for one explicit go from the user at
  execution time, after one combined review of the branch, the PR title and body, and the issue
  texts. (Q32) After the post-merge rebase, one more combined review covers the force-push (with
  lease), the record diffs, the updated PR body and the ready flip, acting on one go. (Q33, Q36)
  Any other outward action (an interim push, a PR title edit, issue linking after creation)
  stops and asks, per the repo's standing stop-before-push rule. Merging and commenting are never
  covered. (AGENTS.md)
- No issues are filed on Anthropic repositories. (Q12)
- Every issue or PR mention on an interview page is a link. (Q2)
- PRs open as drafts with Conventional Commits titles and the repo's PR body contract; stop
  before push, merge, or commenting. (AGENTS.md)

### Acceptance criteria

- `prompts/loops/loop-lane-prompts.md`: the effort paragraph keeps its instruction (leave effort
  at its default) but no longer states or quotes any default; its reason is a one-line pointer to
  Claude Code model-config's effort section, with a check date and recheck trigger. (Q7, Q29)
- The boris reference's default-effort statement and always-thinking list
  (`plugins/playbooks/skills/boris/reference/advanced.md`, `autonomy.md`) become one-line
  pointers to the Claude Code model-config sections, with check date and recheck trigger; no
  model names or effort values remain there. (Q7, Q29)
- The context-guard native-1M model list (`plugins/context-guard/reference/reader-contract.md`)
  becomes a one-line pointer to model-config's context-window section, with check date and
  recheck trigger. (Q7, Q29)
- Each pointer's target section is fetched live at edit time and shown to still cover the topic;
  the PR body's verification section lists each pointer's URL, fetch date and a one-line
  still-covers note. (Q19 rule 2, Q35)
- The session-flow keep-going usage-limit reset checker resolves a reset clock time that is
  already past on the message's own day to the next day; a regression test covers "resets 3am
  (America/New_York)" received at about 14:35 the same day; the existing test suite passes.
- One parent issue in this repo tracks the effort; the reset-checker fix is its sub-issue and the
  PR body closes both. Guard-hook friction on compound and `github`-path commands is a standalone
  issue linked from the parent, not a sub-issue. (Q13, Q21)
- One PR for the effort: opened as a draft at the first go (not waiting on the other branch), kept draft until the Prompting Sonnet 5.5 PR
  merges, then rebased, completed with the post-merge items, and marked ready. (Q18, Q21)
- The 10 minor round-3 verifier findings are fixed in the slice; correct-and-reverify repeats
  until no finding with a known fix remains, and any without a known fix is recorded in the
  slice. (Q14, Q23)
- No repo file carries passages from the post, verbatim or paraphrased; the slice stays
  untracked and is copied outside the worktree before the worktree is removed. (Q14, Q22, Q29)
- After the Prompting Sonnet 5.5 PR merges and this branch rebases: the post's own
  docpage-digest queue entry and `docs/upstream/` provenance record exist, linking the post
  (their subject) and the main doc pages, holding only our decisions phrased without upstream
  values, and carrying a note to correlate later blog posts. (Q18, Q22, Q31)
- The blog extractor's source is handed to the Prompting Sonnet 5.5 session, which ships it in
  its PR; this branch commits no extractor. At rebase time this branch checks that it landed; if
  not, it messages that session and brings the gap to the user before the PR goes ready.
  (Q30, Q34)
- Every finding handed to another session is sent and acknowledged, and the PR body lists them:
  counting rules, recheck trigger, workload table, digest-pipeline defects, advisor conflict and
  re-check, four unclaimed doc items, Priority Tier and between-tools conflicts, and the blog
  extractor source (credited to this branch's finding). (Q26, Q30)
- The two Model routing lines in the user's `~/.claude/CLAUDE.md` are revised in the chezmoi
  source on its own branch; the user sees the diff and approves commit, push and apply. This
  does not gate the PR. (Q11, Q27)

### Captured assumptions

- The peer branches' candidate file lists are as they reported by message on 2026-09-30; a later
  change arrives by message before any edit.
- The facts this work rests on (Sonnet 5.5's Claude Code defaults and `sonnet` alias resolution)
  are as [Claude Code model-config](https://code.claude.com/docs/en/model-config) stated on
  2026-09-29; recheck at edit time.

- Acceptance-criteria coverage (unwanted-behavior "if … then" and state-driven "while …" cases)
  was asked once at confirmation and got no reply; the user confirmed the restatement, so those
  cases are unexamined.

### Out-of-scope

- Every guide-driven change listed under Constraints (owned by the Prompting Sonnet 5.5 branch).
- Changing any agent's or lane's model or effort binding.
- Filing upstream issues on Anthropic repositories.
- Graduating the digest slice into the repo.

### Deferred questions

- Q15 (arbiter: /planning:plan): mechanism-level choices, such as the parent issue's title, the
  exact pointer wording, the reset checker's code change and test shape.
## Plan
