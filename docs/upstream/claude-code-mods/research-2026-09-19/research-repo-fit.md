# Fit with `melodic-software/claude-code-plugins`

Self-contained. Pin: 2026-09-19. Internal facts are from
`plugins-repo-explore/`, verified in its `VERIFICATION.md` (67 CONFIRMED, 9
WRONG, 0 UNVERIFIABLE across 76 rows) plus the follow-up sidecar
`plugins-repo-explore/EXPLORE-hook-budget-and-gates.md`. Every count below was
recomputed by script, not read off another artifact.

Basis labels: `OBSERVED` / `SOURCE` / `BINARY` / `STAFF` / `COMMUNITY` /
`INFERRED`. Internal repository facts are `OBSERVED`.

## Starting position

The repository has **zero prior contact with mods**: no mention of mods, function
hooks, `/plugin-types`, `claude plugin test`, `register(on`, or in-process hooks
anywhere in tracked content, on `main` or `origin/main`. `OBSERVED` · HIGH
(grep-verified absence). The phrase "in-process hook" appears only in a commit
*subject*, #4185.

But the repo already owns the machinery to decide this, written and precedented
four times over.

## The adoption gate, and what a `Wait` stance means

`docs/plugin-philosophy.md` line 218, **Native-first**, three conjunctive tests.
Test 2, verbatim (lines 234–235):

> is stable and works cleanly, so **experimental or immature features wait for
> maturity** and are re-verified against current docs before each fleet audit

`OBSERVED` · HIGH. Mods are explicitly early access in Anthropic's own words
(*"may change between releases without notice"*) and carry **no documentation at
all** to re-verify against. On the gate as written, mods do not clear test 2.

Precedent verdicts for exactly this shape, each recorded with a **recheck
trigger** rather than a date:

| Component | Stance | Rationale |
|---|---|---|
| Monitors | `Wait` | Experimental; schema may change between releases |
| Themes | `Wait` | Same |
| Channels | `Wait` | **Not** experimental — *"No longer carries an official experimental label, but fails the adoption gate today: no fleet gap it fills"* |
| Agent teams | `Defer` | *"Fails gate 2 and stops there"* (recorded under Recorded gate runs, not Component stances) |

`OBSERVED` · HIGH. (The Channels rationale was one of the nine WRONG rows the
verifier corrected; do not restate it as "experimental".)

### The binding consequence: a `Wait` stance is itself a shipping prohibition

`docs/migration-playbook.md` line 774, the eleven-step per-plugin migration gate,
**step 7**: every component a plugin ships must conform to the Component-stances
table — *"wait-listed components absent"*. `OBSERVED` · HIGH.

**The stance verdict and the shipping permission are the same decision. There is
no "Wait but pilot in `plugins/`" state.** A spike kept under `.work/` is the
only shape compatible with a `Wait` verdict.

Other playbook clauses a mod inherits: research fresh (WebFetch the official docs
for every component — **there are none**, which is itself a finding for step 1);
declare `userConfig` and use no custom config channel; validate with
`claude plugin validate` and test with `--plugin-dir` **in a clean repo that is
not the source repo**; explicit semver plus a changelog entry; a `./`-prefixed
relative marketplace `source`. Migration ordering is seams-first, one atomic PR
per cohesive unit, with `marketplace.json` and `docs/catalog.md` conflicts
resolved by **serializing the final merges, not authorship**. `OBSERVED` · HIGH.

The one fleet-scale hook migration this repo has run
(`docs/hook-migration-audit.md`, an audit **snapshot** dated 2026-07-12, not
durable policy) sets three precedents a mods sweep inherits: the accept/defer
discriminator is **concept-specificity, not path-count**; every deferral carries
an explicit revisit trigger; and cutover is **blue-green and staged** — no
in-repo original was removed in the PR that added its replacement.
`OBSERVED` · HIGH.

## The hook fleet, counted

| Measure | Value |
|---|---|
| Plugins shipping `hooks/hooks.json` | **20** (a 21st `hooks.json` is an eval fixture) |
| Wired hook command entries | **93** |
| Distinct events | **31** |
| Implementation scripts under `plugins/*/hooks` | **82** — 81 `.sh` + **1** `.mjs` |
| `*.test.sh` siblings | 46 of the 81 shell scripts (**57%**, not "every") |
| `.py` / `.ps1` inside `hooks/` | **0** / **0** |
| Skill-frontmatter hooks (a second surface) | **2** — `disk-hygiene/skills/clean`, `repo-hygiene/skills/clean`; both `PreToolUse`, matcher `Bash\|PowerShell` |
| Project-scope hooks (`.claude/settings.json`) | **1** entry, 1 event (`SessionStart`), shell form |
| Repo shape | 77 plugin dirs / 77 manifests / 77 changelogs / 77 marketplace entries / 273 `SKILL.md` |

