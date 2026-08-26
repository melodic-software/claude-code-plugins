# Cluster: lane-telemetry-upsert

**Concept.** The inlined `gh api` upsert that a loop lane runs to maintain its ONE
marker-identified telemetry comment: marker construction, lane-instance validation, the
`LOOKUP()` pagination walk, the pre-write body gate, the PATCH, and the post-write read-back.

**Bucket.** N>=3 (three markdown reproductions). Highest-value cluster in this lane.

**Multiplicity evidence (Tier 0).** Maximal repeated-block detection found an 818-word
byte-identical shell block shared by two files and a 380-word block shared by three, plus five
further shared blocks of 43 to 137 words across the same three files:

- `plugins/source-control/skills/babysit-loop/reference/telemetry-upsert.md` (10980 bytes)
- `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md` (9258 bytes)
- `plugins/work-items/skills/attend-queue/SKILL.md:166-220` (inlined, not in a reference file)

Shared blocks, by first line and site:

| Words | First normalized line | Sites |
|---|---|---|
| 818 | `SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # $BODY_FILE MUST open with this line` | babysit-loop ref:38, work-loop ref:44 |
| 380 | same sentinel block, truncated | babysit-loop ref:38, work-loop ref:44, attend-queue SKILL:187 |
| 137 | `Creation race reconcile (encoded above). Two sessions racing the first-ever upsert can both` | babysit-loop ref:108, work-loop ref:125 |
| 96 | `something else: a mangled body, a concurrent overwrite, a deleted comment. It is also the half that` | all three |
| 96 | `write, and a failed verification all have to be carried forward: stderr does not survive the session` | all three |
| 84 | `[ -n "$INSTANCE" ] \|\| INSTANCE="$(hostname \| tr '[:upper:]' '[:lower:]' \| tr -c 'a-z0-9-' '-')"` | babysit-loop ref:24, work-loop ref:24 |
| 69 | `^[a-z0-9][a-z0-9-]{0,31}$ — empty, a leading hyphen, any other character, or` | babysit-loop ref:25, work-loop ref:25 |
| 64 | `skill ("Never pass a body as an @path string"). The floor is measured on everything below line 1` | all three |
| 55 | `Creation race reconcile (encoded above). Two sessions racing the first-ever upsert can both` | all three |
| 45 | `body gate, write check, and read-back (encoded above, #943). Three checks, because they catch` | all three |

## Why this is a defect and not the licensed inline pattern

This repo has a documented, working pattern for content that must be carried inline because an
installed plugin cannot reach a sibling plugin's files: declare the inline-floor rule, keep the
block byte-identical, and cite the owner for provenance only. `Rate-limit guard floor (inlined)`
does exactly that across the same three skills and is byte-identical at all three sites (see
`refused-deliberate-duplication.md`, cluster R6).

The telemetry upsert does not. Three things are missing:

