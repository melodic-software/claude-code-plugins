---
bump: minor
---

### Added

- `/review:reviewer-media <pr>` builds a narrated walkthrough for a pull request's reviewers: it decides whether the pull request needs one, builds a storyboard from `/review:explain-change`'s digest, checks that every changed file appears in a moment, has `/explainer-video:produce` render it, and hands the manifest to `/source-control:pull-request media`. A build that fails twice records one failure for that commit.
- The `reviewer-media` convention (`docs/conventions/reviewer-media.yaml`, `schemas/reviewer-media.schema.json`): `policy` (`never`, `on-request` by default, `when-selected`, `always`), the three label names, the voice chain and voices, the upload limit and the artifact retention. The team file is read from the pull request's base commit only; `voice_command` and `allow_unattended_paid_voice` are team-only. A fork's pull request gets media only through the request label or a direct run, and posted media are rebuilt only when the changes since them cross a review-digest trigger.
- `/review:explain-change` names `/review:reviewer-media` under Related and Next.
