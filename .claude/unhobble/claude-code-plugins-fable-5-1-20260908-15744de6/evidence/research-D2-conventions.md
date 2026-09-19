# Research memo D2 — should the four "convention" units be stripped for this unhobble run?

Research only. No recommendation. All web sources fetched live 2026-09-11 via WebFetch.

## Question

For each of four units classified `convention` by `/claude-config:unhobble` Phase 1 and kept by
default under the official carve-out, gather the evidence an operator needs to decide whether to
opt each one into the strip:

- **(a)** `AGENTS.md` § "Validate a change"
- **(b)** `AGENTS.md` § "Open a pull request as a draft"
- **(c)** `.claude/rules/pr-body-contract.md`
- **(d)** `.claude/rules/ruff-pin.md`

All four are always-loaded or near it: `CLAUDE.md` is `@AGENTS.md`; `pr-body-contract.md` carries no
`paths:` frontmatter (rules without `paths` "are loaded unconditionally"); `ruff-pin.md` is
path-scoped to `**/*.py`, so it loads only on reading a Python file, and not inside subagents.

## Findings

### 1. Official Claude Code docs — what belongs in CLAUDE.md, the cut test, the carve-outs

**1.1** `https://code.claude.com/docs/en/best-practices`, § "Write an effective CLAUDE.md"
(fetched 2026-09-11) — the cut test, verbatim:

> "Keep it concise. For each line, ask: *'Would removing this cause Claude to make mistakes?'* If
> not, cut it. Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"

**1.2** Same page, same section — the include/exclude table. Its Include column contains
**"Bash commands Claude can't guess"**, **"Testing instructions and preferred test runners"**,
**"Repository etiquette (branch naming, PR conventions)"**, and **"Developer environment quirks
(required env vars)"**. Its Exclude column contains **"Anything Claude can figure out by reading
code"** and **"Standard language conventions Claude already knows"**. All four units under review
sit inside named Include rows: (a) is a test runner instruction, (b) and (c) are PR conventions /
repository etiquette, (d) is a bash command plus an environment quirk.

**1.3** Same page, § "Avoid common failure patterns":

> "**The over-specified CLAUDE.md.** If your CLAUDE.md is too long, Claude ignores half of it
> because important rules get lost in the noise. **Fix**: Ruthlessly prune. If Claude already
> does something correctly without the instruction, delete it or convert it to a hook."

**1.4** Same page, same section — the team-convention posture: "Check CLAUDE.md into git so your
team can contribute. The file compounds in value over time."

**1.5** `https://code.claude.com/docs/en/memory`, § "When to add to CLAUDE.md" (fetched
2026-09-11):

> "Keep it to facts Claude should hold in every session: build commands, conventions, project
> layout, 'always do X' rules."

and the trigger list: "Claude makes the same mistake a second time"; "A new teammate would need the
same context to be productive".

**1.6** `memory`, § "My CLAUDE.md is too large" — the only official statement of what an automated
trim cuts and what it keeps:

> "it cuts content Claude can derive from the codebase, such as directory layouts, dependency
> lists, and architecture overviews, and keeps pitfalls, rationale, and conventions that differ
> from tool defaults."

This is the closest official wording to a conventions carve-out. Note its qualifier: conventions
**that differ from tool defaults**. All four units differ from a tool default — (a) run a selector
not the whole corpus; (b) draft not ready; (c) a body shape `gh` does not impose; (d) a wrapper not
bare `ruff`.

**1.7** `memory`, § "CLAUDE.md vs auto memory": "Use for: Coding standards, workflows, project
architecture". And the enforcement caveat, twice: "Claude treats them as context, not enforced
configuration. To block an action regardless of what Claude decides, use a PreToolUse hook".

**1.8** No official page states a carve-out for "team conventions" **as a class exempt from the cut
test**. The cut test in 1.1 is stated without exception; the conventions language in 1.2 / 1.5 / 1.6
is an inclusion list, not an exemption from "would removing this cause mistakes".

### 2. Official Anthropic prompting guidance — over-constraining and judgment

**2.1** `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`
(fetched 2026-09-11; `docs.claude.com` 302-redirects here):

> "**Prefer general instructions over prescriptive steps.** A prompt like 'think thoroughly' often
> produces better reasoning than a hand-written step-by-step plan. Claude's reasoning frequently
> exceeds what a human would prescribe."

**2.2** `https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5`,
§ "Task scope and over-verification" (fetched 2026-09-11) — the removal directive is scoped to
*verification scaffolding*, not to conventions:

> "If your prompt contains explicit verification instructions ... remove them: instructions like
> these cause over-verification on Claude Opus 5 ... The same applies to legacy harness scaffolding
> that adds separate verification steps."