1. **No declared owner.** None of the three files says which copy is canonical. The nearest
   authority, `plugins/claude-ops/skills/lanes/SKILL.md:249-300`, documents
   `scripts/telemetry-upsert.sh` and then licenses the inline form
   ("or through the `gh api` upsert a lane inlines, since an installed plugin cannot invoke a
   sibling plugin's script") without naming a canonical text for that inline form.
2. **No drift check.** `scripts/check-cross-plugin-source-drift.sh` clusters by path-within-plugin.
   These two reference files sit at `skills/babysit-loop/reference/telemetry-upsert.md` and
   `skills/work-loop/reference/telemetry-upsert.md`, different relative paths, so the script never
   clusters them and `scripts/cross-plugin-source-registry.txt` has no entry for them.
3. **They have already drifted.** Verified by direct diff this session.

## The drift, verbatim

`plugins/source-control/skills/babysit-loop/reference/telemetry-upsert.md:11`

> Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane type
> (#1295): a marker naming only the lane makes two concurrent instances resolve one comment and
> clobber each other's durable state. The id is `${user_config.lane_instance}`; a surviving literal
> `${user_config.…}` placeholder means the key is unset, so fall back to the sanitized lowercased
> hostname (headless-config floor: log the assumption).

`plugins/work-items/skills/work-loop/reference/telemetry-upsert.md:11`

> **Resolve the lane instance first (#1295).** The marker names the *writer*, not the lane type — per
> the convention's lane-instance identity rule. Resolution order matches
> `SKILL.md`'s invocation surface (cited from [invocation-argv.md](invocation-argv.md)): a supplied
> `--instance` token wins, else persisted `lane_instance` from the durable state block, else
> `${user_config.lane_instance}`; a surviving literal `${user_config.…}` placeholder means the key
> is unset, so fall back to the sanitized lowercased hostname (headless-config floor: log the
> assumption).

Consequences visible in the code blocks:

- `babysit-loop ref:23`: `INSTANCE="<lane-instance>"   # ${user_config.lane_instance}, else \`hostname\` sanitized`
- `work-loop ref:23`: `INSTANCE="<lane-instance>"   # --instance, else durable lane_instance, else ${user_config.lane_instance}, else \`hostname\` sanitized`

And a section present in one copy only:

`plugins/work-items/skills/work-loop/reference/telemetry-upsert.md:114`

> ## Gotcha — compound-shell classifier and isolated-calls fallback

The hostname-fallback paragraph also moved: it sits before the `MARKER=` assignment in the
babysit-loop copy and after it in the work-loop copy.

**Reader burden.** A maintainer changing the upsert cannot tell which of the three is authoritative,
and the two reference files now disagree about how many resolution rungs the lane instance has.
This is anti-pattern #11, the accidental branch of source-of-truth bifurcation.

**Stability.** A change to the upsert forces three lockstep edits today, four once any further lane
adopts it. Both branches of the stability plus reader-burden test pass.

## Remedy

`name-an-owner` plus `normalize-wording`. No new artifact: the concept already has an authority
(`plugins/claude-ops/skills/lanes/SKILL.md` "Never pass a body as an `@path` string" and
`scripts/telemetry-upsert.sh`), and the portability constraint means the operable text stays inline
at all three sites regardless. What is missing is a named canonical text and a guard, both of which
are in-place fixes.

### Step 1: name the owner

Declare `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md` canonical. It carries
the superset: the extra resolution rungs, the compound-shell gotcha section, and the
invocation-argv citation. Reducing it to the babysit-loop copy would lose content.

Add to `plugins/claude-ops/skills/lanes/SKILL.md`, immediately after the paragraph ending
`...since an installed plugin cannot invoke a sibling plugin's script.` (around line 285):

```text
The inlined form has one canonical text: `plugins/work-items/skills/work-loop/reference/telemetry-upsert.md`
in the marketplace repository. Every lane that inlines the upsert carries that text byte-identical
below its own lane-instance resolution order, and varies only the `MARKER=` value and the lane's own
resolution rungs. A second wording is a second contract.
```

### Step 2: replacement text per call site

**Call site A: `plugins/source-control/skills/babysit-loop/reference/telemetry-upsert.md`**

Replace lines 11 through 23 with the canonical resolution paragraph, with the babysit-loop lane's
own rungs substituted into the slot. Exact text:

```text
**Resolve the lane instance first (#1295).** The marker names the *writer*, not the lane type — per
the convention's lane-instance identity rule. The id is `${user_config.lane_instance}`; a surviving
literal `${user_config.…}` placeholder means the key is unset, so fall back to the sanitized
lowercased hostname (headless-config floor: log the assumption). It is operator-supplied text about
to be interpolated into a shell string and a `jq` program, so it is validated and **rejected**,
never sanitized-and-continued. Substitute the resolved value for `<lane-instance>` below; the check
runs **before** `MARKER` is built, because a lane that validates only in prose has documented a
guard that does not run:
```

Then move the hostname-fallback sentence to sit after the `MARKER=` assignment, matching the
canonical order, using the canonical wording:

```text
The hostname fallback is a *default*, not a sanitizer: the same gate validates it, so a hostname
that cannot produce a conforming id stops the lane rather than yielding a marker nobody chose.
```

Add the canonical `## Gotcha — compound-shell classifier and isolated-calls fallback` section
verbatim from the owner, since the same classifier applies to this lane's identically-shaped block.

Keep `MARKER="source-control:babysit-loop@$INSTANCE"` unchanged. That is the per-site slot.

**Call site B: `plugins/work-items/skills/attend-queue/SKILL.md:166-220`**

This site inlines the block into a SKILL body rather than a reference file, and already carries the
per-lane exception note at line 23 (`the \`#502\` telemetry upsert is an inlined \`gh api\` call`).
Two changes:

1. Add the provenance line immediately above the code block at line 176:

```text
The block below is inlined **verbatim** from the canonical text
(`plugins/work-items/skills/work-loop/reference/telemetry-upsert.md` in the marketplace repository),
cited for provenance only, since an installed plugin cannot read a sibling skill's files at runtime.
Only `MARKER` and this lane's resolution rungs vary.
```

1. Bring the prose around the block onto the canonical wording, same substitutions as call site A.
   Keep `MARKER="work-items:attend-queue@$INSTANCE"`.

**Call site C: the owner itself.** No text change. Add nothing.

### Step 3: register the guard

`scripts/cross-plugin-source-registry.txt` cannot hold these, because the drift script clusters by
path-within-plugin and these three sit at three different relative paths. Recommend a dedicated
check in the same family as `scripts/sync-standards-contract.sh`, asserting that the shared spine of
all three sites is byte-identical after slot substitution. Out of scope for a docs-hygiene sweep;
recorded here so the reconciliation can route it. `code-extract-advisory`.

## ROI

HIGH. Three files, a demonstrated live divergence in a security-relevant guard (the lane-instance
validation that prevents two concurrent lanes clobbering each other's durable state), and no
existing mechanism that would have caught it.

## Cross-lane observations

- The canonical text carries two em dashes: one in the resolution paragraph
  (`the lane type — per the convention's`) and one in the heading
  `## Gotcha — compound-shell classifier and isolated-calls fallback`. The replacement text above
  reproduces them so the three sites stay byte-identical. Both are house-style defects under
  `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`. They must be fixed **in the owner and
  all three sites in one edit**, not site by site, or the normalization is undone. Sequence that
  after this cluster, not before.
- No encapsulation violation. `attend-queue/SKILL.md` cites the loop-lane convention and
  `claude-ops`, both public surfaces. The proposed provenance line points at a sibling skill's
  `reference/` file, which is that skill's private body: L4 should confirm whether a
  provenance-only citation to a private path is permitted under the encapsulation contract, or
  whether the citation should name the `claude-ops` public surface instead. Flagging rather than
  deciding, since it is L4's call.
