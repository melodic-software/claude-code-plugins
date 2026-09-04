# handoff-prompt-qol

## Brief

### TLDR

- `/session-flow:handoff` always ends with a well-formed copy/paste resume prompt, and the prompt is also stored in the handoff file as its final `## Resume prompt` section.
- Handoff shape 2: one self-contained file per hop carrying the full chain, transcript path, opening ask, per-session one-liners, and provenance-tagged cumulative sections (design: `design/design-threads.md`).
- One script (`new` / `validate` / `emit`) owns every deterministic field; the model writes only reasoning slots; `validate` gates the rails.
- The three surfaces that license free-hand handoff files (resume directive, `context-guard` zone-gate, `implementation` implement fallback) tell the successor to invoke the skill.
- Acceptance is a headless `claude -p` harness over a 3-hop chain, plus validator fixtures and updated evals. No hooks.

### Goal

An operator who runs `/session-flow:handoff`, or resumes from any handoff file, always gets a uniform, validated save-point: the copy/paste prompt is on screen and in the file, every breadcrumb a fresh session needs (session id, transcript, whole chain, verbatim goal and opening ask, what each prior session did, what is still binding and who asserted it) is in the one file, and successor sessions keep using the skill instead of writing handoffs free-hand. Context carried across a `/clear` is high-resolution for the last session and pointer-backed for prior ones, so the handoff beats `/compact` on fidelity.

### Constraints

- No new hooks; no extension of the existing SessionStart hook in V1. The deferred Stop hook stays deferred (revisit on recurrence after this ships).
- Consumers keep working unchanged unless named: `retro` reads frontmatter `session_id` + bare-filename `previous_handoff`; `orient` reads `Resumption brief`; `keep-going` / `reanchor` read `Original goal`; `find-handoff` rung 3 keys on U+2500 rails, the `Read @…handoffs/<TS>-handoff-…` directive, and `Prior session: <UUID>`; `continue-in-background` takes exactly the between-rails text; `context-guard` zone-gate exempts paths containing `handoff`.
- Rails are U+2500 only, exactly two, `## Resume prompt` is the final section, `Next:` ≤5 headline lines between the rails, `Then: /<one skill>` only at a stage boundary; one `Handoff origin:` form: `Handoff origin: <remote URL, userinfo stripped> <repo-relative path>`.
- Frontmatter shape 2: `type, handoff_shape, date, topic, session_id, transcript, previous_handoff, chain[]` (bare filenames, root first). No `hop` field, no index file.
- Body: the existing 14 sections in order, `Opening ask:` line in `Original goal` (verbatim at hop 1, pointer to `chain[0]` after), the five cumulative sections (Constraints, Side effects, Decisions, Abandoned, Findings) copied forward with `[hN]` provenance tags and a `Superseded:` line (never deleted), `## This session` (`did: … · left: …`, past tense, no "next"), `## Prior sessions` table (predecessor's rows verbatim + predecessor's own row), `## Resume prompt` last, plus a below-rail `claude --resume <session_id>` line.
- `session_id` comes from `CLAUDE_CODE_SESSION_ID` (never `CLAUDE_CODE_BRIDGE_SESSION_ID`), validated as a UUID with an existing transcript; transcript resolved by the documented `~/.claude/projects/*/<session_id>.jsonl` glob and `stat`ed at write, `unresolved (…)` when absent.
- Validator: absent `handoff_shape` = shape 1 → WARN, checks skipped, rails still emitted, file never rewritten; `handoff_shape` higher than known → hard fail "read it, do not rewrite it"; any leftover `<!-- FILL -->` slot, prefixed pointer, non-UUID session id, missing transcript, heading out of order, non-U+2500 rail, `Next:` > 5 lines → non-zero, rails not emitted.
- Prompt-only path untouched. Legacy files never rewritten. Scripts are read-only on the repo except the handoff file they create.
- Repo conventions: plugin version bumps + changelog for every touched plugin (session-flow, context-guard, implementation); `docs/conventions/hook-*` are not engaged (no hooks); handoff files stay gitignored memory tier.

### Acceptance criteria

- Headless harness (`claude -p`, `--output-format json`, `--max-turns`, fixture repo): a 3-hop chain where each hop ends with `/session-flow:handoff`; every produced file passes `validate` (exit 0); the assistant's final text contains exactly two U+2500 rails and its between-rails text byte-equals the file's `## Resume prompt` between-rails text, on 100% of runs (run count N set by the plan); a fourth session resumed via the hop-3 prompt invokes `/session-flow:handoff` through the Skill tool (Skill call present in its transcript before any handoff write).
- Validator fixtures under the plugin's scripts tests: shape-1 legacy → WARN + exit 0; shape-2 good → exit 0; prefixed `previous_handoff` → non-zero; non-UUID `session_id` → non-zero; ASCII rails → non-zero; leftover FILL slot → non-zero; `handoff_shape: 3` → hard-fail exit distinct from validation failure.
- `emit <file>` prints the `## Resume prompt` section verbatim; `find-handoff` rung 1 returns it for any shape-2 file; `continue-in-background` sources its payload from it.
- `retro`'s chain walker resolves a `previous_handoff` carrying a `handoffs/` prefix by basename (regression test on the existing fixture chain).
- The three licensing surfaces are reworded: the resume directive gains the invoke-the-skill line; `plugins/context-guard/hooks/zone-gate.sh` deny reason names only the skill; `plugins/implementation/skills/implement/SKILL.md` fallback note includes the rails prompt.
- `structure.md` and `save-point.md` document shape 2 (sections, frontmatter, `<repo-identity>` now stored); handoff `evals.json` updated so every rails case also asserts "validator ran, exit 0, on-screen rails == file section"; skill-quality check passes for the touched skills.
- Resume-read budget at hop 1, 5, 20 measured by the harness and recorded in `design/design-threads.md`, replacing the estimates.

### Captured assumptions

