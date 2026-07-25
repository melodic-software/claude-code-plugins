# S7 — "Then: Memory in CLAUDE.md files / Now: Auto-memory"

Source span: `source-article.md:76-79`. Four sentences; the smallest section in the article and the
one whose consequence reaches furthest into this machine's configuration model.

All Claude Code behavior below was fetched this session (2026-07-24) from
`code.claude.com/docs`. Nothing is asserted from memory.

## Claims

| # | Verbatim source | Assertion |
|---|---|---|
| 1 | `**Then: Memory in CLAUDE.md files` / `Now: Auto-memory**` (`:76-77`) | The header frames a substitution: CLAUDE.md-as-memory is the superseded practice, auto-memory the current one. |
| 2 | "We used to encourage users to save things to Claude's memory, by using the # hotkey to write to their CLAUDE.md automatically." (`:79`) | A `#` hotkey existed, it wrote to CLAUDE.md, and recommending it is retired. |
| 3 | "Instead, Claude now automatically saves memories" (`:79`) | Automatic, unprompted saving is the current mechanism. |
| 4 | "…that are relevant to the work and to you." (`:79`) | Those saved memories are scoped to two things: the work, and the user. |

Claims 3 and 4 come from one sentence and are kept apart deliberately — 3 is CONFIRMED and 4 is
not. The word "Instead" carries claim 1's substitution into the sentence too; claim 1 is scored on
the header plus that connective.

## Evidence status

Tally, in the brief's vocabulary: **CONFIRMED 1 (claim 3), PARTIAL 2 (claims 2, 4), UNBACKED 1
(claim 1).** Each claim carries exactly one token; the qualifiers below are substance, not a fifth
verdict.

