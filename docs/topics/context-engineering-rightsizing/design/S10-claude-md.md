# S10 — Applying this to your context → CLAUDE.md

Source span: `source-article.md:99-102`.

All measurements below were produced by commands run this session against
`D:/repos/.worktrees/context-engineering-rightsizing` (repo scope) and `C:/Users/KyleSexton/.claude/`
(user-global scope, read-only). Byte counts are exact (`wc -c`, `awk length($0)`). Token figures are
labelled estimates at a stated 4-bytes-per-token divisor — no tokenizer was run.

## Claims

| # | Claim | Verbatim source |
|---|---|---|
| C1 | CLAUDE.md should be lightweight. | "Keep your CLAUDE.md lightweight" (`source-article.md:100`) |
| C2 | It should briefly state the repo's purpose. | "and briefly describe what your repo is for" (`source-article.md:100`) |
| C3 | The majority of the token budget goes to in-codebase gotchas. | "but spend most of the tokens on gotchas inside of the codebase" (`source-article.md:100`) |
| C4 | Worked example of a gotcha: a monolithic types file. | "For example, you may organize your code to keep types in one monolithic file and nowhere else." (`source-article.md:100`) |
| C5 | Do not state "the obvious" — anything derivable from the file system or the repo. | "Avoid stating 'the obvious' things Claude should know by looking at your file system or your repo." (`source-article.md:100`) |
| C6 | Detail belongs behind progressive disclosure. | "Use progressive disclosure for more details" (`source-article.md:102`) |
| C7 | Worked example of progressive disclosure: extract several unique verification instructions into a verification skill, referenced from CLAUDE.md. | "for example if you have several unique instructions on how to verify your work, create a verification skill and reference it from your CLAUDE.md." (`source-article.md:102`) |

Seven distinct claims. C4 and C7 are worked examples, not independent assertions, but the brief
assigned them as owned concepts and they carry the operational weight of C3 and C6 respectively, so
they are graded separately.

## Evidence status

Fetched this session:

- <https://code.claude.com/docs/en/memory> ("How Claude remembers your project")
- <https://code.claude.com/docs/en/commands> (`/doctor`, `/context`, `/memory`, `/init` entries)
- <https://code.claude.com/docs/en/sub-agents> ("What loads at startup")

| # | Status | Basis |
|---|---|---|
| C1 | **CONFIRMED** | memory: "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence." And: "CLAUDE.md files are loaded in full regardless of length, though shorter files produce better adherence." The article's soft "lightweight" is given a hard number upstream. |
| C2 | **PARTIAL — and upstream contradicts itself here** | memory's "When to add to CLAUDE.md" lists as keepers: "build commands, conventions, **project layout**, 'always do X' rules." But the `/doctor` entry says the trim "cuts sections such as **directory layouts**, dependency lists, and architecture overviews." Purpose-of-repo in one or two sentences is defensible under neither list explicitly; a repo *layout* is explicitly on both lists. See Conflicts §1. |
| C3 | **CONFIRMED** | commands `/doctor`: the trim "keeps **pitfalls**, rationale, and conventions that differ from tool defaults." "Pitfalls" is upstream's word for the article's "gotchas". |
| C4 | **UNBACKED** | No official page describes a monolithic-types-file example or any equivalent. Legitimate: it is an illustration of C3, not a separate behavioral claim. Nothing upstream contradicts it. |
| C5 | **CONFIRMED, and operationalized more sharply than the article does** | commands `/doctor`: "trims checked-in `CLAUDE.md` files by cutting content Claude could derive from the codebase... The trim cuts sections such as directory layouts, dependency lists, and architecture overviews, and keeps pitfalls, rationale, and conventions that differ from tool defaults." memory repeats it under "My CLAUDE.md is too large". This gives named cut-classes and keep-classes, not just a judgment call. |
| C6 | **PARTIAL — the mechanism matters and the article omits it** | Confirmed as an objective: `/doctor` "migrates the always-loaded guidance that remains into skills and nested `CLAUDE.md` files that load on demand." But memory is explicit that the obvious implementation does **not** defer: "You can also split content into imports for organization, though **imported files still load and enter the context window at launch**," and "Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch." Only three mechanisms actually defer: skills, `paths:`-scoped `.claude/rules/`, and subdirectory `CLAUDE.md` ("Claude also discovers `CLAUDE.md` and `CLAUDE.local.md` files in subdirectories under your current working directory. Instead of loading them at launch, they are included when Claude reads files in those subdirectories."). A backticked-path pointer also defers, because "Import parsing skips Markdown code spans and fenced code blocks." |
| C7 | **CONFIRMED** | memory: "If an entry is a multi-step procedure or only matters for one part of the codebase, move it to a skill or a path-scoped rule instead." And skills "only load when you invoke them or when Claude determines they're relevant to your prompt." `/doctor` performs exactly this migration. |