- The 10/25 no-rails sample partly overlaps an unhobble / handoffs-disabled window, so the free-hand rate is an upper bound; the fix is instruction-only either way — revisit if a free-hand write recurs after this ships (that is the Stop-hook trigger).
- `CLAUDE_CODE_SESSION_ID` is undocumented but present in Bash tool commands — revisit if it disappears in a Claude Code release (fallback: the existing SessionStart hook recording `session_id` / `transcript_path` to `${CLAUDE_PLUGIN_DATA}`).
- The script is Python with no third-party dependencies (the repo already ships Python for retro's chain walker) — revisit if a plan-stage check shows Python absent on a target machine.
- `claude plugin eval` is undocumented; the harness is `claude -p` based — revisit if it becomes documented.
- Growth of ~2 lines per hop plus net-new tagged knowledge is acceptable — revisit if the measured hop-20 budget exceeds ~4k tokens.

### Out-of-scope

- Cleaning or migrating the 94 legacy handoff files (never rewritten; shape 1 tolerated on read).
- Any hook (Stop, PostToolUse, PreToolUse deny) — explicitly declined; SessionStart hook not extended.
- Collapsing or changing the prompt-only path.
- CI wiring of the headless harness (plan may propose; not required for acceptance).
- A separate per-topic index file; a `hop` field; storing the opening ask verbatim in every hop.

### Deferred questions

- Q13 — Were the three free-hand writes on 2026-09-03 (00:27, 01:22, 01:56) inside the handoffs-disabled window? — defer until the plan's evidence section is written; **arbiter: USER-RESERVED** (affects only the recorded evidence, not scope).

## Plan

### Approval record (2026-09-03)

Plan approved by the user as presented ("approved"), with every gate recommendation adopted and no
flip reply sent. The Brief text above stays as locked; the following amendments are recorded here
and govern implementation:

1. **Validator failure after the bounded fix loop:** the skill emits the rails from the file's
   `## Resume prompt` section anyway, with an `UNVALIDATED: <validator output>` banner ABOVE the
   top rail (outside the copy region); the checklist box reads `validate: FAILED`. Supersedes the
   Brief's "rails not emitted" for this case.
2. **Transcript strictness:** a stated `transcript:` path that does not exist → FAIL; the honest
   `unresolved (…)` value → WARN (exit 0) by default, FAIL under `--strict-transcript` (the
   harness passes it).
3. **Harness N:** 3 light-context runs at the CLI's default model plus 1 padded-context run
   (`--pad-context`); each hop bounded by `--max-turns`, `--max-budget-usd 3`, and a timeout;
   every live run announced with its cost before spending.
4. **Scope option declined (user, same day):** the `implement` Step 4 ritual reorder (items 3–5
   after a hard-STOP skill) is filed as a follow-up work item, NOT changed in this PR; the PR body
   names the follow-up at its end (Phase 6).
5. **Q13 (USER-RESERVED):** not ruled at approval. The evidence section stands as recorded; the
   Captured-assumption "upper bound" wording is unchanged. Re-raise only if the user rules later.
6. **Standards index:** not persisted (no request); the plan keeps its rung-4 inference grounding.

### Goal

**What**: make `/session-flow:handoff` produce a shape-2 save-point whose deterministic fields a
script owns (`new` / `validate` / `emit`), whose file carries its own resume prompt as the final
`## Resume prompt` section, and whose successor sessions are told by every licensing surface to
invoke the skill; prove it with validator fixtures and a headless 3-hop `claude -p` harness.
**Why**: the audit shows the prompt goes missing only when the skill is never loaded (10/25 writes),
and shape drift (ASCII rails, five origin forms, bridge ids, prefixed pointers) comes from the model
re-deriving deterministic fields by hand. Script the deterministic tier, store the prompt, close the
free-hand licences.

### Standards grounding

No standards index exists (`docs/standards/README.md` absent, no `.claude/standards.yaml`), so this
is rung-4 inference from non-ambient repo context. Offer-to-persist is raised once at the approval
gate; nothing is written unprompted.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| validate-a-change | `AGENTS.md` "Validate a change" (`scripts/affected-tests.sh --run`; R2 co-located suite naming: `<stem>.test.sh`, `test_<stem>.py`, `<dir>/tests/test_<stem>.py`, `-` folded to `_`) | team |
| python | `.claude/rules/ruff-pin.md` (lint via `scripts/run-ruff.sh check`); precedent `skills/retro/scripts/parse_transcript.py` + `parse-transcript.test.sh` (pytest behind a SKIP-on-missing wrapper), `skills/keep-going/scripts/check-usage-limit-reset.py` (documented exit taxonomy) | team |
| shell tests | `docs/conventions/shell-test-helpers/README.md` (per-plugin helpers, per-script exit taxonomies are deliberate) | team |
| windows paths | `docs/conventions/windows-path-emit/README.md` (native side computes its own paths; platform temp, never drive-root `/tmp`) | team |
| plugin contract | `docs/PLUGIN-PHILOSOPHY.md` "Cross-platform contract", "Evidence and validation" (`--plugin-dir` smoke tests, fail-fast boundaries); `docs/conventions/liveness-assertion/README.md` (never green-silent) | team |
| release gates | `scripts/check-changelog-parity.sh --check-bump` (bump ⇒ new `## [v]` entry), `scripts/check-changed-skills.sh` (skill-quality check on touched skills, evals required), `scripts/check-skill-portability.sh`, CI "Check for machine-specific paths" (no `C:/Users/…`, `D:/…` in tracked fixtures) | team |
| skill QA | `plugins/skill-quality/scripts/check-skill.sh` caps (`LINE_SOFT_CAP=200`, `LINE_HARD_CAP=500`, `DESC_FIELD_CAP=1024`), `reference/evals.schema.json`, `check-evals-quality.sh` Q1–Q9 | team |
| hooks | `docs/conventions/hook-*` NOT engaged (no hook added or widened; `zone-gate.sh` change is reason text only) | team |

### Evidence recorded for the deferred question (Q13, arbiter USER-RESERVED)

Mechanical check run 2026-09-03 over the three free-hand sessions' transcripts (`~/.claude/projects/*/<sid>.jsonl`):

| session | first record (UTC) | `session-flow:handoff:` present in the session's skill listing | all 13 session-flow skills listed |
|---|---|---|---|
| `9d379dd1` | 2026-09-03T00:11:57Z | yes (1 hit) | yes |
| `8011f665` | 2026-09-03T00:58:03Z | yes (1 hit) | yes |
| `15c2e770` | 2026-09-02T20:44:07Z | yes (1 hit) | yes |
| control `fe3121c9` (skill path, well-formed) | 2026-09-02 | yes (1 hit) | yes |

The listing is captured at session start; it does not show a plugin disabled mid-session. Current
`~/.claude/settings.json` has `session-flow@melodic-software: true`. `15c2e770` ran the
`hook-performance-levers` experiment whose baseline records session-flow enabled. Reading: the skill
was visible to all three sessions when they started. The user rules on Q13 at the approval gate;
the answer changes only this evidence section and the "upper bound" wording in Captured assumptions.

### Baseline (measurable goal: resume-read budget)

Shape-1 corpus on this machine, captured 2026-09-03 (read-only; the per-file TSV lives in the
memory slice and is not cited here):

| files | lines median | lines mean | lines p90 | lines max | tokens (chars/4) median | mean | p90 | max |
|---|---|---|---|---|---|---|---|---|
| 96 | 154 | 188 | 296 | 1184 | 3.2k | 3.6k | 5.4k | 21.1k |

The design's "hop 1 ≈170 lines / ≈2.3k tokens" estimate already sits below the shape-1 median in
tokens, so the hop-20 ≤ ~4k target is tighter than the design assumed; Phase 5 measures it with the
same chars/4 method and the comparison is recorded here as distilled values.

### Approach (phases)

Integration-first: Phase 0 settles the headless seam the acceptance criteria depend on; Phase 1 is
the deterministic engine and its fixtures; Phase 2 wires the skill and its consumers to it; Phases
3–4 are file-disjoint side edits; Phase 5 is the live harness; Phase 6 closes out. Technique: kept
tracer bullet (script → spec → harness), after the Phase 0 feasibility spike.

#### Script contract (consumed by Phases 1, 2, 5)

`plugins/session-flow/scripts/save_point.py` — Python 3.10+, stdlib only, invoked from the skill as
`"$PY" "${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py" <subcommand> …` after the retro-style
interpreter ladder (`python3`, then `python`). Read-only on the repo except the handoff file it
creates and the memory root's self-ignore `.gitignore` (announced).

| subcommand | inputs | output | exit |
|---|---|---|---|
| `new --topic <slug> (--previous <file> \| --no-previous) [--memory-dir <root>] [--session-id <uuid>] [--projects-root <dir>] [--repo-root <dir>] [--now <iso>]` | env `CLAUDE_CODE_SESSION_ID` unless `--session-id`; `git remote get-url origin`; predecessor file when given. Exactly one of `--previous` / `--no-previous` is required: chain continuity is the model's judgment (structure.md "Chain continuity — same task only"), never an auto-pick of the newest file | writes `<memory-dir>/handoffs/<TS>-handoff-<slug>.md` skeleton, prints its absolute forward-slash path; never overwrites an existing target | 0 written; 1 refused (root-equivalent memory dir, memory root lacking the self-ignore `.gitignore` `*` — the script verifies the guard and names the fix, it never writes the `.gitignore` itself, keeping the Brief's read-only rule; non-UUID session id, bridge-id shape, predecessor unreadable, target exists); 2 usage (neither or both predecessor flags) |
| `validate <file> [--projects-root <dir>] [--strict-transcript]` | the file; its predecessor beside it when `previous_handoff` is set | PASS/WARN/FAIL lines on stdout | 0 pass (shape 1 → WARN + 0); 1 validation failure; 2 usage / unreadable; 3 `handoff_shape` newer than known ("read it, do not rewrite it") |
| `emit <file>` | the file | the `## Resume prompt` section body verbatim (heading excluded, trailing blank trimmed) | 0; 1 section absent (shape 1: says so) or the file still carries a `<!-- FILL` slot (unfinished skeleton, never emitted); 2 usage |