**Claim 1 — UNBACKED, and actively contradicted.** No official page supports the substitution, and
one denies it — a stronger result than plain absence, but the brief's vocabulary has no slot above
UNBACKED, so it is counted there. <https://code.claude.com/docs/en/memory.md>
states: "Claude Code has two complementary memory systems. Both are loaded at the start of every
conversation." And: "Use CLAUDE.md files when you want to guide Claude's behavior. Auto memory
lets Claude learn from your corrections without manual effort." The doc's own comparison table
splits them by author ("Who writes it": You / Claude) and by content ("Instructions and rules" /
"Learnings and patterns"). Auto-memory added a second channel; it did not retire the first. The
same page still tells you when to *add* to CLAUDE.md ("Claude makes the same mistake a second
time…"), and `/doctor`'s documented CLAUDE.md trim check presumes CLAUDE.md remains in use.

**Claim 2 — PARTIAL.** The assertion as written bundles a present-tense verdict with a historical
one. The half that current documentation can adjudicate is confirmed; the half about the past is
not adjudicable from present-tense docs. Breakdown:

- *Retirement of the `#` hotkey: CONFIRMED by absence, and the absence is load-bearing.*
  <https://code.claude.com/docs/en/interactive-mode.md> "Quick commands" enumerates the complete
  prefix-shortcut surface: `/` at start, `!` at start, `@`, `:`, `?` on empty input. No `#`. The
  only `#` in that page is unrelated (external-editor comment prefix; "PR #446"). The memory page
  documents no `#` shortcut anywhere. The current documented replacements are `/memory` (browse,
  open, toggle) and plain natural language.
- *Historical existence of the hotkey: UNBACKED.* Current docs describe the present and are silent
  on what the shortcut used to be. That is an expected outcome, not a gap — no current page can
  confirm a retired affordance. Do not build a criterion on the history.
- *One substantive correction the article compresses away:* the destination changed, not just the
  keystroke. `memory.md` states: "When you ask Claude to remember something, like 'always use
  pnpm, not npm'… Claude saves it to auto memory. To add instructions to CLAUDE.md instead, ask
  Claude directly, like 'add this to CLAUDE.md,' or edit the file yourself via `/memory`." So the
  natural-language remember-this path now lands in auto memory by default and CLAUDE.md requires
  an explicit ask — the inverse of the retired hotkey's behavior.

**Claim 3 — CONFIRMED.** "Auto memory lets Claude accumulate knowledge across sessions without you
writing anything. Claude saves notes for itself as it works." "Auto memory is on by default."
Approval: there is **no** documented per-write approval gate. The only documented user-facing
signal is after the fact — "When you see messages like 'Saved 2 memories' or 'Recalled 2
memories' in the Claude Code interface, Claude is actively updating or reading from
`~/.claude/projects/<project>/memory/`." Discretion is the model's: "Claude doesn't save something
every session. It decides what's worth remembering based on whether the information would be
useful in a future conversation."

**Claim 4 — PARTIAL.** "relevant to the work" is backed: scope is "Per repository, shared across
worktrees", storage is per-project, and content is characterized as "build commands, debugging
insights, architecture notes, code style preferences, and workflow habits". "and to you" has **no
backing surface**. There is no documented user-scope store for the main conversation's auto
memory — the only `~/.claude`-rooted auto-memory directory in the docs belongs to *subagents*
(`memory: user`), not to the main conversation. Personal preferences discovered in repo A do not
follow you to repo B. `memory.md` is explicit that this is machine-local and unsynced: "Auto
memory is machine-local… Files are not shared across machines or cloud environments."

### Mechanism facts established (all from the fetched pages)

Write paths, per scope:

| Store | Path | Source |
|---|---|---|
| Main conversation, per repo | `~/.claude/projects/<project>/memory/` — `MEMORY.md` index + topic files | `memory.md` §Storage location |
| Relocated main-conversation store | `autoMemoryDirectory` (absolute or `~/`-prefixed), read from **any** settings scope | `memory.md`, `settings.md` |
| Subagent, `memory: user` | `~/.claude/agent-memory/<name-of-agent>/` | `sub-agents.md` §Enable persistent memory |
| Subagent, `memory: project` | `.claude/agent-memory/<name-of-agent>/` — "shareable via version control" | same |
| Subagent, `memory: local` | `.claude/agent-memory-local/<name-of-agent>/` — "shouldn't be checked into version control" | same |

`<project>` "is derived from the git repository, so all worktrees and subdirectories within the
same repo share one auto memory directory."

Load behavior: first 200 lines or 25KB of `MEMORY.md`, whichever comes first, every session; topic
files load on demand. The main conversation's auto memory is *not* loaded into subagents (except a
fork).

Inspect / disable / scope levers:

- `/memory` — browse and open files, plus "the auto memory toggle, which saves `autoMemoryEnabled`
  to your user settings at `~/.claude/settings.json`".
- `autoMemoryEnabled` (default `true`) at any settings scope. "When `false`, Claude does not read
  from or write to the auto memory directory."
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
- `autoMemoryDirectory` — relocation; from project/local settings honored only after the workspace
  trust dialog.
- Files are plain markdown, editable and deletable at any time.

Coupling worth flagging: `sub-agents.md` states that if auto memory is off via `autoMemoryEnabled`
or `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, "the `memory` field has no effect and the subagent launches
without the memory instructions or the memory tool access". One user-scope switch silently
disables every agent-level `memory:` declaration.

## Criteria

**S7-K1 — no `#`-hotkey instruction.** *Surface:* any `.md` in the repo (SKILL.md body, README,
docs, agent definition). *Observable:* prose instructing the user to press/type `#` to save to
memory or CLAUDE.md. *Fails:* "hit `#` to add this to CLAUDE.md". *Must NOT flag:* markdown
headings, `#!` shebangs, `#` comments inside fenced blocks, `PR #446`-style issue references, or
`source-article.md:79` itself (quoting a retired practice as retired is correct).

**S7-K2 — no substitution framing.** *Surface:* SKILL.md bodies, plugin READMEs, repo `CLAUDE.md`,
`docs/`. *Observable:* prose asserting auto memory replaces, supersedes, or obviates CLAUDE.md, or
the converse. *Fails:* "auto memory means you no longer need a CLAUDE.md". *Must NOT flag:*
`plugins/claude-memory/skills/audit/SKILL.md:28-34`, whose scope table lists CLAUDE.md,
`.claude/rules/`, and auto-memory as distinct co-existing entities — that is the correct model, and
a naive keyword rule would flag it.

