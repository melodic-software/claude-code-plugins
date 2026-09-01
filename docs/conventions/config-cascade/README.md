# Config Cascade Convention

> Formerly `consumer-config-layering` (renamed #1188). "Cascade" (CSS `@layer`/`!important`) is the
> established term that natively carries both per-key override and a ratified precedence-inversion —
> matching this seam's user→team→local + policy-floor model.

A versioned, marketplace-wide contract for **how** a plugin's consumer-tracked configuration layers —
which layers exist, what order they resolve in, and what a later layer may do to an earlier one. Every
plugin that reads config from a consuming repo resolves it the same way, so an operator who learns one
surface has learned all of them.

This directory is the source of truth: `README.md` (the contract), `CHANGELOG.md` (version history).

## Boundary — this contract owns the axis, never the keys

It governs **layering and precedence only**. Which keys a config surface has, what they mean, and how
they are validated belong to that concern's own owner doc under `docs/conventions/<concern>/`, or to
the plugin's own bundled reference. The two compose: a per-concern doc declares its keys and points
here for how its layers merge.

The distinction is what keeps this doc from colliding with the one-owner-doc-per-shared-concern rule.
Layering is a genuinely cross-cutting axis every config surface shares; keys are not.

## The layers

Three layers, each optional, resolved in this order — a later layer refines an earlier one:

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/<name>` | the operator, across every repo and machine they work in |
| 2 | team | `${CLAUDE_PROJECT_DIR}/.claude/<name>` | the consuming repository, tracked in version control |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>` | one operator in one repo, gitignored |

`<name>` is the surface's whole path **relative to `.claude/`**, not just its leaf filename. For a
single-file surface that is `source-control.md`; for a folder-form surface it is
`ecosystems/<ecosystem>.yaml`, giving a user-global layer at
`~/.claude/ecosystems/<ecosystem>.yaml`. The folder hierarchy is part of the surface's identity and
repeats in every layer — collapsing it to the leaf would point the user-global layer at a different
file than the team layer. `<stem>.local.<ext>` follows the same rule: the overlay suffix attaches to
the leaf file, never to a folder in the path.

**All three layers absent is a valid state**, not an error. The surface falls through to whatever the
plugin's own resolution ladder specifies next — inference from the repo's own files, an interview, or
a bundled default.

### Why these three and not others

Each layer answers a question the others cannot. User-global carries a preference across repos, which
a tracked file structurally cannot — a per-user setting cannot decide the location or content of a
team-shared artifact. The team layer is the only layer teammates receive. The overlay is the only
place a personal deviation can live without either editing the shared file or going uncommitted and
lost. Dropping any one of them reintroduces a problem the other two cannot solve.

## Merge semantics

**Additive-preferred.** A later layer *adds to or refines* earlier layers. It never silently replaces
them wholesale.

Two sanctioned forms, in order of preference:

1. **Concatenate.** Every layer that exists is loaded and appended. Correct when the content is prose
   the model reads as guidance — the layers genuinely accumulate, and a reader wants all of them. This
   is what the first-party precedent does.
2. **Per-key override.** A later layer replaces an earlier layer's value **key by key**; a key absent
   from a later layer keeps the earlier value. Correct when the values are scalars or closed lists,
   where concatenation is meaningless or actively wrong — two anchored regexes cannot concatenate into
   a third valid regex, and two attribution-trailer templates would emit two trailers.

**Wholesale replacement is forbidden.** A layer that "overrides this file entirely" or takes the first
matching layer and stops is outside the contract: it turns every key the overlay does not mention into
a silent loss of the base layer's value, which is exactly the failure additive-preferred exists to
prevent. Both sanctioned forms preserve unmentioned keys; wholesale replacement is the one that does
not.

**A surface using per-key override must declare it** in its own contract, next to its keys. The
declaration is what makes it a design decision a reviewer can check rather than an accident.

### Sanctioned exception class: policy-floor precedence inversion

One class of surface — and only this class — inverts the precedence *direction* above while staying
additive on every other axis. A **policy-floor surface** encodes, in its team-tracked layer, a floor
that personal layers may extend or tighten but must never weaken. On a **direct conflict the team
layer wins**, the reverse of the default where a later layer refines an earlier one. It never drops a
base layer wholesale; it only decides who wins a conflict.

A surface qualifies for this class only when all three hold:

1. Its team layer is a genuine **policy floor** — a shared standard whose whole purpose is that a
   personal layer cannot loosen it; personal weakening of a team-agreed rule is the failure mode worth
   structurally preventing.
2. Personal layers (user-global and overlay) remain **add/tighten-only** — they may never supply a
   looser value that takes effect.
3. **Provenance is reported** — when a personal-layer rule materially shapes output, the surface names
   the contributing layer, so a reader can tell a team floor from a personal addition.

This mirrors well-established prior art — managed settings that supersede user settings, org-enforced
rulesets a repo cannot loosen, MDM managed preferences — where a higher-authority layer may be extended
but not weakened. A surface in this class is **conformant, not a tolerated deviation**, and must declare
the inversion in its own contract next to its keys. The class was ratified by #649; `standards` is its
exemplar.

## Overlay naming and the consumer `.gitignore`

The overlay is spelled `*.local.*` — the stem, `.local`, then the original extension. One spelling
across the fleet is the point: a consumer adds one `.gitignore` line and every current and future
surface is covered.

```gitignore
.claude/**/*.local.*
```

That is the whole convention — **one line, recursive form, for every surface**. `.claude/**/` matches
zero or more directories, so this single rule covers a flat `.claude/source-control.local.md`, a
one-deep `.claude/ecosystems/python.local.yaml`, and a profiled
`.claude/ai-briefing/<profile>/x.local.md` alike, while leaving team files tracked. The narrower
`.claude/*.local.*` silently fails to ignore any folder-form overlay; recommend the recursive form
only, and never ask a consumer for two lines where one is exact.

**No plugin writes the consumer's `.gitignore`.** A setup skill recommends the line and leaves the
edit to the consumer; their ignore file is their artifact.

## Expression doctrine — which surfaces are files, and which are convention docs

The layers above describe **where** a surface's values live relative to each other. This section
describes **how** a surface is expressed at all, and it ratifies a second expression form
alongside the dedicated file ([ADR 0018](../../adr/0018-express-team-shared-conventions-as-consumer-convention-docs.md),
2026-09; the decision record cites the blind mechanism tournament under
`docs/topics/customization-consistency/design/`).

**The criterion.** A surface takes exactly one of two expressions, settled by what the content
*is*, never by the author's preference:

- **Team-shared prose configuration** — guidance the model reads (a repo map, audit-target prose,
  a lane description) that every operator on the team is meant to share and that has no
  per-operator axis — is expressed as a **natural-language convention doc at the consumer's
  convention home** (for example `docs/conventions/<topic>/`), discovered or asked once at setup
  and bound by the pointer line below. Such a surface has **no overlay channel**: it has one
  layer, the team's. A migrated surface's setup `check` WARNs on any pre-existing `*.local.*`
  overlay file it finds for that surface rather than silently ignoring it — the overlay no longer
  has an effect, and silence would let a personal deviation look live.
- **Everything else stays a dedicated file under the layers above**: per-operator-keyed surfaces
  (a value keyed by operator identity or machine, or one an operator legitimately overrides
  privately — `testing`'s e2e config is the fleet example), structured data where YAML/JSON is
  the right tool (`topic-docs.yaml`, `routing.yaml`, `binding.json`), every policy-floor surface,
  and all mutable state.

The criterion is applied per surface, in that surface's own migration PR, and recorded in the
Implementers table's row. Nothing in this contract retroactively re-expresses a surface.

**The convention home is bound by one pointer line, and the line IS the binding.** The consumer's
root instruction file carries a single standing index/pointer line naming the convention home
(and, where the home holds several topics, pointing at its index). There is no separate binding
file: a plugin resolves the home by reading that line. The line lives inside a **marked,
machine-owned region** — the `instruction-placement` rules-index block is the precedent — so setup
can rewrite it idempotently without touching the operator's prose around it, and a reviewer can see
the region is generated. The consumer's root file otherwise carries only content needed in
effectively every conversation; topic conventions live at the home, loaded on demand.

Pointer-line rules a resolver honors (the small tested helper the program's mechanism phase ships
owns the grammar; consumer prose it reads is **untrusted input**, never executed or interpolated):

- **Both root files.** `AGENTS.md` is canonical when present; a `CLAUDE.md` whose whole content is
  the `@AGENTS.md` import is a pure shim and is not consulted for a pointer. When both files carry
  a marked region, `AGENTS.md` wins and `CLAUDE.md`'s copy is reported as a duplicate finding
  (remediation: remove it). Two pointer lines inside one region is a FAIL, never first-wins.
- **Ask, never silently rebind.** A pointer absent while a previously-known home still exists on
  disk, or a pointer whose target directory is missing, is a FAIL that routes to `apply`'s
  interview. Inference may *propose* a home from repo evidence; only the operator's confirmation
  writes the line.
- **Branch-scoped.** The pointer line is tracked content, so divergent branches may bind different
  homes and a branch may legitimately re-ask. That is a property of tracked config, not a defect.

**Root-file shape is the downstream repository's call.** Recommended guidance, never forced: an
AGENTS.md-canonical root with a pure `@AGENTS.md` CLAUDE.md shim (the shape `instruction-placement`
already installs) — but a repo that keeps `CLAUDE.md` canonical, or a symlink, is served identically
once setup has discovered which file carries the region.

**Dual-read deprecation window.** A migrated skill that finds the retired dedicated file present
treats it as WARN **and** reads it as authority (at minimum as inference evidence) until the
consumer cleans it through the retirement mechanism (`docs/MIGRATION-PLAYBOOK.md`
§ Retired conventions). This covers a consumer who updated the plugin without re-running setup,
and is the one sanctioned dual-read: declared per surface by its retirement record, WARN-visible on
every run, never silent. The window closes for a consumer when that record's cleanup runs, and for
the fleet when the record is demoted to report-only under the mechanism's demotion rule.

**Scope.** This doctrine governs repository-scope surfaces only. Machine-scope files under
`~/.claude/` (context-guard, rate-limit-guard, machine-health) are outside both the criterion and
the retirement mechanism; ADR 0018 records that exclusion.

## Resolution algorithm

A plugin implementing this contract:

1. **Anchors at the repo root** before any repo-relative read — `${CLAUDE_PROJECT_DIR}` when set,
   otherwise `git rev-parse --show-toplevel`. Never a CWD-relative path: invoked from a nested
   directory, a CWD-relative read finds a nonexistent `<subdir>/.claude/...`, misses the real config,
   and silently degrades to a lower rung. Re-resolve the root in every self-contained shell call.
2. **Reads every layer that exists**, in order, and merges per the surface's declared semantics.
   Reading one layer and stopping is not resolution.
3. **Reports which layer supplied each value** whenever it surfaces the effective config to a human.
   A reader who cannot see which layer won cannot tell why the plugin behaves as it does.
4. **Degrades soft on a malformed layer** — surface the error, name the layer, resolve as if that
   layer were absent. Unknown keys are inert. A consuming repo may validate its own files in a gate;
   plugins do not hard-fail on them.

### Per-layer verification verdicts

The same tracked/ignored question produces opposite correct answers per layer, so a single shared
check is always wrong for two of the three:

| Layer | Version control | On violation |
|---|---|---|
| user-global | outside the worktree — **no git command applies** | n/a |
| team | must be tracked | hard STOP: teammates would never receive the shared convention |
| local overlay | must be gitignored, never staged | FAIL: a personal deviation can reach team history |

The user-global row is not an omission. `git check-ignore` and `git status` against a path outside the
repository return a meaningless verdict — or a confidently wrong one when the operator's home
directory is itself a git repository.

## Versioning

`contract_version` (SemVer) versions this contract; the number lives in `CHANGELOG.md`. A change to
the precedence order or to what a layer means is a major bump. Adding an optional layer, or relaxing a
rule additively, is a minor bump. Per-concern key schemas version independently under their own owner
docs and are deliberately decoupled from this number.

## Deviations

Recorded here whether or not ratified. Listing a deviation documents that it exists and diverges; it
does not by itself bless it. Ratifying one — as #649 did for the policy-floor precedence-inversion
class above — moves it from observed to sanctioned. Ruling on each remaining deviation (correct the
surface, or amend this contract) is a separate human-gated decision.

**Ratified as a sanctioned exception class — one axis only:**

- **`standards` precedence inversion** — the exemplar of the policy-floor precedence-inversion class
  above (ratified by #649). Personal layers may add or tighten only; the team-tracked layer wins a
  direct conflict, with provenance reported. Conformant to that class, not a tolerated deviation.
  **This ratification covers the precedence axis alone.** `standards` also diverges on layer *location*
  (see Declared, below), which #649 did not rule on and which remains observed.

**Declared** — the surface states its divergence and why:

- **`standards` locates its layers outside `.claude/`.** Its team and overlay layers live at
  `<standards_dir>/` (default `docs/standards/`) with a setup-owned in-directory `.gitignore`, rather
  than the contract's `${CLAUDE_PROJECT_DIR}/.claude/<name>` and `*.local.*` paths — deliberately,
  because writes under `.claude/` are permission-guarded. **Observed, not ratified:** #649 ruled the
  precedence axis only; the location model is a separate, still-open ruling.
- **`autonomy` exempts its security axes.** Layers refine additively as the contract requires, except
  that no repo-local value may supply or override a security axis at all — a stricter rule than this
  contract, in the direction of safety.
- **`disk-hygiene`'s `--policy` replaces both standing layers.** Its standing layers merge additively
  (overlays may disable or add hints and add protected globs, never weaken a hard guard); the
  wholesale replacement is confined to an explicit per-invocation flag, not a file layer.

**Undeclared** — divergence with no recorded rationale:

- **`ai-briefing` advertises an overlay layer it does not implement.** Its setup recommends the
  recursive `.claude/**/*.local.*` gitignore line, but no read path resolves a `.local.*` file and
  no file defines what one would do. Its documented resolution covers profile *selection* only, never
  layer precedence. This is the only surface telling consumers to gitignore a layer that has no
  effect.

## Implementers

Conformance is tracked, not assumed. A surface is listed here whether or not it conforms — the gap is
the point. Each row states the surface's conformance **as it exists on `main`**, never as a
migration intends it to be; a row that ran ahead of the code would report a closed gap that is still
open. Every row below is currently expressed as a **dedicated file**; a surface that migrates to a
convention doc under the expression doctrine above rewrites its row in the same PR (path → the
convention home, layers → `team, via pointer line`, conformance → the retirement record id).

| Surface | Consumer config path | Layers | Conformance |
|---|---|---|---|
| `source-control` | `.claude/source-control.md` | all three | conforms (per-key override, #660); enforcement reads team-tracked only per [`commit-convention`](../commit-convention/README.md); loop-lane keys (`babysit_loop_*`, read by the source-control babysit lane; the work-items lanes tie in via the loop-lane convention only) ride the same surface, with the merge-rung key in the policy-floor class — standing raises bind from the team-tracked layer only, and the one named single-invocation exception is an explicitly typed argument rather than a config value in any layer, per [`loop-lane`](../loop-lane/README.md) |
| `toolchain` / `ecosystem-commands` | `.claude/ecosystems/<ecosystem>.yaml` | all three | conforms |
| `codebase-health` | `.claude/codebase-health.md` | all three | conforms (concatenating, with a declared empty-list opt-out) |
| `bugs` | `.claude/bugs.md` | all three | conforms; `lanes` concatenate and deduplicate by lane `name`, with a declared empty-list opt-out that also drops the bundled defaults, and `filing_posture` is a nearest-wins scalar. Keys owned by the plugin's `reference/config.md`, which also partitions them from the plugin's `output_dir` `userConfig` option — that option is never a key in this surface, and a layer declaring it is reported as an inert unknown key. Written (team layer only) by `/bugs:setup apply`, read by `/bugs:scan` |
| `github` | `.claude/github/` (`routing.yaml` per-key override, `conventions.md` concatenating) | all three | conforms; policy-floor inversion on write-posture routing keys, declared in the plugin's `change-routing.md` |
| `autonomy` | `.claude/autonomy/binding.json` | all three, plus an org rung | declared deviation |
| `standards` (`planning`, `review`) | `<standards_dir>/`, rooted by `.claude/standards.yaml` | all three | precedence inversion ratified via policy-floor class (#649); layer location outside `.claude/` still observed, not ratified |
| `disk-hygiene` | `.claude/disk-hygiene.json` | user-global + team | declared deviation; no overlay layer |
| `ai-briefing` | `.claude/ai-briefing/` | team only | undeclared: overlay recommended, never resolved |
| `code-tidying` | `.claude/tidy-lanes/<lane>.md` | team only | declared deviation; no user-global or `*.local.*` overlay (#723). Team layer over a bundled default. A project lane declaring `## Merge semantics` merges per-section with its bundled lane (`Scope` per-section override, watch-for patterns additive — `docs-prose` #701, `shell-tooling` #724). Residual deviation: a project lane that declares nothing still resolves project-only wholesale — the first-match fallback retained in #701 so unmigrated consumer lanes keep working, undeclared at the layer that takes it. Personal variation is limited to lane names the team does not track — an uncommitted `.claude/tidy-lanes/<lane>.md` never added to the index; gitignoring a path the team already tracks does not make it personal |
| `topic-docs` | `.claude/topic-docs.yaml` | team only | single-layer |
| `repo-fleet-hygiene` | `.claude/repo-fleet-hygiene.conf` | user-global + team | declared deviation; whole-file precedence (explicit `--config` > team > user-global fallback), no per-key merge, no overlay layer (#1099) |
| `work-items` | `.work-item-tracker.json` (repo root) | team + local overlay | declared deviation ([ADR 0015](../../adr/0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md)): layers live at the repo root, not under `.claude/` (precedent: `standards` location); overlay (`.work-item-tracker.local.json`) merges per-key over a deny-by-default allowlist (lease TTL, jira/linear/gitea auth identity, `docs`); deliberately no user-global layer — a cross-repo personal rung would reopen the per-user provider trap the allowlist forecloses. Anchors at the repo root (`CLAUDE_PROJECT_DIR`, else git toplevel), no CWD climb. The overlay's gitignore line is outside the `.claude/**/*.local.*` one-liner, so `/work-items:setup apply` appends it, announced — a declared exception to the no-plugin-writes rule |
| `ai-slop` | `.claude/ai-slop.json` | all three | conforms; per-key override, resolved by `/ai-slop:audit` (user-global, team, `.claude/ai-slop.local.json` overlay). Four list keys are additive-by-replacement rather than merged (`vocab_add` / `vocab_remove` tune the shipped word list, `phrase_add` / `phrase_remove` the shipped model-era phrase roster; the later layer's list wins per key). No policy-floor class: every key is a taste dial over prose style, and a personal overlay that silences a rule weakens nothing another surface depends on. Keys owned by `/ai-slop:setup`; `_comment` is an allowed free-text annotation, not drift |
| `rendered-views` | `.claude/rendered-views.md` | all three | conforms; per-key override on `medium`, no policy-floor class (taste dial, the `ai-slop` precedent). Keys owned by [`rendered-views`](../rendered-views/README.md), which also partitions them from plugin `userConfig` dials (never keys in this surface; a layer declaring one is reported as an inert unknown key). Resolved by `visualization:visualize` (wave-1 exemplar) |
| `testing` (`run-e2e`) | `.claude/testing/e2e.md` | all three | conforms; per-key override on `recording` / `browser_mode`, keys owned by `/testing:run-e2e` |
| `plugin-quality` | `.claude/plugin-quality.md` | all three | conforms; per-key override (repo-map entries merge per plugin name), keys owned by the plugin's `reference/config.md` |
| `claude-config` (`audit-pass`) | `.claude/audit-pass.md` | all three | conforms; per-key override (suppression entries merge per `finding_id`), plus policy-floor inversion — the team layer wins a direct conflict, since a personal overlay suppressing a finding the team never accepted is the weakening this class prevents. Keys owned by [`finding-suppression`](../finding-suppression/README.md) |
| `overengineering` | `.claude/overengineering.md` | all three | conforms; per-key override, plus policy-floor inversion on two key groups — the protected-categories set and the suppression entries (which merge per `finding_id`). On both, the team layer wins a direct conflict, personal layers may extend or tighten only, and a personal contribution is named in the report: a gitignored overlay emptying the protected set would defeat the plugin's FLAG-FOR-HUMAN cap on security-class artifacts, and a personal-only suppression is the same weakening `audit-pass` prevents above. Narrowing or emptying the protected set stays available on the tracked layer, spelled one category at a time so the diff names each protection dropped. The threshold and observation-window keys take ordinary refinement. Keys owned by the plugin's `reference/consumer-config.md`; suppression-entry keys by [`finding-suppression`](../finding-suppression/README.md) |

Migrating a single-layer surface is one change against that surface's own plugin, not a fleet-wide
sweep — and each migration updates its own row in the same change.

### Overlay spelling drift

Every setup surface now recommends (or, for `source-control`, appends) the
recursive line above. The narrow spellings the fleet used to ship — `.claude/*.local.*`,
`.claude/ecosystems/*.local.*`, `.claude/autonomy/**/*.local.*` — were each narrowly correct for
their own surface but collectively defeated the one-line promise: a consumer running three plugins
was asked for three lines, and the non-recursive spellings would silently miss a nested overlay if
their surface ever grew a folder. Two deliberate exceptions remain: the bare `*.local.md` inside
the setup-owned `<standards_dir>/.gitignore` (a dedicated ignore file scoped to the standards
root, not the consumer's `.gitignore`), and `work-items`' repo-root
`.work-item-tracker.local.json` line (ADR 0015; outside `.claude/` entirely). This contract does
not retroactively rewrite narrow lines already written into consumer repositories — the recursive
line simply supersedes them where both exist.
