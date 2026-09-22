# Contradictions and corrections

Every claim that was wrong at some stage, and its resolution. Read this before
asserting anything that "sounds obvious" — most entries below sounded obvious
when they were written.

Pin: 2026-09-19, Claude Code 2.1.278. Precedence when lanes disagreed:
**locally observed behavior on 2.1.278 > source tree / `.d.ts` > binary readable
string > staff statement > minified-code inference > community.** Where a lane's
prose and its own `VERIFICATION.md` disagreed, `VERIFICATION.md` won.

## A. Cross-lane resolutions carried into this report

These were settled by the dispatch and are **not** open. Do not reopen them.

### A1 — Deny semantics. The architecture PDF extraction was wrong

`architecture-pdf/ARCHITECTURE-PDF.md` asserted that *"`{deny}` does not block
the tool"* and that *"PDF p5 misleads"*. **Both are wrong: a conflation of two
true statements into one false one.**

`architecture-pdf/DENY-AND-ERROR-SEMANTICS.md` supersedes, on read plus direct
local observation:

- A well-formed `{ deny }` returned **instead of** `next(e)` **blocks** —
  observed in the test kit (hook beneath never ran) and live (the model received
  `<tool_use_error>DENIED_BY_GUARD_MOD</tool_use_error>` with `is_error: true`
  and the shell command did not execute).
- A `{ deny }` returned **after** `await next(e)` cannot un-run anything.
- `{}` or `undefined` without `next` is a **malformed** return: the hook is
  skipped and the chain beneath runs, so the tool executes and the model is told
  it succeeded. **This is the trap.**
- A throw and a 10 s overrun are **fail-open**, unless
  `on(...).catch(() => ({ deny }))` is attached.

The maintainer comment that seeded the error is about a deny returned *after*
`next(e)`. The PDF's p4 and p5 say the same thing as the shipped `.d.ts`
(p4 uses the word *"instead"*, and its listing has no `next` call).

**Both statements have been marked superseded in place in
`architecture-pdf/ARCHITECTURE-PDF.md`, with a pointer.** That is the one input
file this report edited.

### A2 — Desktop is demoed, not shipped

Claude Code Desktop was **demoed in an internal prototype on 2026-09-03 only**.
The `x-threads` lane originally wrote "Confirmed on terminal CLI and local Claude
Code Desktop"; its verifier corrected it in four places. Every Desktop reference
traces to one staff comment about an internal prototype and two demo-video
captions, all dated six days before the public flag; a `desktop` grep over all
203 comments returns nothing later. `x-threads/VERIFICATION.md` row 4;
`community-falsification/RESEARCH-falsification.md` claim 3.

### A3 — Enablement is a gate with an override, not an env var

