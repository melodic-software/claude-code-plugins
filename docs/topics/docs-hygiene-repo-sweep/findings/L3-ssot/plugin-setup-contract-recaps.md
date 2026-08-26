# Cluster: plugin-setup-contract-recaps

**Concept.** The uniform setup contract's four operable claims, restated inside every plugin's
`skills/setup/SKILL.md`: the headless reconfiguration recipe, the write-versus-session-effect
distinction, the probe-do-not-recite directive, and the never-writes boundary.

**Bucket.** N>=3 (four sub-clusters at 17, 18, 22, and 41 instances) plus one N=1 residual.

**Owner (existing).** `docs/PLUGIN-PHILOSOPHY.md`, two headings:

- `## Configuration ownership and scope` (line 270) owns the `claude plugin install --config`
  already-installed claim and its verification stamp.
- `## Setup is explicit and repeatable` (line 345) owns the check/apply contract, the
  evidence-bearing readback, and `**Keep two claims apart:**` (line 411).

**Portability constraint applies.** Every call site is a plugin runtime surface under
`plugins/*/skills/setup/`. An installed plugin cannot read the marketplace `docs/` tree, so
`trim-to-citation` is structurally unavailable here. The skill's own
`context/lessons.md` "Lesson 13: Portability inverts the output type on plugin runtime surfaces"
governs: the output type is normalize-inline plus a provenance-only citation. That shape is
already in place across the fleet. The residual defects are drift and one missing citation, not
the duplication itself.

---

## Sub-cluster 1: `setup-headless-reconfigure-recipe`

**Instances.** 22 setup skills carry the recipe. 21 of them also carry a document-scope provenance
citation to `docs/PLUGIN-PHILOSOPHY.md`; one does not.

**Canonical wording, from the owner** (`docs/PLUGIN-PHILOSOPHY.md:298`):

> `already installed` **and still writes the value**: the short-circuit is about the install, not the
> config write. **Empirically verified on Claude Code 2.1.240** (a non-sensitive option at `user`
> scope: a non-default value written to an installed plugin, then restored)

**Variant family A (16 files, matches the owner's parenthetical form).** Representative:

`plugins/bash-format/skills/setup/SKILL.md:105`

> still writes the value**, verified on Claude Code 2.1.240 (a non-sensitive option at `user`
> scope: a non-default value written to an installed plugin, then restored). The short-circuit is
> about the install, not the config write.

Also at: `plugins/actionlint/skills/setup/SKILL.md:70`,
`plugins/biome-format/skills/setup/SKILL.md:84`,
`plugins/context-budget/skills/setup/SKILL.md:86`,
`plugins/desktop-notification/skills/setup/SKILL.md:76`,
`plugins/disk-hygiene/skills/setup/SKILL.md:169`,
`plugins/eol-normalizer/skills/setup/SKILL.md:73`,
`plugins/go-format/skills/setup/SKILL.md:72`,
`plugins/knowledge/skills/setup/SKILL.md:66`,
`plugins/markdown-format/skills/setup/SKILL.md:102`,
`plugins/powershell-format/skills/setup/SKILL.md:92`,
`plugins/rate-limit-guard/skills/setup/SKILL.md:19`,
`plugins/repo-hygiene/skills/setup/SKILL.md:80`,
`plugins/ruff-format/skills/setup/SKILL.md:105`,
`plugins/source-control/skills/setup/SKILL.md:261`,
`plugins/typos-format/skills/setup/SKILL.md:85`.

**Variant family B (6 files, a shortened restatement that drops the empirical conditions).**

`plugins/bugs/skills/setup/SKILL.md:58`

> still writes the value, verified on Claude Code 2.1.240 for a non-sensitive option at `user`
> scope. Never uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry and
> resets every option to its manifest default).