Cross-platform and shape details the script owns: every write uses `newline="\n"` and UTF-8 (the
harness compares bytes; Windows Python defaults to CRLF); the `Read @` self-path check compares
`Path.resolve()` on both sides, never raw strings (drive-letter case, MSYS `/d/` forms);
`--repo-root` defaults to the git top level of the resolved `--memory-dir`, never cwd (save-point.md:
"name the repository the file was actually written to"); a repo with no `origin` remote, or an
SCP-style one, falls back to the root directory name in `Handoff origin:`; hop 1 writes
`## Prior sessions` as `None (first hop).` and `validate` anchors its "adds exactly one row" check
on that; `validate` also checks that every cumulative entry of the predecessor survives in the
successor in place or on its `Superseded:` line (design T4 "never deleted"); `Opening ask:` longer
than 15 lines at hop 1 is a WARN (design T2 cap); the `[hN]` tag is the engine's
`UNVERIFIED (<source>)` marker for carried entries, and re-verifying an entry re-tags it to the
current hop (design T4), which `structure.md` states explicitly; the skeleton `new` writes is
markdownlint-clean as generated. Module names use underscores (`save_point.py`, `hop_chain.py`) so
pytest imports them directly and affected-tests R2 pairs them with `save_point.test.sh` /
`hop_chain.test.sh` and `tests/test_save_point.py` by exact stem. Encoding is explicit at every
boundary: `sys.stdout.reconfigure(encoding="utf-8")` at entry, `encoding="utf-8"` on every open,
and the skill invokes `python3 -X utf8 …`. A rail is a line consisting solely of ten or more U+2500
characters. `Next:` may read `Next: none (closed)` for a closing handoff (zero headline lines);
otherwise 1–5. The skeleton pre-places `## This session` as `did: <!-- FILL --> · left: <!-- FILL -->`
and `validate` rejects a `|` in that line (it becomes a table cell downstream); `None.` lines in
the five cumulative sections are exempt from the `[hN]` rule. `Handoff origin:` slots that contain
whitespace are double-quoted; on the no-project-root branch the second slot is the absolute path.
Legacy predecessors: a shape-1 file may carry the older 7-section body (`## Task`, `## Progress`,
`## Decisions made`, …; 11 of 33 files in this checkout's corpus, 16 without `## Original goal`);
`new` maps an absent section to `None. (shape-1 predecessor had no <section>)`, and an absent
goal to a `<!-- FILL: goal — RECONSTRUCTED from the transcript; settle with the user -->` slot that
`validate` refuses to pass while empty or placeholder-shaped. `validate` also runs a WARN-only
secret-shape scan (the shape-marker regexes `running-retro/scripts/observer.py` already holds);
the model rules on hits. `emit` compares the stored `Read @` path with its own real path and, on a
mismatch (a file preserved out of a removed worktree), prints a WARN to stderr and substitutes the
current path on stdout only, never rewriting the file.

Unfinished skeletons (a `new` re-run after compaction, or a fix loop that ended `UNVALIDATED`) stay
on disk as `type: handoff` files with `<!-- FILL` slots. They are never emitted, `find-handoff`
rung 1 skips them and names them as unfinished, `continue-in-background` cannot launch from one
(its `validate` gate fails first), and cleanup stays user-controlled like every other handoff file.

Malformed predecessor: when `--previous` names a file that itself fails shape-2 validation (or a
hand-written Python-absent file), `new` still copies forward what it can and tags the carried rows
`UNVERIFIED (predecessor failed validation)`; `validate` on the successor downgrades the
predecessor-derived prefix checks (chain prefix, Prior-sessions prefix) to WARN with the
predecessor's failure named, so one bad hop never blocks every later hop. The predecessor is never
rewritten.

`new` fills every deterministic field: filename + `date:`; `session_id` (UUID-validated; the
`CLAUDE_CODE_BRIDGE_SESSION_ID` value is never read and a `cse_`/non-UUID id is refused);
`transcript:` resolved by `<projects-root>/*/<session_id>.jsonl` (`--projects-root` default
`~/.claude/projects`) and `stat`ed, else `unresolved (session <id>, projects-root <dir>)`;
`previous_handoff` (bare filename) + `chain:` (predecessor's chain + self; `[self]` at hop 1;
shape-1 predecessor → `[predecessor, self]`); `handoff_shape: 2`; heading scaffold (14 sections in
order, then `## This session`, `## Prior sessions`, `## Resume prompt`); `Original goal` quote and
amendments copied off disk + `Opening ask:` (hop 1: `<!-- FILL -->` verbatim slot; hop N>1: pointer
`see <chain[0]> § Original goal`; shape-1 root: same pointer with `(shape-1 root, no verbatim ask
recorded)`); the five cumulative sections (§4, §6, §8, §9, §10) copied verbatim with `[hN]` tags
(untagged legacy entries get `[h1]`), a `Superseded:` line preserved; `## Prior sessions` = the
predecessor's rows verbatim + the predecessor's own row (`date · session id · transcript · did/left
· file`; a shape-1 predecessor's `did/left` cell reads `UNVERIFIED (shape-1 predecessor; brief:
<first Resumption brief line>)`); the rails block: copy instruction, top rail, `Read @<abs path>,
confirm its Original goal still governs the remaining next steps, then continue them. For the next
save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.`,
`Prior session: <uuid>.`, `Handoff origin: <remote URL, userinfo stripped> <repo-relative path>`,
`Next:` FILL slot (≤5 headline lines; last may be `Then: /<skill>`), bottom rail, below-rail
`claude --resume <session_id>` line, plus deletable optional slots for the `/goal` first line and the
`Re-arm` entries. Reasoning slots are `<!-- FILL: <name> — <instruction> -->` and every one must be
filled or (optional ones) deleted before `validate` passes.

`validate` (shape 2): required frontmatter keys; `date` ISO Z; `session_id` UUID; `previous_handoff`
matches `^\d{8}T\d{6}Z-handoff-.+\.md$` and exists beside the file; `chain[-1]` = own basename,
`chain[-2]` = `previous_handoff`, predecessor's `chain` is a strict prefix; predecessor's
`## Prior sessions` rows are a prefix of this file's and this file adds exactly one row; the 17
headings in order with `## Resume prompt` last; `Opening ask:` line present; every entry in the five
cumulative sections carries an `[hN]` tag with N ≤ len(chain); `## This session` is one line `did: …
· left: …`; no leftover `<!-- FILL` anywhere; exactly two U+2500 rails in `## Resume prompt`,
nothing between rails but the prompt; `Read @` line names an absolute forward-slash path equal to
the file's own; `Prior session:` UUID = `session_id`; `Handoff origin:` two-slot form; `Next:` 1–5
lines, an optional `Then: /<one skill>` last; `transcript:` path stats when stated (`unresolved (…)`
→ WARN, FAIL under `--strict-transcript`). Shape 1 (key absent) → one WARN, checks skipped, exit 0,
file never rewritten. Fixtures cover every Brief case plus: hop-1 no predecessor; shape-1
predecessor; `Then:` not last; six `Next:` lines; a cumulative entry without a tag; `Read @` path
mismatch.

### Phase 0: Headless-seam spike and baseline [DONE]

Probes already run this session (2026-09-03, CLI 2.1.259): `--max-turns` is hidden from
`claude --help` but accepted (`printf … | claude -p --max-turns 1 --output-format json --tools ""`
→ `subtype: success`, `num_turns: 1`; the official CLI reference documents it as print-mode only),
so the Brief's acceptance wording stands; `--bare` fails with `terminal_reason: api_error` on this
OAuth-login install (matches `reference/observer.md`); `claude -p --output-format json --tools ""
--max-budget-usd 0.10 --permission-mode dontAsk --setting-sources user` returns
`{"type":"result","subtype":"success","result":"ok","session_id":"<uuid>","num_turns":1,
"total_cost_usd":0.06,…}` in 2.6 s; the probe's transcript persisted under
`~/.claude/projects/<cwd-slug>/<sid>.jsonl` (`entrypoint: sdk-cli`) despite the inherited
`CLAUDE_CODE_CHILD_SESSION=1`. Remaining probes (each a bounded `claude -p` call, ≤ $0.50), run
2026-09-03 as three bounded calls from a throwaway fixture repo under `%LOCALAPPDATA%/Temp` with an
allowlisted child env (every `CLAUDE_*` stripped) and a pinned `--session-id` (spend $1.01 + $0.10 +
$0.92 = $2.03, all at the CLI default `claude-opus-5[1m]`; scripts and raw results in the memory
slice `scratch-scripts/probe_phase0*`, `probes/`):

- [x] plugin isolation. Overlay shape (`--setting-sources user --settings <file with
  {"enabledPlugins":{"session-flow@melodic-software":false}}> --plugin-dir <worktree>/plugins/session-flow`)
  loads correctly but drags the whole user plugin fleet in: a 75k-token system prompt, ≈ $0.17 per
  turn, budget-exhausted at $1.00 after 6 turns before the skill was reached. **Primary shape is now
  `--setting-sources project`** (documented value; the fixture has no project settings): no user
  plugins, hooks, or overlay, OAuth auth intact, ≈ 25k-token system prompt, and the skill expansion
  reads `Base directory for this skill: <worktree>\plugins\session-flow\skills\handoff` (backslashes,
  compared separator-insensitively; never `plugins/cache`). Add `--add-dir <worktree>/plugins/session-flow`
  so the skill's `Read` of its own reference docs is in scope. The overlay stays the fallback for a
  consumer that needs a project-level setting. `~/.claude/settings.json` was never edited
- [x] session-flow's own SessionStart hook (`hooks/observer-arm.sh`, self-guarded on `sdk-cli`)
  stays a no-op: no observer process after any run and no observer artifacts. The CLI did create an
  EMPTY `~/.claude/plugins/data/session-flow-inline/` for the `--plugin-dir` plugin, a second
  install-tree write the harness cleanup must know about (leave it; it is empty)
- [x] a prompt that ends "…then invoke /session-flow:handoff via the Skill tool" fires a `Skill`
  tool_use under `--permission-mode dontAsk --allowedTools "Read,Write,Edit,Bash,Skill,Glob,Grep"`:
  project-mode run `subtype: success`, 22 turns, 89 s, $0.92; `Skill {"skill":"session-flow:handoff","args":"file probe-hop1"}`
  at transcript record 30, the handoff `Write` at record 87, no earlier tool_use touching `handoffs/`;
  the final assistant text holds exactly two U+2500 rails (the 0.34.21 three-line shape-1 prompt
  between them). `PowerShell` was denied (absent from the allowlist) and the model recovered via
  Bash at the cost of a turn: the harness adds `PowerShell` to `--allowedTools`. Fixture lessons the
  harness inherits: `git config commit.gpgsign false` (the user's global ssh signing makes every
  child commit fail with `failed to write commit object`), `core.autocrlf false`, and a pre-created
  `.work/.gitignore` holding `*` (the guardrails hooks a user-fleet child inherits block the
  skill's `printf >>` guard). A budget-exhausted run returns `is_error: true`,
  `subtype: error_max_budget_usd`, and an EMPTY `result`, so the per-hop cap needs headroom
- [x] the run's transcript lands at `~/.claude/projects/<cwd-slug>/<session_id>.jsonl` for a fixture
  repo under the platform temp dir (slug `C--Users-<user>-AppData-Local-Temp-ccp-probe-<rand>`,
  `entrypoint: sdk-cli`, 95 records); the child's `printenv CLAUDE_CODE_SESSION_ID` returned the
  pinned id and the file's `session_id` equals it, so the env allowlist + `--session-id` pin holds.
  The hop-1 shape-1 file was 117 lines / 5.3 KB (≈ 1.3k tokens chars/4) in this light-context regime
- [x] capture the shape-1 baseline TSV (`scratch-scripts/baseline_shape1.py` over the corpus paths)
  into `.work/handoff-prompt-qol/baselines/` and record the distilled numbers in the Baseline
  section above (done 2026-09-03 during planning; the MSYS-path lesson it taught is in the
  decisions table)

**Sanity Check:** each probe's JSON `subtype` is `success`; the expansion grep (separator-insensitive)
returns the worktree path; a `Skill` tool_use record exists in the probe transcript; the Baseline
table above carries numbers, not a placeholder.

### Phase 1: `save_point.py` (`new` / `validate` / `emit`) with fixtures [DONE]

Review: code-design

TDD: write `plugins/session-flow/scripts/tests/test_save_point.py` first from the fixture matrix,
watch it fail, then implement. Fixtures under `plugins/session-flow/scripts/tests/fixtures/` use
neutral roots (`/work/repo/.work/handoffs/…`, fixture `projects-root` `/work/projects/<slug>/`)
holding empty `<sid>.jsonl` files, so nothing tracked carries a machine path (CI
machine-specific-paths lane) and nothing collides with the Phase 1 grep below. The test module
carries an explicit fixture manifest naming every fixture basename, so a fixture edit selects the
suite under affected-tests R3 (fixture `.md` files are otherwise in the `*.md` no-suite class).
Because `validate` compares the `Read @` line against the file's own absolute path (both sides
through `os.path.realpath` + `os.path.normcase`; `%TEMP%` on this machine is a short 8.3 name), the
test helper materializes every fixture chain under `tmp_path` and rewrites the neutral root to the
materialized directory (mixed-form path on Windows) before invoking `validate`; tracked fixtures
are never validated in place. Fixture layout is `fixtures/<case>/handoffs/<file>.md` plus
`fixtures/projects/<slug>/<sid>.jsonl`, never a `.work/` directory (the root `.gitignore` ignores
`.work/` at any depth). A nested `plugins/session-flow/scripts/tests/fixtures/.markdownlint-cli2.jsonc`
ignores `**` so deliberately malformed fixtures (ASCII rails, FILL comments, heading order) are not
linted by the synced root config, which is never edited. The manifest in the test names every
fixture basename including the `.jsonl` files (no `*.jsonl` no-suite class exists). One test runs
`emit` and `validate` through `subprocess` with `PYTHONIOENCODING=cp1252` and asserts exit 0 with
the rails intact, reproducing the Windows pipe condition on the ubuntu CI runner. `new`'s
absolute-path rendering is exercised through `--repo-root`/`--memory-dir` under `tmp_path`.

| File | Action | What changes |
|---|---|---|
| `plugins/session-flow/scripts/save_point.py` | CREATE | the three subcommands per the contract above; `--help`; documented exit taxonomy |
| `plugins/session-flow/scripts/tests/test_save_point.py` | CREATE | pytest over the fixture matrix (Brief's seven + the extras listed under `validate`), `new` round-trips (hop 1, hop 2 from shape 2, hop 2 from shape 1), `emit` verbatim |
| `plugins/session-flow/scripts/tests/fixtures/**` | CREATE | shape-1 legacy (14-section), shape-1 legacy (7-section), shape-2 good chain (3 files), prefixed pointer, non-UUID id, ASCII rails, leftover FILL, `handoff_shape: 3`, malformed shape-2 predecessor (successor validates with WARN), dropped predecessor cumulative entry (FAIL), moved-file `Read @` mismatch (`emit` substitutes), plus the extras; nested `.markdownlint-cli2.jsonc` |
| `plugins/session-flow/scripts/save_point.test.sh` | CREATE | CI wrapper mirroring `retro/scripts/parse-transcript.test.sh` (SKIP when Python 3.10+/pytest absent) |

**Sanity Check:** `bash plugins/session-flow/scripts/save_point.test.sh` exit 0 and its output
contains no `SKIP`; `bash scripts/run-ruff.sh check plugins/session-flow/scripts` exit 0; the seven
Brief fixtures return exactly: legacy → exit 0 with a `WARN` line; good → exit 0; prefixed pointer,
non-UUID, ASCII rails, FILL leftover → exit 1; `handoff_shape: 3` → exit 3; `grep -rEl
'[A-Z]:/|/Users/|/home/' plugins/session-flow/scripts/tests/fixtures` returns nothing; a skeleton
generated by `new` into a temp dir passes `npx --no-install markdownlint-cli2 <that file>` exit 0;
`git check-ignore -v plugins/session-flow/scripts/tests/fixtures/*/handoffs/*.md` prints nothing;
the cp1252 subprocess test is collected and passes; `grep -c "─" plugins/session-flow/scripts/save_point.py` ≥ 1
with the file declared UTF-8.

**Result (2026-09-03):** landed. `save_point.test.sh` runs 52 pytest cases (with
`-p no:cacheprovider`, so no `.pytest_cache/README.md` trips the plugin-wide markdownlint glob),
exit 0, no `SKIP`; ruff clean; the seven Brief fixtures return 0 (with a WARN line) / 0 / 1 / 1 /
1 / 1 / 3; the machine-path grep over the fixtures is empty; `git check-ignore` prints nothing;
generated hop-1 and hop-2 skeletons pass markdownlint under the root config; the plugin-wide
`markdownlint-cli2 "plugins/session-flow/**/*.md"` is clean (the nested fixtures config is
honored); gitleaks, editorconfig-checker and typos are clean on `scripts/`; the fresh-context
verifier reported 9/9 PASS on an independent materialization and named three defects outside the
criteria, all fixed with a test each: the empty-or-`None.` goal check was dead (it read the label
line), the self-ignore guard was skipped for a memory root outside any git repository, and a
shape-3 file printed a plain `FAIL` summary (now `UNSUPPORTED-SHAPE`, exit 3 unchanged). Twenty
fixture cases cover the seven
Brief cases plus: hop 1 alone, the 3-file good chain, a shape-1 (14-section and 7-section)
predecessor, a malformed shape-2 predecessor (WARN, exit 0), a dropped predecessor entry, a
moved-file `Read @` mismatch (`emit` substitutes, `validate` fails), `Then:` not last, six
`Next:` lines, an untagged entry, heading order, an `unresolved (…)` transcript (WARN / FAIL under
`--strict-transcript`), a stated transcript path that does not exist, CRLF input, a secret-shaped
string (WARN only), a chain longer than predecessor-plus-self, and a `previous_handoff` missing
beside the file. Small refinements of the contract text, recorded rather than silently applied:
`validate --projects-root` re-globs an `unresolved (…)` transcript and names the located path in
the finding (severity unchanged); the WARN-only secret scan omits the observer's email pattern
because it matches the bare `git@` account in every `Handoff origin:` line; `emit` trims leading
as well as trailing blank lines of the section; the below-rail line reads
"Or reopen the producing session in place:" followed by `claude --resume <id>` in a code span;
`Next:` headline lines are
plain lines (no bullets), which keeps the skeleton markdownlint-clean; a 7-section legacy
predecessor's sections are not aliased onto the 14-section names (absent → `None. (shape-1
predecessor had no <section>)` exactly as specified). Phase 2 wires the skill to the CLI exactly
as the contract table reads.

### Phase 2: Shape-2 spec, skill wiring, consumers, evals [DONE]

Review: code-design

Pre-flight (first work item): re-grep consumers of the file shape and prompt shape
(`grep -rn "previous_handoff\|Resumption brief\|Original goal\|U+2500\|Handoff origin\|Prior session:" plugins/`)
and confirm the list matches `EXPLORE-skill-contract.md` "Consumers" before editing.

| File | Action | What changes |
|---|---|---|
| `plugins/session-flow/reference/structure.md` | MODIFY | frontmatter shape 2 (`type, handoff_shape, date, topic, session_id, transcript, previous_handoff, chain[]`); `Opening ask:` in §1 (hop-1 verbatim, ~15-line cap, transcript as the full source); `[hN]` + `Superseded:` rule on §4/§6/§8/§9/§10 with the `[hN]` = `UNVERIFIED (<source>)` relation and re-tag-on-reverify stated; new sections `## This session` (`did: … · left: …`, past tense, no "next"), `## Prior sessions` (table, copied forward; `None (first hop).` at hop 1), `## Resume prompt` (final; stores the rails block); the write procedure becomes "resolve `memory_dir` via `parse-concern-value.sh` (retro's call form, as today), run the existing self-ignore guard, run `new --memory-dir …`, fill the slots, run `validate`"; shape-1 files never rewritten. All full-path only |
| `plugins/session-flow/reference/save-point.md` | MODIFY | "Writing the handoff file" cites the script; "Emit the copy/paste resume prompt" gains a **full-path-only** block: `validate` exit 0 gates the rails, on-screen block = `emit` output pasted verbatim (never regenerated), `Next:` ≤5 headlines between the rails ("headlines yes, detail no"), `Then: /<skill>` only at a stage boundary, one `Handoff origin:` form, the invoke-the-skill sentence, below-rail `claude --resume <id>` line, `<repo-identity>` now stored; the prompt-only rules in that section are untouched (Brief: prompt-only path untouched); detection contract section lists the shape changes; template examples keep `<handoffs-dir>`/`<TS>`/`<topic>`/`Prior session: <UUID>` placeholders |
| `plugins/session-flow/skills/handoff/SKILL.md` | MODIFY | full-path checklist gains: `memory_dir` resolved via `parse-concern-value.sh`, script `new` ran (invoked `python3 -X utf8`; the path it printed is the path reused everywhere, never recomputed in bash), only FILL slots edited, `validate` exit 0 quoted (or, after three failed attempts, the approved degraded exit: `UNVALIDATED` banner above the top rail, rails still emitted), rails = `emit` output; Python-absent fallback line; session-UUID-absent routing to prompt-only with the reason stated; the **Prompt-only path** checklist is byte-unchanged; stays ≤ 500 lines |
| `plugins/session-flow/skills/handoff/context/gotchas.md` | MODIFY | the two evidenced gotchas only: free-hand write (skill never loaded → no rails, 10/25 in the audit) and ASCII rails (2/15); orphan-skeleton and malformed-predecessor behavior live in the engine doc as rules, not gotchas; a retyped-`emit` gotcha is added only if Phase 5 observes byte drift (instruction economy: standing text needs an observed stumble) |
| `plugins/session-flow/skills/continue-in-background/SKILL.md` | MODIFY | launch payload = between-rails text of `emit <file>` (full path) |
| `plugins/session-flow/skills/find-handoff/SKILL.md`, `reference/rung-1-known-location.md`, `reference/rung-3-marker-detection.md` | MODIFY | rung 1 prints `## Resume prompt` via `emit` for a shape-2 candidate (design T7's `sed -n` on the section stays as the Python-less fallback, minus `emit`'s path substitution) and skips a file still carrying `<!-- FILL` (named as an unfinished skeleton, never presented as the lost handoff); rung 3 accepts both `Handoff origin:` forms (legacy `<identity>, relative path <p>.` and locked `<url> <p>`), skips the `claude --resume` line when anchoring re-arm capture to the bottom rail, tolerates the `Next:`/`Then:` lines and the extra directive sentence |
| `plugins/session-flow/skills/handoff/evals/evals.json` | MODIFY | every rails case adds "validator ran (`save_point.py validate`) and exited 0 before the rails; the on-screen rails block equals the file's `## Resume prompt` section"; new cases: skeleton via `new` (only FILL slots edited), validator failure blocks the rails (guardrail), shape-1 predecessor copy-forward, `Then:` only at a stage boundary, Python-absent fallback |
| `plugins/session-flow/skills/find-handoff/evals/evals.json`, `continue-in-background/evals/evals.json` | MODIFY | one case each for the shape-2 source of the prompt |
| `plugins/session-flow/README.md` | MODIFY | handoff/find-handoff paragraphs mention shape 2 and the script |

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh handoff`, `… find-handoff`,
`… continue-in-background` each report PASS; `bash plugins/skill-quality/scripts/check-evals-quality.sh`
over the three `evals.json` exit 0; `grep -c "Resume prompt" plugins/session-flow/reference/structure.md`
≥ 3; `grep -c 'save_point.py' plugins/session-flow/reference/save-point.md` ≥ 3;
`grep -rl "write a resume file" plugins/session-flow | wc -l` = 0; `wc -l plugins/session-flow/skills/handoff/SKILL.md`
≤ 500; `grep -n '<handoffs-dir>' plugins/session-flow/reference/save-point.md` non-empty;
`diff <(git show origin/main:plugins/session-flow/skills/handoff/SKILL.md | awk '/^\*\*Prompt-only path:\*\*/,/^## What this skill does NOT do/') <(awk '/^\*\*Prompt-only path:\*\*/,/^## What this skill does NOT do/' plugins/session-flow/skills/handoff/SKILL.md)`
is empty; `bash scripts/check-purged-em-dashes.sh` exit 0 (`plugins/session-flow/README.md` is a purged surface).

**Result (2026-09-03):** landed. Pre-flight re-grep matched the "Consumers" table; the extra hits
(`orchestrate` rails for its own brief, `running-retro` / `retro` reading `previous_handoff` as a
pointer, `keep-going` / `reanchor` reading `Original goal` by name) are unaffected by shape 2. One
free-hand licence the table did not list, `skills/workflow/context/continuation.md` ("Absent that
skill: write a resume file by hand"), was reworded because the Sanity Check's
`grep -rl "write a resume file" plugins/session-flow` demands zero hits (the parenthetical was
dead: `workflow` and `handoff` ship in the same plugin). `structure.md` documents the shape-2
frontmatter, the `Opening ask:` line, the cumulative-section `[hN]` + `Superseded:` rule (with the
`UNVERIFIED (<source>)` relation and re-tag-on-reverify), the three new sections, the scripted
write procedure (`parse-concern-value.sh` → guards → interpreter ladder → `new` → fill →
`validate` → `emit`), the Python-absent fallback, and the legacy / malformed-predecessor /
unfinished-skeleton rules; `save-point.md` documents the three subcommands with the exit taxonomy
and adds the full-path-only block (validate gates, three-attempt fix loop then the `UNVALIDATED`
banner, rails = `emit` output verbatim, fixed directive text, one `Handoff origin:` form, `Next:`
1 to 5 headlines with `Then:` only at a stage boundary, the below-rail `claude --resume` line),
flips the "`<repo-identity>` is NOT a stored field" sentence, routes the no-UUID case to
prompt-only, and lists the shape-2 changes under the detection contract; the handoff SKILL.md
full-path checklist gained three boxes and a rewritten rails box (311 lines; the prompt-only
checklist is byte-identical to `origin/main`); `gotchas.md` gained exactly the two evidenced
entries; `continue-in-background` sources its payload from `emit`; `find-handoff` rung 1 prints
`## Resume prompt` via `emit` (with the `sed -n` fallback) and skips `<!-- FILL` skeletons, rung
3 accepts both origin forms, matches the directive on its path shape regardless of tail, and
skips the `claude --resume` line before the re-arm header scan; the handoff evals carry the
validator/emit expectation on all ten full-path rails cases plus five new cases (16 to 20), and
the other two sets gained one shape-2 case each; the README describes shape 2 and the script.
Sanity Check: `check-skill.sh --require-evals` PASS on all three skills (run with
`CHECK_SKILL_SKILLS_ROOT=plugins/session-flow/skills`; soft-cap WARNs only),
`check-evals-quality.sh` exit 0 (two pre-existing Q4 WARNs), the four grep counts and the line
cap hold, the prompt-only diff is empty, the purged em-dash gate and the plugin-wide markdownlint
are clean, typos / editorconfig-checker / gitleaks clean; `scripts/check-changed-skills.sh
origin/main` 14 skills, 0 failed. The fresh-context verifier (criteria withheld rationale)
reported 12 of 13 PASS with the docs-vs-engine probes all confirmed against the running script
(directive text, origin slots, below-rail line, `emit` refusing an unfilled skeleton, `new`
exit 2 without a predecessor flag, the optional slot names, `NEXT_MAX` / `NEXT_CLOSED` /
`THIS_SESSION_RE`, the 52-case suite green) and three defects, all fixed before the commit: eval
case 3 lacked the validator/emit expectation (added); the new free-hand gotcha asserted that the
zone-gate and implement surfaces already carry the rule (Phase 4, not landed; reworded to the
directive only); the full-path template's second `Handoff origin:` slot read
`<memory_dir>/handoffs/…` while the rule called it `<repo-relative path>` (template now uses the
rule's name and the rule defines it).

### Phase 3: retro chain-walker tolerates a directory-prefixed pointer [DONE]

TDD: add `test_chain_from_resolves_prefixed_pointer_by_basename` to
`plugins/session-flow/skills/retro/scripts/test_parse_transcript.py` (flat `handoffs/` dir, pointer
`.work/handoffs/<file>.md`) and watch it fail (chain truncated to one id), then add a third candidate
`cursor.parent / Path(prev_handoff_rel).name` after the two existing resolutions in
`extract_chain_from_handoff` (the `journal/` and flat tests keep passing).

**Sanity Check:** `bash plugins/session-flow/skills/retro/scripts/parse-transcript.test.sh` exit 0
with the new test collected; `bash scripts/run-ruff.sh check plugins/session-flow/skills/retro/scripts` exit 0.

**Result (2026-09-03):** landed. `test_chain_from_resolves_prefixed_pointer_by_basename` was
written first and failed against the unchanged walker (`AssertionError: assert 'sid-oldest' in
['sid-middle']`: the chain truncated to one id); the third candidate
`cursor.parent / Path(prev_handoff_rel).name`, guarded like the second, turned it green with the
`journal/` and flat-layout chain tests unchanged. Sanity Check: `parse-transcript.test.sh` exit 0,
`38 passed` (37 before) with the new test collected; `run-ruff.sh check` on the scripts dir exit 0.
Two Phase 2 wording fixes ride this commit: the Phase 2 Result now counts ten full-path rails
cases (case 3 gained the expectation after the count was written), and `save-point.md` drops the
clause that let a prompt-only block swap its opening line (prompt-only has no directive and is
Brief-locked untouched). The fresh-context verifier reported 9 of 9 PASS, including an empirical
red proof: the working-tree test file run against the HEAD script in a scratch copy fails exactly
as predicted while the two pre-existing chain tests pass there too, so the green run masks no
regression. typos, editorconfig-checker, gitleaks, and markdownlint on the touched docs are clean;
the diff carries no em dash and no machine path.

### Phase 4: Close the free-hand licences (context-guard, implementation) [DONE]

| File | Action | What changes |
|---|---|---|
| `plugins/context-guard/hooks/zone-gate.sh` | MODIFY | deny reason names only the skill: "… run /session-flow:handoff (if installed) via the Skill tool; the save-point it writes is exempt from this gate." — the `*handoff*` path exemption logic is untouched |
| `plugins/context-guard/hooks/zone-gate.test.sh` | MODIFY | add: deny reason does NOT contain `write a resume file`; existing `routes to a handoff` assertion stays |
| `plugins/context-guard/.claude-plugin/plugin.json`, `CHANGELOG.md` | MODIFY | 0.7.34 → 0.7.35 + entry; the entry records that a consumer without session-flow now gets no free-hand route in the reason text while the `*handoff*` path exemption itself is unchanged (recorded gap, per Brief "names only the skill") |
| `plugins/implementation/skills/implement/SKILL.md` | MODIFY | Step 4 item 2 already routes to the skill when session-flow is installed; only its absent-plugin fallback is free-hand today. That fallback gains the rails prompt: copy instruction, two U+2500 rails, `Read @<handoffs-dir>/<TS>-handoff-<topic>.md` directive (the engine's own placeholder tokens, so rung 3's template filter rejects the example), `Prior session: <UUID>`, `Handoff origin:`; no `Re-arm … — …` header (its em dash would trip the purged-surface gate; re-arm notes are the engine's, not the fallback's); the present-plugin sentence adds "never written free-hand"; the item order is NOT changed here (the items-3–5-after-STOP conflict is the Phase 6 follow-up, Approval record 4) |
| `plugins/implementation/.claude-plugin/plugin.json`, `CHANGELOG.md` | MODIFY | 0.16.0 → 0.16.1 + entry |

**Sanity Check:** `bash plugins/context-guard/hooks/zone-gate.test.sh` exit 0; `grep -c "write a resume file" plugins/context-guard/hooks/zone-gate.sh` = 0;
`grep -c "─" plugins/implementation/skills/implement/SKILL.md` ≥ 2; `bash plugins/skill-quality/scripts/check-skill.sh implement` PASS;
`scripts/check-changelog-parity.sh --check-bump origin/main` exit 0; `bash scripts/check-purged-em-dashes.sh` exit 0
(`plugins/implementation/skills/*/SKILL.md` is a purged surface).

**Result (2026-09-03):** landed as an Opus sub-agent worker under the A2 fence; the fresh-context
verifier reported 10 of 10 PASS. `zone-gate.test.sh` gained the "does NOT contain
`write a resume file`" assertion first and failed against the unchanged hook (`PASS=24 FAIL=1`, the
deny reason still carried the free-hand clause); the one-line `reason=` rewrite in `zone-gate.sh`
turned it green (`PASS=25 FAIL=0`) with the `*handoff*` path exemption byte-identical (test 4,
`handoff-path write exempt`, still passes). The verifier reproduced the red empirically: HEAD's
`plugins/context-guard` via `git archive` into a scratch dir plus the working-tree test file. In
`implement/SKILL.md`, item 2 (+11 lines, one hunk) gained the engine-shaped copy region as a fenced
block with the placeholder tokens, `Prior session: <UUID>.` and the two-slot `Handoff origin:`; the
fallback directive deliberately omits the engine's second sentence (it names a skill the
absent-session-flow consumer does not have) and the illustrative `Next:` lines; items 1 to 5 keep
their order; the file has zero em dashes. Bumps 0.7.35 and 0.16.1 with entries; the context-guard
entry records the unchanged path exemption as the gap. Sanity Check all green: the hook suite, both
greps (the only remaining `write a resume file` under `plugins/` is the new assertion itself),
`check-skill.sh implement` PASS with the pre-existing soft-cap WARN (226 lines, was 215), changelog
parity, the purged em-dash gate, shellcheck, markdownlint, typos, editorconfig-checker; the diff
carries no machine path. Delta: 7 files, +42/-4.

