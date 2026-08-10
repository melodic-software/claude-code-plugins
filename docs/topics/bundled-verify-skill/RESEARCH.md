# Bundled `/verify` — what it is, how it is built, what we can package

## Brief

**TLDR:** Claude Code's bundled `/verify` is a single ~10 KB prompt-only skill plus two example
files, registered in code (not from disk) with a frontmatter surface of exactly `name` +
`description`. Its one real extensibility point is a **filesystem convention**, not an API: it
`ls`-probes `.claude/skills/` for `verifier-*` / `run-*` directories, and it writes
`.claude/skills/verify/SKILL.md` — which, at the repo root, **replaces** the bundled skill
outright. Plugin skills are namespaced `plugin:name` and live outside `.claude/skills/`, so a
plugin **cannot** shadow `/verify` and **is not discovered** by its probe.

The permission is one-directional and that is the design: we **cannot** invoke `/verify` (hard
tool-layer block, proven), but `/verify` **can** invoke our plugin skills. So the workable shapes
are the ones that *tell it we exist* — either at run time via its free-text argument (shape E, the
prompt shim: cheap, writes nothing) or on disk via a generator (shape C: durable, but root-level
emission destroys the consumer's bundled `/verify`). Ruled out: shadowing it, and expecting its
`ls` probe to find plugin-shipped `verifier-*` skills.

**Status:** research only. No plugin work started. Feeds a `/planning:interview` decision.

### Provenance

| Source | What | When |
|---|---|---|
| `~/.local/share/claude/versions/2.1.226` (installed binary) | `verify` SKILL.md, `examples/cli.md`, `examples/server.md`, the `Iu({...})` registration call, the PR-prep suggestion generator | extracted 2026-08-10 |
| `~/.local/share/claude/versions/{2.1.223,2.1.224,2.1.225}` | differential check on the registration call and the invocability mechanism (§3) | extracted 2026-08-10 |
| [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills) — "Bundled skills", "Run and verify your app", "Where skills live" | version floors, invocability, precedence | fetched 2026-08-10 |

Binary strings are a **point-in-time observation of specific builds**, not a contract. Version
floors below come from the docs; mechanism details come from the four builds named above and can
change without a doc change. `/verify`'s SKILL.md body and the `verifier-*` probe are byte-stable
across all four; only the registration call moved (§3).

**Reproduce the extraction:**

```bash
BIN=~/.local/share/claude/versions/<version>
grep -abo 'name: verify' "$BIN"            # byte offset of the frontmatter
grep -abo 'var _hh=' "$BIN"                # SKILL.md template literal (id is build-specific)
grep -abo -E 'var (mhh|ghh)=' "$BIN"       # examples/cli.md, examples/server.md
grep -abo 'name:"verify"' "$BIN"           # the registration call
```

For the §3 differential, count markers across every build in `~/.local/share/claude/versions/`:
`skills/verify/SKILL.md` (the replacement seam), `verifier-\*` (the probe), and
`tengu_pr_prep_suggestion_rendered` (the pre-commit nudge). Where `name:"verify"` does not match,
the name is minified to an identifier — locate `name: verify` (the frontmatter, always a literal)
and read forward to the registration call.

The identifiers (`_hh`, `mhh`, `ghh`, `Wie`, `I0r`) are minifier output and **will differ every
build** — re-derive them from the string content, never reuse them. A decoded copy of all three
files for 2.1.226 was produced during this research; it is deliberately **not committed** — see
[Open question 5](#open-questions-for-the-interview).

## 1. What `/verify` is

One of three bundled skills that make up Claude Code's "run the app" story (docs floor: **v2.1.145**
for all three):

| Skill | Purpose | Model-invocable in 2.1.226? |
|---|---|---|
| `/run` | Launch and drive the app to see a change working | **Yes** — no `disableModelInvocation` |
| `/verify` | Build + run + drive to confirm a change does what it should | **Flag-gated** — see §3 |
| `/run-skill-generator` | Record the build/launch recipe as `.claude/skills/run-<name>/` | **No** — `disableModelInvocation: !0` (hard) |

`/verify`'s thesis, stated in its first three lines:

> **Verification is runtime observation.** You build the app, run it, drive it to where the changed
> code executes, and capture what you see. That capture is your evidence. Nothing else is.
>
> **Don't run tests. Don't typecheck.** Running them here proves you can run CI — not that the
> change works.
>
> **Don't import-and-call.** [...] The app never ran. Whatever calls `foo` in the real codebase ends
> at a CLI, a socket, or a window. Go there.

That negative space is the whole design. It is an anti-`/toolchain:check` — it defines itself by
what it refuses to accept as evidence.

## 2. How it is used

- Typed: `/verify` or `/verify <free-form text>`.
- No `argument-hint`, no `$ARGUMENTS`, no mode parsing, no ecosystem filter. The prompt assembly is:

  ```js
  async getPromptForCommand(e) {
    const { SKILL_MD: t } = await load();
    const r = [parseFrontmatter(t).content.trimStart()];
    if (e) r.push(`## User Request\n\n${e}`);
    return [{ type: "text", text: r.join("\n\n") }];
  }
  ```

  **The user's argument is appended verbatim under a `## User Request` heading and nothing else
  happens to it.** Whatever you type is natural-language steering interpreted by the skill body —
  scope ("verify just the auth change"), surface ("drive it through the TUI"), or a claim to check.
  `/run` and `/run-skill-generator` use the identical assembly; it is the bundled-skill house
  pattern.