Same page, same section, the counter-direction: "For narrow tasks, constrain scope explicitly."
And § "Capability improvements": "If your review prompt says 'only report high-severity issues' ...
the model may follow that instruction literally" — current models follow standing text **literally**,
which cuts both ways for a convention line.

**2.3** The "highly important areas" carve-out. Verbatim, from
`https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`
(fetched 2026-09-11), under its **"Skills"** heading:

> "Avoid making them overconstrained, except in highly important areas."

Two load-bearing qualifications, both verified: (i) it is stated about **skills**, not about
CLAUDE.md or rules files; (ii) "highly important areas" is **never defined on the page**. The repo
reaches the same conclusion independently — `plugins/claude-config/skills/audit-instructions/reference/criteria.md`
line 1887: "**Source:** none — the 'except in highly important areas' carve-out appears on no
official page". Same blog, on team conventions: "It's best when skills encode particular opinions,
knowledge, or best practices that are particular to you, your team, or product."

**2.4** Same blog, precedent for aggressive subtraction, as cited by this repo's own philosophy
doc: Anthropic removed "over 80%" of Claude Code's system prompt for the Opus 5 / Fable 5
generation with no measurable loss on coding evals (`docs/PLUGIN-PHILOSOPHY.md` § "Instruction
economy", which cites the blog, verified there 2026-08-08).

### 3. Repo doctrine (second tier)

**3.1** `docs/PLUGIN-PHILOSOPHY.md` § "Instruction economy" — the **durable-tier exemption**, which
is where the unhobble `convention` class comes from:

> "**The durable tier is exempt.** Deterministic policy hooks (gates that enforce team or safety
> policy regardless of model capability) and team conventions checked into git are the officially
> carved-out durable instruction tiers."

Note the claim "officially carved-out" is the repo's reading of 2.3; per 2.3(i)/(ii) and the repo's
own criteria.md line 1887, the upstream wording is about skills and leaves the term undefined.

**3.2** Same section — **evidence-gated additions** (governs re-add, symmetrically informs strip):

> "A new standing instruction requires observed, repeated stumble evidence against the current
> model — the same failure seen more than once — never anticipation of a failure a past model had."

**3.3** Same doc, § "Classifying a hook" — the **ground-truth-oracle carve-out**, the rubric's
sharpest instrument and directly applicable to (d):

> "a hook with a *behavioral purpose* but a *non-derivable ground-truth oracle* ... is a keep, not
> an ablation candidate. It corrects hallucination with machine ground truth no model can know
> unaided, so 'it corrects the model' alone is never the delete criterion; 'the model could derive
> this itself' is."

**3.4** `docs/conventions/instruction-exception-register/README.md` — the register adopts Gate 0's
six classes by reference and applies them to **deletion**:

> "A candidate matching any Gate 0 class is **not deletable** by an instruction-audit trim."

On unhobble specifically, the register's consumer table: the experiment "may strip a protected rule
during the run, since the strip is reversible and branch-local, but Phase 4 restores it regardless
of whether the ledger logged a stumble against it". Also: "**Omission from this register is not
licence to delete.**"

**3.5** `plugins/instruction-placement/context/routing-rubric.md` § "Gate 0 — the hard-deny
classes". Relevant row verbatim:

> | `external-publication` | Governs anything that leaves the machine | opening PRs, deploying,
> posting, sending mail, publishing packages |

and the recognition rule:

> "**Recognition is by consequence, not by phrasing.** ... Ask what breaks when the instruction is
> absent at the moment it was needed, not how the sentence is worded."

Also rung 1 of the ladder: "**Does removing it cause a mistake?** No → **delete**."

**Gate 0 determination, by consequence:**

- **(a)** No class. A skipped or over-broad local test run costs wall clock; CI decides.
- **(b)** *Contested.* The literal `external-publication` example is "opening PRs", and the rule
  governs the act of opening one. By consequence the miss is bounded and reversible: a PR opened
  ready can be returned to draft (`gh pr ready --undo`); the cost is spent CI minutes and one
  AI-review pass, not an unrecoverable state. Evidence supports either reading; both recorded.
- **(c)** *Contested, weaker than (b).* It governs PR body text — content that leaves the machine —
  but the enforcing composite is explicitly advisory (§4), so the failure mode is a bot comment and
  a label, both removable.
- **(d)** No class. Tooling-version fidelity; no irreversible, secret, data, legal, or authority
  consequence.

### 4. Remaining deterministic oracles

**(a) `scripts/affected-tests.sh`.** CI runs the same selector: `.github/workflows/ci.yml`
line ~1460, job `test-linux`, step "Run plugin contract tests":
`scripts/affected-tests.sh --run --shard "$LEG/$LEGS" --base "origin/$BASE_REF"`. `test-linux` is in
`ci-status.needs`, and `ci-status` is the single required check — so **gating**. The script's own
header states the contract the AGENTS.md line summarizes: "FAIL LOUD, NOT OPEN. A changed file that
maps to NO suite is an ERROR"; and "--run IS A LINUX GATE". `README.md` § "Validate a change" owns
the full contract. Caveat from `ci.yml` line 133: `run_tests` carries
`github.event.pull_request.draft != true`, so the gate does not fire while the PR is a draft.