**S7-K3 — auto-memory paths match the documented per-scope set.** *Surface:* any file naming an
auto-memory location. *Observable:* the path string is one of the five rows in the table above, or
is explicitly framed as an `autoMemoryDirectory` override. *Fails:* asserting a user-scope
main-conversation memory store, or `~/.claude/memory/`. *Must NOT flag:*
`plugins/claude-memory/skills/audit/scripts/resolve-memory-dir.sh`, which derives the path at
runtime rather than hardcoding one — runtime resolution is the preferred form, not a violation.

**S7-K4 — a declared agent `memory:` scope has a matching, *committed* ignore posture.**
*Surface:* `plugins/*/agents/*.md` frontmatter. *Observable:* for every agent with `memory: local`,
`git check-ignore -v <scope-path>` resolves to a **tracked** ignore file (`.gitignore` /
`.git/info/exclude` does not count, being machine-local and uncommittable); for `memory: project`,
the repo has a deliberate, documented decision to commit that directory. *Fails:* the current state
(see Targets). *Must NOT flag:* agent definitions with no `memory:` field —
`plugins/*/agents/*.md` without the key inherits no store and needs no ignore rule.

*Authority note:* unlike K1–K3 and K5, this criterion is **derived**, not quoted. `sub-agents.md`
says a `local`-scope store "shouldn't be checked into version control" and `claude-directory.md`
describes `.claude/agent-memory/` (project scope) as "meant to be shared with your team"; neither
states that a committed ignore rule is required. The committed-vs-`info/exclude` requirement is
engineering judgment applied to that stated intent — a promise that only holds on one clone does
not hold. Treat it as repo policy, not a documented mandate.

**S7-K5 — routed, user-scope.** *Surface:* the dotfiles source
`~/.local/share/chezmoi/.chezmoidata/claude.json`. *Observable:* a settings key that an in-session
Claude Code UI writes (documented: `/memory` writes `autoMemoryEnabled` to
`~/.claude/settings.json`) sits in `claudeSettings.force` rather than `claudeSettings.seed`.
*Fails:* `autoMemoryEnabled` today. *Must NOT flag:* keys with no documented in-app toggle
(`permissions`, `hooks`, `statusLine`) — pinning those in `force` is the whole point of the block.

## Targets in this repo

Counts are from commands run in `<repo-root>`.

- **S7-K1 population: zero.** `grep -rn -iE "# hotkey|hash hotkey|'#' to (add|save)|# to add to memory"`
  over all `*.md` returns exactly one hit, `.work/context-engineering-rightsizing/source-article.md:79`,
  which is the article text itself. The repo never taught the retired practice, so K1 is a
  regression guard, not remediation work. Stating the zero explicitly is the finding.
- **S7-K2 / K3 population: 20 lines across the memory-aware surface.**
  `grep -rn "projects/<project>/memory\|agent-memory" --include='*.md' --include='*.sh' plugins/ docs/ CLAUDE.md README.md`
  → 20. Reviewed spot checks, all currently correct:
  - `plugins/claude-memory/skills/audit/reference/official-guidance.md:171-173` — the three
    subagent scopes, matching the fetched `sub-agents.md` table exactly.
  - `plugins/claude-memory/skills/stateless/SKILL.md:30` — store path plus `autoMemoryDirectory`
    relocation.
  - `docs/conventions/topic-docs/README.md:48`, `plugins/review/README.md:22` — agent-memory
    directories described accurately.
  - Broader `auto.?memory` grep across `*.md|*.sh|*.json` hits 48 files, but that count includes
    `.claude-plugin/marketplace.json` blurbs and unrelated plugins; 20 is the population the
    criteria actually decide.