- Scope resolution when no argument is given (from the body): `git log --oneline @{u}..`,
  `git diff @{u}.. --stat`, `git diff origin/HEAD... --stat`, `git diff HEAD --stat`, `gh pr diff`.
  Explicitly **the full branch range, not `HEAD~1`**. No repo → "the scope is whatever the user
  named; ask if they didn't."

- It is nudged, not auto-run. A separate code path emits a pre-commit suggestion naming `/verify`,
  `/simplify`, and `/code-review medium` by literal name, with hard language: *"your own tests,
  typecheck, e2e, or any 'equivalent' do not count as a check having run; only invoking the skill
  does."* That suggestion is gated on the **same flag** as model invocation (§3), and it only
  includes a skill if a skill by that name is registered.

## 3. Invocability — user-only by default, with a new runtime opt-in

Registration in 2.1.226:

```js
Iu({
  name: "verify",
  description: <the frontmatter description, duplicated as a JS string>,
  userInvocable: true,
  disableModelInvocation: () => !flagEnabled("tengu_opal_circuit"),
  files: () => ({ "examples/cli.md": ..., "examples/server.md": ... }),
  getPromptForCommand,
})
```

Compare `/run` (no `disableModelInvocation` at all) and `/run-skill-generator`
(`disableModelInvocation: !0`).

**The mechanism changed mid-series.** Differential check across four installed builds:

| Build | `verify` registration | `tengu_opal_circuit` present | PR-prep suggestion present |
|---|---|---|---|
| 2.1.223 | `disableModelInvocation: !0` (hard) | no | no |
| 2.1.224 | same | no | no |
| 2.1.225 | — | **yes** | yes |
| 2.1.226 | `disableModelInvocation: () => !flag(...)` | yes | yes |

So the trajectory is: model-invocable before v2.1.215 → **hard** user-only through at least 2.1.224
→ from 2.1.225 user-only **unless** a runtime flag re-enables model invocation. The same flag gates
the pre-commit suggestion, which does not exist at all in 2.1.223/224 — they ship together as one
feature.

**Finding:** the docs' statement is the accurate default ("others, including `/verify` and
`/code-review`, run only when you invoke them [...] Before v2.1.215, Claude could also run `/verify`
and `/code-review` on its own"). What the binary adds is that from 2.1.225 the restriction is no
longer purely version-keyed: **two users on the same version can differ** depending on flag
rollout. In this session on 2.1.226 the flag is off — `verify` is absent from the model-visible
skill list while `run`, `code-review`, and `security-review` are present.

The flag name is an internal identifier observed in two builds. Treat "a runtime gate exists" as
the durable fact and the name as disposable.

### The block is enforced, and it is one-directional

Attempted in this session on 2.1.226, `Skill({skill: "verify", args: "..."})` returns:

> Skill verify cannot be used with Skill tool due to disable-model-invocation. Ask the user to run
> `/verify` themselves — it cannot be invoked via the Skill tool. Do not replicate this skill's
> workflow by other means — it is reserved for explicit user invocation.

So delegation is **hard-blocked at the tool layer**, not merely discouraged — proof, not inference.

But the permission runs **one way only**, and this is the most useful fact in the whole document:

