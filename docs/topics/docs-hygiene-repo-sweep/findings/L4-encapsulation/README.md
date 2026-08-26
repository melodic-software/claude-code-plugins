# L4 encapsulation. Wave 1 audit roll-up

Read-only audit. No source file was edited. Every finding below is a remediation spec for wave 3,
which runs after L1 deletions, L2 splits, and L3 SSOT extraction have settled the final layout.

## Headline

| Measure | Value |
|---|---|
| Adjudicated violations | **89** |
| Distinct leaked skills | **35** (of 235 skill directories found on disk) |
| Distinct leaked plugins | **25** (of 71) |
| Distinct leaking files | **46** |
| Findings files written | 25 per-plugin files, plus this roll-up |

A violation is one external citation reaching past a skill's public surface. The Rule of Three does
not gate this lane: one violation is a defect, and 15 of the 25 plugins below carry one or two.

## Leak-kind distribution

| Kind | Count | Note |
|---|---|---|
| Private subdirectory | 86 | `context/`, `reference/`, `references/`, `actions/`, `templates/`, `fixtures/` |
| Heading anchor | 2 | `SKILL.md#the-nesting-invariant-verified`, `safety-model.md#standalone-git-checkout-evidence` |
| Schema file | 1 | `autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` |
| Other | 0 | |

## Leaker-shape distribution

Where the violations come from matters more than the count, because the shapes have different blast
radii.

| Citing surface | Violations | Files | Why it matters |
|---|---|---|---|
| Skill body reaching a sibling skill | 30 | 18 | Breaks rip-and-paste portability of both skills; the contract puts skill-to-skill on slash-only with no carve-out |
| Plugin-level doc (`context/`, `reference/`, `agents/`) | 23 | 10 | The plugin can ship the doc and the skill separately; a skill refactor silently breaks the plugin's own contract docs |
| Repo convention doc (`docs/conventions/**`) | 17 | 4 | Highest blast radius: other plugins are told to implement these, so the dependency is transitive |
| Plugin README | 16 | 12 | Named explicitly in the contract as an external consumer; not carried on rip-and-paste |
| Repo doctrine doc (`docs/PLUGIN-PHILOSOPHY.md`) | 2 | 1 | One is a live Convention-registry row other plugins consult |
| Repo rule (`.claude/rules/**`) | 1 | 1 | Tier 1, always loaded, paid for in every session |

## Ranked. Most-leaked skills

| Rank | Skill | Inbound violations | Leaked surfaces |
|---|---|---|---|
| 1 | `review:fanout` | 12 | `context/default-mode.md`, `context/fix-pass-mode.md`, `context/findings-normalization.md` |
| 2 | `work-items:track` | 8 | `actions/add.md`, `actions/done.md`, `actions/due.md` |
| 3 | `source-control:babysit-prs` | 6 | `reference/safety.md`, `reference/loop.md`, `reference/orchestration.md`, `reference/independent-resolution.md` |
| 3 | `source-control:pull-request` | 6 | `reference/monitor.md`, `reference/readiness.md` |
| 5 | `ai-slop:audit` | 5 | `reference/rewrite-guide.md`, `reference/catalog.md`, `context/persist-findings.md` |
| 5 | `evals:methodology` | 5 | `reference/success-criteria.md`, `reference/grading.md`, `reference/recipes.md`, `reference/eval-design.md` |
| 7 | `review:quality-gate` | 4 | `context/pr.md` |
| 8 | `discovery:trace-intent` | 3 | `context/dispatch.md`, `context/artifact-shape.md` |
| 8 | `mutation-testing:principles` | 3 | `reference/scaling-and-suppression.md`, `reference/metrics.md` |
| 8 | `skill-quality:check` | 3 | `reference/fresh-eyes-declarations.md` |
| 11 | `claude-ops:plugins`, `discovery:explore`, `discovery:research`, `disk-hygiene:clean`, `mutation-testing:audit`, `overengineering:audit`, `repo-fleet-hygiene:audit`, `source-control:babysit-loop`, `source-control:worktree` | 2 each | |
| 20 | 16 further skills | 1 each | |

## The three findings worth reading first

1. **`docs/conventions/detector-findings/README.md` names three `review:fanout` private files as its
   "External authority"** (12 violations, `review.md`). A repo-level convention other plugins
   implement defers its own rules to one skill's internal file layout, and says so in prose. This is
   the only case in the corpus where the dependency is stated as a contract rather than written as a
   convenience.
2. **A Tier 1 always-loaded rule points into a private reference** (`ai-slop.md`, V-slop-01).
   `.claude/rules/vendor-docs-are-not-style.md:10` sends every agent in every session to
   `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`. This sweep's own PLAN.md restates the
   same instruction to all eight lanes, so eight agents are currently told to open a private path.
