# Upstream source: AI Hero Cohort 005, Workshop 2 "Domain Language" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Domain Language** workshop of Matt Pocock's AI Hero cohort (Cohort 005): seven lessons (Domain
Language; Using Grill with Docs; ADRs; Writing an ADR; Pruning the Glossary; Pruning ADRs; Q&A),
four with worked solutions. Rows hold our decisions and our own descriptions of each idea, under
the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no lesson text is recorded or linked here; the skills it
teaches are public and versioned in [mattpocock/skills](https://github.com/mattpocock/skills),
whose record is [mattpocock-skills.md](mattpocock-skills.md). Earlier course units have their own
records: [aihero-course.md](aihero-course.md) (crash-course and Steering lessons) and
[aihero-shipping-course.md](aihero-shipping-course.md) (Shipping section).

- **Pointer**: when a row needs the upstream mechanism, fetch the public skills it rests on live:
  [`domain-modeling`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/domain-modeling)
  and
  [`grill-with-docs`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/grill-with-docs).
  The workshop's skill text matched these files when it was absorbed.
- **As of**: 2026-11-10
- **Recheck trigger**: a mattpocock/skills changeset naming `domain-modeling` or `grill-with-docs`,
  checked as [mattpocock-skills.md](mattpocock-skills.md) describes. Course page updates are not
  observable events; the skills-repo changeset stream is the proxy, as in
  [aihero-shipping-course.md](aihero-shipping-course.md).

**Decision ids.** `Q<n>` is an owner decision from the workshop's interview register (rounds 4 to
13, 2026-11-09 to 2026-11-10). The register is not committed; each row names the decisions and
the pull request that landed them. Q52 to Q59 were withdrawn when the owner moved to one lesson per
round, and re-asked as the later ids.