### Phase 5: Headless harness and the measured budget [TODO]

Review: code-design

`plugins/session-flow/scripts/harness/hop_chain.py` (+ `hop_chain.test.sh` running its `--dry-run`
self-test so `affected-tests.sh` maps it). Flags: `--runs N` (default 3), `--hops 3`, `--model <id>`
(pinned explicitly for every live run; recorded in the TSV), `--max-turns 40`, `--budget-usd-per-hop 3`,
`--timeout-seconds 900`, `--plugin-dir <path>` (default: this worktree's `plugins/session-flow`),
`--pad-context <tokens>` (the fixture carries a large file the prompt orders read first; one padded
run per acceptance set), `--dry-run`, `--keep`. The child environment is built from an allowlist
(`HOME`, `USERPROFILE`, `PATH`, `TEMP`, `TMP`, `APPDATA`, `LOCALAPPDATA`, `SystemRoot`, `ComSpec`,
`CLAUDE_CONFIG_DIR` when set) with every other `CLAUDE_*` variable removed, so a hop never inherits
the launching session's id, effort, or plugin-data dir; each hop gets `--session-id <uuid4>` and
the file's `session_id`, the flag, and the JSON `session_id` must agree. Per run: a fixture git repo
under the platform temp dir (`tempfile`, native paths per windows-path-emit) with a tiny
four-step task, so hop 4 still has work before its own save-point; hop 1 prompt = task + "after
step 1, invoke /session-flow:handoff via the Skill tool"; hops 2–3 prompt = the previous hop's
`emit` between-rails text verbatim, delivered on stdin;
each hop: `claude -p --output-format json --permission-mode dontAsk --allowedTools "Read,Write,Edit,Bash,PowerShell,Skill,Glob,Grep"
--setting-sources project --plugin-dir … --add-dir <plugin-dir> --max-budget-usd …` (Phase 0
result: project-only sources, no overlay; the fixture repo sets `commit.gpgsign false` and
`core.autocrlf false` and pre-creates `.work/.gitignore` = `*`) run through `subprocess.run(…, timeout=…)` (never
coreutils `timeout`), prompt on stdin; the hop's transcript is located by the same
`<projects-root>/*/<session_id>.jsonl` glob `new` uses, never a computed cwd slug; assertions per hop: exactly one new
`*-handoff-*.md`; `validate --strict-transcript` exit 0; the JSON `result` text AND the transcript's
final assistant `text` record each hold exactly two rail lines (a line solely of ≥10 U+2500);
the between-rails bytes equal `emit`'s between-rails bytes (CRLF-normalized); the TSV records
the handoff turn's `usage.input_tokens` so the context regime of every run is visible;
hop 4: prompt = hop-3 rails text; the transcript (`~/.claude/projects/<slug>/<session_id>.jsonl`)
holds a `Skill` tool_use naming `session-flow:handoff` before ANY tool_use (`Write`, `Edit`, `Bash`,
or other) whose serialized input contains `handoffs/`, and before the first `*-handoff-*.md`
appears on disk; a file that appears with no preceding `Skill` call (including one written through
Bash) is a `FAIL` row, never a vacuous pass; hop 4 passes only when BOTH the `Skill` call and one
new handoff file exist. Report: one TSV row per hop + `N/N` summary, non-zero exit on any miss.
Timeouts kill the whole process tree (a new process group; `taskkill /T` on Windows), never just
`claude.exe`. At run end, unless `--keep`, the harness deletes exactly the transcripts whose session
ids it created (`~/.claude/projects/*/<sid>.jsonl` and the sibling `<sid>/` dir), the install-tree
writes it makes (the CLI also creates an empty `~/.claude/plugins/data/session-flow-inline/` for the
`--plugin-dir` plugin, left alone), so harness sessions with real rails never outrank an operator's
lost handoff in `find-handoff`'s mtime-ranked scan; it never touches `~/.claude/settings.json`. `--budget` mode:
generate a 20-hop chain through `new` with per-section filler sized from the shape-1 corpus median
(Phase 0 baseline), report lines and chars/4 tokens at hops 1, 5, 20; the live hop-1 file is
reported beside the generated hop 1. Note: the implementing session dogfoods the CACHED 0.34.21
skill at its own phase boundaries; shape 2 is exercised only through this harness until release.

**Sanity Check:** `bash plugins/session-flow/scripts/harness/hop_chain.test.sh` exit 0 (dry-run,
no spend); a live `hop_chain.py --runs N` exits 0 with `N/N` in its summary and zero rows marked
`FAIL`; `design/design-threads.md` "Resume-read budget" section contains `measured` and no longer
contains `ESTIMATES`; the four probe boxes in Phase 0 are ticked.

### Phase 6: Close-out [TODO]

session-flow 0.34.21 → 0.35.0 with a CHANGELOG entry naming shape 2, the script, the consumer
changes, and the detection-contract changes; full gates; then the follow-up filing and the PR.

- [ ] **Phase-entry check** (first work item of the filing; verifies no duplicate exists):

  ```bash
  gh issue list --state all --search 'implement phase-boundary ritual handoff STOP order in:title' --json number,title,state
  ```

- [ ] **If search returns a match** → pivot: `gh issue comment <N> --body '<evidence: implement/SKILL.md Step 4 items 3–5 run after item 2 invokes /session-flow:handoff, whose hard rule is STOP with the rails as final text; proposed order 1, 3, 4, then 2>'`; skip the create step; record the comment URL
- [ ] **If search returns empty** → create:

  ```bash
  gh issue create --title 'implement: run the phase-boundary ritual before the handoff skill, not after its STOP' --body '<same evidence + proposed order; deferred from handoff-prompt-qol at the user's request>'
  ```

- [ ] **Sanity Check:** the item number (created OR pivoted-to) is recorded in the PLAN notes and URL captured
- [ ] PR body (via `/source-control:pull-request create`): ends with a "Follow-up" line naming that
  item: "File the implement ritual reorder as a follow-up, not in this PR" (the user's wording), so
  the reviewer sees the deliberately unchanged ordering.

**Sanity Check:** `scripts/affected-tests.sh --run` exits 0 or 3, and when 3, every suite it lists
under `NOT RUN` is a `test_*.py` whose co-located `*.test.sh` wrapper ran in the same invocation
with no `SKIP` in its output (the runner executes only `*.test.sh`; it exits 3 whenever a Python
suite is selected, so 3 is the expected code here, never 1 or 2); `bash scripts/run-plugin-tests.sh` exit 0
for the session-flow, context-guard, implementation suites; `scripts/check-changelog-parity.sh --check-bump origin/main` exit 0;
`scripts/check-changed-skills.sh origin/main` exit 0; `scripts/check-skill-portability.sh origin/main` exit 0;
`npx --no-install markdownlint-cli2 "plugins/session-flow/**/*.md" "docs/topics/handoff-prompt-qol/**/*.md"` exit 0;
`git status --porcelain` shows no `.work/` path.

### Files affected (summary)

CREATE: `plugins/session-flow/scripts/save_point.py`, `scripts/save_point.test.sh`,
`scripts/tests/test_save_point.py`, `scripts/tests/fixtures/**`, `scripts/harness/hop_chain.py`,
`scripts/harness/hop_chain.test.sh`. MODIFY: session-flow `reference/structure.md`,
`reference/save-point.md`, `skills/handoff/{SKILL.md,context/gotchas.md,evals/evals.json}`,
`skills/continue-in-background/{SKILL.md,evals/evals.json}`,
`skills/find-handoff/{SKILL.md,reference/rung-1-known-location.md,reference/rung-3-marker-detection.md,evals/evals.json}`,
`skills/retro/scripts/{parse_transcript.py,test_parse_transcript.py}`, `README.md`, `CHANGELOG.md`,
`.claude-plugin/plugin.json`; context-guard `hooks/zone-gate.sh`, `hooks/zone-gate.test.sh`,
`CHANGELOG.md`, `.claude-plugin/plugin.json`; implementation `skills/implement/SKILL.md`,
`CHANGELOG.md`, `.claude-plugin/plugin.json`; `docs/topics/handoff-prompt-qol/design/design-threads.md`
(budget section). KEEP (audited): `skills/orient`, `keep-going`, `reanchor`, `clean-stop`, `workflow`
(section names unchanged), `plugins/docs-hygiene/.../noise-shapes.sh`, `hooks/hooks.json` (no hook).
Sub-topic promotion: Phases 1 and 5 each exceed 300 LOC, but both are single-PR siblings sharing this
Brief's acceptance criteria; verdict: not promoted `[EXEC-SHAPE]`.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Stop / PostToolUse hook keyed on a handoffs-dir write | Brief declines hooks in V1 | a free-hand write recurs after this ships (Brief's Stop-hook trigger) |
| Per-topic index file (design B) | second write per handoff; the free-hand failure mode is exactly a skipped write | measured hop-20 file exceeds ~4k tokens after tagging |
| Derive the chain by script at resume (design C) | a script stands between the agent and its breadcrumbs | a resume path appears that cannot run Python at all |
| Shell instead of Python for the script | YAML/frontmatter parsing, UUID/glob/stat logic, and byte-compare are error-prone in bash; Python precedent already ships in this plugin | a target machine without Python 3.10+ becomes a supported resume host |
| `claude plugin eval` as the harness | undocumented on this CLI | it becomes documented and can drive a multi-hop chain |
| Validator only warns; rails always emitted | reintroduces the drift the validator exists to stop | the bounded fix loop proves unable to converge in practice (harness data) |

### Test strategy

TDD default. Boundaries the tests drive:

| Boundary | Status | Tests |
|---|---|---|
| `save_point.py` CLI (`new`/`validate`/`emit`) | introduced | pytest fixture matrix; exit codes; byte-verbatim `emit`; copy-forward from shape 1 and shape 2 |
| `parse_transcript.py --chain-from` | existing | regression: prefixed pointer resolved by basename (fails pre-fix) |
| `zone-gate.sh` deny reason | existing (`zone-gate.test.sh`) | reason routes to the skill only |
| `claude -p` JSON `result` + transcript JSONL | existing, external | harness assertions (live, gated on cost); `--dry-run` self-test in CI |
| handoff / find-handoff / continue-in-background evals | existing, model-graded | schema + `check-evals-quality.sh` in CI; not executed by CI |

Edge cases: CRLF files; `unresolved` transcript; `Next:` with a `Then:` line; a predecessor whose
`chain:` is longer than expected (validate FAIL); a `previous_handoff` whose predecessor is missing
(validate FAIL); SCP-style remote (origin falls back to root dir name); Windows drive-letter paths
rendered forward-slash.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model retypes the `emit` output instead of pasting it (byte drift) | Med | High | SKILL.md rule + eval expectation + harness byte compare on every hop; `find-handoff` rung 1 can always re-emit from the file |
| Validator still failing after the bounded fix loop | Low | High | three fix attempts, then a loud `UNVALIDATED` banner with the path and the validator output (never green-silent); the rails still follow, banner above the top rail (Approval record 1); prompt-only path untouched as the manual escape |
| Headless hop never invokes the skill | Med | High | Phase 0 probe; prompt names the Skill tool explicitly; harness reports the miss as a FAIL row, not a crash |
| Cached `session-flow@melodic-software` shadows the worktree plugin in the harness | Med | Med | Phase 0 probe settled `--setting-sources project` (no user plugins load at all); harness asserts the worktree path in the skill expansion |
| `CLAUDE_CODE_SESSION_ID` absent → `new` refuses | Low | Med | `--session-id` from the `printenv` probe; documented in gotchas; Brief's captured assumption names the SessionStart-hook fallback for a later release |
| Tracked fixtures trip the machine-specific-paths lane | Med | Low | neutral `/work/…` roots; `--projects-root` / `--repo-root` injection |
| Harness spend | Certain | Low | explicit approval gate before any live run; `--max-budget-usd` per hop; N is an argument |
| Detection-contract drift breaks `find-handoff` on legacy transcripts | Low | High | rung 3 accepts both origin forms and the legacy directive; evals `accepts-rooted-and-rootless-directive-forms` kept |
| Acceptance runs all sit in a light-context regime; the observed failure is heavy-context | Med | Med | one `--pad-context` run per set; `input_tokens` column in the TSV; both regimes recorded in design-threads; the Stop-hook trigger stays armed for recurrence |
| Prompt-only resumes still carry no invoke-the-skill sentence | Med | Low | Brief-locked (prompt-only untouched); accepted risk, covered by the same recurrence trigger |
| Windows-only encoding or newline bug escapes CI (suite runs on ubuntu only) | Med | Med | explicit UTF-8/newline contract; cp1252 subprocess test; manual Windows run of the suite recorded in Phase 6 |

## Blast radius

**HIGH.** Three plugins, a file-shape contract with eight consumers, hook deny-reason text
(infrastructure), and a new convention (shape 2 + validator) that constrains every future handoff.
Reversible by `git revert` (legacy files never rewritten; shape 1 tolerated on read). Stress-test
needed: yes — `/planning:devils-advocate` via a fresh-context sub-agent (Step 4).

## Stress-test summary

Step 3 (fresh-context plan-reviewer): CRITICAL 2 / IMPORTANT 7 / SUGGESTION 8, all verified
against the files and folded in (fixture materialization under `tmp_path`; `affected-tests.sh`
exits 3 for Python suites; mandatory `--previous`/`--no-previous`; no-overwrite and FILL-skeleton
handling; malformed-predecessor WARN path; Bash-blind hop-4 check; prompt-only scoping with a
byte-unchanged diff check; purged em-dash gates; exact-stem test pairing; `parse-concern-value.sh`
reuse; hop-1 `## Prior sessions` base case; T4 never-deleted check; T2 cap; UTF-8/newline;
fixture manifest; Brief amendments listed rather than silently applied).

Step 4 (`/planning:devils-advocate` in a fresh-context sub-agent): 22 assumptions graded, 21
findings (6 HIGH, 9 MEDIUM, 6 LOW), 0 CRITICAL. Contradicted and corrected: `--max-turns` exists
(hidden; probe succeeded, Brief wording restored); Windows Python defaults (cp1252 pipes, CRLF);
the corpus holds a 7-section legacy shape; T4 never-deleted lacked a validate rule; the hop-4
task was vacuous; the fix-loop exit contradicted the skill's ALWAYS-emit rule (now Open question
1 for the user); harness env inheritance and session-id pinning; fixture and CI-lane hazards;
transcript litter; `--setting-sources ""` undocumented (replaced by a `--settings` overlay).
Accepted as recorded risks: light-context regime (mitigated by one padded run), prompt-only
licence (Brief-locked), session-id-absent routing, secret-shape scan at WARN, closing-handoff
`Next: none (closed)`. Confidence after the round: HIGH on every claim that a probe or file read
could settle; the two remaining unverified items (bridge sessions' env var; `--plugin-dir`
precedence over the cached copy) are Phase 0 probes with named fallbacks.

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 0 | `.work/handoff-prompt-qol/**` (memory), `PLAN.md` baseline section | none |
| 1 | `plugins/session-flow/scripts/{save_point.py,save_point.test.sh,tests/**}` | none |
| 2 | `plugins/session-flow/{reference/*.md,README.md,skills/handoff/**,skills/continue-in-background/**,skills/find-handoff/**}` | none (reads Phase 1's CLI contract) |
| 3 | `plugins/session-flow/skills/retro/scripts/{parse_transcript.py,test_parse_transcript.py}` | none |
| 4 | `plugins/context-guard/{hooks/zone-gate.sh,hooks/zone-gate.test.sh,CHANGELOG.md,.claude-plugin/plugin.json}`, `plugins/implementation/{skills/implement/SKILL.md,CHANGELOG.md,.claude-plugin/plugin.json}` | none |
| 5 | `plugins/session-flow/scripts/harness/**`, `docs/topics/handoff-prompt-qol/design/design-threads.md` | none |
| 6 | `plugins/session-flow/{CHANGELOG.md,.claude-plugin/plugin.json}` | none |

### Dependency graph

- 0 → 5 (probe outcomes fix the harness flags); 1 → 2 (SKILL.md and save-point.md cite the CLI contract); 1 + 2 → 5; every phase → 6.
- 3 and 4 are independent of everything.
- Integration-first: Phase 0 is the seam probe; Phase 1 the engine slice; Phase 5 the end-to-end runtime probe.

### Recommended shape `[EXEC-SHAPE]`

Fully sequential by default: 0 → 1 → 2 → 3 → 4 → 5 → 6. Phases 3 and 4 are parallel-safe
(file-disjoint, dependency-free) but together carry only ~100 LOC of independent work, so the
saving is marginal; they may be dispatched as two sub-agent workers alongside Phase 1 when
wall-clock matters. Cost note: 2 workers + main vs sequential main-only.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 0 | main-session | live probes spend money and need the operator's gate |
| 1 | main-session | validator semantics are judgment-heavy and coupled to the spec Phase 2 writes |
| 2 | main-session | spec prose across four skills; detection-contract edits need the whole picture |
| 3 | sub-agent worker (optional) | mechanical: one resolution candidate + one regression test |
| 4 | sub-agent worker (optional) | mechanical: two prose edits, one test assertion, two bumps |
| 5 | main-session | spends money; results feed design-threads.md |
| 6 | main-session | gate runs and the release bump |

### Scope-fencing tables (only if the optional workers are used)

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 3 | `plugins/session-flow/skills/retro/scripts/parse_transcript.py`, `plugins/session-flow/skills/retro/scripts/test_parse_transcript.py` | ~40 |
| A2 | 4 | `plugins/context-guard/hooks/zone-gate.sh`, `plugins/context-guard/hooks/zone-gate.test.sh`, `plugins/context-guard/CHANGELOG.md`, `plugins/context-guard/.claude-plugin/plugin.json`, `plugins/implementation/skills/implement/SKILL.md`, `plugins/implementation/CHANGELOG.md`, `plugins/implementation/.claude-plugin/plugin.json` | ~60 |

Each agent FORBIDDEN: any file outside its ALLOWED list; `PLAN.md`; the other agent's territory;
staging/commit/push. Each reports work items done + per-criterion Sanity Check verdict + LOC delta.

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief —
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task — STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

Sequential fallback: a scope-fence violation, a concurrent-edit race, or a cannot-complete report
aborts that worker and the affected phase runs main-session in the default order; the other worker continues.

## Open questions

All four gate questions below were ruled at approval per their recommendations (Approval record
1–4); Q13 remains unruled and non-blocking. Kept for the record:

- Q13 (USER-RESERVED): see the evidence section; not ruled at approval.
- Brief amendments the user ruled on (the Brief is locked; the plan does not silently diverge):
  1. Validator failure after the bounded fix loop. Brief constraint: "non-zero, rails not
     emitted". The skill's own hard rule: "A resume prompt is ALWAYS emitted", and the observed
     failure class is exactly an operator left with nothing to paste. Proposed: after three failed
     `validate` attempts the skill still emits the rails from the file's `## Resume prompt`
     section, with an `UNVALIDATED: <validator output>` banner ABOVE the top rail (outside the copy
     region, so the detection contract holds), and the checklist box reads `validate: FAILED`.
     Alternative (Brief as written): withhold the rails, print the banner and the file path only
     `[FALLBACK — confirm or override]`.
  2. Constraint "missing transcript → non-zero" vs constraint "`unresolved (…)` when absent".
     Proposed reading: a stated path that does not stat → FAIL; the honest `unresolved (…)` value →
     WARN by default, FAIL under `--strict-transcript` (the harness passes it). Alternative: strict
     by default, which blocks the rails wherever the transcript glob misses (a custom config dir).
  3. Acceptance line 1 leaves N to the plan. Proposed: N = 3 runs at the CLI's default model
     (12 live hops + 3 hop-4 resumes, ≈ $0.06–$3 per hop under the per-hop budget cap); the harness
     takes `--runs` and `--model` so a larger N or a cheaper model is one flag away. Below the
     confidence bar (sizing), so the user picks. Plus one padded-context run (`--pad-context`,
     the fixture orders a large file read before the task) so at least one acceptance run sits in
     the heavy-context regime where the observed failure lives; both regimes recorded in
     design-threads.
  4. Scope option, same file and bump as Phase 4: `implement` Step 4's ritual runs items 3–5
     (status summary, commit, resume prompt) AFTER item 2 invokes a skill whose hard rule is STOP
     with the rails as the final text, so every phase boundary violates one or the other today.
     Proposed: reorder to 1, 3, 4, then 2 (the skill's rails satisfy item 5). Not in the Brief;
     the user decides whether it rides along or is filed as a follow-up.
- Session-id absent (no `CLAUDE_CODE_SESSION_ID`, or a non-UUID such as a bridge id): `new`
  refuses by Brief rule; the skill then takes the prompt-only path with the reason stated
  ("no session UUID available; chain gap accepted"), never a hand-written shape-2 file. Whether a
  bridge session sets the variable at all cannot be probed from here; recorded, not blocking.

## Handoff to implementation

### User-approval gates

- Any live harness run (Phase 0 probes beyond the four already run, Phase 5 `--runs N` plus the
  padded run): state the per-hop budget, model, and N before spending.
- The harness's end-of-run deletion of its own transcripts (`--keep` disables it).
- Any mid-flight pivot that changes an acceptance criterion or an Approval-record item.
- Python-absent fallback in the skill `[FALLBACK — confirm or override]`: interpreter ladder finds
  nothing → the skill prints `validator unavailable: no python3/python on PATH`, writes shape 2 by
  hand per `structure.md`, marks the checklist box `validate: SKIPPED (no interpreter)`, still emits
  the rails from the file's `## Resume prompt` section.
- `transcript: unresolved (…)` is WARN (exit 0) by default and FAIL under `--strict-transcript`
  (the harness passes it) `[EXEC-SHAPE]`.

### Execution shape ([EXEC-SHAPE] tagged)

Decisions /planning:plan made within the briefed scope (each cheap to reverse; basis is evidence read this session):

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Script lives at plugin level, `plugins/session-flow/scripts/save_point.py`, tests in `scripts/tests/` `[EXEC-SHAPE]` | Phase 1 file list; SKILL.md cites `${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py` | the engine doc it implements is plugin-level `reference/save-point.md`, shared by handoff and continue-in-background; design T8 names `plugins/session-flow/scripts/tests/`; affected-tests R2 accepts `<dir>/tests/test_<stem>.py` |
| Exit taxonomy 0 pass / 1 validation failure / 2 usage / 3 shape-newer-than-known `[EXEC-SHAPE]` | Phase 1 contract table and fixture expectations | Brief: "hard-fail exit distinct from validation failure"; shell-test-helpers convention: per-script taxonomies are deliberate; `check-usage-limit-reset.py` documents its own |
| `transcript: unresolved (…)` is WARN by default, FAIL under `--strict-transcript` (harness passes it) `[EXEC-SHAPE]` | Phase 1 validate rules; Phase 5 harness flags | Brief line "`unresolved (…)` when absent" makes it a legal stored value; Brief's "missing transcript → non-zero" reads as a stated path that does not stat |
| Bounded fix loop: three `validate` attempts, then rails emitted with an `UNVALIDATED` banner above the top rail (ruled by the user at approval; see Approval record 1) | Phase 2 SKILL.md checklist wording | liveness-assertion: never green-silent; the skill's ALWAYS-emit rule wins over the Brief's "rails not emitted" for this case |
| Harness lives in-plugin at `scripts/harness/` with a `--dry-run` self-test suite `[EXEC-SHAPE]` | Phase 5 file list | affected-tests R4 errors on a `.py`/`.sh` with no suite; `plugins/planning/tests/*.test.sh` precedent for in-plugin dev suites; CI wiring is out of scope |
| Phases 1 and 5 not promoted to sub-topics `[EXEC-SHAPE]` | one PLAN.md, one PR | both exceed 300 LOC but share one acceptance-criteria set and one commit boundary |
| Version bumps: session-flow minor (0.35.0), context-guard and implementation patch `[EXEC-SHAPE]` | Phases 4 and 6 | semver: new script + shape = capability; the other two are text-only |
| Sequential default, Phases 3/4 optionally as workers `[EXEC-SHAPE]` | Execution shape section | file-overlap matrix; ~100 LOC independent work is below the material-saving bar |
| Harness bound = `--max-turns` (Brief) plus `--max-budget-usd` per hop plus a `subprocess` timeout `[EXEC-SHAPE]` | Phase 5 flags | `--max-turns 1` probe succeeded (hidden flag, documented in the CLI reference); a looping hop otherwise burns the whole budget before failing |
| Harness child env built from an allowlist with every `CLAUDE_*` removed; `--session-id <uuid4>` per hop; file `session_id` == flag == JSON `session_id` asserted `[EXEC-SHAPE]` | Phase 5 assertions | a Bash-tool child inherits the parent's `CLAUDE_CODE_SESSION_ID`, `CLAUDE_EFFORT`, `CLAUDE_PLUGIN_DATA`; without the pin `new` would record the parent id and hop 4 would read the wrong transcript |
| Harness deletes only the transcripts whose session ids it created, unless `--keep` `[EXEC-SHAPE]` | Phase 5 cleanup step | `find-handoff` rung 2 ranks transcripts by mtime, so harness transcripts with real rails would outrank an operator's lost handoff for days; ids are known from each hop's JSON, so the delete is safe by construction |
| UTF-8 everywhere: `sys.stdout.reconfigure(encoding="utf-8")`, `encoding="utf-8"` on every open, `newline="\n"` on write, skill invokes `python3 -X utf8` `[EXEC-SHAPE]` | Script contract; Phase 1 cp1252 test | Windows Python 3.14 defaults to cp1252 on pipes and CRLF on write; the rails are U+2500; CI runs the suite on ubuntu only, so the condition is simulated with `PYTHONIOENCODING=cp1252` |
| Legacy 7-section predecessors mapped explicitly (absent section → `None. (shape-1 predecessor had no <section>)`; absent goal → `RECONSTRUCTED` FILL slot that `validate` refuses to pass empty) `[EXEC-SHAPE]` | Script contract; Phase 1 fixture | corpus scan: 11 of 33 files in the main checkout use the older 7-section shape and 16 lack `## Original goal` |
| `emit` substitutes its own real path on stdout when the stored `Read @` path differs (WARN on stderr, file untouched) `[EXEC-SHAPE]` | Script contract; rung 1 | handoffs preserved out of a removed worktree keep a dead absolute path; rung 1 would otherwise hand back a prompt to a missing checkout |
| `validate` runs a WARN-only secret-shape scan reusing `observer.py`'s shape-marker regexes `[EXEC-SHAPE]` | Script contract | design T9 assigns secret-shaped strings to the script's detect-then-judge tier; copied-forward sections would otherwise carry a token through every hop with only the model sweep as defence |
| Python-absent path: explicit `validator unavailable` line, hand-written shape 2, checklist box `validate: SKIPPED`, rails still emitted from the file's section `[FALLBACK — confirm or override]` | Phase 2 SKILL.md | Brief's captured assumption ("revisit if Python absent"); liveness-assertion forbids green-silent |
| Token estimate = chars/4, labelled as such `[FALLBACK — confirm or override]` | Phase 5 `--budget` report; design-threads budget section | no token counter ships with the CLI; the baseline above uses the same method so before/after compare |
| Fixture and harness paths handed to Python in mixed/native form (`cygpath -m` on Git Bash) `[EXEC-SHAPE]` | Phase 1 tests, Phase 5 harness | observed this session: native Python cannot open MSYS `/c/…` paths (the baseline script read 0 files until converted); windows-path-emit convention |
| Underscore module names (`save_point.py`, `hop_chain.py`) and exact-stem test pairs `[EXEC-SHAPE]` | Phase 1 and 5 file lists | affected-tests R2 pairs `<stem>.test.sh` / `tests/test_<stem>.py` by exact stem; pytest imports need a valid identifier; `parse_transcript.py` precedent |
| Self-ignore guard stays with the skill's existing bash step; `new` verifies and refuses, never writes `.gitignore` `[EXEC-SHAPE]` | Script contract `new` exit 1 case; structure.md write procedure | Brief: scripts read-only except the handoff file; the guard already exists in structure.md's procedure |
| `new` requires an explicit `--previous` or `--no-previous` (exit 2 otherwise) `[EXEC-SHAPE]` | Script contract | structure.md "Chain continuity — same task only" forbids auto-picking the newest file (splices unrelated tasks; retro aggregates them) |

### Mechanical work

- Commit boundaries: one commit per phase, plan marks riding the same commit (contract tier `branch`);
  `docs/topics/handoff-prompt-qol/` is currently untracked and enters the branch with the Phase 0 commit.
- Verification checkpoints: each phase's Sanity Check before its commit; Phase 6 runs the full gate set.
- Memory tier never staged: `.work/**` (fixtures for tests live under `plugins/…/tests/fixtures`, not `.work`).