`OBSERVED` · HIGH. `repo-hygiene` is a **21st plugin with a hook surface**,
absent from the 20-row table and from ADR 0028's classification.

The two skill-frontmatter hooks use **shell form deliberately**, with long in-file
comments: exec form resolves `command` on PATH, which on Windows finds the WSL
relay (`System32\bash.exe`) or the zero-length WindowsApps `python3` alias stub;
the hook then fails to launch, and **a failed launch is non-blocking, so the
guard silently enforces nothing.** Only `disk-hygiene` records that
`${CLAUDE_PLUGIN_ROOT}` is the *only* substitution a skill-frontmatter hook
receives. `OBSERVED` · HIGH.

**That comment block is the sharpest existing internal evidence for what an
in-process runtime would buy: it is exactly the class of silent-fail-open the
block exists to route around.** It is also the class the mods runtime
*reintroduces* in a different place — see `research-security-and-semantics.md`.

## The hook budget is max-shaped, and that decides the cost argument

`docs/conventions/hook-budget/README.md`: ≤ 1 s typical / ≤ 2 s worst-case per
tool call, ≤ 500 ms per turn, over every **always-on** hook a consumer install
fires. `OBSERVED` · HIGH.

The decisive fact: *"Claude Code runs matching hooks in parallel, so the wall is
the max of the set under spawn contention, **not the sum**."* Every per-surface
figure in the doc is labelled *slowest hook*.

**A "mods are cheaper per call" claim is a per-hook claim. Against a max-shaped
aggregate, removing cost from every hook except the slowest moves the budgeted
wall by exactly zero.** The doc names where the max sits: the **guardrails
dispatcher**, 1,360–3,048 ms per fire across the Write, Edit and Bash rows,
followed by `markdown-format`'s `markdownlint-cli2` Node process. Both are
already single processes fanning out internally — the shape a mod would produce.

So the honest framing: *a mod does not cut the wall unless it replaces the
guardrails dispatcher itself* — and guardrails is ADR-0028 **Class A** (the hooks
ARE the plugin), which never splits.

Three further binding facts:

1. **The fleet is already over the ceiling and the doc says so in its own voice**
   — *"no per-tool-call surface meets the budget, and on the reference host no
   per-turn surface does either."*
2. **Rule 2 forecloses the escape:** *"The budget never relaxes to absorb an
   overage… that overage is per-plugin remediation work, not grounds to move the
   ceiling."* "We are over anyway" is not a justification.
3. **Rule 3 is the one rule that favours mods:** *"Interpreter choice is a budget
   decision. Every always-on hook pays its interpreter's startup on every fire."*
   An in-process runtime is precisely an interpreter-startup elimination. Rule 1
   then obliges any plugin adding or widening an always-on hook to state its
   measured share in its README by that doc's method — an obligation a mod pilot
   inherits.

