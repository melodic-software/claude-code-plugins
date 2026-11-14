# Host reviewer media by attachment, else an Actions artifact, else nothing

- Status: accepted
- Date: 2026-11-13
- Refs: owner decisions of 2026-11-13 (Q22, Q35, Q49, Q59, Q75, Q84; design thread T7);
  [ADR 0056](0056-verify-ui-with-linux-side-playwright-and-attach-produced-demo-evidence-to-prs.md)
  (attach route)

## Context

Reviewer media must appear in the pull request description without billing the owner and without
cutting content or quality to fit a size limit. `gh pr edit --attach` uploads with the user's token;
on a public repository the upload is permanent. `gh` has no artifact upload: an Actions artifact
exists only from a workflow's upload step.

## Decision

`source-control:pull-request` hosts the media, trying in order:

1. **`gh pr edit --attach`** with the user token on github.com.
2. **Else, inside a GitHub Actions run only, an Actions artifact** uploaded by the workflow, linked
   with its expiry date; retention 30 days by default, never above 90.
3. **Else nothing is posted,** with the reason reported.

A video is encoded once at the visible-quality profile and never recompressed or cut to fit. Over the
upload limit, it goes to the artifact inside Actions, or is split at chapter boundaries locally.

The media sit between `<!-- reviewer-media:start -->` and `<!-- reviewer-media:end -->`; nothing
outside the markers is rewritten.

### One-way doors

An attachment on a public repository cannot be deleted; the scan floor runs before every upload
([ADR 0107](0107-scan-every-media-upload-and-online-voice-request-against-a-fixed-floor.md)).

## Considered options

- **Secure blob storage.** Deferred: a new service and a possible bill.
- **Per-PR temporary branches holding the media.** Rejected.
- **Actions artifact from a local session.** Rejected: no upload path exists outside a workflow.
- **A CRF size chain gated by a legibility check.** Rejected: about 19% smaller in measurement, and
  the gate rested on one frame.

## Consequences

- Local sessions without attach rights post nothing rather than a degraded video.

## Revisit triggers

- GitHub ships an artifact upload API usable with a user token.
- Videos over the upload limit become common.