`plugins/education/skills/setup/SKILL.md:62` (identical wording),
`plugins/discipline/skills/setup/SKILL.md:79`,
`plugins/machine-health/skills/setup/SKILL.md:132`,
`plugins/skill-quality/skills/setup/SKILL.md:47`,
`plugins/planning/skills/setup/SKILL.md:127`.

**Why family B is a defect, not a licensed variation.** The owner's claim is an empirical
observation bounded by the conditions it was observed under. Family B keeps the version stamp but
drops "a non-default value written to an installed plugin, then restored", which is the sentence
that says what was actually tested. A reader of a family-B skill cannot tell how far the claim
extends. `context/lessons.md` "Lesson 12" makes an empirical mechanism the exact class where a
second wording is a second contract.

**Remedy: `normalize-wording`.** Replace the family-B sentence at each of the six sites with the
family-A spine, byte-identical. Exact replacement text for each family-B call site (preserve the
site's own leading indentation and line wrapping; the two fragments that must survive wrapping
unbroken are `still writes the value` and `Claude Code 2.1.240`):

```text
Against an already-installed plugin it prints `already installed` **and still writes the value**,
verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default value
written to an installed plugin, then restored). The short-circuit is about the install, not the
config write. Re-verify before relying on it outside those conditions. A `sensitive` option, or
`project`/`local` scope, were not covered.
```

**Out of scope, flagged.** 34 plugin `README.md` files carry the same claim inside the block
delimited by `<!-- ai-slop-ignore-start: generated options block; source is plugin.json +
scripts/sync-plugin-options-docs.py -->`. That block is generated from a shared template, so the
generator is the dedup mechanism (identify form (f)). Fixing the wording there means editing
`scripts/sync-plugin-options-docs.py` and regenerating, not editing 34 READMEs.
`config-extract-advisory`; the README sites must not be counted as call sites
(`context/lessons.md` "Lesson 14").

---

## Sub-cluster 2: `setup-write-vs-session-effect`

**Instances.** 18 setup skills. Discriminating phrase: `keep the two claims apart`.

**Owner.** `docs/PLUGIN-PHILOSOPHY.md:411`, under `## Setup is explicit and repeatable`:

> **Keep two claims apart:** that the write was issued and stored, and how the *running* session
> behaves.

**Sites.** `plugins/actionlint/skills/setup/SKILL.md:80`,
`plugins/ai-briefing/skills/setup/SKILL.md:70`,
`plugins/bash-format/skills/setup/SKILL.md:114`,
`plugins/biome-format/skills/setup/SKILL.md:93`,
`plugins/claude-ops/skills/setup/SKILL.md:84`,
`plugins/desktop-notification/skills/setup/SKILL.md:87`,
`plugins/disk-hygiene/skills/setup/SKILL.md:178`,
`plugins/eol-normalizer/skills/setup/SKILL.md:82`,
`plugins/go-format/skills/setup/SKILL.md:81`,
`plugins/guardrails/skills/setup/SKILL.md:71`,
`plugins/machine-health/skills/setup/SKILL.md:140`,
`plugins/markdown-format/skills/setup/SKILL.md:111`,
`plugins/planning/skills/setup/SKILL.md:135`,
`plugins/powershell-format/skills/setup/SKILL.md:101`,
`plugins/rate-limit-guard/skills/setup/SKILL.md:28`,
`plugins/ruff-format/skills/setup/SKILL.md:114`,
`plugins/session-flow/skills/setup/SKILL.md:85`,
`plugins/typos-format/skills/setup/SKILL.md:94`.

Representative body (`plugins/bash-format/skills/setup/SKILL.md:114`):

> Afterwards, keep the two claims apart. The write is issued and the stored value is what you
> passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
> skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
> session start, so a same-session `check` still reports the OLD value.

**Verdict.** `REFUSE-already-cites-canonical` for 17 of 18. The block is byte-identical across all
17 and each host file carries the document-scope provenance citation in its `## Purpose`. This is
the normalize-inline plus provenance-only shape working as designed. Do not trim.

