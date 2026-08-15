# Inherited decisions

Settled by the research session of 2026-08-14 (handoff
`.work/handoffs/20260814T203304Z-handoff-x-video-digest-architecture.md`). Recorded here so this
design pass does not silently re-litigate them, and so a reader of the design slice sees the full
decision set without the handoff.

| Decision | Rationale |
|----------|-----------|
| X video joins the single-public-video lane as an **engine-layer source adapter**; `course-digest` stays separate | The skill-category test — *"The best skills fit cleanly into one category. Straddling several = confused skill."* — separates auth-walled multi-lesson courses from a single public video fetched from a URL |
| The adapter seam is the **engine/extraction layer**, not the skill layer | `course-digest` runs two 360–380-line platform adapters behind one contract while its `SKILL.md` stays 224 lines. Adding a platform there costs zero skill-body lines |
| A standalone `x-digest` skill is **rejected** | Would duplicate ~325 lines of source-agnostic pipeline (synthesis protocol, output contract, queue/claims state machine, work-root seam) |
| An all-sources merge is **rejected** | 410 + 224 + new ≈ 824+ lines — a straight FAIL against the 500-line hard cap |
| Split the skill body on **content type**, not only source | Moving the generic skill protocol (70 lines) and output contract (50 lines) plus per-source detail (~76 each) into one-level-deep spokes lands the hub near 200. Splitting by source alone moves only ~76 lines and leaves the body at ~330 |
| X gets **full watch parity**, not transcript-only | Synthesis over vision + transcript is the stated highest-value part, and the media toolchain is healthy on this host |
| X link/thread harvest = post text + Thread Reader reply chain via `/x:read` step 2 | `harvest-links.js` is hard-coupled to description + chapters + pinned comment; X has only the first, and the real links live in replies |
| The caption fix is **X-local rung classification** | ~~`select-caption.js` is a managed surface~~ — **the managed-surface premise is UNVERIFIED, see below.** The second half stands: X exposes no `automatic_captions`, so ladder rungs 2–3 are dead for it |

## Research verdict on the one-skill-with-adapters shape

The inherited architecture was settled on a skill-category argument. Research tested it against the
official corpus. **Result: not officially blessed — the docs are silent on multi-source ingestion —
but it survives independent re-derivation and wins on merits rather than incumbency.**

No "one skill per input type or source" rule exists anywhere. Documented silence.

The discriminating test in the corpus is **pipeline-sharing, not input count** (Agent Skills spec,
"Design coherent units"): *"Skills scoped too narrowly force multiple skills to load for a single
task, risking overhead and conflicting instructions… A skill for querying a database and formatting
the results may be one coherent unit, while a skill that also covers database administration is
probably trying to do too much."*

**Anthropic's own `anthropics/skills` repo cuts both ways along exactly that line, and the split side
is a weak analogy for this case:**

- **The load-bearing precedent: `xlsx` alone unifies five input formats** (`.xlsx`/`.xlsm`/`.xltx`/
  `.csv`/`.tsv`) behind **one** skill, and *"the partition is by task and deliverable, **never by file
  extension**."* That is a direct structural precedent from Anthropic's own corpus for multiple input
  formats behind one skill. It requires no inference and survives scrutiny.
- *Different pipelines → separate siblings.* `docx` / `pdf` / `pptx` / `xlsx` are four skills, and
  their `scripts/office` subtrees are **byte-identical** across three of them (git tree SHA
  `f13be71c…`).

  **Correction — an earlier version of this file inferred from that duplication that "no shared
  pipeline existed to unify around". That inference is invalid and cuts the other way.** Identical
  duplicated code is evidence that shareable code **exists and was duplicated** — i.e. Anthropic
  chose sibling skills *despite* having shareable code. Read plainly, it is counter-evidence, not
  its dissolution.

  The real distinction is available but must be argued from flow structure, not from the copy-paste:
  the office skills share **leaf utilities** (a converter, a validator, schemas) while each owns its
  own end-to-end flow; the video-digest sources share the **entire** flow and differ only at the
  edges. The copy-paste establishes duplication and says nothing about pipeline structure, so it is
  demoted here to a footnoted observation rather than a proof.
- *One pipeline, N source variants → one skill with an internal routing table.* This is the
  structural match to acquire → transcript → research → synthesis. `skills/claude-api/SKILL.md`
  carries a `## Language Detection` dispatcher routing 8 languages to 8 per-language directories over
  a `shared/` core. `skill-creator` states the shape outright: *"Domain organization: When a skill
  supports multiple domains/frameworks, organize by variant"* — `cloud-deploy/SKILL.md` +
  `references/{aws,gcp,azure}.md` — *"Claude reads only the relevant reference file."*

**Two Claude Code mechanics independently penalize the sibling-skill shape:**