**Landed** means merged unless marked open. As of 2026-11-10,
[#15240](https://github.com/melodic-software/claude-code-plugins/pull/15240),
[#15241](https://github.com/melodic-software/claude-code-plugins/pull/15241) and
[#15242](https://github.com/melodic-software/claude-code-plugins/pull/15242) are open.

## Loop mapping

The workshop closes on a five-step loop. Ours, step for step:

| Course step | Ours | Difference |
|---|---|---|
| Grill with docs | [`/planning:interview`](../../plugins/planning/skills/interview/SKILL.md) | Writes the glossary (through `ubiquitous-language`) and ADRs (through `record-decision`) per the `domain_docs` setting, `auto` by default (Q70). A settled term's glossary change and code rename land as their own change before the next step (Q218) |
| Write a spec | [`/planning:prd`](../../plugins/planning/skills/prd/SKILL.md) or [`/planning:plan`](../../plugins/planning/skills/plan/SKILL.md) | Covered for the Shipping section in [aihero-shipping-course.md](aihero-shipping-course.md) |
| Write tickets | [`/work-items:decompose`](../../plugins/work-items/skills/decompose/SKILL.md) | Same |
| Implement | [`/implementation:implement`](../../plugins/implementation/skills/implement/SKILL.md) | Unattended work lists coined terms as glossary candidates in its PR body (Q221) |
| Code review | [`/review:code-review`](../../plugins/review/skills/code-review/SKILL.md) | Same |

## Attribution table

Disposition is `take`, `adapt`, `already have` or `reject`, with the reason. The upstream-problem
cells are **Inference** throughout: the lesson pages that state them are paid and not linked.

### Lesson 1: Domain Language

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| A shared glossary raises agent output quality | Keeps one file of agreed terms the agent consults | Agents and people name one concept several ways, so code is missed or duplicated | Readers did not reliably consult our glossary: a baseline eval showed `testing:write` skipping it | **adapt:** measure first (Q60), then one public read action every reader calls, no always-loaded import (Q64, Q65) | [#14891](https://github.com/melodic-software/claude-code-plugins/pull/14891), [#14959](https://github.com/melodic-software/claude-code-plugins/pull/14959), [#14952](https://github.com/melodic-software/claude-code-plugins/pull/14952) |
| Glossary upkeep inside one domain-modeling skill | One skill owns terms and decisions | Inference: one entry point for the vocabulary work | Our glossary skill was named for one verb and had no seed or audit | **adapt:** keep `domain-driven-design`; rename `curate-language` to [`ubiquitous-language`](../../plugins/domain-driven-design/skills/ubiquitous-language/SKILL.md) with locate, lookup, seed, curate, audit (Q61 to Q63, Q67, Q73) | [#14952](https://github.com/melodic-software/claude-code-plugins/pull/14952) |
| Rejected-synonym line in each entry | Lists words not to use beside the canonical term | Inference: stop drift back to old names | Same need; his marker style read as noise | **adapt:** plain `Avoid:` with one header sentence (Q68); a CI check was dropped in favor of `audit` finding rejected words (Q66 superseded by Q91) | [#14952](https://github.com/melodic-software/claude-code-plugins/pull/14952) |
| Fixed glossary and map file names at the root | Puts the glossary at known paths | Inference: agents find it without search | Already configurable defaults per bounded context | **already have** (Q69): defaults kept; this repository keeps [`docs/glossary.md`](../glossary.md), found by discovery | none |
| Separate docs-writing interview variant, user-invoked only | A second interview skill writes the glossary and ADRs; model invocation disabled | Inference: keep the plain interview free of file writes | One interview with an opt-in is simpler | **adapt:** `domain_docs` setting `auto`, `ask`, `off` (Q70); skills stay model-invocable (Q71); "interview" in our text, "grill me" kept as a trigger (Q72) | [#14953](https://github.com/melodic-software/claude-code-plugins/pull/14953) |
| Ubiquitous language spans team talk, UI and code | One term everywhere | Translation between code, team and product is the friction | Canon scopes the language to one bounded context | **already have**, scope corrected: per-context glossaries plus an index | none |
| Agents coin compact names | Explains why agent text gets hard to follow | Inference: the user loses track of invented labels | Our instructions already require defining a label where it first appears | **reject the cause, keep the effect:** no source measures the stated cause | none |
| Glossary for a folder outside a repository | n/a (owner question) | n/a | User config is rendered from dotfiles; any folder can declare a path that `locate` honors | **already have** (Q228): no change | none |
| His trigger phrasings | Descriptions name terminology and glossary edits | Inference: the skill fires on the words users say | Our descriptions might miss those phrasings | **adapt:** probe with `/skill-quality:check`, add a phrase only where a probe misses (Q227) | [#15240](https://github.com/melodic-software/claude-code-plugins/pull/15240) (open) |

### Lesson 2: Using Grill with Docs

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Compact terminal question layout | Short question line, then a recommendation line | Inference: questions readable at a glance | Ours carried fields that were often empty | **adapt, partly:** keep our fields; merge Inference into the reason; show two fields only when they carry something (Q74) | [#14953](https://github.com/melodic-software/claude-code-plugins/pull/14953) |
| Compare candidate terms against scenarios | Walks edge cases to choose between terms or models | Inference: a term that survives cases maps cleanly to code | No named step for competing candidates | **adapt:** offer a "scenario comparison" table when candidates compete (Q75, Q76) | [#14953](https://github.com/melodic-software/claude-code-plugins/pull/14953) |
| One glossary entry per state | Each status of an entity gets its own entry | Inference: states are distinct concepts | Splits one entity across entries | **reject the shape:** one entry per entity with its states; a state earns an entry only as a noun with rules of its own (Q77) | [#14952](https://github.com/melodic-software/claude-code-plugins/pull/14952) |
| Error messages and copy use the domain language | Treats user-facing text as part of the vocabulary | Inference: users meet the old word in errors | Renames left copy unchecked | **adapt:** report rejected words in copy, never auto-rewrite (Q78); optional `Shown to users as:` line (Q79) | [#14952](https://github.com/melodic-software/claude-code-plugins/pull/14952), [#14955](https://github.com/melodic-software/claude-code-plugins/pull/14955) |
| Code names follow the glossary | Renames code when a term settles | Inference: code and talk drift apart | Same | **take:** renames through [`rename-references`](../../plugins/docs-hygiene/skills/rename-references/SKILL.md) in their own reviewed change (Q80) | [#14955](https://github.com/melodic-software/claude-code-plugins/pull/14955) |
| Human rejects a term the agent added | Person removes an unagreed entry | Inference: agent speculation pollutes the glossary | Same | **already have:** the contract bars speculative terms | none |
| Out-of-scope and parked questions | Interview names what is deferred | Inference: keep the session bounded | Same | **already have:** the Brief's out-of-scope and deferred lists | none |

### Lesson 3: ADRs

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Glossary and ADRs in one skill | One skill writes both | Inference: one place for domain docs | Two concerns; ours were split but did not name each other | **reject the shape:** keep separate, each names the other; an explicit numbered step in the caller, measured by eval (Q81, Q88, Q89, Q92) | [#14969](https://github.com/melodic-software/claude-code-plugins/pull/14969), [#14970](https://github.com/melodic-software/claude-code-plugins/pull/14970) |
| ADR admission test, all conditions required | Writes an ADR only when every condition holds | Inference: keep ADRs few | Our all-of test rejected decisions worth keeping, and had three copies | **adapt:** a real alternative AND at least one of hard to reverse, shapes structure or a key quality (Q82), later not discoverable from the code (Q215); one copy in [`record-decision`](../../plugins/architecture/skills/record-decision/SKILL.md) (Q83) | [#14966](https://github.com/melodic-software/claude-code-plugins/pull/14966), [#14969](https://github.com/melodic-software/claude-code-plugins/pull/14969), [#14972](https://github.com/melodic-software/claude-code-plugins/pull/14972), [#14984](https://github.com/melodic-software/claude-code-plugins/pull/14984) |
| Very short ADR format file | A few sentences, sections optional | Inference: ADRs stay cheap to write and read | We had no template | **adapt:** default [`templates/adr.md`](../../plugins/architecture/skills/record-decision/templates/adr.md) with Considered options, overridable through the config layers (Q84), repository level only for now (Q90); team keys for extra triggers and template path (Q86) | [#14966](https://github.com/melodic-software/claude-code-plugins/pull/14966) |
| Decision rationale kept in a code comment | Leaves the why beside the code | Inference: the reason survives with the code | Comment removal could lose a real decision | **adapt:** `remove-comments` hands deleted rationale that passes the test to `record-decision` (Q85) | [#14971](https://github.com/melodic-software/claude-code-plugins/pull/14971) |
| Business rules inside glossary entries | Entries carry rules | Inference: one place to read the domain | Rules change faster than terms | **reject:** rules in code and tests, reasons in ADRs (Q87) | [#14970](https://github.com/melodic-software/claude-code-plugins/pull/14970) |
| A surprising business rule as an ADR case | Treats a surprising rule as ADR-worthy | Inference: stop the next person reverting it | Our test drops surprise as a gate | **reject** (Q235): no change; a named test pins the rule | none |

### Lesson 4: Writing an ADR

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Drill into one confusing term with concrete cases | Switches to worked scenarios when wording gets unclear | Inference: confusion signals a glossary gap | No scenario lane inside the interview | **adapt:** a scenario walk, numbered scenarios inside a question (Q93), offered on the user's confusion or an undefined or doubled term (Q94) | [#15142](https://github.com/melodic-software/claude-code-plugins/pull/15142) |
| Draw terms and relationships during the walk | A sketch of the domain beside the talk | Inference: a picture settles relationships faster | No diagram offer; owner asked about canvas tools | **adapt:** opt-in diagram through [`/visualization:visualize`](../../plugins/visualization/skills/visualize/SKILL.md) (Q95), target picked by surface with a `hosted_canvas` key (Q200, Q202), a `diagram_target` preference (Q210); Excalidraw and tldraw installed at user level (Q201, Q203) | [#15142](https://github.com/melodic-software/claude-code-plugins/pull/15142), [#15141](https://github.com/melodic-software/claude-code-plugins/pull/15141), [#15201](https://github.com/melodic-software/claude-code-plugins/pull/15201), [dotfiles#1539](https://github.com/melodic-software/dotfiles/pull/1539) |
| Everyday words stay out of the glossary | Admits only terms that remove ambiguity | Inference: a bloated glossary hides the useful terms | Same | **take:** one admission sentence (Q96) | [#15140](https://github.com/melodic-software/claude-code-plugins/pull/15140) |
| Competing verbs for one action | Picks one verb | Inference: verbs drift like nouns | No place for a verb | **adapt:** an `Actions:` line under the entity with the rejected verb (Q97); readers treat it as rejected | [#15140](https://github.com/melodic-software/claude-code-plugins/pull/15140), [#15199](https://github.com/melodic-software/claude-code-plugins/pull/15199) |
| Closing recap with an ADR pass | Restates decisions and asks again about ADRs | Inference: catch decisions the first pass missed | A second ADR pass swung between too few and too many | **adapt:** grouped closing summary with one ADR verdict line per decision, overrulable in the reply (Q98) | [#15142](https://github.com/melodic-software/claude-code-plugins/pull/15142) |
| Decisions that fail the gate go to the spec | Routes non-ADR decisions elsewhere | Inference: keep them without an ADR | Same | **already have:** [`/planning:prd`](../../plugins/planning/skills/prd/SKILL.md) | none |

### Lesson 5: Pruning the Glossary

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Prune the glossary in a session | Removes implementation detail, general words and unused terms | Inference: glossaries accumulate entries nobody needs | No prune path; our own glossary broke our contract | **adapt:** `audit` lists grouped candidates, `curate` removes or merges only accepted ones, no new action (Q204); on request plus a read-only audit in the repo-sweep catalog (Q206); removal reports surviving references and where each meaning went (Q230, Q231); a cut sentence's destination named (Q232) | [#15187](https://github.com/melodic-software/claude-code-plugins/pull/15187), [#15190](https://github.com/melodic-software/claude-code-plugins/pull/15190), [#15240](https://github.com/melodic-software/claude-code-plugins/pull/15240) (open) |
| A general content pruner | One pass over all markdown | Inference: every agent-touched file grows | Each content kind already has an owning skill | **reject** (Q205): no general skill | none |
| Pick between two terms by usage counts | Counts each candidate in the code | Inference: follow what the code already says | Two counting methods gave two numbers in one session | **adapt:** one stated counting method in `curate` (Q207) | [#15187](https://github.com/melodic-software/claude-code-plugins/pull/15187) |
| Rename terms inside accepted ADRs and their files | Reinforces current language everywhere | Inference: old words in ADRs mislead agents | File renames break links | **adapt:** update the text, keep file names and numbers (Q208); a rename reports hits by layer, stored values migrated in phases or mapped behind an ADR (Q209) | [#15189](https://github.com/melodic-software/claude-code-plugins/pull/15189) |
| Prune this repository's glossary | n/a (applies the rules to our file) | n/a | [`docs/glossary.md`](../glossary.md) held history notes and routing sentences | **take** (Q229) | [#15242](https://github.com/melodic-software/claude-code-plugins/pull/15242) (open) |

### Lesson 6: Pruning ADRs

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Delete a reversed ADR, record the reversal in the new one | Removes the stale file; git keeps it | Inference: a superseded ADR left in the folder reads as current | Ours stayed in place with a status line | **adapt:** `record-decision` retires by an `adr_retirement` setting, default `delete`, number never reused (Q211, Q212); a partial reversal keeps the old record marked superseded in part (Q233) | [#15192](https://github.com/melodic-software/claude-code-plugins/pull/15192), [#15241](https://github.com/melodic-software/claude-code-plugins/pull/15241) (open) |
| Check each ADR against the code | Finds records the code no longer backs | Inference: stale records mislead | No ADR-versus-code check | **adapt:** read-only `record-decision audit` (Q213), in the repo-sweep catalog | [#15192](https://github.com/melodic-software/claude-code-plugins/pull/15192), [#15194](https://github.com/melodic-software/claude-code-plugins/pull/15194) |
| ADR lands with its work | Commits the record in the PR that carries the change | Inference: history ties decision to code | Unstated | **take** (Q214) | [#15192](https://github.com/melodic-software/claude-code-plugins/pull/15192) |
| Duplicate ADR numbers | n/a (found in our folder) | n/a | Four numbers used twice here | **no change** (Q234): titles tell twins apart | none |

### Lesson 7: Q&A

| Idea | What it does | Upstream problem | Our problem | Disposition (decisions) | Landed |
|---|---|---|---|---|---|
| Same name, different meaning across contexts | Qualifies a term where contexts meet | Inference: one word collides across teams | Unstated in our contract | **adapt:** bare inside a context, qualified where contexts meet (Q216); "explicit over implicit" in the shared agent instructions (Q217) | [#15195](https://github.com/melodic-software/claude-code-plugins/pull/15195), [dotfiles#1540](https://github.com/melodic-software/dotfiles/pull/1540) |
| Ship glossary updates and renames before spec and tickets | Orders the rename ahead of planning | Inference: tickets then name the new terms | No ordering rule | **take** (Q218): the closing summary lists the rename first | [#15196](https://github.com/melodic-software/claude-code-plugins/pull/15196) |
| Best terms come from users | Takes users' own words | Inference: match how users talk | Users are not always domain experts | **reject as stated:** weigh domain experts, then code usage, then published standards; users' words go on `Shown to users as:` (Q219); tenant renames are display labels, not synonyms (Q220) | [#15195](https://github.com/melodic-software/claude-code-plugins/pull/15195) |
| An agent must not own the glossary | Keeps a person in the loop | Inference: unattended edits degrade it | Unattended work could coin terms silently | **adapt:** unattended PRs list coined terms under Glossary candidates; a person curates (Q221) | [#15197](https://github.com/melodic-software/claude-code-plugins/pull/15197) |
| Build the glossary slowly | Adds only what current work needs | Inference: avoid speculative entries | Same | **already have:** `curate` writes on resolution; `seed` proposes, the owner accepts | none |

### Integration round

| Idea | Disposition (decisions) | Landed |
|---|---|---|
| Our own context-zone names, checked with `/naming:name-it-better` | **adapt:** renamed to light, moderate and heavy, bands unchanged (Q222, Q224) | [#15202](https://github.com/melodic-software/claude-code-plugins/pull/15202), [dotfiles#1541](https://github.com/melodic-software/dotfiles/pull/1541) |
| Code names that look like a term's concept but are neither the term nor its `Avoid:` words | **adapt:** `audit` reports them, reusing `seed`'s grouping; duplicated logic stays with `/code-metrics:audit-duplication` (Q236) | [#15240](https://github.com/melodic-software/claude-code-plugins/pull/15240) (open) |
| A word on an `Avoid:` line that has its own real meaning | **adapt:** `Avoid:` holds only names for the same concept; a hit on such a word is a candidate entry (Q237) | [#15240](https://github.com/melodic-software/claude-code-plugins/pull/15240) (open) |
| Chat-channel interview | **reject for now** (Q223): recorded as an idea | none |
| Present-tense old skill names in other upstream records; shared-lane restriction line | Handed to the session that owns those files (Q238, Q239) | none here |

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. The public skills repository reads MIT on the host and in
[mattpocock-skills.md](mattpocock-skills.md); no text or code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-10
- **Recheck trigger**: the skills repository's license file changes.
