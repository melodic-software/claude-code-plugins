# Reviewer Media Convention

When `/review:reviewer-media` builds a narrated walkthrough for a pull request, and the values it
hands the voice, the renderer and the pull-request `media` action. This file is the owner doc for
the `reviewer-media` cascade concern. The team layer is
[`reviewer-media.yaml`](reviewer-media.yaml), validated by
`plugins/review/schemas/reviewer-media.schema.json`.

## The policy

| `policy` | Media are built |
|---|---|
| `never` | never; the request label and a direct run are ignored |
| `on-request` (default) | when the request label is on the pull request, or a reader runs the skill on it |
| `when-selected` | as `on-request`, and when a ready pull request fires a [review-digest trigger](review-digest.md#the-triggers) |
| `always` | as `on-request`, and for every ready pull request |

`decide.mjs` applies these in order, the first match deciding:

1. `never` skips.
2. Media already showing the head commit are not rebuilt.
3. The request label or a direct run builds.
4. A pull request whose head is in a fork, or a fork since deleted, skips: its code is an outside
   contributor's, and building narrates it to an online voice and uploads its frames for good. A
   maintainer who adds the request label has looked at it.
5. `on-request` skips; so does a draft.
6. Media that show an older commit are rebuilt when the changes since that commit fire a
   review-digest trigger on their own; otherwise the section only gets its `Out of date` line.
   When git cannot measure those changes, the line is written and nothing is rebuilt.
7. `always` builds; `when-selected` builds when a trigger fires on the whole pull request.

A commit whose build already failed for good is refused by `media claim`
([media action](../../plugins/source-control/skills/pull-request/reference/media.md#failure)), so no
run builds on it again.

## The keys and their layers

| Key | Default | Use |
|---|---|---|
| `policy` | `on-request` | above |
| `labels.requested`, `labels.posted`, `labels.failed` | `reviewer-media: requested`, `reviewer-media: posted`, `reviewer-media: failed` | passed to the `media` action; `false` turns one off. Labels are created by the repository's label configuration, never by a skill |
| `voice_chain` | `[edge-tts, kokoro]` | `/speech:narrate --backend-chain` |
| `voices` | none | `--voice <backend>:<voice>` per entry |
| `voice_command` | none | team-only: the `command` backend's template, `{script}` in and `{out}` WAV out |
| `allow_unattended_paid_voice` | `false` | team-only: lets an unattended run use `openai` or `elevenlabs` |
| `ui_paths` | none | globs; a changed path matching one adds screenshot moments |
| `scan.extra_patterns` | none | Python regexes the secret and machine-data scan also refuses (a private codename, an internal host), passed as `--scan-pattern` to the renderer, the voice and the `media` action. While one does not compile, `decide.mjs` skips (reason `invalid-scan-pattern`, the pattern named in `warnings`) before claiming the head, so nothing is built without it and no commit is marked failed; the scans themselves also refuse it |
| `upload_limit_mb` | `10` | `stills.py --upload-limit-mb` |
| `artifact_retention_days` | `30` | the Actions artifact's retention and `media --retention-days`, 1 to 90 |

The stitcher and the frame stylesheet are `/explainer-video:produce` settings in its own team file.

Layers resolve per the [config-cascade convention](../contracts/config-cascade/README.md), a later
layer replacing an earlier one key by key:

1. defaults, above;
2. team: `docs/conventions/reviewer-media.yaml`, read from the pull request's base commit
   (`baseRefOid`), never the working tree, so a pull request cannot configure its own media. When
   that commit is not in the clone, the layer is skipped with a warning. An invalid value is named
   and the default stands;
3. personal override: `docs/conventions/reviewer-media.local.yaml`, applied only when untracked.
   It never sets a team-only key: one runs a command, the other spends money. Its
   `scan.extra_patterns` add to the team's list instead of replacing it, so it can only make the
   scan stricter.

An explicit `--policy` argument beats every layer.

## In GitHub Actions

`gh pr edit --attach` needs a signed-in user, so a workflow run hosts the media as an artifact. A
job that runs the skill (through Claude Code) on a pull request:

1. runs `/review:reviewer-media <pr> --handoff --out "$RUNNER_TEMP/reviewer-media"`, which claims
   the head with run id `$GITHUB_RUN_ID` and builds into that folder, then stops before posting
   because it is in Actions, printing the resolved `config`;
2. uploads the folder with `actions/upload-artifact`, `retention-days` set to
   `artifact_retention_days`;
3. runs `/source-control:pull-request media <pr> --manifest "$RUNNER_TEMP/reviewer-media/manifest.json" --run-id "$GITHUB_RUN_ID" --artifact-url <url> --retention-days <days> --no-attach`
   with `--label-requested`, `--label-posted` and `--label-failed` set from that `config`, one
   `--scan-pattern` per `scan.extra_patterns` entry,
   `<url>` being the upload step's `artifact-url` output.

The job needs `pull-requests: write` and `issues: write` (labels and the failure comment) and
`contents: read`. Inputs: the action's
[README](https://github.com/actions/upload-artifact#outputs) for its outputs, and
[the retention limits](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/storing-and-sharing-data-from-a-workflow#configuring-a-custom-artifact-retention-period).
