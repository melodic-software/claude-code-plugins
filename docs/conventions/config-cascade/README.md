# Config Cascade Convention

> Formerly `consumer-config-layering` (renamed #1188). "Cascade" (CSS `@layer`/`!important`) is the
> established term that natively carries both per-key override and a ratified precedence-inversion,
> matching this contract's user→team→local + policy-floor model.

A versioned, marketplace-wide contract for **how** a plugin's consumer-tracked configuration layers
resolve: which layers exist, what order they resolve in, and what a later layer may do to an earlier one. Every
plugin that reads config from a consuming repo resolves it the same way, so an operator who learns one
surface has learned all of them.

This directory is the source of truth: `README.md` (the contract), `CHANGELOG.md` (version history),
and topic siblings such as [`consumer-gotchas.md`](consumer-gotchas.md) (concatenating consumer gotchas
for participating skills, #3547).

## Boundary: this contract owns the axis, never the keys

It governs **layering, precedence, overlay naming, and (from contract 1.2) expression form**.
Which keys a config surface has, what they mean, and how they are validated belong to that
concern's own owner doc under `docs/conventions/<concern>/`, or to the plugin's own bundled
reference. The two compose: a per-concern doc declares its keys and points here for how its
layers merge and which expression form the surface uses.

The distinction is what keeps this doc from colliding with the one-owner-doc-per-shared-concern rule.
Layering and expression form are genuinely cross-cutting axes every config surface shares; keys
are not.

## The layers

Three file layers, each optional, resolved in this order over the plugin's `userConfig`, a later
layer refining an earlier one
([ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) Decision 8):

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 0 | plugin `userConfig` | the plugin's `userConfig` option; `pluginConfigs` is read only from user and managed settings | the operator, per user |
| 1 | user-global | `~/.claude/<name>` | the operator, across every repo and machine they work in |
| 2 | team | `${CLAUDE_PROJECT_DIR}/docs/conventions/<concern>.yaml` validated by a JSON Schema, or the surface's existing location ([location](#location-of-the-team-layer-a-docs-convention-file-or-claudename)) | the consuming repository, tracked in version control |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>` | one operator in one repo, gitignored |

Every resolver reports which layer supplied each value.

`<name>` is the surface's whole path **relative to `.claude/`**, not just its leaf filename. For a
single-file surface that is `source-control.md`; for a folder-form surface it is
`ecosystems/<ecosystem>.yaml`, giving a user-global layer at
`~/.claude/ecosystems/<ecosystem>.yaml`. The folder hierarchy is part of the surface's identity and
repeats in every layer. Collapsing it to the leaf would point the user-global layer at a different
file than the team layer. `<stem>.local.<ext>` follows the same rule: the overlay suffix attaches to
the leaf file, never to a folder in the path.

**All three layers absent is a valid state**, not an error. The surface falls through to whatever the
plugin's own resolution ladder specifies next: inference from the repo's own files, an interview, or
a bundled default.

### Location of the team layer: a docs convention file, or `.claude/<name>`

The team layer of a **structured surface** (a surface whose values are keys, not prose the model
reads) lives in `${CLAUDE_PROJECT_DIR}/docs/conventions/<concern>.yaml`, validated by a JSON Schema
([ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md), superseding
[ADR 0044](../../adr/0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)
for structured configuration). `<concern>` is the owning plugin's name, or the convention's name for
a cross-plugin concern. The root `docs/conventions` is fixed; the pointer line binds the prose home
only and never moves a config file. The concern's prose stays in `<concern>.md` at the convention
home. A plugin concern's schema ships at `plugins/<plugin>/schemas/<concern>.schema.json`; a
cross-plugin convention's schema sits in its convention folder. CI validation of a committed
`docs/conventions/*.yaml` reports and does not block; a runtime reader runs no validator and fails
closed on a value outside the key's enum. A new surface takes this form: no fenced config block
and no folder form.

Surfaces that already use another location keep working until #5906 migrates them, resolved in
this order:

| Precedence | Team-layer location | Read when |
|---|---|---|
| 1 | `${CLAUDE_PROJECT_DIR}/docs/conventions/<concern>.yaml` | the surface reads it |
| 2 | `${CLAUDE_PROJECT_DIR}/docs/conventions/<concern>.md`, the fenced config block in it (ADR 0044 surfaces) | the file exists and holds the block |
| 3 | `${CLAUDE_PROJECT_DIR}/.claude/<name>` | neither of the above supplies the layer |

The rest of this section describes the ADR 0044 block form those surfaces still read. In that
form `<concern>` is the stem of the surface's `.claude/<name>` file, and the file holds the prose
rules for the concern and exactly one config block with the same keys the `.claude/<name>` file
would carry. Other agents and tools read the convention docs; they do not read `.claude/`.

**The block form.** The opening line is three backticks at column 0, then the language of the
`.claude/<name>` file, then `config`: ` ```yaml config ` or ` ```json config `. The body ends at the
first line that is exactly three backticks.

- A reader finds the block with one line-by-line pass: it matches the opening line, stops at the
  closing line, and skips lines inside any other fenced block, so a prose example of the block
  sits in a longer outer fence (four backticks) and never counts. A human finds it by searching
  the file for `config` on a fence line.
- The body parses as the `.claude/<name>` file does. An error names the `.md` file and that
  file's own line number.
- An empty block is a block. A docs file with no block does not supply the team layer.
- Two config blocks in one file is an invalid layer, never first-wins. The error names both lines,
  and the layer degrades per rule 5 of the resolution algorithm.

**Both locations present.** The docs block wins and the resolver prints one warning line naming both
paths and the one it used. `.claude/<name>` is a supported location, not a retired file: its
fallback read carries no retirement record and is not the dual-read window below.

**What does not move.** The user-global layer stays at `~/.claude/<name>` and the overlay at
`${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>`. The team-tracked verdict, the root
classification (resolution step 2), and the merge semantics apply to the docs file as the team
layer.

**The pointer is a load hint, not the binding.** A `CLAUDE.md` or `AGENTS.md` line such as "if
testing, read `docs/conventions/testing.md`" loads the doc into the model's context on demand. It
lives in the consumer's own prose, outside the marked machine-owned region that binds a prose
convention home, and no script reads it. A script reads the fixed path.

### Why these three and not others

Each layer answers a question the others cannot. User-global carries a preference across repos, which
a tracked file structurally cannot: a per-user setting cannot decide the location or content of a
team-shared artifact. The team layer is the only layer teammates receive. The overlay is the only
place a personal deviation can live without either editing the shared file or going uncommitted and
lost. Dropping any one of them reintroduces a problem the other two cannot solve.

## Merge semantics

**Additive-preferred.** A later layer *adds to or refines* earlier layers. It never silently replaces
them wholesale.

Two sanctioned forms, in order of preference:

1. **Concatenate.** Every layer that exists is loaded and appended. Correct when the content is prose
   the model reads as guidance: the layers genuinely accumulate, and a reader wants all of them. This
   is what the first-party precedent does.
2. **Per-key override.** A later layer replaces an earlier layer's value **key by key**; a key absent
   from a later layer keeps the earlier value. Correct when the values are scalars or closed lists,
   where concatenation is meaningless or actively wrong: two anchored regexes cannot concatenate into
   a third valid regex, and two attribution-trailer templates would emit two trailers.

**Wholesale replacement is forbidden.** A layer that "overrides this file entirely" or takes the first
matching layer and stops is outside the contract: it turns every key the overlay does not mention into
a silent loss of the base layer's value, which is exactly the failure additive-preferred exists to
prevent. Both sanctioned forms preserve unmentioned keys; wholesale replacement is the one that does
not.

**A surface using per-key override must declare it** in its own contract, next to its keys. The
declaration is what makes it a design decision a reviewer can check rather than an accident.

### Sanctioned exception class: policy-floor precedence inversion

One class of surface, and only this class, inverts the precedence *direction* above while staying
additive on every other axis. A **policy-floor surface** encodes, in its team-tracked layer, a floor
that personal layers may extend or tighten but must never weaken. On a **direct conflict the team
layer wins**, the reverse of the default where a later layer refines an earlier one. It never drops a
base layer wholesale; it only decides who wins a conflict.

A surface qualifies for this class only when all three hold:

1. Its team layer is a genuine **policy floor**, a shared standard whose whole purpose is that a
   personal layer cannot loosen it; personal weakening of a team-agreed rule is the failure mode worth
   structurally preventing.
2. Personal layers (user-global and overlay) remain **add/tighten-only**: they may never supply a
   looser value that takes effect.
3. **Provenance is reported**: when a personal-layer rule materially shapes output, the surface names
   the contributing layer, so a reader can tell a team floor from a personal addition.

This mirrors prior art: managed settings that supersede user settings, org-enforced
rulesets a repo cannot loosen, and MDM managed preferences, where a higher-authority layer may be extended
but not weakened. A surface in this class is **conformant, not a tolerated deviation**, and must declare
the inversion in its own contract next to its keys. The class was ratified by #649; `standards` is its
exemplar.

## Overlay naming and the consumer `.gitignore`

The overlay is spelled `*.local.*`: the stem, `.local`, then the original extension. One spelling
across the fleet is the point: a consumer adds one `.gitignore` line and every current and future
surface is covered.

```gitignore
.claude/**/*.local.*
```

That is the whole convention: **one line, recursive form, for every surface**. `.claude/**/` matches
zero or more directories, so this single rule covers a flat `.claude/source-control.local.md` and a
one-deep `.claude/ecosystems/python.local.yaml` alike, and would cover a deeper nested overlay if a
surface grew one, while leaving team files tracked. The narrower
`.claude/*.local.*` silently fails to ignore any folder-form overlay; recommend the recursive form
only, and never ask a consumer for two lines where one is exact.

**A setup skill recommends the ignore line and leaves the edit to the consumer; their ignore file is
their artifact.** That is the **recommend** posture, the default. Two consumer-root exceptions
append the line, announce the edit, and touch nothing else:

- `/source-control:setup apply layer=team` appends the recursive `.claude/**/*.local.*` line when
  missing, because an overlay written before that line exists would leak a personal file into the
  index. `layer=local` never edits `.gitignore`: it fails with a recommendation when the overlay is
  exposed
  ([ADR 0040](../../adr/0040-ratify-the-source-control-setup-append-of-the-recursive-overlay-gitignore-line.md)).
- `/work-items:setup apply` appends `.work-item-tracker.local.json`, because that overlay sits at
  repo root outside the one-liner
  ([ADR 0015](../../adr/0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md)).

Discovery, verification, planning, review, harness-ops, and the standards root also write a
self-ignoring `.gitignore`, but *inside a plugin-owned directory* (memory root or
`<standards_dir>/`). That file is not the consumer's `.gitignore`, so it is not an exception.

## Expression doctrine: which surfaces are files, and which are convention docs

The layers above describe **where** a surface's values live relative to each other. This section
describes **how** a surface is expressed at all, and it ratifies a second expression form
alongside the dedicated file ([ADR 0018](../../adr/0018-express-team-shared-conventions-as-consumer-convention-docs.md),
2026-09).

**The criterion.** A surface takes exactly one of the expressions below, settled by what the
content *is*, never by the author's preference:

- **Team-shared prose configuration**, meaning guidance the model reads (a repo map, audit-target
  prose, a lane description) that every operator on the team is meant to share and that has no
  per-operator axis, is expressed as a **natural-language convention doc at the consumer's
  convention home** (for example `docs/conventions/<topic>/`), discovered or asked once at setup
  and bound by the pointer line below. Such a surface has **no overlay channel**: it has one
  layer, the team's. A migrated surface's setup `check` WARNs on any pre-existing `*.local.*`
  overlay file it finds for that surface rather than silently ignoring it. The overlay no longer
  has an effect, and silence would let a personal deviation look live.
- **Structured data where YAML/JSON is the right tool** (`routing.yaml`,
  `binding.json`, `testing.yaml`) stays a keyed config surface under the layers above. Its team
  layer is `docs/conventions/<concern>.yaml`, validated by a JSON Schema
  ([ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) Decision 1);
  a surface not yet migrated keeps its existing location per the
  [location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename). The
  user-global and overlay layers stay dedicated files, so the surface keeps its overlay channel.
  Each surface adopts the YAML file in its own change.
- **Everything else stays a dedicated file under the layers above, team layer included**:
  per-operator-keyed surfaces (a value keyed by operator identity or machine, or one an operator
  legitimately overrides privately, with `testing`'s e2e config as the fleet example), every
  policy-floor surface, and all mutable state. For a policy floor, `docs/conventions/<concern>.yaml`
  is that dedicated file for the team layer (ADR 0060 Decision 5): it is read from the default
  branch, the team layer wins, personal layers may only tighten it, and the surface may declare no
  `userConfig` option.

The criterion is applied per surface, in that surface's own migration PR, and recorded in the
Implementers table's row. Nothing in this contract retroactively re-expresses a surface.

**The convention home is bound by one pointer line, and the line IS the binding.** The consumer's
root instruction file carries a single standing index/pointer line naming the convention home
(and, where the home holds several topics, pointing at its index). There is no separate binding
file: a plugin resolves the home by reading that line. The line lives inside a **marked,
machine-owned region**, the `instruction-placement` rules-index block being the precedent, so setup
can rewrite it idempotently without touching the operator's prose around it, and a reviewer can see
the region is generated. The consumer's root file otherwise carries only content needed in
effectively every conversation; topic conventions live at the home, loaded on demand.

Pointer-line rules a resolver honors (the small tested helper the program's mechanism phase ships
owns the grammar; consumer prose it reads is **untrusted input**, never executed or interpolated):

- **Which file owns the region.** A file without a marked region is not consulted, even if it
  is named `AGENTS.md`. A `CLAUDE.md` whose whole content is the `@AGENTS.md` import is a pure
  shim and is not consulted for a pointer. When exactly one of the two files carries the marked
  region, that file is canonical. When both files carry a marked region, `AGENTS.md` wins and
  `CLAUDE.md`'s copy is reported as a duplicate finding (remediation: remove it). Two pointer
  lines inside one region is a FAIL, never first-wins.
- **Ask, never silently rebind.** A pointer absent while a previously-known home still exists on
  disk, or a pointer whose target directory is missing, is a FAIL that routes to `apply`'s
  interview. Inference may *propose* a home from repo evidence; only the operator's confirmation
  writes the line.
- **Branch-scoped.** The pointer line is tracked content, so divergent branches may bind different
  homes and a branch may legitimately re-ask. That is a property of tracked config, not a defect.

**Root-file shape is the downstream repository's call.** Recommended guidance, never forced: an
AGENTS.md-canonical root with a pure `@AGENTS.md` CLAUDE.md shim (the shape `instruction-placement`
already installs), but a repo that keeps `CLAUDE.md` canonical, or a symlink, is served identically
once setup has discovered which file carries the region.

**Dual-read deprecation window.** A migrated skill that finds the retired dedicated file present
treats it as WARN **and** reads it as authority (at minimum as inference evidence) until the
consumer cleans it through the retirement mechanism (`docs/migration-playbook.md`
§ Retired conventions). This covers a consumer who updated the plugin without re-running setup,
and is the one sanctioned dual-read: declared per surface by its retirement record, WARN-visible on
every run, never silent. The window closes for a consumer when that record's cleanup runs, and for
the fleet when the record is demoted to report-only under the mechanism's demotion rule. The
`.claude/<name>` fallback of the location axis is not this window: it is a supported location with
no retirement record.

**Scope.** This doctrine governs repository-scope surfaces only. Machine-scope files under
`~/.claude/` (context-guard, rate-limit-guard, machine-health) are outside both the criterion and
the retirement mechanism; ADR 0018 records that exclusion.

## Resolution algorithm

A plugin implementing this contract:

1. **Anchors at the repo root** before any repo-relative read: `${CLAUDE_PROJECT_DIR}` when set,
   otherwise `git rev-parse --show-toplevel`. Never a CWD-relative path: invoked from a nested
   directory, a CWD-relative read finds a nonexistent `<subdir>/.claude/...`, misses the real config,
   and silently degrades to a lower rung. Re-resolve the root in every self-contained shell call.
2. **Classifies that root before any team or overlay read.** When the resolved root is `$HOME` or
   an ancestor of `$HOME`, or is not inside a git working tree, team and overlay are **not
   applicable**: report both with that reason and resolve user-global only. Never read `$HOME/.claude/<surface>` as the team layer; those two
   paths are the same file, and writing `apply layer=team` would write the operator's personal
   config. Compare layer paths physically (slash-fold, case-fold, `pwd -P` when the directory
   exists) so a native Windows home spelling and its MSYS alias still collapse. A team or overlay
   path that physically equals the user-global file is skipped even when the root is not home.
   A filesystem or drive root, the OS temp directory, and a cloud-synced
   folder are named follow-up roots for the shared resolver; this step does not skip them for that
   reason alone.
   Surfaces that read more than one layer and find two paths naming one file report the equality
   instead of reading it twice.
3. **Reads every layer that exists**, in order, and merges per the surface's declared semantics.
   Reading one layer and stopping is not resolution. Layers the previous step marked not
   applicable are absent, not empty.
4. **Reports which layer supplied each value** whenever it surfaces the effective config to a human.
   A reader who cannot see which layer won cannot tell why the plugin behaves as it does.
5. **Degrades soft on a malformed layer**: surface the error, name the layer, resolve as if that
   layer were absent. Unknown keys are inert. A consuming repo may validate its own files in a gate;
   plugins do not hard-fail on them.

`fleet-state.sh` (harness-ops `plugins` skill) does not adopt the resolver. Its root answers a
different question: which project-scope install records and `.claude/settings*.json` map belong to
the session. It excludes `$HOME` only in the cwd fallback used when `CLAUDE_PROJECT_DIR` is unset
and no git toplevel exists, spells both sides of that comparison alike, and never treats a
team layer as user-global. `permission-state.sh` (harness-config `audit-permission-state`) does not
adopt it either: at a home or non-repo root it falls back to the start directory and labels the
basis (`start directory (repository root is the home directory)`) instead of reporting the layer as
not applicable, because the local settings file it reports is read from the start directory in that case.

### Per-layer verification verdicts

The same tracked/ignored question produces opposite correct answers per layer, so a single shared
check is always wrong for two of the three:

| Layer | Version control | On violation |
|---|---|---|
| user-global | outside the worktree, so **no git command applies** | n/a |
| team | must be tracked | hard STOP: teammates would never receive the shared convention |
| local overlay | must be gitignored, never staged | FAIL: a personal deviation can reach team history |

The user-global row is not an omission. `git check-ignore` and `git status` against a path outside the
repository return a meaningless verdict, or a confidently wrong one when the operator's home
directory is itself a git repository.

## Versioning

`contract_version` (SemVer) versions this contract; the number lives in `CHANGELOG.md`. A change to
the precedence order or to what a layer means is a major bump. Adding an optional layer, or relaxing a
rule additively, is a minor bump. Per-concern key schemas version independently under their own owner
docs and are deliberately decoupled from this number.

## Deviations

Recorded here whether or not ratified. Listing a deviation documents that it exists and diverges; it
does not by itself bless it. Ratifying one, as #649 did for the policy-floor precedence-inversion
class above and [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md) did for the layer locations below, moves it from observed to sanctioned. Ruling
on each remaining deviation (correct the surface, or amend this contract) is a separate human-gated
decision.

**Ratified as a sanctioned exception class, one axis only:**

- **`standards` precedence inversion**, the exemplar of the policy-floor precedence-inversion class
  above (ratified by #649). Personal layers may add or tighten only; the team-tracked layer wins a
  direct conflict, with provenance reported. Conformant to that class, not a tolerated deviation.
  **This ratification covers the precedence axis alone.** `standards` also diverges on layer *location*
  (see Declared, below), which #649 did not rule on and [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md) ratifies separately.

**Declared**, meaning the surface states its divergence and why:

- **`standards` locates its layers outside `.claude/`.** Its team and overlay layers live at
  `<standards_dir>/` (default `docs/standards/`), rooted by the `standards_dir` key of
  `.claude/standards.yaml`, with a setup-owned in-directory `.gitignore`, rather than the contract's
  `${CLAUDE_PROJECT_DIR}/.claude/<name>` and `*.local.*` paths. Ratified in place as a declared
  exception ([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md), #3577). The pointer file that roots it stays the sanctioned relocation
  mechanism for a surface that needs a configurable root; it is not a fleet rule.
  - **Claim:** `standards` keeps its team layer and overlay at `<standards_dir>/`; the location
    is a declared exception, not drift.
  - **Basis:** [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md) on the owner decision on #3577; the existing `.claude/standards.yaml` pointer
    already roots the directory, so no new mechanism is needed.
  - **As of:** 2026-09-29.
  - **Recheck:** a web-session measurement shows plugin-owned `.claude/<name>` writes are fine
    everywhere and a consumer reports confusion, or Claude Code changes protected-path handling.
- **`songwriting` reads template overrides from `songwriting/templates/`.** The consumer's prompt
  templates live at `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`, outside
  `.claude/`. The craft skills check that path before the bundled
  `context/pat-pattison/templates/<name>.md`, and `/songwriting:setup` scaffolds, inventories and
  removes them. The files are prose the consumer authors and reads, not settings, and they sit
  beside the consumer's other `songwriting/` artifacts. The surface has one consumer layer, the
  tracked team file, over the bundled default: no user-global layer and no overlay. [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md) rules on the
  location only.
  - **Claim:** the override path stays under `songwriting/`; the location is a declared exception.
  - **Basis:** [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md); `plugins/songwriting/skills/setup/SKILL.md` "The two surfaces"; the path the
    `rhyme`, `song-form`, `meter-prosody`, `co-write`, `metaphor`, `diagnose`, `object-writing`,
    `practice` and `workflow` skills check.
  - **As of:** 2026-09-29.
  - **Recheck:** a template override becomes a settings-shaped file (keyed values rather than
    prose), or the setup skill starts writing under `.claude/`.
- **`work-items` reads its recurring schedule from `.github/recurring-schedule.json`.** The file
  is a tracked, team-shared JSON schedule outside `.claude/`, used by the
  `/work-items:track` actions, `/work-items:work` candidate discovery, and `/work-items:setup`,
  which writes an empty skeleton on `apply`; the Implementers row lists each reader and writer. `.github/` holds the workflow tooling that reconciles the
  schedule against the tracker items it files. The surface has one layer, the team's: no
  user-global layer and no overlay. It is separate from the tracker binding at the repo root
  (ADR 0015). [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md) rules on the location only.
  - **Claim:** the schedule stays at `.github/recurring-schedule.json`; the location is a declared
    exception.
  - **Basis:** [ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md); `plugins/work-items/reference/tracker-seam.md` "Recurring schedule";
    `plugins/work-items/skills/setup/SKILL.md`.
  - **As of:** 2026-09-29.
  - **Recheck:** the schedule gains a personal overlay or user-global layer, or the reconciling
    automation moves out of `.github/`.
- **`autonomy` exempts its security axes.** Layers refine additively as the contract requires, except
  that no repo-local value may supply or override a security axis at all, a stricter rule than this
  contract, in the direction of safety.
- **`disk-hygiene`'s `--policy` replaces both standing layers.** Its standing layers merge additively
  (overlays may disable or add hints and add protected globs, never weaken a hard guard); the
  wholesale replacement is confined to an explicit per-invocation flag, not a file layer.
- **`docs-cache` is machine scope, with no repository layer.** Its one file layer is a user-global
  machine file at `${XDG_CONFIG_HOME:-$HOME/.config}/claude-docs-cache/config.json`, not
  `~/.claude/<name>`: Claude Code owns `~/.claude/` and its layout, the reason
  [ADR 0057](../../adr/0057-share-a-user-scope-docs-cache-across-plugins.md) keeps the cache store
  out of it. No team or overlay layer exists, because the values tune one machine's shared cache
  and no repository decides them. The `DOCS_CACHE_*` environment variables and the per-invocation
  flags sit above the file, key by key; neither is a file layer.
- **`ai-briefing` is team-only, with no local overlay (#3580).** Tracked files live under
  `.claude/ai-briefing/` (default profile) or `.claude/ai-briefing/<name>/` (a named profile).
  Selecting a named profile is profile selection, not resolution of a `*.local.*` cascade layer.
  `sources.md`, optional `audience.md`, and optional `brand.json` are profile files in that
  team directory; no read path resolves a `.local.*` file, and setup does not recommend
  gitignoring one. Claude Code documents local behavior only for surfaces it actually resolves
  (`CLAUDE.local.md`, `settings.local.json`); a generic `*.local.*` filename has no
  platform-defined meaning.
- **gitignore postures stay three-way (#3573).** Recommend is the default. Two consumer-root
  appends are declared exceptions, not undeclared drift: `source-control`'s recursive overlay line, appended at `layer=team` only
  ([ADR 0040](../../adr/0040-ratify-the-source-control-setup-append-of-the-recursive-overlay-gitignore-line.md))
  and `work-items`' overlay line
  ([ADR 0015](../../adr/0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md)).
  Own-ignore-file inside a plugin-owned directory is a different file, not a third exception.
  - **Claim:** the three gitignore postures stay; recommend is default; two consumer-root
    appends are declared exceptions; own-ignore-file is a different file.
  - **Basis:** the owner decision on #3573 (keep the three postures), ADR 0040, and ADR 0015.
  - **As of:** 2026-09-29.
  - **Recheck:** a setup skill grows a third consumer-root append, or a maintainer
    converges the fleet onto one posture.
- **`source-control` stops `branch_issue_pattern` resolution on an unusable layer (#4673).**
  Rule 5 of the resolution algorithm would resolve as if a malformed layer were absent. For this
  one key, `parse-branch-issue.sh` instead fails closed: a layer whose `## branch_issue_pattern`
  section exists but yields no usable pattern (a near-miss heading, no value, a heading or HTML
  comment as the first value line, an empty or unterminated fence, or a pattern that fails
  validation) prints a note naming the layer and the reason, emits no issue number, and exits 1.
  The consumer is a `Closes #N` line that closes an issue on merge, so a lower layer or the
  default supplying a different number is worse than no number; the no-number path already exists
  and `/source-control:pull-request create` relays the note. A higher layer that already supplied
  a valid pattern still wins, since the lower layer is never read, and a malformed deprecated
  `userConfig` value is still ignored with a note. Every other `source-control` key keeps the
  soft degrade.
- **`testing` stops on an unusable layer.** Rule 5 of the resolution algorithm resolves as if a
  malformed layer were absent and treats unknown keys as inert. `plugins/testing/scripts/resolve-config.sh`
  instead exits 2, naming the file and line, on any layer it cannot read or parse, on an unknown
  key or an invalid value, and on a team or overlay layer that is a symlink. `/testing:audit`
  refuses to scan (`cant-fail-scan.sh` prints `refusing to scan`), and the `test-scan` hook reports
  the error and does not check the file. A docs block is held to the same stop, so two config
  blocks in `docs/conventions/testing.md` stop the scan where the location axis says the layer
  degrades. The scanner is a gate whose `--check` exit treats an unread input as a failure: a
  scan with a layer dropped would apply different `paths.exclude` or `rules.*` values than the team
  set and report a result that looks clean. The stop covers every key and layer of the surface,
  not one key.

**Undeclared**, meaning divergence with no recorded rationale:

- none currently.

## Semantics at a glance

Who wins and which merge form each surface uses. The table is generated from the `Who wins` and
`Merge form` columns of the Implementers rows, which own the values; edit those rows, then run
`scripts/sync-config-cascade-semantics.py`. The engines stay separate (#3575): the table is an
index, not a unification, and the Implementers row remains the contract for path, layers, and
conformance.

<!-- BEGIN GENERATED: config-cascade semantics. Edit the Implementers table, then run scripts/sync-config-cascade-semantics.py -->

| Surface | Who wins | Merge form |
|---|---|---|
| `source-control` | later layer; team on the merge-rung; fail-closed on a bad `branch_issue_pattern` | per-key |
| `toolchain` / `ecosystem-commands` | later layer | per-key |
| `codebase-health` | later layer | concatenate |
| `bugs` | later layer | lanes concatenate; `## Gotchas` concatenates; `filing_posture` nearest-wins |
| `github` | team on write-posture keys; later layer otherwise | per-key (`routing.yaml`); concatenate (`conventions.md`) |
| `autonomy` | later layer except security axes | declared |
| `standards` (`planning`, `review`) | team on conflict (policy-floor) | add/tighten |
| `disk-hygiene` | team over user-global; `--policy` replaces both | additive standing layers |
| `ai-briefing` | team only | no overlay |
| `code-tidying` | team only; residual wholesale if no `## Merge semantics` | per-section when declared |
| `code-metrics` | later layer | per-key |
| `repo-fleet-hygiene` | `--config` then team then user-global | whole-file, no per-key |
| `work-items` | overlay on the allowlist | per-key overlay |
| `work-items` (recurring schedule) | team only | single-layer |
| `songwriting` | project override over the bundled default | whole-file per template, no per-key |
| `ai-slop` | later layer | per-key (lists replace) |
| `docs-naming` | later layer; team on named policy-floor keys | per-key |
| `rendered-views` | later layer | per-key |
| `testing` (`run-e2e`) | later layer | per-key |
| `testing` (`audit`, `test-scan`) | later layer; the first present of `testing.yaml`, the docs block and `.claude/testing.yaml` in the team layer | per-key (scalars override, lists concatenate) |
| `testing` (`check-visual-parity`) | lowest value (policy floor) | per-key |
| `plugin-quality` | team via pointer line | convention doc |
| `architecture` | team via pointer line | convention doc |
| `harness-config` (`audit-pass`) | team on conflict (policy-floor) | per-key |
| `authoring-formats` | team via pointer line | convention doc |
| `instruction-placement` | team on conflict (policy-floor) | per-key |
| `overengineering` | team on conflict for protected keys | per-key |
| `multi-agent` | later layer; the docs block over `.claude/multi-agent.yaml` in the team layer | per-key |
| `review-digest` | later layer; the docs block over `.claude/review-digest.json` in the team layer; `--policy` over every layer | per-key (lists replace) |
| `playbooks` | later layer | per-key |
| `implementation` | `true` in any layer (policy floor) | per-key |
| `education` | later layer | per-key |
| `session-flow` | later layer; the narrower layer for `transcript_scope` | per-key |
| `discovery` | later layer; a per-run `--output` argument over both | per-key |
| `review` | later layer; `report` in any layer for `downstream_probe` (policy floor) | per-key |
| `planning` | later layer | per-key |
| `docs-hygiene` | later layer | per-key |
| `discipline` | later layer | per-key |
| `verification` | stricter layer for `proof_level`; later layer for `live_workers` | per-key |
| `docs-cache` | flag, then `DOCS_CACHE_*`, then the machine file | per-key |

<!-- END GENERATED: config-cascade semantics -->

- **Claim:** the glance table is generated from the Implementers rows; engines are not unified.
- **Basis:** #3575 and `scripts/sync-config-cascade-semantics.py`.
- **As of:** 2026-09-29.
- **Recheck:** operators still miss the row, then add the per-setup check line.

## Implementers

Conformance is tracked, not assumed. A surface is listed here whether or not it conforms. The gap is
the point. Each row states the surface's conformance **as it exists on `main`**, never as a
migration intends it to be; a row that ran ahead of the code would report a closed gap that is still
open. Every row fills `Who wins` and `Merge form` with one short phrase each, never blank. Every row
below is currently expressed as a **dedicated file**; a surface that migrates to a convention doc
under the expression doctrine above rewrites its row in the same PR (path → the convention home,
layers → `team, via pointer line`, who wins → `team via pointer line`, merge form →
`convention doc`, conformance → the retirement record id). A structured surface that adopts the
[location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) keeps its layers
and merge form, names both team-layer locations in the path column, and states the precedence in
its conformance cell.

| Surface | Consumer config path | Layers | Who wins | Merge form | Conformance |
|---|---|---|---|---|---|
| `source-control` | `.claude/source-control.md` | all three | later layer; team on the merge-rung; fail-closed on a bad `branch_issue_pattern` | per-key | conforms (per-key override, #660), except the declared fail-closed stop on an unusable `branch_issue_pattern` layer (#4673, see Declared) and the ratified gitignore append of the recursive overlay line ([ADR 0040](../../adr/0040-ratify-the-source-control-setup-append-of-the-recursive-overlay-gitignore-line.md)); `parse-branch-issue.sh` implements the home-root rule (#4672): team and overlay are not applicable when the resolved root is `$HOME` or an ancestor of it, or is not inside a git working tree, and a team/overlay path that physically equals the user-global file is skipped; setup `apply layer=team` / `layer=local` refuse in that state; the resolver is `plugins/source-control/lib/config-root.sh`, and other surfaces carry it as in [Root rule by surface](#root-rule-by-surface). Enforcement reads team-tracked only per [`commit-convention`](../commit-convention/README.md); loop-lane keys (`babysit_loop_*`, read by the source-control babysit lane; the work-items lanes tie in via the loop-lane convention only) ride the same surface, with the merge-rung key in the policy-floor class: standing raises bind from the team-tracked layer only, and the one named single-invocation exception is an explicitly typed argument rather than a config value in any layer, per [`loop-lane`](../loop-lane/README.md) |
| `toolchain` / `ecosystem-commands` | `.claude/ecosystems/<ecosystem>.yaml` | all three | later layer | per-key | conforms |
| `codebase-health` | `.claude/codebase-health.md` | all three | later layer | concatenate | conforms (concatenating, with a declared empty-list opt-out) |
| `bugs` | `.claude/bugs.md` | all three | later layer | lanes concatenate; `## Gotchas` concatenates; `filing_posture` nearest-wins | conforms; `lanes` concatenate and deduplicate by lane `name`, with a declared empty-list opt-out that also drops the bundled defaults, and `filing_posture` is a nearest-wins scalar. A `## Gotchas` section outside the YAML fence concatenates across layers and is pre-computed by `/bugs:scan` and `/bugs:write`. Keys owned by the plugin's `reference/config.md`, which also partitions them from the plugin's `output_dir` `userConfig` option. That option is never a key in this surface, and a layer declaring it is reported as an inert unknown key. Written (team layer only) by `/bugs:setup apply`, read by `/bugs:scan` |
| `github` | `.claude/github/` (`routing.yaml` per-key override, `conventions.md` concatenating) | all three | team on write-posture keys; later layer otherwise | per-key (`routing.yaml`); concatenate (`conventions.md`) | conforms; policy-floor inversion on write-posture routing keys, declared in the plugin's `change-routing.md` |
| `autonomy` | `.claude/autonomy/binding.json` | all three, plus an org rung | later layer except security axes | declared | declared deviation |
| `standards` (`planning`, `review`) | `<standards_dir>/`, rooted by `.claude/standards.yaml` | all three | team on conflict (policy-floor) | add/tighten | precedence inversion ratified via policy-floor class (#649); layer location outside `.claude/` ratified in place as a declared exception ([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md)) |
| `disk-hygiene` | `.claude/disk-hygiene.json` | user-global + team | team over user-global; `--policy` replaces both | additive standing layers | declared deviation; no overlay layer |
| `ai-briefing` | `.claude/ai-briefing/` | team only | team only | no overlay | declared deviation; team-only, no local overlay (#3580). Named profile selection (`--profile`, `active_profile`, or `.claude/ai-briefing/<name>/`) is profile selection, not a `*.local.*` cascade layer. `sources.md`, optional `audience.md`, and optional `brand.json` are tracked profile files in the selected directory, not personal overlays |
| `code-tidying` | `.claude/tidy-lanes/<lane>.md` | team only | team only; residual wholesale if no `## Merge semantics` | per-section when declared | declared deviation; no user-global or `*.local.*` overlay (#723). Team layer over a bundled default. A project lane declaring `## Merge semantics` merges per-section with its bundled lane (`Scope` per-section override, watch-for patterns additive, per `docs-prose` #701 and `shell-tooling` #724). Residual deviation: a project lane that declares nothing still resolves project-only wholesale, the first-match fallback retained in #701 so unmigrated consumer lanes keep working, undeclared at the layer that takes it. Personal variation is limited to lane names the team does not track, an uncommitted `.claude/tidy-lanes/<lane>.md` never added to the index; gitignoring a path the team already tracks does not make it personal |
| `code-metrics` | `docs/conventions/code-metrics.yaml` (ADR 0060; schema `plugins/code-metrics/schemas/code-metrics.schema.json`), else `.claude/code-metrics.yaml` | all three | later layer | per-key | conforms (per-key override, declared because every value is a scalar or a closed list: `scope.exclude` and `lanes.<lane>.collectors.<measure>` replace whole), except declared divergences from "Resolution algorithm": (1) the root is `git rev-parse --show-toplevel`, else the working directory, and `CLAUDE_PROJECT_DIR` is not read (`plugins/code-metrics/scripts/resolve-config.py:216-228`; step 1); (2) no home-root or same-file classification of the team and overlay paths (`resolve-config.py:231-258`; step 2). The team layer is one file: the `.claude` file is read only while the docs file is absent, and with both present one warning names both (`resolve-config.py:239-258`). A layer outside the YAML subset reads as absent, and a value of the wrong shape is dropped by file, key and value and resolves from a valid higher layer, else the bundled default, never a lower layer; neither stops the run (`resolve-config.py:131-170,282-301`; ADR 0060 Decision 7). Unknown keys inert. Keys owned by [`plugins/code-metrics/reference/config.md`](../../../plugins/code-metrics/reference/config.md). Written (team layer only, carrying every key of an existing `.claude` file) by `/code-metrics:setup apply`; read by every audit skill. The consumer's `.claude/ecosystems/<lane>.yaml` files are a separate convention (ecosystem-commands); this surface does not absorb them. **Claim:** the plugin implements this row with the declared divergences above. **Basis:** `plugins/code-metrics/reference/config.md` "Layers and merge form" and the cited `resolve-config.py` lines. **As of:** 2026-10-04. **Recheck:** when that section adds a layer, changes merge form, or starts owning an ecosystem-commands key |
| `repo-fleet-hygiene` | `.claude/repo-fleet-hygiene.conf` | user-global + team | `--config` then team then user-global | whole-file, no per-key | declared deviation; whole-file precedence (explicit `--config` > team > user-global fallback), no per-key merge, no overlay layer (#1099) |
| `work-items` | `.work-item-tracker.json` (repo root) | team + local overlay | overlay on the allowlist | per-key overlay | declared deviation ([ADR 0015](../../adr/0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md)): layers live at the repo root, not under `.claude/`; overlay (`.work-item-tracker.local.json`) merges per-key over a deny-by-default allowlist (lease TTL, jira/linear/gitea auth identity, `docs`); deliberately no user-global layer, since a cross-repo personal rung would reopen the per-user provider trap the allowlist forecloses. Anchors at the repo root (`CLAUDE_PROJECT_DIR`, else git toplevel), no CWD climb. The overlay's gitignore line is outside the `.claude/**/*.local.*` one-liner, so `/work-items:setup apply` appends it, announced, a declared exception to the recommend default (ADR 0015) |
| `work-items` (recurring schedule) | `.github/recurring-schedule.json` | team only | team only | single-layer | declared deviation ([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md)): the schedule lives under `.github/`, not `.claude/`, tracked and team-shared with no user-global layer and no overlay. Written by `track add` and `track recheck`; read by `track audit`, `done`, `due`, `search` and `stats`, by `work` candidate discovery, and by `setup`, which also writes it; anchors at `CLAUDE_PROJECT_DIR`, else git toplevel. Separate from the tracker binding row above |
| `songwriting` | `songwriting/templates/pat-pattison/<name>.md` | team only, over a bundled default | project override over the bundled default | whole-file per template, no per-key | declared deviation ([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md)): the override path is under `songwriting/`, not `.claude/`. One tracked team file per template wins whole over `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/<name>.md`, the first match, and freezes that template against plugin updates; no user-global layer and no overlay. The ADR rules on location only. Written by `/songwriting:setup apply`, read by the craft skills |
| `ai-slop` | `.claude/ai-slop.json` | all three | later layer | per-key (lists replace) | conforms; per-key override, resolved by `/ai-slop:audit` (user-global, team, `.claude/ai-slop.local.json` overlay). Four list keys are additive-by-replacement rather than merged (`vocab_add` / `vocab_remove` tune the shipped word list, `phrase_add` / `phrase_remove` the shipped model-era phrase roster; the later layer's list wins per key). No policy-floor class: every key is a taste dial over prose style, and a personal overlay that silences a rule weakens nothing another surface depends on. Keys owned by `/ai-slop:setup`; `_comment` is an allowed free-text annotation, not drift |
| `docs-naming` | `.claude/docs-naming.json` | all three | later layer; team on named policy-floor keys | per-key | conforms, with the one sanctioned dual-read declared by retirement records `docs-naming-r001` and `docs-naming-r002` (the retired `.claude/docs-hygiene.json` and `.claude/docs-hygiene.local.json` are read as authority, with a WARN, only while the new name is absent); per-key override on `file_names.*`, with a policy-floor class on `tiers`, `generated`, `sweep_exclude`, `sweep_exclude_sites`, and the three `exempt_*` keys: a personal layer may ADD entries and never remove them, and `generated` is team-layer only. Those keys decide what `/docs-naming:realign-file-names` does to a tree (which files are frozen, which reference forms are rewritten, and which shell command runs after a move), so narrowing one from a single machine would weaken a team decision, while adding a scope root or an exemption weakens nothing and stays open. `rule`, `regex`, and `redirect_map` are nearest-wins. Keys owned by [`plugins/docs-naming/reference/config.md`](../../../plugins/docs-naming/reference/config.md), which also partitions them from plugin `userConfig` (this plugin declares none, so a layer naming one is an inert unknown key). Written by `/docs-naming:setup apply`, resolved by `plugins/docs-naming/scripts/resolve-config.sh` |
| `rendered-views` | `.claude/rendered-views.md` | all three | later layer | per-key | conforms; per-key override on `medium`, no policy-floor class (taste dial, the `ai-slop` precedent). Keys owned by [`rendered-views`](../rendered-views/README.md), which also partitions them from plugin `userConfig` dials (never keys in this surface; a layer declaring one is reported as an inert unknown key). Resolved by `visualization:visualize` (wave-1 exemplar) |
| `testing` (`run-e2e`) | `.claude/testing/e2e.md` for `recording` / `browser_mode`; `docs/conventions/testing.yaml`, `~/.claude/testing.yaml` and `.claude/testing.local.yaml` for `e2e_driver` / `reuse_running_instance`, over the plugin's `userConfig`; `docs/conventions/testing.yaml` and `.claude/testing.local.yaml` only for `feature_map_dir` (no user-global file, no `userConfig`) | all three | later layer | per-key | conforms; per-key override, keys owned by `/testing:run-e2e`. The three YAML keys are resolved by `resolve-config.sh e2e`, which reports the supplying layer and resolves an unknown or refused value to the default without stopping |
| `testing` (`audit`, `test-scan`) | team: `docs/conventions/testing.yaml` (schema `plugins/testing/schemas/testing.schema.json`), else the `yaml config` block in `docs/conventions/testing.md` (read for one more release), else `.claude/testing.yaml`; user-global `~/.claude/testing.yaml`; overlay `.claude/testing.local.yaml` | all three | later layer; the first present of `testing.yaml`, the docs block and `.claude/testing.yaml` in the team layer | per-key (scalars override, lists concatenate) | conforms to [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md), except the declared stop on an unusable layer, which replaces rule 5's soft degrade and its inert unknown keys (see Declared): one warning names each shadowed team file. Keys and layer merge owned by `plugins/testing/scripts/resolve-config.sh`; written by `/testing:setup apply`, read by `/testing:audit` and the `test-scan` hook, which skip the two `run-e2e` keys the same file carries |
| `testing` (`check-visual-parity`) | team: `docs/conventions/testing.yaml` read from origin's default branch (the working tree only when the repository has no `origin`); user-global `~/.claude/testing.yaml`; overlay `.claude/testing.local.yaml`; per user: the plugin's `pixel_tolerance` `userConfig` option | all three, plus the user option | lowest value (policy floor) | per-key | declared deviation from [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) Decision 5's floor wording, as the `implementation` row: the `pixel_tolerance` map keeps a tighten-only `userConfig` option. The team value, else the default 0, is the ceiling; a personal layer or the option can only lower it, and a raise is reported as ignored. An invalid layer is named with its file or option, key and value and dropped (Decision 7). Resolved by `visual-compare.sh config` in `/testing:check-visual-parity`, which reports the supplying layer; the test scan skips the map and `/testing:setup apply` keeps it |
| `plugin-quality` | convention doc at the consumer's convention home, `<home>/plugin-quality/README.md` (the pointer line binds `<home>`) | team, via pointer line | team via pointer line | convention doc | migrated (expression-doctrine pilot, ADR 0018): conformance is retirement record `plugin-quality-r001` (dual-read window while the retired `.claude/plugin-quality.md` persists: WARN-visible, the file reads as authority until cleaned); overlay layer retired by `plugin-quality-r002`, user-global layer retired prose-only (machine scope, outside the manifest); keys owned by the plugin's `reference/config.md` |
| `architecture` | convention doc at the consumer's convention home, `<home>/architecture/README.md` (the pointer line binds `<home>`) | team, via pointer line | team via pointer line | convention doc | new surface under the expression doctrine, so there is no retirement record: nothing migrated into it, no dedicated-file layer was ever expressed, and no dual-read window exists. `architecture_dir` has no default (an undeclared, unconfirmed value stops every `/architecture:map-*` skill and routes to `/architecture:setup` rather than picking a directory); `landscape_dialect` defaults to `mermaid` and is read by `map-landscape` alone; the other map views take their dialect from `authoring-formats`. Optional `component_layers` is read by `map-components`. Keys owned by the plugin's [`reference/config.md`](../../../plugins/architecture/reference/config.md#map-family-dialect-decision), which maps that landscape key against `authoring-formats`'s `diagram_dialect.system` rather than restating mermaid fitness here; written by `/architecture:setup apply`, read by every `/architecture:map-*` skill for `architecture_dir` |
| `harness-config` (`audit-pass`) | `.claude/audit-pass.md` | all three | team on conflict (policy-floor) | per-key | conforms; per-key override (suppression entries merge per `finding_id`), plus policy-floor inversion: the team layer wins a direct conflict, since a personal overlay suppressing a finding the team never accepted is the weakening this class prevents. Keys owned by [`finding-suppression`](../finding-suppression/README.md) |
| `authoring-formats` | convention doc at the consumer's convention home, `<home>/authoring-formats/README.md` (the pointer line binds `<home>`) | team, via pointer line | team via pointer line | convention doc | declared under the expression doctrine as a new surface, not a migration: no retired dedicated file, no retirement record, no dual-read window. One layer, no overlay channel, unknown keys inert. Keys (`acceptance_criteria_format`, `diagram_dialect.data`, `diagram_dialect.system`) owned by [`authoring-formats`](../authoring-formats/README.md#c4-dialect-surfaces), which also states the ladder consuming skills restate and maps the system key against architecture's `landscape_dialect` rather than restating mermaid fitness here. `diagram_dialect.system` deliberately has no default, so an absent surface emits no C4 container view. No policy-floor class: both keys are team format choices, and the doctrine gives this class no personal layer to weaken them from. **Read on `main` by `/planning:interview` and `/planning:prd` (`acceptance_criteria_format`), by `/planning:design` (`diagram_dialect.data`, `diagram_dialect.system`), by `/architecture:map-data` (`diagram_dialect.data`), and by `/architecture:map-components`, `/architecture:map-context`, `/architecture:map-containers`, and `/architecture:map-deployment` (`diagram_dialect.system`)**, each resolving `<home>` through its plugin's bundled `lib/resolve-convention-home.sh`. Any further consuming slice lands per skill and updates that doc's Consumers table in the same change |
| `instruction-placement` | `.claude/instruction-placement.md` | all three | team on conflict (policy-floor) | per-key | conforms; per-key override (suppression entries merge per `finding_id`), plus policy-floor inversion: the team layer wins a direct conflict and a personal-only entry is reported `personal-only, not applied`, since a decline removes a placement proposal from every future report and a personal layer hiding one the team never accepted is the weakening this class prevents. `suppressions` is the surface's only key today; the plugin's `userConfig` dials stay personal and are never keys here. Written (team layer only) by `/instruction-placement:realign` behind its per-item gate, read by `/instruction-placement:audit` and `/instruction-placement:delta`. Keys owned by the plugin's `reference/consumer-config.md`; suppression-entry keys by [`finding-suppression`](../finding-suppression/README.md) |
| `overengineering` | `.claude/overengineering.md` | all three | team on conflict for protected keys | per-key | conforms; per-key override, plus policy-floor inversion on two key groups: the protected-categories set and the suppression entries (which merge per `finding_id`). On both, the team layer wins a direct conflict, personal layers may extend or tighten only, and a personal contribution is named in the report: a gitignored overlay emptying the protected set would defeat the plugin's FLAG-FOR-HUMAN cap on security-class artifacts, and a personal-only suppression is the same weakening `audit-pass` prevents above. Narrowing or emptying the protected set stays available on the tracked layer, spelled one category at a time so the diff names each protection dropped. The threshold and observation-window keys take ordinary refinement. Keys owned by the plugin's `reference/consumer-config.md`; suppression-entry keys by [`finding-suppression`](../finding-suppression/README.md) |
| `multi-agent` | team: the `yaml config` block in `docs/conventions/multi-agent.md`, else `.claude/multi-agent.yaml`; user-global `~/.claude/multi-agent.yaml`; overlay `.claude/multi-agent.local.yaml` | all three | later layer; the docs block over `.claude/multi-agent.yaml` in the team layer | per-key | conforms to the [location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) ([ADR 0044](../../adr/0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)): the docs block wins, `.claude/multi-agent.yaml` is read only when the docs file holds no block, a note names both paths when both exist, and two blocks in one file make the team layer invalid. Rule 5 holds: a layer that does not parse or names another schema is skipped and named, and an unknown key or a value outside its allowed set is reported and inert. No policy-floor class: every key is a routing dial, and turning the fan-out guard off is a documented opt-in on whichever layer sets it. Keys owned by [`plugins/multi-agent/reference/config.md`](../../../plugins/multi-agent/reference/config.md); resolved by `plugins/multi-agent/scripts/resolve-roles.sh`, read by `/multi-agent:route`, `/multi-agent:audit-defaults` and `/multi-agent:setup check`; written by `/multi-agent:setup apply` (any of the three layers, after a preview and an explicit yes) |
| `review-digest` | team: the `json config` block in `docs/conventions/review-digest.md`, else `.claude/review-digest.json`; user-global `~/.claude/review-digest.json`; overlay `.claude/review-digest.local.json` | all three | later layer; the docs block over `.claude/review-digest.json` in the team layer; `--policy` over every layer | per-key (lists replace) | conforms to the [location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) ([ADR 0044](../../adr/0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)): the docs block wins with a warning naming both paths, and two blocks make the team layer invalid. Rule 5 holds: a layer that does not parse is named and skipped, an invalid value is reported and ignored, and an unknown key is inert. Declared deviation from the per-layer verdicts: an untracked team layer is reported and resolved as absent rather than stopping, and an overlay that is not gitignored is reported and still applied, since every key only decides when a reader is offered a view. No policy-floor class. Keys owned by [`review-digest`](../review-digest.md); resolved by `plugins/review/skills/explain-change/scripts/digest-policy.mjs`, which also reads the `rendered-views` `medium` key |
| `playbooks` | team: `docs/conventions/playbooks.yaml` (schema `plugins/playbooks/schemas/playbooks.schema.json`); per user: the plugin's `userConfig` | `userConfig` + team | later layer | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset, and a value outside a key's list is named and resolves the default. Keys owned by the plugin's `reference/config.md`; read in the skill text of `/playbooks:fable-5` (`described_problem`), which reports the supplying layer |
| `implementation` | team: `docs/conventions/implementation.yaml` (schema `plugins/implementation/schemas/implementation.schema.json`); user: the plugin's `userConfig` option of the same name | user option + team | `true` in any layer (policy floor) | per-key | conforms to the [location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) ([ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md)); no `~/.claude` file and no overlay. `verify_mechanical_phases` is in the policy-floor class: `true` from either layer wins, so the user option can only tighten the team value and the team file can only tighten the user value, and the team file is also read from the default branch's committed copy so a branch cannot lower it. Declared deviation from ADR 0060 Decision 5's floor wording: the key keeps a `userConfig` option, which can only raise the value. A value outside `true` or `false` is named with its file, key and value and that layer resolves as absent (rule 5), so the key falls back to `false` unless the other layer says `true`. Keys owned by [`plugins/implementation/reference/config.md`](../../../plugins/implementation/reference/config.md); read by `/implementation:implement-dispatch` and `/implementation:implement`, and `integration_posture` (team file only) also by `/planning:plan` Step 2 |
| `education` | team: `docs/conventions/education.yaml` (schema `plugins/education/schemas/education.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. The team file is skipped outside a git working tree or when its root is `$HOME` or an ancestor of it. An unexpanded `${user_config.<key>}` reads as unset; a value outside a key's list is named with its file, key and value and that layer is dropped, so a valid higher layer wins and otherwise the default applies. Keys owned by [`plugins/education/reference/config.md`](../../../plugins/education/reference/config.md); read in the skill text of `/education:explain` (`explain_starting_rung`) through its bundled `parse-concern-value.sh`, which reports the supplying layer |
| `session-flow` | team: `docs/conventions/session-flow.yaml` (schema `plugins/session-flow/schemas/session-flow.schema.json`); user: the plugin's `userConfig` option of the same name | user option + team | later layer; the narrower layer for `transcript_scope` | per-key | conforms to the [location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) ([ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md)); no `~/.claude` file and no overlay. An unexpanded `${user_config.<key>}` reads as unset. A value outside a key's values is named with its file, key and value and that layer is dropped (rule 5), so a valid higher layer still wins and otherwise the key resolves its default. No policy-floor class. Declared deviation for `transcript_scope`: the narrower of the two layers wins (`worktree` < `repo` < `all`) and an unset user option counts as `worktree`, so the team file can narrow a user's transcript scan but never widen it; an invalid team value resolves the default `worktree`. Keys owned by [`plugins/session-flow/reference/config.md`](../../../plugins/session-flow/reference/config.md); read in the priming addendum of `/session-flow:orchestrate` (`worker_continuation`), in `/session-flow:retro codify` (`encode_policy`, `review_mining_prs`), in `/session-flow:handoff` (`wip_commit`, a boolean), in `/session-flow:retro` session mode (`retro_lenses`) and in `/session-flow:find-handoff` and `/session-flow:recall` (`transcript_scope`), all but the first after `setup-apply.mjs --check` tells an empty or invalid value from an absent key, through the plugin's copy of `parse-concern-value.sh`, which reports the supplying layer; `/session-flow:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `discovery` | team: `docs/conventions/discovery.yaml` (schema `plugins/discovery/schemas/discovery.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer; a per-run `--output` argument over both | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset; a value outside a key's list is named with its file, key and value and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves its default. Keys owned by [`plugins/discovery/reference/config.md`](../../../plugins/discovery/reference/config.md); read by `/discovery:explore` (`explore_output`); `/discovery:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `review` | team: `docs/conventions/review.yaml` (schema `plugins/review/schemas/review.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer; `report` in any layer for `downstream_probe` (policy floor) | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset; a value outside a key's values, or a team file that does not parse, is named with its file, key and value and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves its default. `downstream_probe` is in the [policy-floor class](#sanctioned-exception-class-policy-floor-precedence-inversion): `report` from either layer wins, so each layer can only tighten the other, and the team file is read from the default branch's committed copy (`setup-apply.mjs --check --ref origin/<default>` after a fetch, the commit read reported) so a branch cannot loosen it; an invalid layer resolves as absent and the key falls back to `run` unless the other layer says `report`. Declared deviation from ADR 0060 Decision 5's floor wording: the key keeps a `userConfig` option, which can only tighten the value. Keys owned by [`plugins/review/reference/config.md`](../../../plugins/review/reference/config.md); read by `/review:audit-enforceability` (`ratchet_offer`) and `/review:quality-gate` downstream mode (`downstream_probe`) through `/review:setup`'s `setup-apply.mjs --check`, which validates the file and reads values with the plugin's copy of `lib/parse-concern-value.sh`; `/review:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `planning` | team: `docs/conventions/planning.yaml` (schema `plugins/planning/schemas/planning.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset; a value outside a key's list is named with its file, key and value and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves its default. Keys owned by [`plugins/planning/reference/config.md`](../../../plugins/planning/reference/config.md); read in the skill text of `/planning:plan` (`plan_store`, `phase_order`, `scaffold_stubs`) and `/planning:design` (`scaffold_stubs`), each reporting the supplying layer; `scaffold_stubs` is a boolean, and a quoted `"true"` is invalid; `/planning:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one. The `standards` row above is a separate planning surface |
| `docs-hygiene` | team: `docs/conventions/docs-hygiene.yaml` (schema `plugins/docs-hygiene/schemas/docs-hygiene.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset; a key present without a valid value (outside its list, empty, null, a map or list, set twice, or in a file that does not parse) is named with its file, key and value and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves its default. Keys owned by [`plugins/docs-hygiene/reference/config.md`](../../../plugins/docs-hygiene/reference/config.md); read by `/docs-hygiene:compress` (`compress_articles`) through `skills/compress/scripts/articles-setting.sh`, which uses the plugin's copy of `lib/parse-concern-value.sh`, and the skill reports the supplying layer; `/docs-hygiene:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `discipline` | team: `docs/conventions/discipline.yaml` (schema `plugins/discipline/schemas/discipline.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | later layer | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset; a value outside a key's list is named with its file, key and value and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves its default. Only `lever_scope` has the team layer; the `sweep-all` batch options and `research_deep_verification` are `userConfig` only. Keys owned by [`plugins/discipline/reference/config.md`](../../../plugins/discipline/reference/config.md); read in the skill text of `/discipline:script-the-deterministic-work lever-check` (`lever_scope`), which reports the supplying layer and which `/implementation:implement` and `/implementation:implement-dispatch` call when it is among the available skills; `/discipline:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `verification` | team: `docs/conventions/verification.yaml` (schema `plugins/verification/schemas/verification.schema.json`); per user: the plugin's `userConfig` option of the same name | `userConfig` + team | stricter layer for `proof_level`; later layer for `live_workers` | per-key | declared deviation: a [ADR 0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) surface with no `~/.claude/<name>` file and no local overlay. An unexpanded `${user_config.<key>}` reads as unset. `live_workers` (a whole number of at least 1, default 1) is set at both levels, per user through `userConfig.live_workers` and per repository in the team file, and takes the later-layer rule: the team value wins over the user's, which wins over the default; it is read from the default branch by the same `--check --ref` call as `proof_level`, and a value that is not a whole number of at least 1 is named with its file or option, key and value, and that layer is dropped, so a valid higher layer still wins and otherwise the key resolves 1. Declared deviation for `proof_level`: the stricter of the two layers wins (`path` < `live` < `strict`), so either layer can raise the level and neither can lower the other, and the team file is read from the default branch's committed copy (`setup-apply.mjs --check --ref origin/<default>` after a fetch, the commit read reported) so a branch cannot lower its own level. A value outside the key's values, or a team file that does not parse, is named with its file, key and value and that layer is dropped; an invalid team value resolves the default `path`, not the user's value, and the run never stops or prompts. Keys owned by [`plugins/verification/reference/config.md`](../../../plugins/verification/reference/config.md); read by `/verification:confirm` through `/verification:setup`'s `setup-apply.mjs --check`, which validates the file and reads values with the plugin's copy of `lib/parse-concern-value.sh`, and the run reports the supplying layer; `/verification:setup apply` writes the team file after schema validation, showing the diff before it changes an existing one |
| `docs-cache` | user-global `${XDG_CONFIG_HOME:-$HOME/.config}/claude-docs-cache/config.json`; no repository path | user-global only, over a bundled default, under `DOCS_CACHE_*` and flags | flag, then `DOCS_CACHE_*`, then the machine file | per-key | declared deviation (see Declared): machine scope, no team or overlay layer, and the user-global file sits outside `~/.claude/` ([ADR 0057](../../adr/0057-share-a-user-scope-docs-cache-across-plugins.md)). Per-key override, declared because every value is a scalar: a key a higher layer omits keeps the lower layer's value, else the bundled default. Rule 4 holds: `docs-cache.sh config` prints each effective value with the layer that supplied it. Rule 5 holds: a malformed file is named and resolved as absent, and an unknown key is inert. Step 2 does not arise: the surface reads no repository-relative path. Keys and resolution owned by `lib/docs-cache.sh`, carried as generated copies by `harness-config`, `harness-ops` and `discovery` ([ADR 0019](../../adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)) |

### Root rule by surface

Each row states whether the surface implements Resolution algorithm step 2 on `main`: classifies the
root through `plugins/source-control/lib/config-root.sh` (or an inline copy of the same rule) and
skips team and overlay at a `home` or `non-repo` root. A plugin whose reader script adopts the
resolver carries a generated `lib/config-root.sh`, produced from the canonical `lib/config-root.sh`
by `scripts/sync-shared-copies.sh`. "Not yet" names the reader and its anchor. "Prose only" means a
model-run skill with no reader script, so the rule lives in the skill text.

| Surface | Step 2 | Reader and anchor |
|---|---|---|
| `source-control` | implements | `parse-branch-issue.sh` sources the resolver; the `commit` and `pull-request` skills classify before their layer probes; setup `apply layer=team` / `layer=local` refuse at a `home` or `non-repo` root |
| `toolchain` / `ecosystem-commands` | prose only | `/toolchain:check`, `/toolchain:lint`, `/toolchain:setup`; no reader script |
| `codebase-health`, `github`, `standards`, `rendered-views`, `testing` (`run-e2e`), `instruction-placement`, `overengineering`, `harness-config` (`audit-pass`) | prose only | model-run skills; no layer-reader script |
| `bugs` | implements | `scripts/concat-gotchas.sh` classifies its root inline (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) with the same rule and skips a team or overlay path that is the user-global file; it does not source the resolver |
| `docs-naming` | implements | `scripts/resolve-config.sh` sources its `lib/config-root.sh` copy and classifies `--root` (else the git toplevel of the current directory) against `--home`; `paths` reports team and overlay as not-applicable at a `home` or `non-repo` root, and a team or overlay path that is the user-global file is read once |
| `ai-slop` | implements | `skills/audit/scripts/detect.sh` sources its `lib/config-root.sh` copy and classifies its root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`, else `pwd`) before the team and overlay reads; a team or overlay file that is the user-global file is read once |
| `multi-agent` | implements | `scripts/resolve-roles.sh` sources its `lib/config-root.sh` copy and classifies `--root` (else `CLAUDE_PROJECT_DIR`, else the git toplevel) against `--home`; team and overlay are reported not-applicable at a `home` or `non-repo` root, and a team or overlay path that is the user-global file is read once; `/multi-agent:setup apply --layer team` and `--layer local` refuse at a `home` or `non-repo` root |
| `review-digest` | implements | `skills/explain-change/scripts/digest-policy.mjs` classifies its root inline (`CLAUDE_PROJECT_DIR`, else the nearest directory holding `.git`) and skips team and overlay when the root is the home directory, above it, or not a working tree, and any team or overlay path that is the user-global file; it does not source the resolver |
| `attribution` | implements | `skills/audit/scripts/lib.sh` sources its `lib/config-root.sh` copy; `cfg_layers_init` skips team and overlay unless `config_root_classify` returns `repo`, and skips a layer that `config_root_paths_same` matches to the user-global file |
| `code-metrics` | not yet | `scripts/resolve-config.py`: `git rev-parse --show-toplevel`, else the current directory; `CLAUDE_PROJECT_DIR` is not consulted |
| `disk-hygiene` | not yet | the clean engine takes the team file from `--project-dir`; no root classification |
| `repo-fleet-hygiene` | not yet | `audit-fleet.sh`: `--project-dir`, else `CLAUDE_PROJECT_DIR`; `setup-config.sh`: `CLAUDE_PROJECT_DIR`, else `$PWD` |
| `work-items` | not yet | `tools/work-item-tracker/lib/binding.sh` (`wit_project_root`): `CLAUDE_PROJECT_DIR`, else git toplevel; no user-global layer, so the home-root collision does not arise for the binding file. The recurring schedule is read inline as `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json` by every consumer the Implementers row lists, with no user-global layer either |
| `songwriting` | prose only | model-run skills read `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/`; no reader script and no user-global layer |
| `autonomy` | not yet | hooks anchor at `CLAUDE_PROJECT_DIR` (`hooks/hook-utils.sh`); `binding.json` has no shared reader script |
| `plugin-quality`, `architecture`, `authoring-formats` | not yet | each plugin's `lib/resolve-convention-home.sh`: `--root`, else `CLAUDE_PROJECT_DIR`, else git toplevel, else the current directory; team-only via pointer line, no user-global layer to collide with |
| `ai-briefing`, `code-tidying` | prose only | team-only surfaces read by model-run skills |
| `playbooks` | prose only | `/playbooks:fable-5` reads `docs/conventions/playbooks.yaml` in its skill text only when the working directory's git root is neither `$HOME` nor an ancestor of it, and otherwise skips the team layer and says so; no reader script |
| `implementation` | prose only | `/implementation:implement-dispatch` and `/implementation:implement` read `docs/conventions/implementation.yaml` only when the root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an ancestor of it, and otherwise reports the team layer skipped; `/planning:plan` reads that file's `integration_posture` key under planning's own root rule (git root neither `$HOME` nor an ancestor of it); no reader script |
| `education` | prose only | `/education:explain` reads `docs/conventions/education.yaml` (from `git rev-parse --show-toplevel`) through its bundled `parse-concern-value.sh` only when the root is inside a git working tree and is neither `$HOME` nor an ancestor of it; the root classification lives in the skill text, not the reader |
| `session-flow` | prose only | `/session-flow:orchestrate`, `/session-flow:retro codify`, `/session-flow:handoff`, `/session-flow:retro` (`retro_lenses`), `/session-flow:find-handoff` and `/session-flow:recall` read `docs/conventions/session-flow.yaml` in their skill text only when the working directory's git root is neither `$HOME` nor an ancestor of it, and otherwise skips the team layer and says so; the plugin's `parse-concern-value.sh` copy reads the key and does not classify the root; `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, with no `$HOME` check |
| `discovery` | not yet | `/discovery:explore` reads `docs/conventions/discovery.yaml` at the project root in its skill text and skips the team layer only when the root is unknown, with no `$HOME` check; `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel` |
| `review` | prose only | `/review:audit-enforceability` and `/review:quality-gate` downstream mode read `docs/conventions/review.yaml` (the latter at `origin/<default>`) only when the root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an ancestor of it, and otherwise reports the team layer skipped; `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, and refuses a root that is `$HOME` or an ancestor of it |
| `planning` | prose only | `/planning:plan` and `/planning:design` read `docs/conventions/planning.yaml` in their skill text only when the working directory's git root is neither `$HOME` nor an ancestor of it, and otherwise skips the team layer and says so; no reader script. `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, and refuses to write at a root that is `$HOME` or an ancestor of it |
| `docs-hygiene` | implements (inline) | `skills/compress/scripts/articles-setting.sh` anchors at `git rev-parse --show-toplevel` of the working directory, not `CLAUDE_PROJECT_DIR`, and skips the team layer outside a git working tree or when the root is `$HOME` or an ancestor of it (compared after `pwd -P`, without the resolver's case folding); `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, and refuses a root that is `$HOME` or an ancestor of it |
| `discipline` | prose only | `/discipline:script-the-deterministic-work lever-check` reads `docs/conventions/discipline.yaml` in its skill text only when the root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an ancestor of it, and otherwise reports the team layer skipped; no reader script. `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, and refuses to write at a root that is `$HOME` or an ancestor of it |
| `verification` | prose only | `/verification:confirm` reads `docs/conventions/verification.yaml` at `origin/<default>` only when the root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an ancestor of it, and otherwise reports the team layer skipped; `skills/setup/scripts/setup-apply.mjs` anchors at `--root`, else `git rev-parse --show-toplevel`, and refuses a root that is `$HOME` or an ancestor of it |

Migrating a single-layer surface is one change against that surface's own plugin, not a fleet-wide
sweep, and each migration updates its own row in the same change.

### Overlay spelling drift

Every setup surface that owns a `*.local.*` overlay now recommends (or, for
`source-control`, appends per [ADR 0040](../../adr/0040-ratify-the-source-control-setup-append-of-the-recursive-overlay-gitignore-line.md)) the recursive line above. The narrow spellings the
fleet used to ship, `.claude/*.local.*`, `.claude/ecosystems/*.local.*`, and
`.claude/autonomy/**/*.local.*`, were each narrowly correct for their own
surface but collectively defeated the one-line promise: a consumer running
three plugins was asked for three lines, and the non-recursive spellings
would silently miss a nested overlay if their surface ever grew a folder.
The recursive `.claude/**/*.local.*` line is the canonical spelling
([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md)). Each surface adopts it when its setup is next touched, with no separate
migration. Five deliberate exceptions remain: the bare `*.local.md` inside the
setup-owned `<standards_dir>/.gitignore` (a dedicated ignore file scoped to
the standards root, not the consumer's `.gitignore`); `work-items`' repo-root
`.work-item-tracker.local.json` line (ADR 0015; outside `.claude/` entirely);
`ai-briefing`, which is team-only and recommends no overlay line at all
(#3580); `songwriting`; and the `work-items` recurring schedule, both team-only
too and recommending no overlay line. This contract does not retroactively
rewrite narrow lines already written into consumer repositories. The
recursive line simply supersedes them where both exist.

## Surfaces listed for later adoption

Every other plugin's consumer config surface under `.claude/`, listed so each can adopt the
[location axis](#location-of-the-team-layer-a-docs-convention-file-or-claudename) in its own change.
None is migrated by the decision that created the axis. The list comes from
`git grep -ohE '\.claude/[A-Za-z0-9._/-]+' -- plugins | sort -u`, keeping consumer config and dropping
user-global and plugin-owned state, machine-scope surfaces, Claude Code's own files and directories
(`settings*.json`, `rules/`, `skills/`, `agents/`, `commands/`, `hooks/`, `plugins/`), test fixtures,
credentials, and the retired `.claude/provenance.json`. Re-derive it against the live tree before
acting on it.

A surface applies the expression criterion above in its own change. A policy-floor surface, a
per-operator-keyed surface, and mutable state stay dedicated files, and a prose surface takes the
convention-doc form of ADR 0018 rather than a config block. The Note column marks the surfaces the
tables above already declare policy-floor.

| Plugin | Team-layer path | Format | Note |
|---|---|---|---|
| `ai-briefing` | `.claude/ai-briefing/` (`sources.md`, `audience.md`, `brand.json`, per-profile subfolders) | Markdown, JSON | team only |
| `ai-slop` | `.claude/ai-slop.json` | JSON | |
| `attribution` | `.claude/attribution.json` | JSON | |
| `autonomy` | `.claude/autonomy/binding.json` | JSON | security axes never repo-local |
| `bugs` | `.claude/bugs.md` | Markdown with a YAML fence | |
| `harness-config` (`audit-pass`) | `.claude/audit-pass.md` | Markdown | policy-floor |
| `code-tidying` | `.claude/tidy-lanes/<lane>.md`, `.claude/code-tidying/exclusion-overrides.md` | Markdown | team only |
| `codebase-health` | `.claude/codebase-health.md` | Markdown | |
| `disk-hygiene` | `.claude/disk-hygiene.json` | JSON | user-global and team only |
| `docs-hygiene` | `.claude/docs-hygiene.json` | JSON | policy-floor keys |
| `github` | `.claude/github/routing.yaml`, `.claude/github/conventions.md` | YAML, Markdown | policy-floor keys in `routing.yaml` |
| `improvement` | `.claude/improvement.md` | Markdown | |
| `instruction-placement` | `.claude/instruction-placement.md` | Markdown | policy-floor |
| `mutation-testing` | `.claude/mutation-testing.md`, `.claude/mutation-testing-arid.md` | Markdown | `-arid` is a finding-suppression record |
| `overengineering` | `.claude/overengineering.md` | Markdown | policy-floor |
| `planning` | `.claude/interview-surface.json` | JSON | |
| `repo-fleet-hygiene` | `.claude/repo-fleet-hygiene.conf` | key-value conf | user-global and team only |
| `review`, `planning` | `.claude/standards.yaml` | YAML | roots `<standards_dir>/`; policy-floor |
| `source-control` | `.claude/source-control.md` | Markdown | policy-floor merge-rung key |
| `toolchain` | `.claude/ecosystems/<ecosystem>.yaml` | YAML | also read by `code-metrics`, `review` and `code-tidying` |
| `visualization` (`rendered-views`) | `.claude/rendered-views.md` | Markdown | |

Already convention docs under ADR 0018, so outside this list: `plugin-quality`, `architecture` and
`authoring-formats`. Declared location exceptions
([ADR 0042](../../adr/0042-ratify-consumer-config-location-outliers-in-place.md)), also outside it:
`standards`' `<standards_dir>/`, `songwriting`'s templates, and the `work-items` tracker binding and
recurring schedule.
