# Cluster: songwriting-shared-blocks

Two related clusters inside `plugins/songwriting`, reported together because they share the same
nine call sites and the same owner-reachability situation.

---

## Sub-cluster 1: `songwriting-persistence-block`

**Concept.** Where a songwriting skill writes generated files, and the project-level template
override precedence.

**Bucket.** N>=3 (nine instances).

**Owner (existing).**
`plugins/songwriting/context/pat-pattison/research/artifact-persistence.md`, headings
`## Where generated work persists` (line 7) and `## Template override` (line 30).

**Reachability: the owner IS reachable.** All nine sites are in the same plugin as the owner and
already link to it with a relative path that resolves inside an installed plugin. This is one of
the few clusters in the corpus where `trim-to-citation` is structurally available.

### Instances (Tier 0)

| Site | Body hash group |
|---|---|
| `plugins/songwriting/skills/diagnose/SKILL.md:77` | A |
| `plugins/songwriting/skills/meter-prosody/SKILL.md:65` | A |
| `plugins/songwriting/skills/object-writing/SKILL.md:121` | A |
| `plugins/songwriting/skills/rhyme/SKILL.md:55` | A |
| `plugins/songwriting/skills/song-form/SKILL.md:49` | A |
| `plugins/songwriting/skills/workflow/SKILL.md:116` | A |
| `plugins/songwriting/skills/co-write/SKILL.md:85` | B |
| `plugins/songwriting/skills/metaphor/SKILL.md:85` | C |
| `plugins/songwriting/skills/practice/SKILL.md:43` | D |

Group A, six files byte-identical (`plugins/songwriting/skills/rhyme/SKILL.md:57`):

> Write generated files to the paths in
> [artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
> consuming project's own songwriting layout when it defines one. Before loading any bundled
> `templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
> first, a project-level override wins over the bundled default.

Groups B, C, and D are group A plus one skill-specific sentence naming that skill's own output
directory. Verbatim, the varying sentences:

- `plugins/songwriting/skills/co-write/SKILL.md:89`
  > Line/section brainstorm output goes
  > to `variations/` or `worksheets/` as a labeled menu (not inline).
- `plugins/songwriting/skills/metaphor/SKILL.md:89`
  > Metaphor menus go to the song's
  > `worksheets/` as a labeled menu, not an inline dump.
- `plugins/songwriting/skills/practice/SKILL.md:45`
  > (daily practice
  > to `songwriting/practice/<YYYY>/<date>.md`)

`practice` additionally drops the word `songwriting` from `a consuming project's own songwriting
layout`, reading `a consuming project's own layout`. That is drift, not a slot.

### Verdict

Identify form (e): shared framing plus per-instance unique data. Stability test passes (a change to
the override precedence forces nine lockstep edits). Reader-burden test fails: every one of the
nine already links the owner in its first sentence, so a reader can tell what is canonical.

One branch of the combined test passes, so this is **WARN, borderline**, not a clean PROCEED.

### Remedy

`trim-to-citation` for the two-thirds of each block that is pure recap, keeping each site's own
output-directory sentence. **No new artifact.**

Replacement text for all nine sites. Group A files get exactly this; groups B, C, and D append
their own varying sentence unchanged after the first sentence.

```text
## Persistence and template overrides

Write generated files and resolve template overrides per
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md)
"Where generated work persists" and "Template override", and honor a consuming project's own
songwriting layout when it defines one.
```

Per-site additions, appended as a second sentence:

| Site | Appended text |
|---|---|
| `co-write:85` | `Line/section brainstorm output goes to \`variations/\` or \`worksheets/\` as a labeled menu, not inline.` |
| `metaphor:85` | `Metaphor menus go to the song's \`worksheets/\` as a labeled menu, not an inline dump.` |
| `practice:43` | `Daily practice goes to \`songwriting/practice/<YYYY>/<date>.md\`.` |
| the other six | none |

This removes the restated `templates/<name>.md` precedence rule from all nine sites, which is the
only part the owner fully governs and the only part that would need nine edits if the override path
ever changed.

**Before applying, confirm the owner is complete.** `artifact-persistence.md` is 2672 bytes and
already carries `## Template override`; verify at apply time that it states the
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` path explicitly. If it does
not, this becomes `edit-existing-rule` first: add the path to the owner, then trim the nine.

### ROI

MEDIUM. Nine files, three lines removed each, and the removed lines are the ones that would drift.

---

## Sub-cluster 2: `songwriting-author-seam`

**Concept.** That the bundled method content is Pat Pattison's, and that a future author's method
plugs in at `context/<author>/` without changing the skill.

**Bucket.** N>=3 (nine instances).

**Owner (existing).** `plugins/songwriting/README.md`, `## Method content and the author seam`
(line 27).

### Instances

`plugins/songwriting/skills/co-write/SKILL.md:37-39`,
`metaphor/SKILL.md:22-24`, `meter-prosody/SKILL.md:25-27`, `object-writing/SKILL.md:22-24`,
`practice/SKILL.md:22-24`, `rhyme/SKILL.md:23-25`, `song-form/SKILL.md:21-23`,
`workflow/SKILL.md:36-38`, `diagnose/SKILL.md:37-39`.

Verbatim (`plugins/songwriting/skills/rhyme/SKILL.md:23`):

> Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
> author's method plugs in at `context/<author>/` without changing this skill, the author seam per
> the plugin-root `../../README.md` "Method content and the author seam".

### Verdict: `REFUSE-already-cites-canonical`

All nine sites carry a correct citation in the exact form this skill's `context/citation-form.md`
prescribes: `per \`<file>\` "<exact heading text>"` with a one-line inline summary. This is
identify form (d), the desired state, and `verify` Gate 2 refuses it: 9 of 9 already cite.

The two clauses preceding the citation are the licensed one-line summary, not a recap of the
owner's body. Trimming them would leave a bare pointer.

No action. Rostered so the reconciliation can see it was examined and dismissed with evidence,
rather than missed.

---

## Out of scope, noted

`plugins/songwriting/context/pat-pattison/research/**` contains repeated passages across
`form.md`, `song-forms.md`, `song-forms-examples.md`, `hook.md`, `point-of-view.md`, `box-model.md`,
`verse-development.md`, `section-building.md`, `audit-checklist.md`, and `line-edit-rubric.md`
(twelve blocks of 20 to 124 words shared between pairs, e.g.
`form.md:1479` and `song-forms.md:1037` share a 124-word passage beginning
`Either I made up this name, or my friend Tom Frazee did. I don't remember`).

This is distilled external teaching material, not this repository's own authoring. The `identify`
survey scope excludes it on the same ground the vendor tree is excluded. **No findings raised.**

## Cross-lane observations

No encapsulation violations. Every citation in both sub-clusters targets a plugin-root README or a
sibling file inside the same plugin's own `context/` tree.