`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is a **per-process override** of the
server-side GrowthBook gate `tengu_plugin_hooks_modules` (default `false`), via
`??`. **Activation can therefore happen without user action.** Built-in mods use
a **separate predicate** (`canLoadBuiltinHooksModules`) that never consults the
gate.

Three lanes each overstated some part of this and were corrected:

- `official-docs-changelog/RESEARCH.md` line 30 said the gate was "one
  client-side environment variable … no allowlist". **OVERSTATED**; corrected by
  its own verifier's `--debug` capture naming the rollout flag.
- `community-falsification` said *"the flag governs whether the machinery exists
  at all"* and that absence is "quiet in both directions". **WRONG**; corrected
  as **M1**, the lane's one missed ship-blocking risk.
- `surfaces-desktop` said the env var "is how function hooks get enabled".
  **OVERSTATED**; corrected to "one of two enablement paths".

### A4 — Exactly one hooks module per plugin; `hooks.json` may carry both kinds

`repo-primary/RESEARCH-mod-definition.md` said *"`modules` is an array, so more
than one module per plugin is expressible."* **WRONG.** The shipping manifest
schema caps it at one: *"hooks.json `modules` names one hooks module per plugin;
a second entry is refused."* The array type is a schema artifact.

Separately — and the producing lane was silent on this — one `hooks.json` may
carry classic settings-format `hooks`, `modules`, **or both**. Schema refine
message: *"hooks.json must have `hooks` … or `modules` …, or both."*

### A5 — Plugin options are never read from project settings

User settings, `--settings`, or managed settings only. *"a project's
`.claude/settings.json` is **not** read for plugin options."* A mod cannot take
per-repository configuration through the options mechanism. See
`research-repo-fit.md` for why this conflicts with this repo's agnosticity rules.

### A6 — The install path is community-sourced

`claude plugin marketplace add` / `claude plugin install` for a mod comes from
**one community source** (`halluton/Mindful-Claude`'s README). A grep of all 203
comments in #91870 for `marketplace | plugin install | plugin add |
--plugin-dir` returned one false positive. **No staff statement names either
command.** Staff corroborate only the hedged intent that packaging is unchanged.
`x-threads/VERIFICATION.md` row 3 — the claim keeps its conclusion but loses a
pool.

## B. Corrections inside individual lanes

### `repo-primary/` (74 rows: 66 CONFIRMED, 1 WRONG, 4 OVERSTATED, 3 GAP)

| Row | Was | Now |
|---|---|---|
| 5.1 | `modules` array allows several modules | **WRONG** — exactly one; a second is refused. See A4 |
| 6.5 | The GrowthBook-off providers are Bedrock / Vertex / Foundry | **OVERSTATED** — the binary says only *"a third-party provider"*; the trio is interpolated from the CHANGELOG. Mark `INFERRED` |
| 8.8 | The AGENTS.md *"not yet on Bedrock, Vertex or Foundry"* parenthetical corroborates that mods ride the rollout gate | **OVERSTATED and internally inconsistent** — `agents-md` is a built-in and does not ride that gate. It corroborates that **a provider predicate sits inside `canLoadBuiltinHooksModules`**, partially narrowing gap G3 |
| 9.8 | `$.ui.mount`'s drawing has five members | **OVERSTATED** — **thirteen**: `drawn, find, findAll, press, input, select, key, pointer, post, advance, resize, redraw, unmount`. Also, `ui.` in the header example is a **local variable**, not an API path |
| 1.17 | `@inline` provenance at `.d.ts:L6160` | **OVERSTATED** — the JSDoc is at **L6167**; the claim itself is correct |
| 5.4 | *(silent)* | **GAP** — `hooks` and `modules` may coexist. See A4 |
| 5.5 | *(silent)* | **GAP** — a per-plugin `hooks.json` size cap exists; numeric value not read |
| 9.7 | *(silent)* | **GAP** — `RenderComponent` is a closed **15**-member union a `ui.render` matcher selects from |
| 6.9 | "a separate worker process" | Refined — **one worker per plugin**, plus a heartbeat/wedge detector |
| C4 (self-corrected mid-lane) | The `claude plugin test` refusal string names `canLoadBuiltinHooksModules`'s predicates | **Withdrawn** — that string sits on the user-module path; `agents-md`'s README contradicts the mapping directly |

### `official-docs-changelog/` (7 of 7 assigned CONFIRMED, 1 unassigned OVERSTATED)

- The gate description. See A3.
- Precision note kept: bare `plugin test` appears **once** in `llms-full.txt`
  (the English word *testing*); `claude plugin test` → 0.
- Precision note kept: "Sep 9, 2026" is a heading typed into an edited issue
  body, not a GitHub timestamp, and is unverifiable from metadata.
- `EN-5`'s MEDIUM on `/plugin-types` is **not earned by its cited evidence**: the
  probe tests a CLI subcommand while `mods/README.md` describes a slash command.

### `x-threads/` (8 CONFIRMED, 3 OVERSTATED, 1 WRONG)

| Was | Now |
|---|---|
| Desktop confirmed | **OVERSTATED** — demoed in an internal prototype. See A2 |
| The install path has two pools, one of them staff | **OVERSTATED** — one community pool. See A6 |
| "Staff renamed an **event** mid-thread" | **WRONG** — the rename was `fs.readFile` → `fs.read`, a **`$` affordance**. The instability finding survives; the wording does not |
| "every mod system … **converge** to … a Mod Manager" | Quote integrity — the source reads **converging**. Two further unmarked elisions recorded |
| "Sep 19 five-tier list" | The Sep 19 list names **four**; the Sep 7 list names five |

### `community-falsification/` (13 CONFIRMED, 2 OVERSTATED, 2 WRONG, plus M1)

| Was | Now |
|---|---|
| The flag governs whether the machinery exists at all | **WRONG** — see A3 / M1 |
| A version-floor conflict exists (davila7 vs claudefa.st) | **WRONG** — no conflict. Exactly one floor claim exists (davila7, `>= 2.1.259`, third-party, uncorroborated); claudefa.st asserts none |
| Coexistence sourced to `mods/README.md` | **CONFIRMED but re-sourced** — all four built-in mods ship `modules` only. Re-sourced to a local `claude plugin validate` probe (accepts both; rejects a malformed classic block) and `pleaseai/honmoon` in the wild |
| `node:vm` non-containment attributed to staff | **CONFIRMED as labeled**, attribution corrected — staff asserted a boundary and never conceded non-containment; the support is Node's own docs. This is the corpus's inference |
| The `CONTRIBUTOR` badge is evidence against MEMBER | **Corrected** — the badge is **neutral**: org membership on that account is not public, so an outsider cannot distinguish the two. The real signal is self-merge access |
| Three maintainer positions on throw behavior; "any guard rests on an undecided behavior" | **OVERSTATED** — **four** positions, and the fourth describes an author-side construction the maintainer says cannot be skipped. Rewrite: *the engine's default is undecided; a guard that wants fail-closed must construct it itself* |
| HN: one story | **OVERSTATED trivially** — a second, unrelated 2026-07-05 story exists. Conclusion (attention ≈ nil) stands. Also: poteat posted **30** comments in #91870, not "~20" |

### `surfaces-desktop/` (9 CONFIRMED, 2 OVERSTATED, 1 WRONG, 1 UNVERIFIABLE)

| Was | Now |
|---|---|
| Tiers, `prependPlugins`, `next.to`, `e.provider.tier` appear **only** in `sec-default/README.md` | **WRONG** — all are declared in `mods/types/claude-code.d.ts`. The true narrower claim: **no official docs page and no CHANGELOG entry** mentions them |
| The env var is how function hooks get enabled | **OVERSTATED** — see A3 |
| #91870 "names terminal and the desktop app as hosts" | **OVERSTATED** — those are **demo-video captions**; the issue makes no statement about where the gate is honored |
| "Claude Code stays a separate mode after the merge" | **UNVERIFIABLE first-party** — the announcement never names Claude Code. Of three secondary outlets re-fetched, only 9to5Mac carries it; **TechCrunch, cited by the lane for exactly this, does not** |
| Docs silence MEDIUM (`llms.txt` is curated) | **Upgraded to HIGH** — the **full** corpus `llms-full.txt` was grepped |
| `.mcpb` characterization MEDIUM | **Upgraded to HIGH** — the MCPB manifest spec has **no** fields for skills, agents, hooks or commands |
| `prependPlugins` "appears only in the mods source" (gap G7) | **Closed** — 12 occurrences with live UX strings in the 2.1.278 binary, including the seating function |
| "No CLI coordinator equivalent" argued from absence | **Upgraded** to a direct first-party statement in the `claude-projects` docs |

### `plugins-repo-explore/` (67 CONFIRMED, 9 WRONG)

| Was | Now |
|---|---|
| `origin/main` CLI pin 2.1.274 | **2.1.276** |
| `claude-ops` "31 events, 42 entries" | **30 events, 40 entries** (31 is the fleet-wide distinct-event count) |
| 35 convention directories | **33** |
| `.work/` holds 27 slices | **26** directories plus one loose file |
| Six plugin-local `AGENTS.md` plus the root | **five** plugin-local, six with the root |
| "Every hook implementation script has a sibling `.test.sh`" | **46 of 81** (57%) |
| Both skill-frontmatter hooks record the `${CLAUDE_PLUGIN_ROOT}`-only note | **`disk-hygiene` only** |
| Monitors/Themes/Channels all `Wait` **(experimental)** | **Channels is not experimental** — it waits on gate 1 (no fleet gap) |
| miro "~20 `.ts` files" | **17**, 4 of them tests |
| "four duplicated ADR numbers" | **three** numbers (`0018`, `0025`, `0028`) across six files; next free is **0035** |
| "29 of 93 entries" for guardrails + claude-ops | **49** (9 + 40) — wrong under either the old or the new number |
| INVENTORY's "16 distinct events" reproduced without a staleness note | Flagged: right on 2026-09-02, **stale now**. Replay at `8eae8e8e9` gives 20 plugins / 16 events / 55 entries against today's 20 / 31 / 93 |

### Applied but unrecorded (added by `VERIFICATION.md`, 2026-09-19)

Three lane corrections that were already applied to the synthesis prose but
missing from this ledger, per `VERIFICATION.md` Check 2.

| Correction applied where | What was missing from §B |
|---|---|
| `community-falsification/VERIFICATION.md` row 3 tail — the Windows repro at 2.1.272 qualifies the field-evidence sidecar's "No Windows-specific mods defect was found in the tracker." Applied at `research-authoring-and-testing.md:243-244` ("Not defect-free"). | Not listed here until now. |
| `community-falsification/VERIFICATION.md` row 7 refinements — the davila7 tree has grown past the artifact's list, and two repos (`Charlie0113-T/claude-agent-flow`, `shcv/harness-investigations`) were correctly filtered out of the "seven". The "seven" figure is used at `research-enablement-and-distribution.md:205` and `research-roadmap-and-staff-statements.md:236` without the filtering note. | Neither repo's exclusion was recorded here. |
| `surfaces-desktop/VERIFICATION.md` row 1 note — "no single sentence says 'plugin hooks run in Cowork'"; the claim is a sound join of two adjacent sentences, graded CONFIRMED, not a resurrection. `research-surfaces.md:86-90` presents the joined conclusion without the caveat, which is load-bearing for anyone re-quoting it. | The join caveat was never recorded here. |

## C. Unresolved between inputs

Recorded rather than chosen silently.

1. **The hook budget's confidence label.** `repo-primary` rated the 10 s figure
   **MEDIUM** (gap G6: it came from one JSDoc sentence about the *mock clock*,
   and `HookBudget`'s fields were not read). `architecture-pdf/DENY-AND-ERROR-SEMANTICS.md`
   read `HookBudget` at `.d.ts:L4180-4205` directly **and observed a live cut at
   10,249.9 ms**. This report states it as HIGH on `OBSERVED` + `SOURCE`, which
   is the precedence order applied, not an upgrade of a verifier's verdict — no
   verifier lowered it. Recorded here so the divergence is visible.
2. **`canLoadBuiltinHooksModules`'s predicates `kS()` and `mg()`.** Unresolved.
   `agents-md`'s README asserts a built-in is not turned off by `disableAllHooks`
   / `allowManagedHooksOnly` / `--bare`; the `surfaces-desktop` verifier reports
   reading `kS() = policySettings?.disableAllHooks === true` and
   `mg() = kS() || (allowManagedHooksOnly === true || disableAllHooks in user
   settings)` out of the same binary. **A first-party README and a minified-code
   reading disagree.** Under the stated precedence the README wins, but the
   conflict is real and the repo-primary lane explicitly widened it into gap G3.
   Treat the predicate identities as unknown.
3. **Whether `hooks` and `modules` in one `hooks.json` both reliably *fire*.**
   Coexistence is validated; issue #92675 reports plugin-native `PreToolUse`
   hooks not enforced in interactive sessions. OPEN, 0 comments.
4. **Whether `mods/README.md`'s "for now" tsconfig-include advice is stale.** The
   README says per-plugin type contracts are future work; the same-SHA `.d.ts`
   header and the 2.1.278 binary's generator describe them as existing outputs.
   Resolution: the generated `.d.ts` and the binary win, the README paragraph is
   stale — but `/plugin-types` was **not run end to end** by any lane.
5. **Whether a mod's in-process handler sees `CLAUDE.md`.** The repo's four-seam
   contract states *"Hook scripts do not see `CLAUDE.md`; they read env vars and
   file-based config only."* Nothing external settles whether a mod inherits that
   or the model-context rule. It changes which seam a mod's configuration
   belongs in.
6. **`RenderSurface` has no value for a browser tab.** `claude.ai/code` in a
   browser maps to no enum member. Recorded as a gap, **not** a denial.
7. **Whether the rollout gate is on for anyone.** Checked: this machine (off).
   Unchecked: any other account, plan tier, or organization.
8. **Performance.** 50 µs p99 (vendor, dispatch primitive) against 1.4 s (one
   community cold render). No independent benchmark. No claim accepted.
9. **Mods' age depends on which event you date from.** The proposal issue opened
   2026-09-03 (16 days before this report); the `mods/` tree first landed
   2026-09-09T22:30:08Z (10 calendar days, 9.1 elapsed). Lanes used both. State
   the event, not the number.

## D. Evidence-independence warnings

- `mods/README.md`, the `mods/*` commit history, and the #91870 comments are
  **plausibly one author** and count as **one** corroborator. The second
  independent pool for load-bearing claims is the installed 2.1.278 binary; for
  version claims, the npm registry.
- `claudefa.st` states in its own text that it documents the #91870 proposal. It
  **echoes rather than corroborates**.
- The genuinely independent legs across this corpus are: the shipped binary, the
  seven third-party adopter repos, `davila7`'s mods library, the Practical
  Systems migration report, and the independent issue reporters.
