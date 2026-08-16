# Source-adapter liveness lane (video-digest)

Owner doc for the **scheduled / offline-compatible liveness lane** that detects
upstream drift in the video-digest source adapters (YouTube + X). Tracker:
[#2797](https://github.com/melodic-software/claude-code-plugins/issues/2797).
Broader refactor record: `docs/adr/0012-dispatch-video-sources-through-a-static-adapter-registry.md`,
`docs/adr/0013-keep-storage-format-identifiers-stable-across-renames.md`, and the
knowledge plugin CHANGELOG 0.13.0 entry (the refactor that deferred this lane off
the merge path).

## Split from conformance

| Lane | When | Network | Gates merges? |
|---|---|---|---|
| Offline conformance (vitest + X goldens) | Every PR via `video-extraction` | No — fixtures only | Yes |
| This liveness lane | Weekly schedule + `workflow_dispatch` | Yes (yt-dlp live probes) | **Never** |

A red liveness run annotates the Actions job, writes a step summary, and uploads
the probe report as a workflow artifact. It does **not** open or update GitHub
issues (drain forbids filing). It is not wired into `ci.yml` / `ci-status`, so
it cannot block merges. Hermetic CI still exercises the harness: vitest covers
the classifier and offline fixture replay, and pull requests that touch the
liveness files re-run `--offline` only.

## What it probes

Manifest: `plugins/knowledge/skills/video-digest/extraction/liveness/probes.json`

| Probe id | Source | Live URL / fixture role |
|---|---|---|
| `youtube-canonical` | YouTube | Canonical example URL from the registry-conformance suite |
| `x-verified-public` | X | Phase 2/3 verified public status (`lispower1/1001551623938805763`) |
| `x-login-required-shape` | X | Auth-dependent shape; **skips** live when no cookies file is set |

Live mode compares extractor key, id / display_id, and format presence against
`expect.*`. When `extraction/adapters/registry.js` is present, each probe also
round-trips `resolveSourceAdapter` + `matchUrl`.

## How to run

```bash
# Hermetic (default) — fixtures only
node plugins/knowledge/skills/video-digest/extraction/liveness/run-source-liveness.js --offline

# Live — requires yt-dlp on PATH (floor 2026.6)
node plugins/knowledge/skills/video-digest/extraction/liveness/run-source-liveness.js --live
```

Optional cookies (secret holds Netscape cookie-jar **contents**; the workflow
materializes them to a temp file before probing):

- `VIDEO_DIGEST_YT_DLP_COOKIES_FILE`
- `YOUTUBE_YT_DLP_COOKIES_FILE`

Auth-required probes without cookies **skip**, never fail — X auth-fallback
windows are weeks-to-months volatile (Phase 2/3 design note).

## Workflow

`.github/workflows/video-digest-source-liveness.yml`

- `schedule` (weekly) + `workflow_dispatch` → live probes; on failure, annotate /
  summarize / upload `liveness-report.txt` only (never `gh issue create`).
- `pull_request` (paths scoped to the liveness files + this workflow) → offline
  self-test only.
- Not listed in `ci.yml` `ci-status` needs.

## Updating fixtures after intentional upstream change

1. Run `--live` locally (or from a dispatch) and capture the new metadata shape.
2. Update the matching file under `liveness/fixtures/` and any `expect.*` fields
   in `probes.json`.
3. Keep offline vitest green; ship the fixture refresh as the durable record of
   the new upstream shape.