Tally: 4 CONFIRMED (C1, C3, C5, C7), 2 PARTIAL (C2, C6), 1 UNBACKED (C4).

### Load facts established this session (needed by the criteria below)

1. `~/.claude/CLAUDE.md` and every ancestor-directory `CLAUDE.md`/`CLAUDE.local.md` load **in full at
   launch**, concatenated root-down, and are delivered "as a user message after the system prompt".
2. They also load into **every non-fork subagent**: "**CLAUDE.md files**: every level of the CLAUDE.md
   hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`, project rules,
   `CLAUDE.local.md`, and managed policy files. The built-in Explore and Plan agents skip this."
   Cost is therefore per-agent, not per-session — material in a repo whose own workflows fan out.
3. `AGENTS.md` is **not read**: "Claude Code reads `CLAUDE.md`, not `AGENTS.md`." The documented
   remedies are an `@AGENTS.md` import from `CLAUDE.md`, or a symlink (docs note the symlink route
   needs Administrator or Developer Mode on Windows, so the import is the applicable one here).
4. Only `./CLAUDE.md`, `./.claude/CLAUDE.md`, `./CLAUDE.local.md` and `.claude/rules/*.md` are
   auto-loaded project locations. An arbitrary `.claude/<name>.md` is not.
5. Block-level HTML comments in CLAUDE.md "are stripped before the content is injected into Claude's
   context" — a zero-cost channel for maintainer notes.

## Criteria

Each criterion states its surface, its pass/fail observable, and at least one case it must not flag.

### CR-1 — Size gate (from C1)

- **Surface**: any `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`.
- **Observable**: `wc -l` > 200 → FAIL. Report `wc -c` and an estimated token count alongside, and
  FAIL a file whose bytes exceed 200 × the repo's median CLAUDE.md bytes-per-line even when its line
  count passes.
- **Must not flag**: a 40-line file of long, dense, individually non-derivable rules that is under
  both thresholds. Density alone is not a defect; density × derivable content is.
- **Note**: upstream's threshold is line-based only. The byte clause is this section's addition and
  is explicitly *not* an official rule — see Conflicts §4.

### CR-2 — Purpose statement bounded (from C2)

- **Surface**: CLAUDE.md.
- **Observable**: the repo-purpose preamble occupies ≤ 3 non-blank lines and asserts at least one
  fact not present in the repo's own manifest/README metadata. FAIL if it exceeds 3 lines, or if
  every clause in it is a restatement of `package.json` / `.claude-plugin/marketplace.json` /
  `README.md` opening.
- **Must not flag**: a two-line preamble that names a *constraint* on the repo ("plugins here must
  still be reusable and repo-agnostic") — that is policy, not description.

### CR-3 — Gotcha share (from C3)

- **Surface**: CLAUDE.md.
- **Observable**: classify every non-blank, non-heading line into the buckets in CR-5. FAIL when
  lines classified `gotcha` + `keep-class` (rationale, convention-differing-from-default) are ≤ 50%
  of non-structural bytes.
- **Must not flag**: a user-global `~/.claude/CLAUDE.md`, which has no codebase to hold gotchas
  about. This criterion is scoped to *project* CLAUDE.md only. See Conflicts §3.

### CR-4 — Derivability cut (from C5) — the discriminator

Do not use the article's bare "could an agent derive this?" as the primary test; it over-cuts. Apply
upstream's three-bucket test first, and the derivability question only as tiebreaker.

**Step 1 — named classes (`/doctor`, verbatim).**

- CUT on sight: directory layouts, dependency lists, architecture overviews.
- KEEP on sight: pitfalls, rationale, conventions that differ from tool defaults.

**Step 2 — tiebreaker for lines in neither class.** Ask: *is this derivable **before acting**, by an
agent doing the work the line governs, at low cost?*

Three qualifiers, each of which rescues a line that a naive derivability test would cut. These are
the documented false-positive shapes:

| Shape | Test | Verdict |
|---|---|---|
| **Rationale** | Derivable-in-principle from the code, but the *why* is not recoverable from any file. | KEEP. Upstream names rationale a keep-class outright, so this false positive is documented, not inferred. |
| **Derivable only after the mistake** | The fact is discoverable, but nothing prompts the agent to look, and the failure is silent and lands after the edit lands. | KEEP. `AGENTS.md:9-16` (synced files are overwritten by the next sync) is exactly this: derivable from `standards/distribution/sync-manifest.yml` by an agent that thought to check, and by no one else. |
| **Derivable but expensive or ambiguous** | Recoverable, but only via multiple fetches/greps, or with more than one plausible answer. | KEEP only if the cost is repeated every session AND no in-repo pointer already caches it. If an in-repo file already holds it, DEMOTE to a one-line pointer rather than keep. |

- **Surface**: CLAUDE.md, `.claude/rules/*.md`, agent definitions, `AGENTS.md`.
- **Observable**: every non-structural line carries a Step-1 class or a named Step-2 qualifier. A
  line with neither → FAIL (cut candidate).
- **Must not flag**: `CLAUDE.md:44-45` ("Installed plugins run from an isolated cache — reference
  only files inside the plugin via `${CLAUDE_PLUGIN_ROOT}`... No `../` reach-outs"). Derivable from
  the plugins docs, but it is a pitfall whose failure mode appears only after install — Step-1 KEEP.

### CR-5 — Line classification buckets (applies to CR-3 and CR-4 output)

`structural` (heading/blank) · `purpose` · `gotcha` (pitfall; silent or post-hoc failure) ·
`keep-class` (rationale, or convention differing from a tool default) · `derivable-obvious` (Step-1
cut class, or cheap pre-act derivation) · `duplicate` (stated verbatim elsewhere in-tree) ·
`operator-opinion` (a preference with no repo referent) · `pd-candidate` (real content, wrong tier).

### CR-6 — Progressive disclosure uses a deferring mechanism (from C6)

- **Surface**: CLAUDE.md, `.claude/rules/`.
- **Observable**: any content moved out of CLAUDE.md "for progressive disclosure" lands in a skill,
  a `paths:`-scoped `.claude/rules/*.md`, or a subdirectory `CLAUDE.md` — and the CLAUDE.md
  reference to it is a **backticked path or a markdown link, never a bare `@path`**. A bare `@path`
  import presented as progressive disclosure → FAIL, because imports load at launch.
- **Must not flag**: `~/.claude/CLAUDE.md:58-69`, the "Reference docs (read on demand)" block. Every
  target is inside backticks, and "Import parsing skips Markdown code spans", so those five files do
  not load. That block is a correct implementation and a required pass case.
- **Must not flag**: a deliberate `@AGENTS.md` import added purely to make `AGENTS.md` visible. That
  import is a *visibility* fix, not a disclosure claim; it costs the file's tokens by design.

### CR-7 — Multi-step procedure extraction (from C7)

- **Surface**: CLAUDE.md.
- **Observable**: FAIL any CLAUDE.md block that (a) spans ≥ 5 lines, (b) is a procedure or an
  enumerated lookup table rather than a rule, and (c) is needed by fewer than half of plausible
  sessions. Route to a skill (procedure) or a `paths:`-scoped rule (file-class-specific).
- **Must not flag**: a 6-line list of short unconditional "always do X" rules. Length alone is not
  the trigger; conditional applicability is.

## Targets in this repo

### Population

```
$ find . -iname "CLAUDE.md" -not -path "./node_modules/*"   →  ./CLAUDE.md          (1 file)
$ find . -iname "AGENTS.md" -not -path "./node_modules/*"   →  ./AGENTS.md          (1 file)
$ ls .claude/                                               →  settings.json  source-control.md
$ ls .claude/rules                                          →  No such file or directory
$ ls plugins | wc -l                                        →  60
$ find plugins -name SKILL.md | wc -l                       →  187
```

**Absence findings, with where I looked**: there is no `.claude/CLAUDE.md`, no `CLAUDE.local.md`
anywhere, no `rules/` directory under any `.claude/` in the tree (`find . -type d -name rules -path
"*.claude*"` → empty), and no nested `CLAUDE.md` (case-insensitive `find` from the worktree root,
excluding `node_modules`). Three further `.claude/` directories exist under
`plugins/source-control/skills/{commit,pull-request,setup}/` but hold only `source-control.md`
fixtures for the config resolver — no memory files. The repo therefore has exactly one auto-loaded
project memory file. `.claude/rules/` is the routed home for every `pd-candidate` below and does not
yet exist.

Note: the brief's figure of ~181 skills is now 187 by measurement.

### Measurements

| File | Lines | Bytes | Est. tokens (bytes ÷ 4) | Bytes/line | Loads at startup? |
|---|---|---|---|---|---|
| `CLAUDE.md` | 63 | 3,986 | ~1,000 | 63.3 | Yes |
| `AGENTS.md` | 28 | 1,261 | ~315 | 45.0 | **No** |
| `~/.claude/CLAUDE.md` | 69 | 10,550 | ~2,640 | 152.9 | Yes |

Always-loaded total for a session in this repo: **132 lines / 14,536 bytes / ~3,630 est. tokens**,
reloaded into every non-fork subagent except Explore and Plan. The global file is 2.4× denser per
line than the repo file and carries 73% of the always-loaded bytes.

### `CLAUDE.md` — full line classification

| Lines | Content | Class | Action |
|---|---|---|---|
| 1, 6, 12, 31, 36-38, 51-53, 58-60 | headings / blanks | `structural` | — |
| 3-4 | "This repository is a private Claude Code plugin marketplace. Plugins here must still be reusable, repo-agnostic, configurable by consumers, and safe in plugin form." | `purpose` + `keep-class` | **KEEP.** Passes CR-2: 2 lines, and the second line is policy, not description. Model answer to C2. |
| 8-11 | Fresh-docs mandate prose | `keep-class` (convention differing from default) | KEEP. Non-derivable process rule. |
| 13-30 | 18-line table of 15 canonical doc URLs | `duplicate` | **CUT to one pointer line.** Verified: all 15 URLs are a strict subset of the 35 in `docs/OFFICIAL-DOCS.md`, which line 30 *already points at*. The table is a hand-copied subset of a file the repo owns. 1,219 bytes, **30.6% of the file**. Violates the user's own `~/.claude/CLAUDE.md:31-32` (never hand-copy; pointer-not-copy). |
| 32-33 | JSON Schema URLs | `derivable-obvious` (expensive) | Fold into `docs/OFFICIAL-DOCS.md` with the rest. |
| 33-34 | "Claude Code ignores the `$schema` field at load time" | `gotcha` | **KEEP.** Prevents a wrong assumption that no file states. Textbook C3/C4 content. |
| 39-40 | Repo-agnostic: no hardcoded paths | `keep-class` | KEEP. |
| 41-43 | Configurable via `userConfig` without a fork | `keep-class` | KEEP. |
| 44-45 | Isolated cache; `${CLAUDE_PLUGIN_ROOT}`; no `../` reach-outs | `gotcha` | **KEEP.** Silent, post-install failure — CR-4 Step-1 keep, and a mandatory non-flag case. |
| 46 | "Git history is durable: scrub before the first commit, not after" | `gotcha` | **KEEP.** Irreversible; highest-value line in the file per byte. |
| 47 | "Set an explicit semver `version` in each `plugin.json`" | `derivable-obvious` | **CUT candidate.** Measured: 60/60 `plugins/*/.claude-plugin/plugin.json` already carry `"version"`. Any agent copying an existing plugin derives this pre-act at zero cost. |
| 48-50 | Security review gate; deny-by-default on egress | `keep-class` | KEEP — but see `pd-candidate` note: the gate's *procedure* lives in `docs/MIGRATION-PLAYBOOK.md` (102,503 bytes) and is correctly pointed at, not inlined. |
| 54-57 | Pointers to `docs/PLUGIN-PHILOSOPHY.md` and `docs/MIGRATION-PLAYBOOK.md` | `keep-class` | **KEEP — CR-6 pass case.** Markdown links, not `@` imports, so 137,048 bytes of design doc stay out of context. This is the section's C6/C7 pattern already done right; criteria must not flag it. |
| 61-63 | Conventional Commits PR titles; enforced by `.github/workflows/pr-title.yml`; org convention home | `duplicate` + `derivable-obvious` | **CUT candidate.** The same rule is stated in `AGENTS.md:26` and the convention seam is declared in `.claude/source-control.md`. `.github/workflows/pr-title.yml` exists and enforces it mechanically. Three statements of one fact. |

Repo-file verdict against C3: `gotcha` + `keep-class` bytes are roughly 2,130 of ~3,830 non-structural
bytes — a bare pass of CR-3, achieved only because the file is short. Removing lines 13-30, 47 and
61-63 and adding one pointer line takes it to ~2,450 bytes / ~42 lines with the gotcha share above 80%.

### `AGENTS.md` — full line classification, and the finding that dominates it

**All 28 lines are dead context for Claude Code.** Upstream: "Claude Code reads `CLAUDE.md`, not
`AGENTS.md`." `ls -la` shows `AGENTS.md` as a regular file (`-rw-r--r--`), not a symlink, and
`CLAUDE.md` contains no `@AGENTS.md` import. So none of this reaches a session, and the two files
have been maintained as if both did.

| Lines | Content | Class | Action if the file is made visible |
|---|---|---|---|
| 1, 8, 10, 17, 19, 23, 25 | headings / blanks | `structural` | — |
| 3-7 | "It complements the repository's own `README.md`... Read the README first for repository shape" | `derivable-obvious` | **CUT.** This is an instruction to load a 35,350-byte README at session start — the exact anti-pattern C1/C5 target. Also self-describing meta-prose. |
| 9, 11-16 | "Synced standards are overwritten, not edited here" | `gotcha` — best in the tree | **KEEP and promote.** Derivable from `sync-manifest.yml` only by an agent that thought to look; the failure ("a local edit to such a file is silently lost") is silent and post-hoc. The canonical CR-4 Step-2 rescue case. |
| 18, 20-22 | "Stage explicit paths. Never `git add -A`" | `keep-class` (differs from tool default) | KEEP. |
| 24, 26-27 | Conventional Commits PR titles | `duplicate` of `CLAUDE.md:61` | CUT one of the two. |
| 27-28 | "Resolve every review thread before merging" | `keep-class` | KEEP. |

**Routed fix**: add `@AGENTS.md` as the first line of `CLAUDE.md` per the documented pattern, then
de-duplicate the PR-title rule across the two files and cut `AGENTS.md:3-7`. Net effect is a small
reduction (+~800 bytes of newly-visible `AGENTS.md` gotcha, −1,219 bytes of doc-URL table −~600 bytes
of duplicate and derivable lines) while making the single best gotcha in the repository actually load
for the first time.

### `.claude/source-control.md` — not orphaned, but not auto-loaded either

`grep -rn "source-control\.md"` returns 19 in-tree references (`docs/conventions/commit-convention/README.md:12`,
`docs/conventions/config-cascade/README.md:207`, `plugins/source-control/.claude-plugin/plugin.json:5`,
`plugins/guardrails/.claude-plugin/plugin.json:62`, among others). It is a plugin-read config seam,
deliberately not a memory file. Correct as-is; it is *not* a CLAUDE.md progressive-disclosure target,
and criteria must not flag it as one. Worth noting only because `.claude/` is not an auto-load
directory except for `CLAUDE.md` and `rules/*.md`, so its placement carries no implicit load cost.

### `~/.claude/CLAUDE.md` — full line classification (READ-ONLY; recommendations only)

Nothing below is an edit. Every routed change goes through the dotfiles repo
(`melodic-software/dotfiles`, source `dot_claude/`) via its `add-dotfile` / `reconcile-drift` flow,
per `~/.claude/CLAUDE.md:51-56`.

| Lines | Section / content | Class | Recommendation |
|---|---|---|---|
| 1-2, 9-11, 16-18, 26-28, 36-38, 40-42, 44-46, 50-52, 57-59 | headings / blanks | `structural` | — |
| 3 | "Be succinct and concise; never ambiguous." | `operator-opinion` | Keep. 43 bytes, high leverage. |
| 4-7 | List rendering; RECOMMENDED-first questions; copy-paste markers; inline questions not AskUserQuestion | `operator-opinion` | Keep. Non-derivable output-format preference; each is concrete and verifiable per the memory page's specificity guidance. |
| 8 | Multi-agent consolidated state block (675 bytes — the single largest line in the file) | `operator-opinion` + `pd-candidate` | **Route to a skill or `~/.claude/rules/`.** It governs one situation (agents in flight) and costs 675 bytes in every session, including single-turn sessions with no agents. Strongest global-file PD candidate. |
| 12-15 | Research & verification (3 lines, 1,121 bytes) | `operator-opinion` | Keep 12 and 15. Line 13 (444 B) and 14 (522 B) are procedure, not rule — PD candidates, but see the note below on the re-anchor plugins. |
| 19-25 | Problem-solving & decisions (7 lines, 1,798 bytes) | `operator-opinion` | Keep. These are the operator's actual decision posture; none is derivable from anything. Largest single block, and legitimately so. |
| 29-35 | Engineering quality (7 lines, 2,297 bytes) | `operator-opinion` | Keep 29, 31, 32, 34. Line 30 (475 B, producer≠critic≠tester) and 33 (604 B, comment policy) are the two heaviest; both are already fully implemented by installed plugins (`review`, `code-tidying:audit-comment-residue`) — PD candidates. |
| 39 | Review severity vocabulary (582 bytes) | `pd-candidate` | **Route to `~/.claude/docs/`.** Pure reference material about which vocabulary is authoritative. Needed only during a structured review, which is exactly when a review skill loads. Costs 582 bytes in every unrelated session. |
| 43 | Commit trailer precedence (456 bytes) | `pd-candidate` | **Route to `~/.claude/docs/`** or into the `source-control` plugin's own config resolution, which already owns per-key precedence. Needed only when committing. |
| 47-49 | Cross-repository ownership | `gotcha` (org-level) | **Keep — the closest thing in this file to a true gotcha.** "A `managed` component is upstream-owned and returns through a reviewed sync PR" is a silent, post-hoc failure across repos. Same shape as `AGENTS.md:11-16`. |
| 53-56 | User directory & dotfiles (1,112 bytes) | `gotcha` | **Keep.** Line 56's chezmoi orphan behavior ("deleting the source alone only orphans the deployed copy... so the skill would keep loading fleet-wide") is non-derivable, silent, and fleet-wide. Highest-value block in the file. |
| 60 | "These files are not loaded automatically. Use the Read tool when the task touches that domain." | `structural` / correct | Keep. |
| 62-69 | Reference docs block, 5 backticked paths + 1 URL | **correct progressive disclosure** | **Keep unchanged. This is a pass case, not a finding.** Paths are inside backticks, and import parsing skips code spans, so none of the five files load. Measured deferred payload: 10,829 bytes across the five `~/.claude/docs/*.md` files — slightly more than the CLAUDE.md that references them. The comment on 67-69, deliberately citing a URL so it cannot drift, is the pointer-not-copy rule applied to its own reference block. |

**Is the reference-docs pattern applied correctly?** Yes, on all three axes that matter: the
mechanism defers (backticked paths, not `@` imports); the block states its own contract on line 60
so the reader knows to Read rather than assume; and one entry deliberately points at an upstream URL
rather than a local copy. No change recommended to lines 58-69 themselves.

**Should more content go behind it?** Yes — five candidates, in descending byte order: line 8
(675 B), line 33 (604 B), line 39 (582 B), line 30 (475 B), line 43 (456 B). Together 2,792 bytes,
**26.5% of the file**, each needed by a narrow and identifiable class of session. Routing all five
would take the global file from 10,550 to ~7,760 bytes.

**Caveat on that recommendation**: `~/.claude/docs/` is Read-on-demand only — nothing makes Claude
notice it is relevant. `~/.claude/rules/` (loaded before project rules, and supporting `paths:`
frontmatter) or a user-scope skill are the mechanisms with an actual trigger. For line 8 and line 30
a skill is the better home; for lines 33, 39, 43 a docs entry is adequate because the consuming
plugin already knows to look. Note also that this repository *already ships* skills covering several
of these (`re-anchor:do-your-research`, `re-anchor:point-dont-copy`, `re-anchor:tighten-your-output`,
`code-tidying:audit-comment-residue`), which is an argument for routing rather than deleting.

## Conflicts and ambiguity

**1. Upstream contradicts itself on project layout.** memory's "When to add to CLAUDE.md" names
"project layout" a keeper; the `/doctor` entry names "directory layouts" a cut-class. Both fetched
this session, both current. The reconciliation I'd propose — a one-line orientation pointer is
layout, a rendered tree is a directory layout — is *my* reading and is not stated anywhere upstream.
Flagging rather than resolving: any criterion that cuts layout content is standing on contested
ground, and this repo's `CLAUDE.md` happens to contain none, so nothing here turns on it.

**2. The article's "reference it from your CLAUDE.md" is mechanism-blind, and the obvious reading is
wrong.** `@path` imports are the natural way to read "reference", and they defer nothing: "imported
files still load and enter the context window at launch." An operator who follows C6 literally with
`@` syntax pays full price and believes they have paid nothing. This is the sharpest conflict in the
section, and it is a conflict of omission — the article is not false, it is silent on the one detail
that decides whether the advice works.

**3. C3 does not generalize to user-global CLAUDE.md, and the article's model has no slot for what
lives there.** `~/.claude/CLAUDE.md` is 10,550 bytes, of which by my classification ~7,680 are `operator-opinion`
(total, minus 1,811 bytes of gotcha at lines 47-49 and 53-56, 822 bytes of reference block at 60-69,
and 241 bytes of headings): how to communicate, how to decide, who may review whose work. It is not gotcha,
not derivable-obvious, and there is no codebase for it to hold gotchas *about*. The article's
two-bucket model (brief purpose + mostly gotchas) is written for a *project* CLAUDE.md and does not
describe the user-global file at all — whose entire job is non-derivable preference. Do not soften
this to "mostly applies": applying C3 to the global file would score it a near-total failure, and
that score would be meaningless. CR-3 is scoped to project files for this reason.

**4. The 200-line target is a poor proxy and passes both files here.** `CLAUDE.md` (63) and
`~/.claude/CLAUDE.md` (69) both clear it comfortably, yet the global file carries 2.6× the bytes of
the project file at 2.4× the density. A line-count threshold cannot see this. Upstream's own
auto-memory limit is dual (200 lines **or** 25KB, whichever comes first) — the CLAUDE.md guidance
inherited only the line half. CR-1's byte clause is my extrapolation from the auto-memory rule and is
labelled as such; it is not official guidance for CLAUDE.md.

**5. Deferring content does not reduce cost if the deferred file is read anyway — and per-subagent
multiplication cuts the other way.** Because non-fork subagents each reload the whole CLAUDE.md
hierarchy, a byte trimmed from `~/.claude/CLAUDE.md` is saved once per agent, not once per session.
In a repo whose own plugins fan out (`review:fanout`, `session-flow:orchestrate`, the agent-team
topology this very task runs under), that multiplier is the strongest argument for the C6 routing in
§"Should more content go behind it". Conversely, a rule routed *out* of CLAUDE.md is no longer
guaranteed to reach a subagent at all — the sub-agents page: "If a rule must [reach the subagent],
restate it in the prompt you give Claude when delegating." So progressive disclosure of a rule that
governs *delegated* work trades tokens for reliability. `~/.claude/CLAUDE.md:8` and `:30` — the two
biggest PD candidates — are precisely rules about delegation, which is the argument *against*
routing them. I flag this as a genuine tension, not a settled recommendation.

**6. This repository already owns a more careful version of C5, and it disagrees with the article's
framing.** `plugins/docs-hygiene/skills/audit-derivability/SKILL.md` (142 lines) states: "A verdict
is never 'derivable, therefore delete.' Derivability is one factor of four" — the others being
re-derivation cost, drift risk, and fact ownership, with fact ownership as "the trump card". It also
names `CLAUDE.md` and `AGENTS.md` as agent-facing surfaces that "get the full axe", and mandates a
fresh-context spot-test before a confident delete, on the grounds that a context that has read the
document "will overestimate how derivable they were — a self-grade." The article's single-factor
"avoid the obvious" is strictly weaker. The criteria above should be routed *into* that skill's
rubric, not published as a competing test. Also relevant: `plugins/claude-memory/skills/audit/SKILL.md`
(105 lines) and `plugins/claude-config/skills/audit-instructions/SKILL.md` (166 lines) are the
existing homes for CLAUDE.md-specific auditing — three skills already occupy this space.

**7. C4's worked example does not transfer to this repository.** "Types in one monolithic file and
nowhere else" is a source-code-organization gotcha; this repo is 187 markdown skills and JSON
manifests with no type system. The *class* transfers (a convention that a competent agent would
guess wrong); the example does not, and a reviewer applying C4 literally here will find nothing and
wrongly conclude the file is clean. The repo's actual instances of the class are `CLAUDE.md:44-45`
(cache isolation), `CLAUDE.md:33-34` (`$schema` ignored at load), and `AGENTS.md:11-16` (synced files
overwritten).

**8. `/doctor` would act on this repo's CLAUDE.md, and its trim is not free.** The `/doctor` entry
says it "migrates the always-loaded guidance that remains into skills and nested `CLAUDE.md` files
that load on demand" and "Reports findings first and asks for confirmation before changing anything."
For a plugin marketplace whose CLAUDE.md is deliberately terse and pointer-heavy, an automated
migration could route the fresh-docs mandate — the one rule the repo calls "non-negotiable" — into a
file that loads only sometimes. The confirmation gate makes this safe, but it is a reason to run
`/doctor` attended here, not a reason to trust its output unreviewed.

## Open questions for the operator

1. **Make `AGENTS.md` load, or delete it?** Recommendation: **make it load** — add `@AGENTS.md` as
   line 1 of `CLAUDE.md` per the documented pattern, then cut `AGENTS.md:3-7` and the duplicated
   PR-title rule. It contains the repository's single best gotcha and currently reaches nothing.
2. **Cut `CLAUDE.md:13-30` (the doc URL table) to a pointer at `docs/OFFICIAL-DOCS.md`?**
   Recommendation: **yes**, verified strict subset, 29.6% of the file, and line 30 already points at
   the superset. Risk to weigh: the mandate's teeth may depend on the URLs being in-context rather
   than one Read away.
3. **Create `.claude/rules/` in this repo?** Recommendation: **not yet.** With a single 63-line
   CLAUDE.md that will drop to ~35 lines after items 1-2, there is nothing to scope. Revisit when a
   rule is genuinely file-class-specific.
4. **Route the five global-file PD candidates (lines 8, 30, 33, 39, 43 — 2,792 B, 26.5%)?**
   Recommendation: **route 33, 39, 43 to `~/.claude/docs/`** (their consuming plugins already know
   to look), and **hold 8 and 30** pending the delegation-reliability tension in Conflicts §5. All
   via the dotfiles `add-dotfile` flow; never a direct edit.
5. **Should CR-1's byte threshold be adopted as a repo standard, given it is my extrapolation and not
   official guidance?** Recommendation: **adopt it as advisory only**, cited as extrapolated from the
   auto-memory 200-line/25KB dual limit, until upstream states a byte figure for CLAUDE.md.
6. **Where do these criteria land?** Recommendation: **into the existing
   `docs-hygiene:audit-derivability` rubric and `claude-memory:audit`**, as a CLAUDE.md-specific
   application of an already-better framework — not as a new skill. Three skills already cover this
   surface.

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, any other worktree
under `D:/repos/.worktrees/`, or any other agent's file under `sections/`. Every repo command was run
against `D:/repos/.worktrees/context-engineering-rightsizing` only. The `grep -rn "source-control.md"`
sweep did surface paths under `docs/topics/` — `babysit-prs-migration` and
`commit-convention-well-known-path`, neither fenced — and I read no file under `docs/topics/`.