**Exception.** `plugins/planning/skills/setup/SKILL.md:135` carries the block with no provenance
citation anywhere in the file. Routed to sub-cluster 5 below.

---

## Sub-cluster 3: `setup-probe-dont-recite`

**Instances.** 17 setup skills. Discriminating phrase: `don't recite this file`.

**Sites.** `plugins/actionlint/skills/setup/SKILL.md:27`,
`plugins/bash-format/skills/setup/SKILL.md:27`,
`plugins/biome-format/skills/setup/SKILL.md:26`,
`plugins/context-budget/skills/setup/SKILL.md:29`,
`plugins/desktop-notification/skills/setup/SKILL.md:27`,
`plugins/disk-hygiene/skills/setup/SKILL.md:24`,
`plugins/eol-normalizer/skills/setup/SKILL.md:29`,
`plugins/firecrawl/skills/setup/SKILL.md:30`,
`plugins/go-format/skills/setup/SKILL.md:29`,
`plugins/guardrails/skills/setup/SKILL.md:25`,
`plugins/markdown-format/skills/setup/SKILL.md:26`,
`plugins/playwright/skills/setup/SKILL.md:28`,
`plugins/powershell-format/skills/setup/SKILL.md:32`,
`plugins/repo-hygiene/skills/setup/SKILL.md:29`,
`plugins/ruff-format/skills/setup/SKILL.md:27`,
`plugins/session-flow/skills/setup/SKILL.md:28`,
`plugins/typos-format/skills/setup/SKILL.md:30`.

Verbatim (`plugins/bash-format/skills/setup/SKILL.md:27`):

> **Read it first.** Probe what it actually does, don't recite this file. Then run each probe via
> Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

**Owner: none.** `docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" states that setup
must be transparent and evidence-bearing, but it does not state the operable rule that the
implementation artifact is the single source of truth and the setup skill probes rather than
recites it. Grep for `recite` and `probe` in that file returns one unrelated line (484).

**Remedy: `edit-existing-rule`, not a new artifact.** The concept belongs in the contract that all
17 sites already cite by document scope. Adding a paragraph to an existing owner is strictly better
than minting a new rule file that no installed plugin can read.

**Proposed addition** to `docs/PLUGIN-PHILOSOPHY.md`, `## Setup is explicit and repeatable`,
appended to the bulleted contract list:

```text
- probe-driven rather than recitation-driven: the implementation artifact the skill verifies (the
  hook script, the bundled engine, the CLI wrapper) is the single source of truth for what it
  requires and how it resolves things, so `check` reads that artifact and probes what it actually
  does rather than restating the setup skill's own description of it.
```

**Call-site replacement.** None. Each of the 17 sites keeps the operable directive inline
(portability), and each already carries the document-scope citation. After the owner gains the
clause, the 17 sites are conforming restatements rather than orphan rules. The only per-site change
is punctuation normalization: 10 sites write `**Read it first.**` and 7 write `**Read it first**.`
Pick `**Read it first.**` (majority; period inside the bold, consistent with the surrounding
sentence-level bolding in these files).

**ROI.** MEDIUM. The stability test passes (a change to the probe rule forces 17 lockstep edits);
the reader-burden test currently passes too, since no file names an owner for this specific rule.

---

## Sub-cluster 4: `setup-never-writes-boundary`

**Instances.** 41 setup skills carry a non-goal bullet naming the same three write targets.
Discriminating phrase: `plugin cache, Claude Code user settings, or`.

**Three wording families.**

- A: `- Write the plugin cache, Claude Code user settings, or \`pluginConfigs\`.` (28 files, e.g.
  `plugins/markdown-format/skills/setup/SKILL.md:130`,
  `plugins/claude-config/skills/setup/SKILL.md:157`,
  `plugins/toolchain/skills/setup/SKILL.md:133`)