1. **Trigger-stealing.** The enterprise evaluation table asks *"Does adding this Skill degrade other
   Skills?"* with the named failure *"New Skill's description is too broad, stealing triggers from
   existing Skills"* and the remedy *"Consolidate overlapping Skills or narrow descriptions."*
2. **Listing-budget starvation.** *"When the listing overflows, Claude Code drops descriptions
   starting with the skills you invoke least."* A rarely-used `x-digest` sibling would lose exactly
   the keywords that route to it.

**A documented tension that must not be presented as resolved:** the enterprise guidance says to
*"start with narrow, workflow-specific Skills… consolidate related Skills into role-based bundles"*
(portfolio evolution, gated on evaluations confirming equivalent performance), while the spec treats
too-narrow as its own failure mode (one skill's boundary). Different objects; neither cites the
other.

**Skill-invokes-skill is not a documented contract.** The only official statement is a blog post
describing it as pre-native: *"This sort of dependency management is not natively built into
marketplaces or skills yet, but you can just reference other skills by name."* No
`dependency`/`requires`/`includes` frontmatter field exists — verified against the complete
frontmatter table. This forecloses a "thin `x-digest` that calls the real skill" design.

**No *named* multi-source-ingestion pattern exists in Claude Code's feature surfaces** — MEDIUM
confidence, deliberately narrower than the claim first recorded here.

The sweep covered the changelog (through v2.1.232), what's-new w23–w32, `features-overview.md`, and
`glossary.md`. Those establish that multi-source ingestion is not a named feature or glossary term —
a genuine negative. They do **not** establish that no pattern supersedes the shape, because a
*pattern* would be published in **guidance** (best-practices, `skill-creator`, the engineering blog),
not in a changelog or a glossary. **The sweep was aimed at the wrong surface class for the stronger
claim**, so the stronger claim is withdrawn and this is no longer treated as settled.

This also resolves an internal contradiction: the research elsewhere states the docs are **silent**
on multi-source ingestion and calls that *"a gap in the guidance, not a permission."* Silence cannot
simultaneously be a gap and a negative verdict. It is a gap.

Within that narrower scope, the supporting sweep still stands: Dynamic workflows are the only new
orchestration primitive and are ruled out here by three documented constraints (no mid-run user
input, no filesystem or shell access from the workflow itself, no module loading), and every
documented example is homogeneous fan-out rather than branching by input type. `context: fork` and
subagent `skills:` preload are the documented composition pair but **neither is a dispatcher**.
Behavioral corroboration: `context:`, `agent:`, and `skills:` appear **zero** times across all 18
`SKILL.md` files in `anthropics/skills`.

## Corrections and additions from this design pass

These refine inherited statements against the measured tree; they do not overturn any decision
above.

- **`run-watch.js` does not parse YouTube ids.** The handoff left this an open question. Measured:
  `run-watch.js` never calls `extractVideoId`; it takes `metadata.id` from yt-dlp
  (`run-watch.js:106,127`). The hard failure on non-YouTube URLs is one level down, at
  `acquisition/acquire.js:267`.
- **The slice-key invariant conflicts with current code.** `run-watch.js:105` derives the slug from
  `metadata.id`. For X that is the wrong id. Slice-key derivation must therefore become
  adapter-owned rather than a shared call on downloader metadata — a contract obligation the
  handoff's four design dimensions implied but did not state.
- **The `select-caption.js` "MANAGED surface" constraint is UNVERIFIED and must not be treated as
  binding until it is settled.** The handoff carried it as a hard constraint — *"`select-caption.js`
  is a MANAGED youtube-digest surface — the X caption fix is X-local rung classification, never an
  edit there. Editing it makes the change a managed-materialization edit, which the org convention
  forbids as the source of a change."* Searched for corroboration and found none:

  | Where | Result |
  |---|---|
  | `standards/distribution/sync-manifest.yml` | no `select-caption` or `youtube-digest` entry |
  | `melodic-software/standards` (whole repo) | zero matches for `select-caption` |
  | `claude-code-plugins` (whole repo) | matches only in this design slice's own files and the exploration lead list |
  | `select-caption.js` itself | no managed/generated/sync marker |

  Absence in those four places is not proof the file is unmanaged, but the burden has flipped: the
  constraint is an unsupported claim, not an established fact. **If it does not hold, the caption fix
  may be a direct edit to the ladder** — materially simpler than routing around it with an
  adapter-level override. T5 and part of T4's `classifyCaption` method both rest on it.

  **Resolve before T5 closes:** confirm or refute against `melodic-software/standards` governance
  directly. Recorded as thread T12.

- **A third seam exists that the handoff did not consider.**
  `plugins/knowledge/vendor/video-digestion/` (`@melodic/video-digestion`) is a shared package both
  skills already consume, with a declared joint-ownership rule. It is a live candidate home for the
  adapter contract and is evaluated as thread T1 rather than assumed away.