- **We cannot invoke `/verify`.** Blocked.
- **`/verify` can invoke our plugin skills.** Its body already says *"invoke it with the Skill tool"*
  on a verifier match, and none of our skills set `disable-model-invocation`.

We cannot push work into it. Once the user starts it, it can pull ours. Every workable integration
shape follows from that asymmetry (§6).

Consequence for us: **never write a plugin that delegates to `/verify` via the Skill tool.**
Suggesting the user run it is the only path that holds across the whole availability window. Our
`testing:run-e2e` and `verification:confirm` already say exactly this — that guidance is correct,
and the mid-series change is a reason to keep it rather than tighten it. See
[Follow-ups](#follow-ups).

**Scope of the "don't replicate" clause.** That sentence is a runtime instruction to an agent that
just attempted the call — not a policy about what a plugin may contain. `testing:run-e2e` and
`verification:confirm` are independently-owned capabilities and are untouched by it. The boundary
to respect when authoring: a skill body must not tell an agent to *do `/verify`'s job because
`/verify` was refused*. Owning orchestrated e2e verification on our own terms is fine; standing in
for a refused `/verify` is not.

Also relevant to any dependency on `/verify` existing at all: `disableBundledSkills` turns off every
bundled skill except `/doctor`, and `skillOverrides` can set a bundled skill to `"off"`. Neither
reaches plugin skills.

## 4. How it is constructed

### The asymmetry that matters

| Aspect | Bundled `/verify` | Any plugin skill we can ship |
|---|---|---|
| Frontmatter | `name`, `description` — **that is all** | must express everything in frontmatter |
| Invocability | set in the registration call (`userInvocable`, `disableModelInvocation` as a *function*) | `user-invocable` / `disable-model-invocation` (static booleans) |
| Supporting files | `files: { "examples/cli.md": <string>, ... }` — materialized from memory | real files on disk next to `SKILL.md` |
| Prompt assembly | custom JS (`getPromptForCommand`) | fixed: body + substitutions |
| Bash injection (`` !`cmd` ``) | **not used** | used by most of our skills |
| Name collision | reserves bare `/verify` | namespaced `/<plugin>:<name>`, cannot collide |

The bundled skill gets a **conditional, computed** invocability that plugin frontmatter has no way
to express. Everything else about its construction we can match.

### File layout

```
verify/
  SKILL.md          ~10 KB, 8 sections
  examples/cli.md   ~1.7 KB  — worked example: adding a --json flag
  examples/server.md ~2.2 KB — worked example: adding a Retry-After header on 429
```

Linked from the body with plain relative markdown links inside a table:

```markdown
| CLI / TUI      | terminal | type the command, capture the pane — [example](examples/cli.md) |
| Server / API   | socket   | send the request, capture the response — [example](examples/server.md) |
```

This is the same progressive-disclosure shape our skills use (`[context/e2e.md](context/e2e.md)`) —
**hub SKILL.md, spoke files loaded on demand.** Notably the spokes are *worked examples with real
command output and a "What FAIL looks like" section*, not reference tables. Each example is:
Pattern → Worked example (Diff / Claim / Inference / Plan / Execute with captured output / Verdict)
→ What FAIL looks like → edge cases. That "What FAIL looks like" section is the highest-value shape
here — it pre-loads the failure interpretations so the agent doesn't have to guess whether an empty
result means "passed" or "never reached the code."

### Body structure (8 sections, in execution order)

1. **Framing** (3 rules, all negative) — runtime observation only; no tests/typecheck; no
   import-and-call.
2. **Find the change** — git range commands; "The diff is ground truth. Any description is a claim
   about it. [...] If they disagree, that's a finding."
3. **Surface** — a 6-row `Change reaches → Surface → You` table (CLI/TUI, Server/API, GUI, Library,
   Prompt/agent config, CI workflow). Plus: "Internal function? Not a surface." and "Tests in the
   diff are the author's evidence, not a surface."
4. **Get a handle** — the `ls` probe (§5), stale-verifier handling, cold-start timebox (~15 min),
   and the persist-what-you-learned rule.
5. **Drive it** — smallest path that executes the changed code; "Read your plan back before running.
   If every step is build / typecheck / run test file — you've planned a CI rerun."
6. **Push on it** — adversarial probes keyed to change type (new flag → empty value / passed twice /
   conflicting flag / typo; new route → wrong method, malformed body, oversized payload;
   interactive → Ctrl-C mid-op, resize, paste garbage; state → do it twice, stale state, two
   sessions).
7. **Capture** — captured output is evidence, memory isn't; isolate shared process state
   (`tmux -L name`, bind `:0`, `mktemp -d`).
8. **Report** — a fixed inline template with a 4-value verdict.

### The report contract

```
## Verification: <one-line what changed>
**Verdict:** PASS | FAIL | BLOCKED | SKIP
**Claim:** ...
**Method:** ...
### Steps
1. ✅/❌/⚠️/🔍 <what you did to the running app> → <what you observed>
**Screenshot / sample:** ...
### Findings
```

Verdict semantics: **PASS** (ran it, works at its surface — not "tests pass"), **FAIL** (ran it,
doesn't), **BLOCKED** (couldn't reach an observable state — *not a verdict on the change*),
**SKIP** (no runtime surface exists). Two rules worth stealing verbatim:

- *"No partial pass. '3 of 4 passed' is FAIL until 4 passes or is explained away."*
- *"When in doubt, FAIL. False PASS ships broken code; false FAIL costs one more human look.
  Ambiguous output is FAIL with the raw capture attached — don't interpret."*

And the emoji taxonomy is load-bearing, not decoration: **🔍 marks a probe**, and *"A Steps list
that's all ✅ and no 🔍 is a happy-path replay: still PASS, but you stopped at the first half."*
At least one 🔍 is required.

## 5. Extensibility points

Four, in descending order of leverage.

### 5.1 `.claude/skills/verify/SKILL.md` — replacement (the primary seam)

Docs: *"`/verify` can also record its own recipe. [...] it writes what worked to
`.claude/skills/verify/SKILL.md` at the repo root, or in the touched package directory in a
monorepo [...] **At the repo root, the recorded skill replaces the bundled `/verify`.** This
requires Claude Code v2.1.200 or later."*

Precedence (docs, "Where skills live"): *"A skill at any of these levels also overrides a bundled
skill with the same name."* Enterprise > personal > project.

The bundled body's own instruction for writing it:

> Got through → **persist what you learned**: create `.claude/skills/verify/SKILL.md` at the level
> you probed above [...] capturing the build/launch/drive recipe that worked, so the next session
> skips this cold start. Keep it short: the commands that worked, the flows worth driving, any
> gotchas. A project verify skill already exists → **edit it only when it steered you wrong**: a
> documented command failed or turned out wrong, or a needed step it doesn't cover. Routine
> learnings don't warrant an edit, and never rewrite or reorganize existing content for style.

That edit-discipline is deliberate — the docs say the pre-v2.1.205 "fold in anything a run learned"
wording *"caused frequent merge conflicts."*

`/verify` is also the **single sanctioned exception** to Claude Code's own memory rule against
creating project skills. From the memory-types prompt in the same binary:

> Edit existing skill files only; never create one — a new project skill silently shadows a
> same-named built-in skill. **The single exception is verify**, because how a project verifies
> changes is project-specific [...] and if that file does not exist, create it.

**Consequence:** at the repo root this seam is all-or-nothing. A project `verify` skill does not
*extend* the bundled one — it **replaces** it, and everything in §4 (the surface table, the probe
discipline, the report contract, the "when in doubt, FAIL" rule) is gone unless the replacement
restates it. In a **nested** package dir it is additive: nested same-named skills both stay
available under a directory-qualified name (`apps/web:verify`), and from v2.1.203 invoking the
unqualified name appends the qualified variants with an instruction to also invoke the matching
one.

### 5.2 The `verifier-*` / `run-*` `ls` probe — convention, not API

From the body:

> **Check `.claude/skills/` first — even if you already know how to build and run.** A matching
> `verifier-*` skill is the repo's evidence-capture protocol: it wraps the session so a reviewer
> can replay what you saw (recording, screenshots).
>
> ```bash
> ls .claude/skills/                    # repo root
> ls <touched-dir>/.claude/skills/      # each dir level the diff names
> ```
>
> - **`verifier-*` matching your surface** → invoke it with the Skill tool and follow its setup.
> - **`run-*` but no matching verifier** → use its build/launch primitives as your handle.
> - **Neither** → cold start from README/package.json/Makefile. Timebox ~15 min.

**Verified against the binary:** the token `verifier-` appears in only two places — this SKILL.md
prose, and unrelated code (an artifact markup validator, a code-review workflow's agent labels).
**There is no code-level discovery of `verifier-*` skills.** It is a literal shell `ls` written into
a prompt.

**This is the finding that decides the packaging question.** Plugin skills live at
`<plugin>/skills/<name>/SKILL.md` under the plugin cache, not `.claude/skills/`, and surface as
`/<plugin>:<name>`. A `testing:verifier-playwright` skill will **not** appear in `ls .claude/skills/`
and will **not** be found by this probe.

**Discovery and invocation are separate, though.** The body's instruction on a match is *"invoke it
with the Skill tool"* — and if the marketplace is installed, `/testing:verifier-playwright` is
perfectly invocable that way (§3: the block runs the other direction only). What is missing is
purely the *discovery* step. So a plugin's verifier becomes reachable from bundled `/verify` the
moment **anything tells `/verify` it exists** — a generated `verifier-*` shim in `.claude/skills/`,
a line in the consumer's project verify skill, or simply the user's own `/verify` argument, which
lands after the whole body and is free text (§6, shape E).

Naming our skills to `/verify` is not fighting the probe — it **supplies what the probe was looking
for**, for skills the probe structurally cannot see.

The probe text is byte-identical across 2.1.223–2.1.226, so this convention is stable, not in flux.

### 5.3 `/run-skill-generator` — the recorder

Writes `<unit>/.claude/skills/run-<unit-name>/` with a bundled `template.md` plus six worked
examples (cli, server, tui, electron, library, playwright). Hard `disableModelInvocation` — user
only, always. `/verify`'s BLOCKED path is instructed to emit *"a filled-in `/run-skill-generator`
prompt"* rather than just failing. This is the shape a generator-style plugin would imitate.

### 5.4 Kill switches

`disableBundledSkills` (all bundled skills except `/doctor`) and `skillOverrides: {"verify": "off"}`.
Neither reaches plugin skills. Any plugin that *depends* on `/verify` being present must degrade
gracefully.

## 6. Can we package it? — three answers, separately

| Shape | Mechanically possible? | Verdict |
|---|---|---|
| **A. Wrap it** — a plugin skill named `verify` that shadows or replaces the bundled one | **No.** Plugin skills are namespaced `plugin:name` and "cannot conflict with other levels". `/melodic:verify` would coexist; bare `/verify` stays bundled | Rules out the naive wrap |
| **B. Feed it** — ship `verifier-*` skills from the `testing` plugin and let `/verify` find them | **Not on its own.** §5.2 — the probe is `ls .claude/skills/`, which plugin skills are not in. Invocation via the Skill tool works fine; only discovery fails | Rules out the *passive* integration. Works only if something in `.claude/skills/` names the plugin skill — which collapses B into C |
| **C. Generate for it** — a plugin skill that *writes* `.claude/skills/verify/SKILL.md` (and/or `verifier-*`) into the **consuming** repo | **Yes.** This is the only seam that works, and it is the seam Anthropic itself uses (`/run-skill-generator`, and `/verify`'s own persist step) | The live option |
| **E. Brief it** — our skill composes a ready-to-run `/verify <crafted argument>` naming the installed verifier plugins and the detected surface, and hands it to the **user** to press | **Yes.** Writes nothing, depends on nothing, degrades to today's bare suggestion | The cheapest option, and the only one that works with zero consumer-repo footprint |
| **D. Borrow the craft** — port the discipline (surface table, probe taxonomy, verdict rules, "What FAIL looks like" examples) into `testing:run-e2e` / `verification:confirm`, no dependency on `/verify` at all | Yes, trivially | The zero-risk option, independent of A–C. Subject to the authoring boundary in §3 |

### Shape E in detail — the prompt shim

`/verify`'s argument is appended **after the entire body** as `## User Request` and is otherwise
untouched (§2). That makes it the natural place to hand `/verify` the inventory its `ls` probe
cannot build. Our skill would:

1. Detect which verifier-capable skills are installed (`testing:run-e2e`, `playwright:playwright`,
   any project `run-*`) and which surfaces they cover.
2. Detect the diff's surface.
3. Emit one ready-to-run line for the user to press, e.g.

   > `/verify` the auth-callback change on this branch. This repo has `/testing:run-e2e` (orchestrator
   > + Playwright, evidence contract, recording config at `.claude/testing/e2e.md`) and
   > `/playwright:playwright` — use them as your handle rather than cold-starting. They are plugin
   > skills, so they will not appear in `ls .claude/skills/`.

4. Consume the resulting report.

Properties: writes nothing into the consumer repo, cannot destroy their bundled `/verify`, no
dependency on flag state, and it degrades to exactly today's behavior (a bare suggestion) when
`/verify` is absent via `disableBundledSkills` / `skillOverrides`. It is our current
suggest-don't-delegate guidance upgraded from an empty suggestion to a **loaded** one.

Cost: it needs a human keystroke every time, by design — that is what the §3 block enforces and
there is no way around it.

**Unverified.** Whether the bundled body actually *acts* on a namespaced plugin-skill name handed to
it this way cannot be tested from here — running `/verify` requires the user. The mechanism is
sound (free text, appended last, naming skills the body is already primed to look for and is
permitted to invoke) but "it will pick up `/testing:run-e2e`" is a hypothesis, not a finding. See
Open Question 6 — it is the cheapest experiment in this document.

### The C/E discriminator

C and E are **complementary, not alternatives**. The discriminator is the entry point:

| User enters through | What is needed |
|---|---|
| Our skill (`/verification:confirm`, `/testing:run-e2e`) | **E alone.** Nothing on disk; the briefing is composed at run time |
| Bare `/verify`, typed directly — or any later session, or another agent | **C.** Only an on-disk file in `.claude/skills/` can name our verifiers when we are not in the loop |

E costs nothing and is non-destructive. C is durable but re-raises the root-replacement hazard
below. Doing E first and treating C as an opt-in for repos that want the durable version is the
sequencing the interview should probably start from.

Shape C has a real hazard that the interview has to price: **writing `.claude/skills/verify/SKILL.md`
at a consumer's repo root deletes their bundled `/verify`.** Everything in §4 stops applying to that
repo. A generator that emits a thin recipe file silently downgrades verification quality for that
project. Two mitigations to weigh: emit at the **package** level only (additive, §5.1), or have the
generated file restate the discipline it is replacing.

Note also that this marketplace's own `docs/PLUGIN-PHILOSOPHY.md` posture on shadowing (per
`docs/topics/shadowed-skill-renames/PLAN.md`) is that namespacing removed the shadow constraint —
that reasoning covers plugin-vs-plugin collisions and does **not** extend to the
project-skill-replaces-bundled case, which is a genuine destructive overwrite.

## 7. What we already reference (and what we don't)

Already correct and current:

- `plugins/testing/skills/run-e2e/SKILL.md` — Handoff: names bundled `/verify`, floors it at
  `≥2.1.145`, notes user-invoked-only from v2.1.215, and **suggests rather than delegates**.
- `plugins/verification/skills/confirm/SKILL.md` — Delegation section: same floors, same
  suggest-don't-delegate rule, verified 2026-08-02 against the bundled-skills doc; `confirm`'s eval
  suite asserts it.
- `plugins/verification/CHANGELOG.md` — mentions the `run-skill-generator` sibling.
- `docs/topics/context-engineering-claude-5/` — `disableBundledSkills` / `skillOverrides` semantics,
  including that `skillOverrides` does not reach plugin skills.

Not referenced anywhere in the marketplace:

- The **`verifier-*` / `run-*` `ls`-probe convention** — the actual integration surface. Nothing we
  ship participates in it.
- **`.claude/skills/verify/SKILL.md` as a replacement seam**, or the v2.1.200 floor for it.
- **`/run-skill-generator` as a callable step** — named once in a changelog, never in a skill body,
  never offered on a BLOCKED path.
- The **`tengu_opal_circuit` flag** as the mechanism behind `/verify`'s invocability.

## Craft worth stealing regardless of the packaging decision

Ranked by what our skills currently lack:

1. **"What FAIL looks like" per worked example.** Both spokes end with a short list mapping observed
   symptom → likely cause (`unknown flag: --json` → not wired up *or a stale build*; all 200s → you
   never triggered the changed path). Our `context/` spokes explain what to do; almost none explain
   how to read a bad result.
2. **BLOCKED as a first-class verdict, distinct from FAIL.** "Not a verdict on the change." We have
   the *concept* but not the vocabulary, and it is inconsistent across two of our own skills:
   `run-e2e`'s prerequisite hard-fail already emits a "structured verification-environment gap
   report", which is BLOCKED under another name, while `confirm` has only `CONFIRMED` / `NEEDS
   WORK` and has to fold an unreachable surface into one of those. One shared verdict word would
   align them. `/verify` also pairs BLOCKED with a rule worth copying: *"Never report an approach
   blocked or impossible until you've enumerated the skills along the touched subtree"* — the
   unlock is usually a skill you didn't look for.
3. **The mandatory adversarial probe (🔍).** A verdict with no probe is explicitly called an
   incomplete job. Our evidence contracts require assertions but never require an off-happy-path
   step.
4. **"The verdict is table stakes. Your observations are the signal."** The Findings section
   deliberately lowers the bar below "is this a bug" to "would I mention this if they were sitting
   next to me" — and requires a line per probe *even when it held*.
5. **"Read your plan back before running"** as an inline self-check against having planned a CI
   rerun.
6. **Evidence-reachability rule** — "A file path is only evidence if the person reading the report
   can open it"; use `SendUserFile` when present, otherwise inline the capture. Directly relevant to
   our e2e evidence contract on remote/cloud sessions.
7. **Negative-space framing.** Three of the first four paragraphs say what *not* to accept. Our
   skills lead with process; this leads with disqualifiers.

## Open questions for the interview

1. **Which of C / D / E, in what order?** E (compose a briefed `/verify` line for the user to press)
   is cheap, non-destructive, and probably first. C (author the consumer's
   `.claude/skills/verify/SKILL.md`) is the durable version and only matters for entry points we are
   not in. D (port the craft) is independent of both. These are not exclusive.
2. **If C: which level?** Repo root (replaces bundled `/verify` — destructive) or package dirs only
   (additive, monorepo-shaped, no destruction). Root emission needs an explicit consent step and a
   generated file that carries the discipline forward.
3. **Do we want to participate in the `verifier-*` convention** by having a plugin skill *write*
   `.claude/skills/verifier-<surface>/` shims that re-invoke `/testing:run-e2e`? That would make our
   e2e machinery reachable from bundled `/verify`'s probe — at the cost of generated files in every
   consumer repo.
4. **Which plugin owns it?** `testing` (owns run-e2e, the surface-driving machinery),
   `verification` (owns the verdict/evidence vocabulary), or `claude-config` (owns writing into a
   consumer's `.claude/`). The generator behavior argues for `claude-config`; the domain argues for
   `testing`.
5. **Do we vendor the extracted SKILL.md?** The decoded 2.1.226 text (SKILL.md + both examples,
   ~16 KB) exists in this session's scratchpad but is **not committed** — it is Anthropic's bundled
   prompt and this is a public repo. The repo does vendor upstream skill text elsewhere
   (`plugins/playbooks/skills/boris/vendor/SKILL.md`), so there is precedent; this is a call for you,
   not a default. The extraction recipe above makes it reproducible without vendoring.
6. **Run the shape-E experiment before designing anything.** One hand-written invocation is enough:
   in a repo with the marketplace installed and a real runtime diff, type a `/verify` line that
   names `/testing:run-e2e` as the evidence-capture protocol, and see whether the bundled skill
   invokes it or cold-starts anyway. That single observation decides whether E is a product or a
   nice theory — and it is the one thing in this document that only you can run (§3).

## Follow-ups

Not changed in this pass — flagged for the decision step:

- `plugins/testing/skills/run-e2e/SKILL.md:60` and
  `plugins/verification/skills/confirm/SKILL.md:111` both state the invocability restriction as
  "user-invoked only from v2.1.215". That was exactly right for 2.1.215–2.1.224 (hard
  `disableModelInvocation`), and from 2.1.225 it becomes the *default* rather than an absolute —
  a runtime gate can re-enable model invocation (§3). **The operational guidance those files give —
  suggest, never delegate — is unaffected and correct**, and the mid-series change argues for
  leaving it alone. If either file is reopened for another reason, "user-invoked only from
  v2.1.215" could become "user-invoked by default from v2.1.215". Do not name the flag in a skill
  body — it is an internal identifier that may be renamed.
- `plugins/verification/skills/confirm/SKILL.md:111` says `/run`'s "sibling `/verify` covers the
  same ground". Accurate, but `/verify` is materially stricter than `/run` (refuses tests as
  evidence, mandates a probe, has a 4-value verdict). Worth a sharper sentence if the file is
  reopened.