- **S7-K4 population: 6 of 7 agent definitions, all currently failing.**
  `find plugins -path '*/agents/*.md' | wc -l` → 7; `grep -rln "^memory:" plugins/*/agents/` → 6,
  every one `memory: local`:
  - `plugins/review/agents/architecture-guardian.md:8`
  - `plugins/review/agents/ci-log-auditor.md:8`
  - `plugins/review/agents/code-reviewer.md:8`
  - `plugins/review/agents/doc-drift-detector.md:8`
  - `plugins/review/agents/ecosystem-specialist.md:8`
  - `plugins/review/agents/security-reviewer.md:8`

  `git check-ignore -v .claude/agent-memory-local/code-reviewer/MEMORY.md` resolves to
  `.git/info/exclude:17` — **not** `.gitignore`. `.gitignore` has no `agent-memory` entry
  (`grep -n "agent-memory" .gitignore` → no match; the file's "Local-only Claude Code state" block
  covers `.claude/settings.local.json`, `.claude/observability/`, `.claude/worktrees/`, and
  `.claude/**/*.local.*` — note `agent-memory-local` does not match `*.local.*`). `.git/info/exclude`
  is per-clone and never committed, so on any other contributor's checkout — or a fresh clone on
  this machine — a review agent's memory writes would appear as untracked files and be
  commit-eligible, directly against the doc's "shouldn't be checked into version control".
  `plugins/review/README.md:22` already promises they are "never checked into version control";
  that promise currently rests on an uncommittable file.
- **Repo scale for context:** `find plugins -name SKILL.md | wc -l` → 187.

## Chezmoi assessment — which auto-memory write paths are tracked

Determined empirically. `chezmoi managed` returns 131 entries; the `.claude`-rooted subset is:
`CLAUDE.md`, `docs/`, `hooks/`, `plugins/data/machine-health/**`, `scheduled-tasks/**`,
`settings.json`, `skills/consult-fable/SKILL.md`, `statusline/**`.

| Auto-memory write path | Tracked? | Evidence | Backfill obligation |
|---|---|---|---|
| `~/.claude/projects/<project>/memory/**` | **No** | absent from all 131 `chezmoi managed` entries (`chezmoi managed \| grep -i projects` → none) | **None.** Auto-memory file writes are outside the tracked model entirely. |
| `~/.claude/agent-memory/<agent>/**` (subagent `memory: user`) | **No** | not in `chezmoi managed`; directory does not exist on this machine (`ls ~/.claude/agent-memory` → No such file) | None today. See deferred trigger below. |
| `~/.claude/settings.json` | **Yes** | `chezmoi managed` entry; source is `dot_claude/modify_settings.json` | **Yes** — and this is the only tracked surface auto-memory touches. |

So the store is untracked and the **switch** is tracked. The exposure is narrower than "auto-memory
writes into a managed tree", and it is asymmetric.

### The switch, precisely