**(b) draft PRs.** **No oracle at all.** No CI job, no local hook (`.claude/hooks/` holds only
`cloud-bootstrap-plugins.test.sh` and `hook-telemetry-sink.sh`), and no default in the
`source-control:pull-request` skill (`reference/create.md` mentions `draft` only as an optional REST
field). The `draft` flag only *gates other lanes*: `ci.yml` lines 133-137 disable the test lanes on
a draft; `claude-review.yml` line 46 and `claude-security-review.yml` lines 59/103 skip on
`draft == true`. The convention is a cost-control etiquette rule with no detector.

**(c) PR body contract.** `ci.yml` job `ci-status`, step "Check the pull-request contract", the
composite `melodic-software/ci-workflows/.github/actions/pr-contract@5776760…` (v0.22.2). Per the
rule file itself and `.claude/source-control.md`: the linkage/section half is **advisory** — "a body
that misses a closing keyword or a required section gets a warning, an upserted comment and the
`needs-issue-linkage` label, and `ci-status` still passes on that account". The gating part of the
same composite is the Conventional-Commits title check and the `do-not-merge` label. A second
surviving derivation path: `.claude/source-control.md` (not one of the four units, and not stripped
with them) carries `pr_body_required_sections` = Summary / Fix / Verification / Related.

**(d) ruff pin.** `scripts/run-ruff.sh` resolves the pin from `.github/requirements-ci.txt`
(`ruff==0.16.5`) and **exits 2** when a PATH ruff drifts and `uvx` is absent, printing "ruff on PATH
is ${got}, but CI pins ruff==${pin}". Rationale is owned by `docs/CI-RUNNER-ROUTING.md` § "Local /
workstation ruff": "Do **not** trust a bare `ruff` on `PATH` for verification in this repository."
CI reaches ruff only through `plugins/source-control/skills/babysit-prs/scripts/engine.test.sh`
(lines 42-53), which lints `. tests` **in that one subtree** and **SKIPs on exit 127** ("pinned ruff
not available … lint pass omitted"). So the oracle is gating only for that subtree, fail-open when
the pin is unavailable, and there is **no repo-wide ruff lane** in `ci.yml` (the only other `ruff`
hit is `ruff.toml` in the `changes` path filter). Nothing detects a *local* bare-`ruff` run.

## Per-unit evidence table

| Unit | Gate 0 class match? | Remaining oracle | Gating or advisory | What the model could derive without the line |
|---|---|---|---|---|
| (a) AGENTS.md "Validate a change" | No | `scripts/affected-tests.sh` run by `ci.yml` job `test-linux`; script header + `README.md` § "Validate a change" | **Gating** (via `ci-status.needs`), but suppressed while the PR is a draft | The script exists and self-documents (usage block, `--explain`, `--run` Linux-gate note); README owns the contract. Derivation requires the model to look — nothing prompts it, and a bare model may run the whole corpus, one suite, or none. Selector existence is not inferable from source layout alone. |
| (b) AGENTS.md "Open a pull request as a draft" | **Contested**: `external-publication` names "opening PRs" literally; by consequence the miss is bounded and reversible (`gh pr ready --undo`) | **None** | n/a — no detector | Inferable only by reading `ci.yml` lines 133-137 plus both `claude-*-review.yml` draft guards and reasoning backwards about cost. No repo file states the rule outside AGENTS.md. Low derivability, zero feedback: a violation is silent and self-inflicted spend. |
| (c) `.claude/rules/pr-body-contract.md` | **Contested (weak)**: governs PR body content leaving the machine; failure is a comment + `needs-issue-linkage` label | `pr-contract` composite step inside `ci-status`; plus `.claude/source-control.md` `pr_body_required_sections` (survives this strip) | **Advisory** for body/linkage (the rule says so); the composite's title and `do-not-merge` checks are gating | Section list is recoverable from `.claude/source-control.md` and from any recent merged PR body; the composite is named in `ci.yml`. The advisory comment is a real feedback loop — a violation announces itself on the PR within one CI run, so the bare model gets a correction signal the other three units lack. |
| (d) `.claude/rules/ruff-pin.md` | No | `scripts/run-ruff.sh` (exit 2 on drift, 127 when unavailable); `engine.test.sh` lints one subtree in CI; `docs/CI-RUNNER-ROUTING.md` owns rationale | Wrapper exit code is deterministic but **only when invoked**; the CI lint is gating for `plugins/source-control/skills/babysit-prs/**` only and **fail-open** (SKIP) otherwise | The wrapper exists at `scripts/run-ruff.sh` with a full rationale header, and `ruff.toml` sits at the root. But the pin's existence and the "bare ruff disagrees in both directions" fact are **non-derivable ground truth** (a release moving 18 E/F rules into defaults) — the exact shape §3.3 calls a keep. A bare model typing `ruff check` gets a clean-looking wrong answer with no error. |

## Consensus table

| Claim | Official CC docs | Anthropic prompting guidance | Repo doctrine | Verdict |
|---|---|---|---|---|
| Cut any line whose removal would not cause mistakes | Yes, verbatim (1.1) | Consistent (2.1, 2.2) | Adopted verbatim (3.1 quotes it) | **Consensus** |
| Team conventions / PR etiquette / test-runner instructions belong in CLAUDE.md | Yes, explicit Include rows (1.2, 1.5) | Analogous for skills (2.3) | Yes (3.1) | **Consensus** |
| "Team conventions in git" are a class *exempt from the cut test* | **Not stated anywhere** (1.8); the trim "keeps … conventions that differ from tool defaults" (1.6) is the nearest wording | Blog carve-out is about **skills** and is undefined (2.3) | Repo asserts an "officially carved-out durable tier" (3.1) | **Disagreement**: repo doctrine is stronger than any source supports; the repo's own criteria.md line 1887 concedes the carve-out "appears on no official page" |
| Deletion floor is the six Gate 0 consequence classes | Not addressed | Not addressed | Owned by register + rubric (3.4, 3.5) | **Repo-only**, uncontradicted upstream |
| A rule with a non-derivable machine oracle is a keep | Not addressed | Not addressed | Explicit (3.3) | **Repo-only**, uncontradicted |
| Instructions are disposable per model generation; ablate at release | Implied ("prune regularly") | Strongly (2.2, 2.4) | Explicit (3.1 "Generation-triggered ablation") | **Consensus** |

## Unverified claims

- **The Gate 0 class of (b) and (c).** No source adjudicates whether a reversible publication-cost
  rule is inside `external-publication`. The rubric's own instruction ("by consequence, not by
  phrasing") points away from inclusion; its example list points toward it. Unresolved by evidence.
- **The `ci-workflows` `pr-contract` composite's internals** were not fetched (it lives in
  `melodic-software/ci-workflows` at SHA `5776760…`). The advisory-vs-gating split is taken from
  `.claude/rules/pr-body-contract.md` and `.claude/source-control.md`, both of which state it;
  neither was checked against the composite at that SHA.