- B: same, plus `, per the uniform setup contract` (7 files, e.g.
  `plugins/autonomy/skills/setup/SKILL.md:488`,
  `plugins/context-guard/skills/setup/SKILL.md:456`,
  `plugins/rate-limit-guard/skills/setup/SKILL.md:288`,
  `plugins/dometrain/skills/setup/SKILL.md:126`,
  `plugins/bugs/skills/setup/SKILL.md:141`,
  `plugins/education/skills/setup/SKILL.md:79`,
  `plugins/miro/skills/setup/SKILL.md:108`)
- C: `Do not write the plugin cache, ...` in running prose rather than a bullet (6 files, e.g.
  `plugins/session-flow/skills/setup/SKILL.md:62`,
  `plugins/context7/skills/setup/SKILL.md:112`,
  `plugins/knowledge/skills/setup/SKILL.md:112`,
  `plugins/discipline/skills/setup/SKILL.md:92`)

**Owner.** `docs/PLUGIN-PHILOSOPHY.md:284`, `## Configuration ownership and scope`:

> Claude Code owns the configuration prompt and storage; plugin skills must not hand-edit
> `pluginConfigs` or invent a marketplace-qualified plugin ID.

**Remedy: `normalize-wording`, LOW ROI.** The bullet is a single sentence naming three contract
identifiers. Per the skill's keep-inline test and `context/lessons.md` "Lesson 5", a one-sentence
low-drift unit stays inline. The only worthwhile change is family alignment: append
`, per the uniform setup contract` to the 34 family-A and family-C sites so all 41 read the same
and each carries its own provenance, matching the 7 that already do.

**Judgment.** This sub-cluster is worth reporting and cheap to fix, but it is genuinely borderline
against Lesson 5. If wave 3 is time-boxed, drop this one before dropping sub-clusters 1, 3, or 5.

---

## Sub-cluster 5: `planning-setup-uncited-reconfigure-recap` (N=1)

**Bucket.** N=1. Admission gate satisfied: a canonical home exists
(`docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope" and "Setup is explicit and
repeatable") and this one file recaps both without citing either.

**Site.** `plugins/planning/skills/setup/SKILL.md:120-141`, under `### Interview-rendering toggle`.

Verbatim (`plugins/planning/skills/setup/SKILL.md:127`):

> Against an already-installed plugin it prints `already installed` and still writes the value,
> verified on Claude Code 2.1.240 for a non-sensitive option at `user` scope; a `sensitive` option,
> and `project`/`local` scope, were not covered, so re-verify before relying on it there.

**Evidence it is uncited.** The file contains no occurrence of `uniform setup contract` or
`PLUGIN-PHILOSOPHY.md`. Every other setup skill carrying this block declares the contract in its
`## Purpose`; this one declares only the topic-docs seam.

**Remedy: `trim-to-citation` is unavailable (portability); apply `normalize-wording` plus a
provenance citation.** Two edits:

1. Replace lines 127 through 133 with the family-A spine given in sub-cluster 1.
2. Add a provenance sentence to `## Purpose` (after the existing paragraph ending
   `...owns the resolution order and runtime guards.`, around line 18):

```text
Setup shape and `userConfig` handling follow the uniform setup contract
(`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" and "Configuration ownership and
scope" in the marketplace repository), cited for provenance only, since an installed plugin cannot
read the marketplace `docs/` tree.
```

**ROI.** HIGH for its size. One file, two edits, closes the last uncited recap in a 41-file family.

---

## Cross-lane observations

- `plugins/knowledge/skills/setup/SKILL.md:67` starts a continuation line at column 0 inside an
  indented list item (`Verified on Claude Code 2.1.240 ...`), which breaks the list continuation.
  Formatting defect, L5/L6 territory, not mine.
- No encapsulation violations found in this cluster. Every cross-plugin reference here targets
  `docs/PLUGIN-PHILOSOPHY.md`, a public repository surface, not another skill's private body.
