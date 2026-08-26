# Consume the knowledge corpus from a separate org-owned repository

- Status: accepted
- Date: 2026-07-13

## Decision

The `knowledge` plugin's ingest artifacts (transcripts, keyframes, source media, syntheses) get a
single dedicated consuming home rather than living in any one product repo, so a session can analyze
the whole corpus and fit relevant findings into *any* target repo. Decided with the owner in an
interview session against medley EPIC #1273 / wave-2 map #1369 (issue #1393); recorded here because
the wave's codification requirement puts convention decisions in tracked docs, not issue comments.

- **Repo:** `melodic-software/knowledge-corpus`, private, org-owned. Organization ownership was
  chosen because source media is retained and storage/bandwidth usage belongs with the shared corpus,
  not a personal account. Created pure-IaC via the `melodic-software/github-iac` governed registry
  (no ad-hoc `gh`, no import/drift window); the repo comes into being at the Pulumi deploy.
- **Media retention + LFS:** retain source video, keyframes, and any input useful for re-scraping or a
  fresh analysis — the corpus is the durable substrate for re-runnable synthesis, not just derived
  text. LFS-backed: a `.gitattributes` tracking media globs (mp4/mov/webm/png/jpg/jpeg/gif/pdf/epub/
  mp3/wav) plus pushed LFS objects. Git LFS is **not** expressible on the pulumi-github v6.14.0
  `Repository` resource → it is content-side, landing via a follow-up content PR to the repo, not
  governed in IaC. Basis: the provider schema at the pinned tag —
  <https://raw.githubusercontent.com/pulumi/pulumi-github/v6.14.0/provider/cmd/pulumi-resource-github/schema.json>,
  where `github:index/repository:Repository` declares 48 properties and 39 input properties, none
  matching `lfs`, and the document contains no case-insensitive `lfs` match at all (fetched and
  probed 2026-07-29; re-run the same fetch against the then-pinned tag when the trigger below fires).
  **Recheck trigger:** a pulumi-github
  release notes LFS support on `Repository`, or the pinned provider version moves past v6.14.0 →
  re-derive the IaC-vs-content-side call. GitHub's quotas, metering, and prices change;
  verify the current account allowance, budget, and overage behavior in the
  [official Git LFS billing documentation](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)
  before changing retention or ownership policy.
- **Artifact landing:** no consuming-repo name is baked into the plugin (contract v2.1 seam 1 + the
  convention-resolution ladder), so it serves any consumer unchanged. Which pipeline lands where — and
  which honor `library_dir` vs write elsewhere — is fast-moving plugin-seam state; the `knowledge`
  plugin's own skill docs are the SSOT, not recapped here.
- **Integration flow — first-class capability:** the value step is analyze-here → fit-into-any-target.
  Shape decided = a knowledge-plugin **`apply`/`integrate` skill** (a repeatable, invocable capability
  seam-consistent with contract v2.1), NOT a documented manual workflow (which would rely on operator
  memory and codify nothing). Full spec — target-repo scan, relevance ranking, how integrations are
  proposed/applied — is decomposed to a dedicated `design(knowledge-integration)` issue under #1369
  per the one-session sizing rule, rather than half-built inline.
- **Scope boundary:** the songwriting-corpus (Pat Pattison EPUBs) destination is owned by #1402, not
  decided here. How existing artifacts consolidate into this repo is operational — see #1393.
