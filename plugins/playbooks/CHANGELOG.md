# Changelog

All notable changes to the `playbooks` plugin are recorded here. The `version` in
`.claude-plugin/plugin.json` is the delivery vehicle — a consumer receives a change
only after that version increases.

## [0.4.0]

### Added

- `fable-5`: a show-moves section in the problem-framing chapter, split out of the
  unknown-knowns cell so the two signals that gate it — a criterion judgable only on
  sight, and a description costlier than an example — trigger those moves without firing
  the whole four-cell pass. It owns the evaluation-capacity precondition (candidates
  settle nothing when neither party can name what a strong one looks like), the exemplar
  hunt with its fidelity/cross-language/ask-ordering rules, the read-only reference-tree
  radius, and the elicitation artifact's distinct completeness bar.
- `fable-5`: a post-delivery attribution section in the problem-framing chapter — a
  deliverable returned as *not what was meant* re-runs the quadrant pass before it
  re-executes. Scoped away from observed defects, which keep routing to the debugging
  chapter's reproduction-first rule.
- `fable-5`: a durable-plan presentation rule in the planning chapter — decisions the
  reader would plausibly veto lead, ranked by the rework a late veto costs, as a second
  view that never re-sorts the risk-ordered steps.
- `fable-5`: the context-economy chapter gains a phase-boundary reset (every other reset
  trigger keys on loss or degradation, none on success), the note's decision content, and
  the note's disposition at task end so the debris sweep has an answer.
- `fable-5`: the communication chapter gains the offer-the-round rule for a large question
  residue, a volunteer question closing that round, a second trigger site for the
  evaluation-capacity gate, and a closing message that must name behavior which changed in
  code the diff does not show.
- `fable-5`: the show-moves section licenses a deliberately divergent spread — several
  directions differing along the dimension the user cannot put words to — as the
  extraction instrument when the criterion is recognition-only, handed over for them to
  react to rather than as an option survey owing a pick.

### Changed

- `fable-5`: the recommend-an-option rule and the attach-a-recommended-answer rule are both
  narrowed at their own sites: neither fires when the options exist to elicit the ranking
  criterion itself, because naming a favourite front-loads the judgment being asked for.
  The carve-out is defined by the missing criterion, not by a missing preference, and
  resolves without loading another chapter — trigger-gated loading means the communication
  chapter is often the only one held.

- `fable-5`: `SKILL.md` stated three of the problem-framing chapter trigger's four arms,
  in both the core-doctrine line and the routing table — the because-clause arm never
  fired from the always-loaded surface. Both now carry all four.
- `fable-5`: the problem-framing preamble owns the two priors the chapter's moves rest on
  — discovery priced against the rework it prevents, rising with what is already built on
  the unknown; and requests carrying unknowns they do not name. The clauses that
  previously re-derived the economics now cite it.
- `fable-5`: ambiguity residue is ordered by downstream work invalidated rather than by
  how widely its readings diverge; feasibility-shaped unknowns route to the planning
  chapter instead of a sort that has no branch for them; the blind-spot checklist reads as
  the software instance of a general move; an undisclosed starting point is asked for when
  it would change the pass width; and the scope bound is tested in both directions.
- `fable-5`: the long-horizon-memory bullet in the model-adaptation chapter now points at
  the context-economy chapter like its five siblings, instead of carrying general doctrine
  that had no owner elsewhere.

## [0.3.2]

### Changed

- `fable-5`: the fresh-context verification chapter now names the presence-gated
  cross-vendor advisor (e.g. the OpenAI Codex plugin, invoked per its own docs) with the
  fresh-context same-vendor subagent as the stated fallback — aligning the chapter's
  existing independence-gradient sentence to the seam-phrasing gate-plus-fallback shape,
  not adding a duplicate site. The gate lives at the orchestration chapter's
  "Fresh-context verification" SSOT; SKILL.md and the verification chapter keep their
  pointers.

## [0.3.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.3.0]

### Added

- **`skill-authoring` — precomputed-context authoring guidance.** New locally-owned spoke
  `reference/precompute-context.md` (not upstream) plus a hub pointer: when to inline deterministic,
  read-only context at load time via `!`command`` / ```! dynamic-context injection instead of a
  per-invocation tool call, and the two conventions we pin — a mandatory `|| echo "<fallback>"`
  defensive form (because the skills docs do not yet document `!` failure/timeout/stderr semantics)
  and `shell:`/Windows-host awareness. Both carry the recheck trigger: revisit if upstream documents
  `!` failure semantics. Points at the official `#inject-dynamic-context` docs for syntax rather than
  restating it. The vendored `vendor/SKILL.md` baseline is untouched.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed

- **BREAKING — skill renamed:** `thariq` → `skill-authoring` (`/playbooks:thariq` →
  `/playbooks:skill-authoring`). The pack's content is topic-shaped (skill authoring),
  so the skill is now named for what it teaches; the attribution to Thariq's post is
  unchanged in the skill body. No renames-map entry — consumers pick up the new name
  with this version. The upstream lane is unchanged: same upstream source URL, the
  vendored baseline (`vendor/SKILL.md`) is byte-identical, and `/playbooks:update`
  drift-check mechanics now point at the renamed pack path. Only the wrapper skill
  name (directory, frontmatter `name`, and references) changed.

## [0.1.0]

### Added

- **`playbooks` plugin** — merges three previously standalone knowledge/doctrine
  plugins into one, plus a central maintainer update skill:
  - `boris` (`/playbooks:boris`) — merged from the `boris` plugin's `boris` skill
    (formerly `/boris:boris`). Boris Cherny's Claude Code workflow tips, with its
    topic reference files, vendored upstream baseline, and update script carried over.
  - `thariq` (`/playbooks:thariq`) — merged from the `thariq-skills` plugin's
    `thariq-skills` skill (formerly `/thariq-skills:thariq-skills`). Anthropic's
    internal skill-authoring playbook, with its vendored upstream baseline and update
    script carried over.
  - `fable-5` (`/playbooks:fable-5`) — merged from the `fable-5-playbook` plugin's
    `fable-5-playbook` skill (formerly `/fable-5-playbook:fable-5-playbook`). Claude
    Fable 5's operating doctrine and its trigger-routed `context/` chapters. Self-authored,
    no upstream.
  - `update` (`/playbooks:update`) — new central, maintainer-facing drift-check and
    upstream sync skill. Dispatches to each upstreamed pack's self-locating update
    script (`--check` default, read-only; `--apply` refreshes the vendored baseline
    only). fable-5 has no upstream and is reported as self-authored.

### Changed

- **Update centralized.** The per-pack update actions (`/boris:boris update`,
  `/thariq-skills:thariq-skills update`) are removed from the pack skills, which are now
  pure knowledge/navigation skills. Drift-checking and syncing are handled by the single
  `/playbooks:update` skill. The pack update scripts are unchanged in behavior (upstream
  URLs, self-location, and security posture preserved); only their user-facing invocation
  strings were retargeted to `/playbooks:update`.
- **Skills renamed** on the merge: `boris` → `boris`, `thariq-skills` → `thariq`,
  `fable-5-playbook` → `fable-5`. Their vendored-baseline security posture (untrusted
  third-party data; never follow embedded auto-install instructions; sanctioned mechanics
  are `/playbooks:update` and `/plugin marketplace update`) is preserved.