**Measure, do not cite.** The published reference figures (2026-09-02) predate a
69% growth in wired entries (16 events / 55 entries then; 31 / 93 now, almost
entirely `claude-ops`'s default-off logging pipeline), and seven unpulled
`perf(...)` commits on `origin/main` already optimised the exact plugins a mod
would replace — one titled *"run the guard chain in-process"* (#4185). Pull
`origin/main` first and state that any comparison is post-perf-work.
`OBSERVED` · HIGH.

## The exec-form gate is blind to `modules`

`scripts/check-hook-exec-form.sh` selects only hook objects satisfying **both**
`has("command")` and `has("args")`. A hook entry naming a TypeScript module
carries neither, so it never reaches the rule and **no finding is emitted**. The
same two-predicate filter governs the manifest-inline `.hooks` object and the
skill/agent frontmatter reader. `OBSERVED` · HIGH ·
`plugins-repo-explore/EXPLORE-hook-budget-and-gates.md` §(b).

**A mod-shaped `hooks.json` passes vacuously — the gate prints "No exec-form
hooks with a bare command name" over a tree containing mods.** That is the same
silent-no-op defect class the gate exists to catch, one level up; its own header
records that the class *"has shipped three times"*.

Scope note: *"A `hooks/*.json` file the manifest never references is not loaded
by Claude Code and is not scanned."* A mod pilot under `.work/` is out of scope by
construction; one under `plugins/<x>/hooks/hooks.json` is in scope and vacuously
clean.

One stale line found in passing and **not** fixed (that lane is read-only): the
gate's header says `.claude/settings.json` *"declares no hooks today"*. It
declares one `SessionStart` hook. The conclusion (out of scope either way) holds;
the stated reason does not.

## `npm ci` placement, and committed build output

> Claude Code runs `npm ci` in the cached copy whenever the plugin **ROOT** holds
> both a `package.json` and a lockfile, and that install cannot be turned off.

`OBSERVED` · HIGH (`plugins-reference`, verified 2026-09-11, recorded in
`plugins/miro/server/build.mjs`'s header). `plugins/miro`'s Node project lives at
`server/`, not the plugin root, **specifically** to avoid materialising its
devDependencies in every consumer's cache.

**Rule for a mod pilot: never put `package.json` + `package-lock.json` at
`plugins/<name>/`.** The lockfile still pins CI and Dependabot from a
subdirectory.

The same header states the platform fact behind the build-output question:
*"Plugin install copies the plugin directory into the consumer's cache and runs
no build step, so the runtime artifact must ship committed."* Unless the mods
runtime compiles for the consumer, compiled output must be committed, and there
is no install-time escape hatch. The repo's only precedent
(`plugins/miro/server/dist/index.min.js`) commits generated output and fails CI
on drift via byte-exact string equality against a pinned esbuild 0.28.2; a
one-byte toolchain change fails the gate until the bundle is rebuilt. Two
conventions a committed mod bundle would inherit: `.min.` in the filename (the
repo-wide carve-out keeping generated bundles out of the text-quality lanes) and
a stripped shebang (so it does not trip the shebang exec-bit gate).
`OBSERVED` · HIGH.

TypeScript in-tree today is **only** bundled Node packages. `plugins/miro/server`
is the reference: 17 `.ts` files (4 of them tests), strict tsconfig, vitest,
Biome, esbuild, committed drift-checked bundle. **There is no root TypeScript
build**, and `scripts/affected-tests.sh` contains **no `.ts` reference at all** —
it knows exactly four ecosystems (`*.test.sh`, `*.test.js`/`*.test.mjs`,
`test_*.py`, `*.Tests.ps1`). A `hooks.test.ts` would be invisible to the repo's
primary suite selector. `OBSERVED` · HIGH.

Recommended default from the explorer: a mod pilot ships as its own Node package
with a `run-tests.sh {install,build,test}` shim — the pattern
`video-digest`/`course-digest`/`ai-briefing` already use — plus one hand-added
`ci.yml` block. **Do not teach `affected-tests.sh` `*.test.ts` as part of a
pilot.** `OBSERVED` · recommendation.

## The CLI pin is a hard gate

`@anthropic-ai/claude-code` is pinned in root `package.json` devDependencies:
**2.1.276 on `origin/main`** (2.1.268 on local `main`; #4162 took it 268→274,
and #4200 took it 274→276). `OBSERVED` · HIGH.

`claude plugin test` appears to arrive around 2.1.271 (third-party binary diff,
`COMMUNITY` · MEDIUM) and is verified working on 2.1.278 (`OBSERVED`). No
first-party floor exists. Recommended default: treat the pin as a hard gate and
do not adopt until the pinned version supports the verb, rather than floating the
pin.

## The per-repo-configuration conflict

**This is a genuine structural misfit, not a preference.**

- Mods: plugin options are read from user settings, `--settings`, or managed
  settings — *"a project's `.claude/settings.json` is **not** read for plugin
  options."* `SOURCE` · HIGH
- This repo: org-agnosticism (philosophy line 26) and the two-lane convention
  posture (286) require shipped defaults not to impose a convention, and the
  migration gate requires proving repo-agnosticism by testing `--plugin-dir` in a
  repo that is not the source. `OBSERVED` · HIGH
- The four-seam extensibility contract is how a plugin takes consumer input.
  Seam 1 is `userConfig` → `pluginConfigs`, seam 4 is `${CLAUDE_PLUGIN_DATA}` for
  machine state **only, never configuration**. `OBSERVED` · HIGH

A mod therefore **cannot take per-repository configuration through the options
mechanism at all**. A consuming project that wants different behaviour in
different repositories has no seam-1 path; it must fall back to env vars or
file-based config, which is seam 3 — and seam 3 carries its own open question:
*"Hook scripts do not see `CLAUDE.md`; they read env vars and file-based config
only."* **Whether a mod's in-process handler inherits that restriction or the
model-context one is unresolved**, and it changes which seam a mod's
configuration belongs in. `OBSERVED` · unresolved.

Compounding it: the host fills an option's default before `register` sees it, so
a plugin cannot distinguish "unset" from "set to the default" — which removes the
usual migration affordance. `SOURCE` · HIGH.

## Pilot candidate

**`context-budget`**, if a pilot happens at all. It is the only plugin already on
Node (its single `hooks/settings-write-ask.mjs`, wired in the sanctioned
`"command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/…"]` exec form), its hook
surface is one `PreToolUse` entry, it has a boolean `userConfig` kill switch
(`settings_write_ask_enabled`), and it has **zero shell hook scripts to lose**.
`OBSERVED` · HIGH.

`biome-format` is the clearest *demonstration* (ten `if:` rows collapsing to one
predicate) but is ADR-0028 **Class A**, which never splits. `guardrails` is the
only plugin that would move the budget wall and is also Class A.

Recommended default: `context-budget` for a spike, **kept under `.work/` and
never merged**, so no Class A/B/C packaging question is opened and step 7 is not
violated.

## Where the verdict is recorded, and the ADR number

Three surfaces could hold it — the Component-stances table, the Recorded-gate-runs
table, or a new ADR. ADR 0021 used all three for its three components.
Recommended default: **one ADR carrying the verdict and recheck trigger, plus one
Component-stances row and one Recorded-gate-runs row pointing at it**, in the
four-part upstream-drift shape: claim, basis, as-of, trigger.

**Next free ADR number is 0035.** `docs/adr/` holds 37 files spanning 0001–0034
with no gaps and **three** duplicated numbers (`0018`, `0025`, `0028`) across six
files. A bare "ADR 0028" is ambiguous; the hook-packaging taxonomy is
`0028-classify-a-plugin-s-hooks-by-packaging-before-proposing-a-split.md`. Treat
the collisions as pre-existing and unrelated; do not fix them inside a mods
change. `OBSERVED` · HIGH. (The earlier "four duplicated ADR numbers" was
arithmetic matching neither reading; corrected.)

ADR 0021's enforcement hierarchy applies: **default REJECT** unless the value is
concrete and not already covered by an existing mechanism; a rejection still
emits an explicit recheck trigger, and zero implementation issues are opened on a
reject.

One more philosophy constraint worth naming: the hook rubric (line 783) requires
every kept hook to be classifiable as policy, behavioral, or hybrid, with
behavioral hooks as ablation candidates at each model generation. **A mechanism
change (shell → in-process) does not change a hook's class**, so it does not
rescue a hook that would otherwise be ablated. `OBSERVED` · HIGH.

## The reusable "deep-dive a new Claude Code feature" skill

**The explorer's recommendation: no new skill this round.** `OBSERVED` ·
recommendation · `plugins-repo-explore/EXPLORE-open-questions.md` q3.

Reasoning as recorded:

- The composition already exists — `discovery:research-deep` fanning lanes +
  `knowledge:map-corpus` / `docpage-digest` + `claude-ops:changelog` +
  `claude-ops:known-issues`. **Five of the six steps in a feature deep-dive are
  already owned.**
- The repo's own precedent for this class of question concluded *"no new plugin.
  Five work-item containers, three new skills inside existing plugins, everything
  else extends existing skills"*
  (`.work/plugin-concept-enhancements/shared-understanding.md`, 2026-09-06).
- If anything is built, **extend `claude-ops:changelog` with a feature-scoped
  subject** rather than a release range: it already owns
  `context/repo-surfaces.md` (the "which repo surface must move" map) and a
  persistent ledger marker.
- **Escape hatch:** the one **unowned** step is arbitration into the philosophy
  tables (Component stances / Recorded gate runs). If this is the second or third
  early-access feature to get this treatment, that arbitration step is the one
  worth skilling.

## The shape of the decision

The decision is **not** "build a mod or not". It is a verdict on one row of
`docs/plugin-philosophy.md`'s Component-stances table, recorded in the
Recorded-gate-runs four-part shape with a recheck trigger — machinery that is
written, precedented four times, and needs no new mechanism.

Suggested recheck trigger, matching the precedents' form: *the official mods
documentation page drops its early-access label, or `claude plugin test` reaches
a stable CLI surface listed in `claude plugin --help`.* See
`research-recheck-triggers.md` for the commands.