- **`docs.claude.com` Claude-4/5 prompting pages**: `claude-5-best-practices` returned **404**; the
  Claude-4 URL redirects to the consolidated `claude-prompting-best-practices` page, which is what
  was read. No separate "Claude 4.x best practices" wording was verified.
- **Whether any of the four has prior stumble evidence.** No ledger, issue, or PR search was run for
  observed violations of these four lines; 3.2's symmetric question ("what evidence earned this
  line?") is unanswered for all four.
- Whether `test-windows` is intentionally absent from `ci-status.needs` (observed, not investigated).

## Options the evidence supports

1. **Keep all four** (unhobble default). Grounds: 1.2's Include rows name all four categories;
   3.1's durable-tier exemption; the strip would measure nothing new for (c), whose violation is
   already self-announcing.
2. **Strip all four.** Grounds: 1.1's cut test is stated without exception; 1.8 and 2.3 show the
   conventions carve-out is undefined and upstream-unstated; 2.4's 80% precedent; the point of the
   experiment is to replace a judgment with a measurement, and all four are reversible and
   branch-local (3.4).
3. **Strip the units with a live oracle, keep the ones without.** Strip (a) — CI is gating and will
   catch a bad selection — and (c) — the advisory comment is a real, fast feedback loop. Keep (b),
   which has no detector at all, and (d), whose oracle is fail-open outside one subtree and whose
   ground truth is non-derivable per 3.3.
4. **Invert on derivability rather than on oracle.** Strip (a) and (d), whose rationale is fully
   written down in files the model can read (`README.md` § "Validate a change"; `run-ruff.sh`
   header + `docs/CI-RUNNER-ROUTING.md`), on the theory that the experiment tests whether the model
   *finds* them. Keep (b) and (c), whose content is stated nowhere outside the instruction surface.
5. **Strip (b) under a named Gate 0 hold.** Treat (b) as `external-publication`, strip it anyway
   (3.4 permits it), and pre-commit to restoring it at Phase 4 as a register hold regardless of the
   ledger. Yields an observation without accepting the silence-as-evidence inference.
6. **Split (a) rather than strip it whole.** The unit is two claims: *use the selector* (derivable
   from README) and *zero suites is an error* (a non-obvious failure-mode fact). SKILL.md Phase 1
   already licenses section-granular splitting of mixed files; the same mechanic applies here.