3. **`docs/PLUGIN-PHILOSOPHY.md:337-342` prescribes the violation.** The repo's doctrine document
   instructs skill authors that "one skill citing another skill's supporting file writes the full
   `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form", and gives a worked example. That
   doctrine is why 30 of the 89 violations are sibling-skill reaches, and why so many of them use the
   `${CLAUDE_PLUGIN_ROOT}` spelling. The citation on that line is itself legal (it is a syntax
   example, not a cite), so it carries no violation id, but no amount of call-site repair holds while
   the doctrine stands. **Recommendation to the orchestrator:** reconcile
   `docs/PLUGIN-PHILOSOPHY.md`'s cross-skill citation rule against
   `plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md` before wave 3
   applies any sibling-skill fix. The two documents currently contradict each other, and this lane
   does not own the doctrine.

## Method

### Step 1. The bundled detector, read before it was trusted

`bash plugins/docs-hygiene/skills/audit-encapsulation/scripts/detect.sh --apply-filters` reported
`raw=791 mech-filtered=162 candidates=629`, exit 1. The script fits the whole-repo case here: this
repo is a marketplace monorepo, and the detector's pattern covers the
`plugins/<plugin>/skills/<skill>/...` layout as well as `.claude/skills/` and the relative forms.

What it does **not** catch, established by reading it rather than by assuming:

- It emits only the matched path fragment, truncated at the first subdirectory slash
  (`plugins/x/skills/y/context/`), so a raw run cannot tell two files in the same subdirectory apart.
- Its mechanical self-citation filter only vacates cites whose text names the same plugin **and**
  skill as the citing file. A cite written relative to the *plugin root*
  (`skills/audit/catalog/...` inside `plugins/machine-health/skills/setup/SKILL.md`) resolves to a
  path the filter never constructs, so those pass through unresolved.
- It does not resolve paths embedded in URLs, so SHA-pinned GitHub permalinks into skill internals
  are invisible to it.
- Exit 1 means candidates remain after mechanical filters, not that any of them is illegal. The
  script's own header says so.

### Step 2. An independent enumerator, to get full paths and owner attribution

A Python pass over the 1302 files in `inventory/manifest.tsv` extracted every path-shaped token per
line, resolved each against four candidate roots (repo-relative, citing-file-relative,
citing-plugin-relative, and a skill-leaf-name guess), plus a separate pass for paths embedded in
`github.com/.../blob/<ref>/<path>` permalinks. A resolution counts only when it lands on a real
directory under `plugins/<p>/skills/<s>/`, verified against the 235 skill directories on disk. Each
row records the citing file's own owning skill, so self-citations drop out by construction.

Result: 11 641 resolving citations, of which 7 903 are self-citations (legal progressive disclosure),
leaving 407 non-self citations onto private surfaces after deduplication.

### Step 3. Taxonomy classification, in session

The 407 were classified against the filter taxonomy. The legal buckets, with counts:

| Filter | Count | Example |
|---|---|---|
| KIND-1, historical narrative in CHANGELOGs | 127 | `plugins/claude-config/CHANGELOG.md:1301` recording a file that shipped |
| KIND-1, measurement-sample provenance | 93 | `docs/specs/d1-model-already-knows-measurement.md`, an adjudicated sample table whose rows are the files sampled |
| KIND-1, SHA-pinned permalinks | 29 | `docs/topics/fable-field-guide-audit/codex-review.md`, links pinned to a commit and therefore immune to refactor |
| Foreign contract | 16 | `docs/upstream/aihero-course.md` describing another repo's skills |
| KIND-1, decision and design records | 28 | `docs/adr/0004`-`0017` (18), `docs/topics/**` design records (10), citing evidence they weighed |
| KIND-1, audit status board | 14 | `plugins/docs-hygiene/context/derivability-route-followups.md`, a table of paths audited |
| Non-existent targets | 7 | port-plan checklists naming files to create in a different repo; ambiguous short cites resolving to nothing |
| KIND-1, narrative and evidence rows in repo docs | 3 | `docs/PLUGIN-PHILOSOPHY.md:340` (a syntax example), `docs/NATIVE-SURFACES.md:53` (an evidence bullet), `docs/conventions/upstream-drift/README.md:150` (a hoisting narrative) |
| Vendor-tree license attribution | 1 | `plugins/playwright/README.md:83` naming `skills/playwright/vendor/LICENSE` |
| **Adjudicated illegal** | **89** | |

Those rows sum to 407, the deduplicated non-self private-surface citation set.

The classification rule applied consistently at the borderline: **does the citing text send a reader
or agent to open the private file in order to do work?** If yes, violation. If the path appears as
evidence, an example, or a record of what was inspected, KIND-1. Four rows sit close to that line and
are reported at medium confidence with the reasoning stated in place: V-slop-02, V-dhg-01,
V-review-13, V-review-14. They are registry and exemplar rows, live enough to go stale silently.

### Step 4. Remediation

Every violation carries the owning skill, the public surface element to cite instead named
semantically, and exact replacement text. Three remedy shapes are used:

- **Path B, route.** Replace the path with `/plugin:skill <action>`. Used where the caller wants
  behavior. The majority.
- **Path A, promote to plugin-shared.** Move the leaked doc up to `plugins/<p>/reference/` or
  `plugins/<p>/context/`, which sit outside every skill directory and are therefore legal external
  cite targets. Used where two sibling skills share vocabulary. `source-control`, `discovery`,
  `review`, `work-items`, and `overengineering` already have such directories; `evals` and
  `mutation-testing` would gain one.
- **Path A, promote to repo convention.** Move the content to `docs/conventions/<topic>/` or
  `.claude/rules/`. Used for the three genuinely repo-wide cases: the house prose style (V-slop-01),
  the findings-file shape (V-review-01..12), and the fresh-eyes declaration contract (V-sq-01..03).

No violation is blocked on a missing public action, so no tracking work item is proposed. Where the
public action for a route was in doubt, the doubt is stated in the finding
(`improvement.md`'s note on an unadvertised unattended mode).

## Recall. What this pass did not reach

Stated plainly, because a clean exit here would be misleading.

1. **Non-markdown citing files are out of the sweep's corpus and were not given remediation specs.**
   `detect.sh` surfaced 81 candidates in `.sh`, `.yml`, and `.json`. Most are legal under the
   glob-config and KIND-2 forced-cite filters (CI path filters in `.github/workflows/ci.yml`,
   exclusion lists in `.claude/ai-slop.json`, fixture paths in `plugins/source-control/hooks/*.sh`)
   or are the detector's own regression fixtures under KIND-3. Two are worth a second look by whoever
   owns the shell surfaces, and neither is actionable in a docs sweep:
   `plugins/source-control/scripts/babysit-readiness-gate.sh:53,88` reaching
   `skills/babysit-prs/reference/`, and `plugins/skill-quality/scripts/check-skill.sh` reaching
   `skills/check/reference/` at seven lines. Both are plugin-level scripts reaching into a skill's
   private reference rather than through the `scripts/` entry surface the contract carves out.
2. **Prose references with no path are invisible to both passes.** A sentence saying "see the
   fanout skill's fix-pass mode document" is the same dependency with no token to match. Nothing here
   estimates how many exist.
3. **Anchors are under-counted.** Only 2 heading-anchor violations were found, and both were written
   as `#fragment`. Many cites in this corpus pin a section by quoting its title in prose (`"Two
   Gates, One Merge-Ready"`, `"Step 2"`, `§5.1.2`). Those bind to body structure just as tightly and
   break just as silently, but they are not mechanically detectable. Several are recorded inside
   findings where they ride along on a path cite; standalone ones are not counted.
4. **Cross-plugin skill-leaf-name collisions were resolved by hand, not mechanically.** Two plugins
   ship a `check` skill, so a short cite of the form `skills/check/reference/...` is ambiguous. The
   three instances found were resolved by file-existence check
   (`skill-quality.md` records the reasoning). Any short cite whose target does not exist in either
   candidate plugin was dropped as a non-existent target, which is correct for the port-plan
   checklists it removed but would also silently drop a genuine cite whose target was deleted before
   this sweep.
5. **`docs/topics/docs-hygiene-repo-sweep/` was excluded per the plan**, including this lane's own
   findings. Note that PLAN.md itself carries a T1-rule restatement pointing at
   `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`; it is out of audit scope but is named
   in V-slop-01 because fixing the rule without fixing the plan leaves the instruction split.
6. **`plugins/*/skills/*/vendor/**` was not read.** One candidate resolved into a vendor tree
   (`plugins/playwright/README.md:83` citing `skills/playwright/vendor/LICENSE`) and was classified
   legal without opening the file: a license attribution has to name the license file, and the tree
   is off limits to edit.
7. **No fan-out was used.** The plan's suggested worker partition by cited skill was built (four
   balanced packets over 25 plugins), but no subagent-spawning tool is available in this agent
   context, so all 407 candidates were classified in session against one rubric. The upside is
   consistency at the borderline; the downside is that no second reader checked the KIND-1 calls, and
   the 353 rows vacated as legal had one adjudicator.

## Wave 3 preconditions

Re-resolve every target before editing. The findings name post-wave targets semantically (owning
skill plus public surface element) precisely so that L1 deletions, L2 splits, and L3 extractions can
move files underneath them without invalidating the spec. Specific dependencies flagged in the
per-plugin files:

- `plugins/source-control/skills/babysit-prs/reference/loop.md` is a split candidate and the origin
  of five cites (`source-control.md`).
- `plugins/work-items/reference/dogfood-filing.md` is a deletion candidate and the origin of four
  (`work-items.md`).
- Three Path A targets overlap L3's likely SSOT artifacts: the house prose style, the findings-file
  shape, and the fresh-eyes contract. Each should land one file, not two.

## Findings files

`review.md`, `source-control.md`, `work-items.md`, `discovery.md`, `ai-slop.md`, `evals.md`,
`mutation-testing.md`, `claude-ops.md`, `overengineering.md`, `skill-quality.md`, `disk-hygiene.md`,
`repo-fleet-hygiene.md`, `autonomy.md`, `bugs.md`, `claude-config.md`, `claude-memory.md`,
`code-tidying.md`, `computer-use.md`, `context-budget.md`, `docs-hygiene.md`, `dometrain.md`,
`improvement.md`, `session-flow.md`, `visualization.md`, `x.md`.
