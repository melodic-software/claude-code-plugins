# Discovery output and link map formats (`discovery-output/v1`, `link-map/v1`)

Owner doc for the corpus mapper's discovery layer: the deterministic URL extraction
(`parse_discovery.py`) and the classified link map the user approves before any bulk fetch
(`check_linkmap.py` gates it).

The same denominator discipline as the node manifest, one layer up: the set of URLs that MUST be
classified is produced by a script over immutable discovery snapshots, never by an agent's recall
of what it saw. An agent classifies; it does not get to choose what needs classifying.

## Discovery ladder (V1: rungs 1–2 only)

1. **Rung 1 — `llms.txt`**: fetch `<origin>/llms.txt` (and `llms-full.txt` when the profile or
   user says so), snapshot it into the slice under `discovery/`.
2. **Rung 2 — sitemap**: fetch the site's sitemap (`sitemap.xml`, `sitemap.md`, or a
   robots.txt-declared location), snapshot likewise.
3. **Rung 3 — in-page link extraction: NOT IN V1.** Deferred and USER-RESERVED: reaching it
   requires either a presence-gated `/firecrawl:firecrawl map` seam or a recorded reason to
   reimplement. The trigger is the first corpus whose seeds resolve neither an
   `llms.txt` nor a sitemap. Until then a corpus with neither artifact stops loudly at discovery.

Fetching is the skill's job (WebFetch/curl per the skill's own text, channel recorded); parsing
the snapshots is `parse_discovery.py`'s job and is deterministic: same snapshot bytes, same
output bytes.

## `discovery-output/v1` (per snapshot; emitted by `parse_discovery.py`)

```json
{
  "schema": "discovery-output/v1",
  "rung": "llms-txt",
  "snapshot": {"basename": "llms.txt", "sha256": "<hex64>", "byte_length": 1234},
  "base_url": "https://agent-plugins.org/",
  "url_count": 13,
  "urls": ["https://agent-plugins.org/", "https://agent-plugins.org/spec"]
}
```

- `rung` — `llms-txt` | `sitemap-xml` | `sitemap-md`.
- `base_url` — the URL the snapshot was fetched from, supplied by the caller; relative links
  resolve against it.
- `urls` — normalized (see below), deduplicated, sorted lexicographically. Sorting is part of the
  determinism contract.

URL normalization (mirrors `docpage-digest`'s canonical-URL rules, minus the redirect step a
offline script cannot take): scheme+host lowercased, fragment dropped, tracking-only query
params dropped (`utm_*`, `gclid`, `fbclid`) with content-selecting params kept, trailing slash
dropped (a bare root normalizes to the origin with no slash, so `https://x.org/` and
`https://x.org` are one URL). Redirect resolution happens at fetch time and updates the link map,
not the discovery output.

Only `http`/`https` URLs are emitted; `mailto:`, `tel:`, `javascript:` etc. are not resources.

**URL identity has one owner:** `normalize_url` in `parse_discovery.py`. Seeds and any
hand-added URL must pass through `parse_discovery.py --normalize-url <url>` before entering the
link map; the gate rejects any seed or row URL that differs from its normalized form, so one
resource cannot enter the map under two spellings. (Known, disclosed approximation vs
`docpage-digest`'s slug rule: the normalizer re-encodes query strings — `%20`/`+` unify,
`?flag` becomes `?flag=` — where the per-page skill hashes the URL string as handed. The mapper
is the sole producer of queue URLs, so identity is stable within mapper-driven runs; only a slice
digested stand-alone earlier under a different spelling would not resume.)

**Sitemap index files:** a `<sitemapindex>`'s `<loc>` entries are child SITEMAPS, not pages. The
skill must fetch each child sitemap as an additional rung-2 snapshot and parse it too; the child
`.xml` URLs themselves are then classified `ignore` (reason: sitemap index member) in the map.
Skipping the child fetch under-discovers with a clean-looking gate — the gate cannot see URLs
nobody parsed.

## `link-map/v1` (one per corpus slice; agent-authored, gate-checked, user-approved)

```json
{
  "schema": "link-map/v1",
  "topic": "agent-plugins spec corpus",
  "seeds": ["https://agent-plugins.org"],
  "bounds": {"max_resources": 30},
  "rows": [
    {
      "url": "https://agent-plugins.org/spec",
      "rungs": ["seed", "llms-txt", "sitemap-md"],
      "classification": "in-corpus",
      "reason": "The spec itself; the corpus exists for it."
    }
  ]
}
```

- `seeds` — the user-supplied starting URLs, normalized. Every seed must appear as a row.
- `bounds` — declared before approval; V1 requires `max_resources` (a positive integer): the
  maximum number of `in-corpus` rows the run may fetch and digest. Optional `notes` string.
- `rows` — exactly one row per distinct URL across seeds + every discovery output. Each row:
  - `url` — normalized URL.
  - `rungs` — non-empty subset of `seed` | `llms-txt` | `sitemap-xml` | `sitemap-md`, the
    provenance of every appearance. (`in-page` joins this enum only when the deferred rung-3
    decision above is made.)
  - `classification` — exactly one of:
    - `in-corpus` — fetched, snapshotted, node-extracted, inventoried, queued for digestion.
    - `companion` — same corpus context but a different ingest type (e.g. a repo, a video);
      recorded for the interview, not fetched by this run.
    - `referenced-external` — cited by the corpus but outside it; recorded as a citation target.
    - `ignore` — noise (pagination, feeds, login, duplicates by content); reason required.
  - `reason` — non-empty for every row (one line; the approval gate is only meaningful if each
    classification is argued).

## Gate contract (`check_linkmap.py`)

Inputs: the link map and every discovery-output JSON for the slice (at least one is required —
a map with no discovery basis cannot demonstrate coverage; a corpus consisting solely of
resource seeds, with no origin seed and so no discovery output, is outside V1 gate scope — the
same recorded deferral as the repo-tree enumeration rung). Checks:

1. All inputs parse (duplicate JSON keys rejected at any depth); unknown or missing keys rejected
   in the link map, its rows, AND each discovery output; schema literals exact; seeds and row
   URLs must be in normalized form. Failures name the file/row; exit 2 for unusable input.
2. **Classification coverage** — this gate's reason to exist: every URL in every discovery output
   and every seed has exactly one row; every row's URL traces back to at least one discovery
   output or the seed list (no phantom rows); every row carries a valid classification and
   non-empty reason;
   every row's `rungs` match where the URL actually appeared, exactly.
3. **Bounds**: `in-corpus` row count ≤ `bounds.max_resources`, else a named failure — the
   bound-breach stop that forces the run back to the user.
4. A clean run prints what it exercised (files, row/URL counts, per-classification tally).

Exit codes: 0 pass; 1 named check failures; 2 unusable input; 3 internal gate bug.

## What approval means

The user approves the LINK MAP (classifications + bounds), not raw discovery. After approval the
map is frozen for the run; a later discovery change (re-fetch finds new URLs) reopens approval —
rows never appear or change classification silently. The approved queue handed to
`/knowledge:docpage-digest` is exactly the `in-corpus` rows, in map order.
