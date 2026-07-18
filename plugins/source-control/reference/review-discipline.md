# Shared per-PR review discipline

Plugin-scope seam: the canonical, detailed home of the review discipline shared by
`/source-control:pull-request` (single-PR monitor) and `/source-control:babysit-prs` (all-PR
fleet loop). Both skills' always-loaded checklists are compact skeletons that cite this file;
the rules here are the single committed copy. Workers dispatched by either skill cite this file
directly — never a sibling skill's router.

The deterministic companion scripts live beside this file:

- `${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh <pr>` — fetches every comment from all
  3 GitHub API surfaces (issue-level, review-level, inline review comments) as one JSON array
  sorted by `created_at`, each object carrying `type` (`general` | `review` | `inline`),
  `author`, `body`, `path`, `line`, `id`. Never select API surfaces by judgment — an agent that
  picked `gh pr view --json comments,reviews` missed inline findings and declared "no comments
  to address".
- `${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh <pr>` — mechanical under-decomposition
  gate (§2).

## 1. Evidence-based comment state

GitHub is the source of truth — not model memory, not prior-iteration state, not comment counts.
Compaction loses classification state; comment-count heuristics miss edits, deletions, and
multi-finding comments. Every pass re-derives comment state from GitHub:

1. **Filter out own prior replies.** Comments authored by your own posting identities
   (`gh api user --jq .login`, plus any project bot identity — the same set the readiness gate's
   `--self` / `--extra-self` covers) that ARE classification replies (contain the
   `| # | Finding | Classification |` table pattern) are NOT findings — skip them. Own follow-up
   replies citing commit SHAs are also not findings. Only comments from OTHER authors are
   potential finding sources.
2. **Classify each remaining comment** as addressed or unaddressed by checking GitHub for
   evidence:
   - **Addressed (skip)** — the comment has a substantive reply (from ANY author) containing
     BOTH: (a) a classification token (VALID, INCORRECT, or UNCERTAIN), AND (b) evidence (code
     reference, test output, or reasoning).
   - **Unaddressed (process)** — no reply meeting both criteria. "Noted" or "will fix" without
     classification + evidence does NOT count.
3. **Extract findings** per §2 — one comment may contain multiple work items.

## 2. Structured finding extraction

AI review summaries (claude[bot], codex, cursor, etc.) and detailed human reviews often pack
multiple findings into a single comment — markdown tables, numbered severity items,
multi-paragraph analyses. Each finding is a separate work item requiring its own §3 cycle.

**Extraction rules:**

- One comment with N findings = N entries in the work-item list
- Each finding gets its own D1–D7 cycle (read, explore, validate, classify, reply, fix,
  follow-up)
- Findings are tracked individually — addressing 3 of 5 findings in a comment means 2 remain
  unaddressed
- Reply with a per-finding classification table (not one blanket reply for the whole comment)

**Finding identification signals:**

- Numbered items with severity labels (CRITICAL, IMPORTANT, SUGGESTION, P1/P2/P3)
- Markdown table rows with file/line/description columns
- Bullet lists where each bullet describes a distinct code concern
- Multiple `###` sub-headings each addressing different files or concerns

**Per-finding classification table format** (reply on the comment):

```text
| # | Finding | Classification | Evidence | Reacted |
|---|---------|---------------|----------|---------|
| 1 | <summary> | VALID — fixing | <evidence> | 👍 |
| 2 | <summary> | INCORRECT | <evidence why wrong> | 👎 |
| 3 | <summary> | VALID (defer) | <reason for deferral> | 👍 |
```

The reaction is per-comment (GitHub allows one reaction type per user per comment). Post the
reaction BEFORE the reply — reviewers scanning a PR see 👍/👎 at a glance without expanding
threads.

**MANDATORY subagent dispatch for multi-finding comments (≥3 findings):**

When a single PR comment packs 3+ findings, dispatch a finding-extractor subagent rather than
attempting inline extraction. The subagent:

1. Preserves main session context — large comment bodies + per-finding investigation evidence
   stay in the subagent's context window; only the structured ledger returns
2. Structurally enforces the per-finding work-item shape — the subagent returns a fixed-schema
   ledger; missing entries trigger main-session escalation