`~/.claude/settings.json` is not a plain managed file. Its source is a chezmoi `modify_` merge
template (`~/.local/share/chezmoi/dot_claude/modify_settings.json`, 187 lines) that reads the live
file from stdin and overlays only owned keys, documenting three tiers in its own header comment:
`force` (always enforced), `seed` (written only when absent, "so… a later in-app toggle is
respected"), and pass-through for everything else.

`autoMemoryEnabled` is in **`force`**:
`~/.local/share/chezmoi/.chezmoidata/claude.json:221` → `claudeSettings.force.autoMemoryEnabled = false`.
It is the only `autoMemory*` key anywhere in the dotfiles source (`grep -rn -i "autoMemory\|AUTO_MEMORY"`
over the whole source tree returns that one line).

Consequences, both verified:

- **Auto memory is off on this machine, by declaration.** Live `~/.claude/settings.json:580` reads
  `"autoMemoryEnabled": false`. `ls -d ~/.claude/projects/*/memory` → 0 directories: nothing has
  ever been written. `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is unset, so the setting governs.
- **The toggle asymmetry.** A runtime `/memory` toggle to **on** writes `true` to
  `~/.claude/settings.json` and is reverted to `false` by the next `chezmoi apply` — the in-app
  affordance the docs advertise is silently undone. A toggle to **off** is a source no-op. Nothing
  warns the operator; the revert happens on an unrelated apply, arbitrarily later.

The generic "live edits to tracked files must be backfilled" rule therefore under-describes this
case in one direction and over-describes it in the other: memory *content* carries no obligation at
all, while the *switch* carries something worse than an obligation — an unannounced revert.

### Reconciling silent automatic writes with a tracked-dotfiles model — options

1. **Leave `autoMemoryEnabled` in `force: false`.** Auto memory stays off fleet-wide, deterministic,
   zero drift. Cost: the `/memory` toggle is a trap, and every agent-level `memory:` field in every
   plugin is silently inert (see the `sub-agents.md` coupling above) — including this repo's own six
   review agents.
2. **RECOMMENDED — move `autoMemoryEnabled` from `force` to `seed`, keep the store at its default
   untracked path.** The merge template already documents `seed` as exactly this seam: declared on a
   fresh machine, "but a later in-app toggle is respected". Auto memory becomes operator-controllable
   per machine through the documented UI without drifting the tracked file, because a passed-through
   or seeded key is not re-asserted. The store stays outside the tracked tree, so writes never create
   a backfill event. This is the only option that makes the article's "now" actually available here
   while preserving the dotfiles model.
3. **Delete the key entirely.** Accepts the product default (`true`) with nothing declared. Rejected:
   a fresh machine would silently start writing memory with no recorded decision, which is the exact
   posture the `force`/`seed` split exists to avoid.
4. **Relocate the store into a tracked subtree via `autoMemoryDirectory`.** **Reject.** `memory.md`:
   "Auto memory is machine-local… Files are not shared across machines or cloud environments." A
   per-repo, machine-local, model-written store inside a fleet-synced dotfiles repo is permanent
   three-way drift with no merge story, and it would convert every silent memory write into a
   backfill obligation — inverting today's zero-obligation position.
5. **Env-var lever instead of the setting.** `CLAUDE_CODE_DISABLE_AUTO_MEMORY` set at OS scope, or in
   the tracked settings `env` block. Sidesteps nothing: `env` lives in `force` too, and an OS-scope
   var is a second, less visible source of truth for the same decision. Rejected as a primary
   mechanism; useful only if the operator wants a hard machine-level kill independent of settings.

**Deferred, with trigger:** `autoMemoryDirectory` is unset everywhere (verified — the source grep
above finds no such key at any scope). It is the single mechanism that could move auto-memory writes
onto a tracked surface. Trigger to revisit: any future setting of `autoMemoryDirectory`, at any
scope, to a path under a chezmoi-managed subtree. Likewise `~/.claude/agent-memory/` — untracked and
nonexistent today, but the first subagent declared `memory: user` creates a new durable directory
under the managed root, which the standing rule treats as a tracking *candidate*. The correct answer
there will be to add it to `.chezmoiignore` (model-written state, never a dotfile), not to adopt it.

**Routing:** every change above is to `melodic-software/dotfiles`
(`.chezmoidata/claude.json`), through that repo's own reviewed flow. Nothing under `~/.claude` was
edited by this agent; all inspection was read-only.

## Does the `claude-memory` plugin already cover this?

Substantially, yes — better than the article. What it misses is specific.

**Covered:**

- `stateless/SKILL.md` owns auto memory end to end: store location, `autoMemoryDirectory`
  relocation from any scope, `CLAUDE_CONFIG_DIR` relocation of the whole root, the
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY`-overrides-`autoMemoryEnabled` precedence, Windows registry
  managed policy as unreadable-not-empty, and status/disable/purge actions.
- `stateless/context/disable.md:60-105` already implements the dotfiles concern generically — a
  three-manager detector (chezmoi/yadm/stow, including stow tree-folding), a fingerprint fallback for
  "manager present but tracking unconfirmed", and the instruction to backfill through the source and
  "never run an `apply`/`restow` from this session that could revert the live edit". This is a better
  articulation of the rule than the rule itself.
- `audit/SKILL.md:28-34` keeps CLAUDE.md, rules, and auto-memory as distinct co-existing entities —
  i.e. it already encodes the *complementary* model that claim 1 contradicts.

**Gaps, all concrete:**

1. **No `enable` action.** `stateless` parses `status|disable|purge` only
   (`stateless/SKILL.md:39-45`). On a machine where the operator's actual open question is "should I
   turn this on", the plugin offers no path — and the naive answer (flip it in `/memory`) is the one
   that gets silently reverted here.
2. **The tracked-settings concern is advisory prose, not a check.** It fires in the `disable`
   workflow. `status` reports the effective posture but never reports *why* it is what it is or that
   a runtime change will not survive. On this machine `status` would correctly say "disabled" while
   omitting the operative fact: the value is force-pinned in a dotfiles source and a toggle will be
   undone. A `status` that resolved the tracked-source declaration would have surfaced the trap.
3. **`disable`'s backfill detector has no inverse.** It detects tracking to warn about drift *after*
   an edit. It cannot answer the prior question — "is this key already declared upstream, and at what
   tier" — which is what determines whether an edit is drift, a no-op, or futile.
4. **The `audit` skill's auto-memory tier is inert here.** Its precomputed context
   (`audit/SKILL.md:12-13`) counts memory files and `MEMORY.md` lines; both resolve to 0 on this
   machine because the store has never been written. The M1–M4 checks have no input. Not a defect —
   correct behavior on an empty store — but worth stating so the audit's coverage is not overread.
5. **Neither skill knows about subagent memory as a *live* surface.** `audit/reference/official-guidance.md:171-173`
   records the three scopes correctly, but nothing checks whether a repo's declared agent `memory:`
   scopes have a coherent ignore posture (criterion S7-K4), and nothing surfaces the
   `autoMemoryEnabled: false` → `memory:` field inert coupling.

## Conflicts and ambiguity

1. **Sharpest: the section's framing is wrong.** "Then… / Now…" and "Instead" assert replacement;
   `memory.md` asserts complementarity in its first paragraph and never walks it back. Applied
   literally, S7 would license deleting CLAUDE.md content in favor of a store that is machine-local,
   per-repo, unsynced, model-curated, capped at 200 lines / 25KB at load, and *off by default on this
   machine*. Every other section of this article — S9's "Keep your CLAUDE.md lightweight… spend most
   of the tokens on gotchas" — presumes a living CLAUDE.md. S7 read as substitution contradicts S9
   read as guidance. Rightsizing CLAUDE.md is the real instruction; retiring it is not.
2. **The article omits the destination change, which is the part that actually matters.** The
   retired hotkey wrote to CLAUDE.md — a file you own, review, and commit. The current default for
   "remember this" writes to auto memory — a store the model curates, that no teammate sees, that no
   review catches, and that requires an explicit "add this to CLAUDE.md" to land in the shared
   artifact. That is a governance change, not a keystroke change, and the article does not name it.
3. **"and to you" does not generalize.** There is no user-scope main-conversation auto memory. A
   reader who takes claim 4 at face value would expect cross-repo personal-preference retention that
   the product does not provide; the closest thing (`~/.claude/CLAUDE.md`, which this operator uses
   heavily) is exactly the mechanism claim 1 tells them to retire.
4. **The article's "now" is unavailable on this machine as configured**, and deliberately so —
   `force.autoMemoryEnabled: false` is an operator decision recorded in the dotfiles source, not
   accidental drift. Any application pass that acts on S7 without reconciling that decision first
   would be writing guidance for a feature that cannot run here.
5. **Team and fleet scale are unaddressed.** "Auto memory is machine-local… not shared across
   machines or cloud environments." For a marketplace repo whose plugins ship to other people's
   machines, auto memory can never be a place to put anything a *consumer* needs. Guidance that
   moves knowledge out of CLAUDE.md/skills and into auto memory would make it unshippable. This
   repo's existing posture — durable knowledge in skills and reference files, contributor-local
   memory audited but never committed (`audit/SKILL.md:87-89`, "Audit output is contributor-local by
   design") — is already the correct resolution and should not be disturbed.
6. **This repo already does the thing S7 gestures at, more rigorously than S7 does.** The
   `claude-memory` plugin's two skills, with doc-sourced reference files and script-backed checks,
   cover more ground than the article's four sentences. S7's value here is not new practice; it is
   the prompt to check the *switch*, which is where the real finding was.

## Open questions for the operator

1. **Move `autoMemoryEnabled` from `claudeSettings.force` to `claudeSettings.seed` in
   `melodic-software/dotfiles`?** RECOMMENDED — yes. It is the merge template's own documented seam
   for "declared on a fresh machine, in-app toggle respected", and it removes the silent-revert trap
   without adopting any untracked state. **The tier change and the seeded value are two decisions,
   not one.** `seed` writes "only when absent", so on *this* machine the existing `false` persists
   and nothing changes until you toggle — but on every fresh machine the seeded value becomes the
   standing default. Seeding `false` means auto memory starts off fleet-wide and needs a manual
   toggle per machine; seeding `true` matches the product default. Decide the value alongside (2),
   and do not ratify the tier move on its own assuming the posture is unchanged.
2. **Do you want auto memory on at all?** Recommendation: yes, at least in this plugin repo, gated
   behind (1) so the choice is per-machine and reversible. The concrete unlock is this repo's six
   `memory: local` review agents, which are inert while it is off. If the answer is a durable no, say
   so in the dotfiles source as a comment — the current bare `false` reads as unexamined.
3. **Promote the `.claude/agent-memory-local` ignore from `.git/info/exclude` into the committed
   `.gitignore`?** RECOMMENDED — yes, in this repo. It is a one-line change, it makes
   `plugins/review/README.md:22`'s promise true for every clone, and it is the only S7 finding that
   is a live correctness gap rather than a decision.
4. **Add an `enable` action to `claude-memory:stateless`, and teach `status` to resolve the tracked
   declaration?** Recommendation: yes for `enable` (the missing half of a lever the skill otherwise
   owns completely); `status` enhancement is the higher-value half but the larger build — it needs to
   answer "is this value declared upstream, at what tier, and will a runtime change survive". Route
   as two separate work items.
5. **Should S7-K4 become a durable check?** It generalizes beyond this repo — any plugin author
   shipping an agent with `memory:` faces it. Recommendation: yes, in `claude-memory:audit` as a new
   check ID rather than a one-off topic artifact, since that skill already owns the memory layer.

## Fence events

None. No fenced path was read, listed, grepped, or referenced. All work stayed within
`<repo-root>`, read-only inspection of `~/.claude` and
`~/.local/share/chezmoi`, and freshly fetched `code.claude.com/docs` pages.

`.work/context-engineering-rightsizing/interview-checklist.md` was read (own working directory, not
fenced). It is an operator ledger of session decisions, not an interpretation of the article; it
contains no reading of S7's content. Noting it for transparency, not as a fence event.

## Sources fetched this session

- <https://code.claude.com/docs/llms.txt> — index
- <https://code.claude.com/docs/en/memory.md> — auto memory, CLAUDE.md, `/memory`, storage location
- <https://code.claude.com/docs/en/settings.md> — `autoMemoryEnabled`, `autoMemoryDirectory`,
  `claudeMdExcludes`, precedence, file locations
- <https://code.claude.com/docs/en/interactive-mode.md> — Quick commands shortcut table (the `#`
  absence finding)
- <https://code.claude.com/docs/en/sub-agents.md> — `memory` field, per-scope agent-memory paths,
  the `autoMemoryEnabled`-off coupling
- <https://code.claude.com/docs/en/claude-directory.md> — `.claude` layout. Read for the
  auto-memory and agent-memory passages specifically (not in full). Corroborates every path in the
  table above and adds one framing fact used in S7-K4: project-scope `.claude/agent-memory/` is
  "meant to be shared with your team", while "To keep memory out of version control use
  `memory: local`, which writes to `.claude/agent-memory-local/` instead."