3. Is scope-fenced — ALLOWED: read PR-branch files + `gh api` against the specific PR;
   FORBIDDEN: edits, commits, pushes, reactions, replies on GitHub (those stay in the main
   session)

**Subagent dispatch prompt (compose verbatim, substitute `<PR>` and `<COMMENT_ID>` /
`<REVIEW_ID>`):**

```text
Extract individual findings from the multi-finding bot/human review at:
  https://github.com/<owner>/<repo>/pull/<PR>#issuecomment-<COMMENT_ID>
  (or pull/<PR>#pullrequestreview-<REVIEW_ID>)

ALLOWED scope (read-only on PR branch <BRANCH>):
- `gh api repos/<owner>/<repo>/issues/<PR>/comments` and per-id endpoints
- `gh api repos/<owner>/<repo>/pulls/<PR>/{comments,reviews}` and per-id endpoints
- `Read` / `Grep` / `Glob` against the repo working tree
- `Bash` for git inspection (`git show`, `git log`, `git diff`) — NEVER state-mutating

FORBIDDEN:
- Any Edit / Write of repo files
- Any `git add` / `git commit` / `git push`
- Any reaction / reply / comment POST to GitHub
- Any Skill invocation other than read-only exploration

Return a SINGLE markdown ledger with this exact shape (one row per finding):

| # | Severity | File:Line | Finding (≤120 chars) | Validation status | Evidence | Suggested classification |
|---|---|---|---|---|---|---|
| 1 | CRITICAL | path/to/file.cs:42 | <one-line summary> | VERIFIED — code matches claim | <quote 1-3 lines of code OR test output OR doc text> | VALID — fix now |
| 2 | IMPORTANT | path/to/file.cs:73 | <one-line summary> | INCORRECT — code already does X | <counter-evidence> | INCORRECT |
| 3 | SUGGESTION | path/to/file.md:12 | <one-line summary> | UNCERTAIN — behavior depends on Y | <what's missing> | UNCERTAIN |

CRITICAL constraints on the ledger:
- Severity column MUST match the parent comment's severity labels verbatim (CRITICAL / IMPORTANT / SUGGESTION / P1 / P2 / P3)
- Validation status MUST come from your own code reading, not a paraphrase of the bot claim
- Evidence MUST cite line numbers + verbatim snippets (≤3 lines) OR direct command output
- Suggested classification MUST be one of: VALID — fix now | VALID (defer) | INCORRECT | UNCERTAIN
- One row per finding. If the parent comment has 6 findings, the ledger has 6 rows. No collapsing.

If the parent comment is genuinely single-finding, return a 1-row ledger anyway.

Report ONLY the ledger + a one-line summary count ("Extracted N findings: X CRITICAL, Y IMPORTANT, Z SUGGESTION"). No prose framing.
```

**Main-session contract after the subagent returns:**

1. Receive the ledger. Verify the row count matches the source comment's finding count
   (independent count via grep on the parent comment body for severity markers)
2. For each ledger row, the main session runs D4.5 (react) + D5 (reply with the per-finding
   sub-row from the ledger) + D6 (fix if VALID — fix now) + D7 (follow-up SHA) with verification
   gates between each step
3. The subagent ledger is the D1–D4 work product. The main session NEVER skips D4.5–D7 by
   trusting the ledger alone — the ledger feeds the work, it doesn't replace it

**Single-finding comments** (1-2 findings): inline extraction in the main session is fine;
subagent overhead is not warranted.

**Why a subagent for ≥3 findings:** empirically, multi-finding comments treated as single work
items in the main session produce near-zero per-finding D1–D7 cycles — dozens of findings
glossed in one pass. Subagent dispatch structurally forces the per-finding shape because the
ledger contract demands it.

**Mechanical enforcement (gate, not prose):** advisory "MANDATORY" wording alone still
under-decomposed in practice. So enforcement is a gate:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh" <pr>` counts source findings
(severity markers in reviewer comments) vs classification rows (VALID/INCORRECT/UNCERTAIN in
your replies) and exits non-zero when rows < findings. The subagent-dispatch rule above tells
you HOW to decompose; the gate enforces THAT you did — readiness cannot be declared while it
reports `READINESS_BLOCKED`.

## 3. Per-finding D1–D7 verification gates

D steps operate **per-finding**, not per-comment. One comment with 5 findings = 5 individual
D1–D7 cycles. Exploration and validation must run on the PR's head branch.

- [ ] D1 — Read full finding context (parent comment body + surrounding findings)
- [ ] D2 — Explore referenced code on the PR branch
- [ ] D3 — **Validate the claim** — verify against actual code before trusting. Research
  non-trivial claims. Never implement a fix based solely on a bot's assertion
- [ ] D4 — Classify with evidence: VALID (fix now) / VALID (defer) / INCORRECT / UNCERTAIN.
  Classification MUST cite evidence from D2–D3
- [ ] D4.5 — React to the parent comment via `gh api .../reactions`. One reaction per comment
  (not per finding). **Tiebreaker for mixed-finding comments:** `+1` if ANY finding is VALID
  (signals action taken), `-1` only when ALL are INCORRECT, `eyes` when all UNCERTAIN or a mix
  of UNCERTAIN + INCORRECT with zero VALID
  - [ ] **verify reaction exists:** GET the same reactions endpoint filtered by your posting
    identities — non-zero confirms. Use `pulls/comments/<id>/reactions` for inline review
    comments. **Exemption:** PR review BODIES have no reactions endpoint in the REST API — skip
    the reaction there; the D5 reply is the audit signal
- [ ] D5 — Reply with the per-finding classification table + evidence (before fixing). Table
  format per §2 — includes the Reacted column. **Route the reply by comment type — REQUIRED,
  not interchangeable:** inline review comments (diff-anchored, `pulls/comments`) MUST reply
  THREADED via `gh api repos/{owner}/{repo}/pulls/<pr>/comments/<comment-id>/replies -f
  body='...'` so the reply lands under the source thread — NEVER a detached `pr comment`.
  Issue-level / review-level comments (no thread) → `gh pr comment <pr> --body '...'`. Use the
  project's bot-identity wrapper for these writes when it has one; plain `gh` otherwise.
  Answering an inline finding with a detached issue comment orphans the reply from the thread
  the reviewer tracks — a routing error, not a style choice
  - [ ] **verify reply exists — on the surface it was posted to:** inline threaded replies →
    `gh api repos/{owner}/{repo}/pulls/<pr>/comments --jq '.[] | select(.in_reply_to_id ==
    <original-id>)'`; issue-level → `gh api repos/{owner}/{repo}/issues/<pr>/comments --jq
    '.[].body'`. Querying only issues/comments false-fails a correctly posted inline reply
- [ ] D6 — Fix if VALID (fix now) → edit, `git add <specific-files>` (never `-A` or `.`),
  commit, push
  - [ ] **verify commit pushed:** `gh api "repos/{owner}/{repo}/commits?sha=<branch>&per_page=1"
    --jq '.[0].sha'` — confirm the fix commit SHA on the remote
- [ ] D7 — Post a follow-up reply citing the fix commit SHA
  - [ ] **verify follow-up reply posted — same surface routing as D5:** inline thread →
    `pulls/<pr>/comments` filtered by `in_reply_to_id`; issue-level →
    `gh api repos/{owner}/{repo}/issues/<pr>/comments --jq '.[-1].body'`
- [ ] D7.5 — Resolve review thread — **author-conditional, inline review comments only** (this
  section is the canonical policy). Resolve ONLY threads whose OPENING comment is authored by a
  BOT reviewer that you addressed. NEVER resolve HUMAN-authored threads — the human resolves
  their own after verifying the fix. NEVER resolve your OWN threads (any of your posting
  identities — same self set as §1 step 1). Skip issue-level comments (no thread). **Thread
  author = login of the THREAD-OPENING comment** (replying into it does not change the author).
  **Bot detection is API-surface-specific:** resolution runs via GraphQL (the threadId fetch),
  where bot authors have `author.__typename == "Bot"` and `login` omits the `[bot]` suffix;
  REST surfaces show the suffix. When fetching the threadId, also select
  `author{__typename login}` to apply the conditional in one query
  - [ ] **verify thread resolved:** query the thread node via `gh api graphql` — `isResolved`
    must be `true`

**"Done" means GitHub shows evidence.** A per-finding work item is addressed only when the
verification sub-step confirms the action landed on GitHub. Model memory of "I posted a reply"
or "I pushed the fix" is not evidence — compaction can lose that state between iterations.
Re-query the API.
