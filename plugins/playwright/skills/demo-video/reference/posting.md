# Posting the video

In the local session and CI sections below, the video goes to the pull request through access
that already exists (the user's own `gh` login, or the workflow's token); no new credential is
created for it. The evidence step needs an identity of its own, described in its section. Post only after the quality control and the independent review pass, including its check for
secrets, personal data and internal hosts in the frames. Record against fixture or test accounts so
the video carries none to begin with.

## Verification evidence: call the evidence step

When the video is evidence for a verification run and `/source-control:pull-request evidence` is
among the available skills, post through it. The video is evidence when an `e2e-summary.json` or
`report.json` lists it in `publishable`: pass that listed path, which must resolve to the same
absolute path the run listed. The step attaches a video only when its frame-text sidecar
(`demo.mp4.txt`, the text every frame shows after masking) sits beside it and is not empty.

```text
/source-control:pull-request evidence <pr> --evidence <evidence file> --attach <listed video path>
```

In CI, upload the non-zipped artifact first (below) and add
`--artifact-url <artifact url> [--retention-days <n>]`, so the comment links it with its expiry.

That step owns the verdict gate, the leak scan, the one-comment rule and the `gh` attach checks,
and its report says whether the video was attached or left out. That call is the video's only
post: when it refuses or leaves the video out, report its reason and post the video no other way.

This route needs an identity that posts only evidence. The step edits the last comment of the
account `gh` runs as, so its one-comment check refuses when that account has any other comment on
the PR, and it expects a separate account with its own `GH_TOKEN`. The user's own login usually
fails that check once it has commented on the PR (review replies, an earlier demo). On that
refusal, report it and name the identity the step needs: an account that posts nothing on the PR
but the evidence comment, run through its own `GH_TOKEN`. Do not create that account or token
yourself.

When the step does not resolve, or the demo is one a person asked for outside verification, use
the sections below.

## Local session: attach inline with `gh`

`gh` uploads the file and the PR body or comment renders an inline player:

```bash
gh pr comment <pr> --body "Demo: <what it shows>" --attach <work>/demo.mp4
```

`--attach` also works on `gh pr create` and `gh pr edit` (an edit appends; the body is kept).
Check the installed `gh` first (`gh pr comment --help` lists `--attach`). When it does not, the
known-working form runs a newer `gh` through mise without changing the user's default:

```bash
mise exec gh@2.102.0 -- gh pr comment <pr> --body "Demo: <what it shows>" --attach <work>/demo.mp4
```

- **Pointer:** [gh v2.99.0 release notes](https://github.com/cli/cli/releases/tag/v2.99.0), the
  "Attach images and videos to issues and pull requests" section, and `gh help pr comment` for the
  current file limits.
- **As of:** 2026-10-04 (`--attach` first released in 2.99.0; probed working with 2.102.0 on a PR
  body, a PR comment and an edit, each rendering an inline video player).
- **Recheck trigger:** a `gh` release note that changes `--attach`, or a posted video that renders
  as a link instead of a player.

## CI: non-zipped artifact plus a link comment

A workflow has no user login to attach with. Upload the MP4 as a single-file, non-archived
artifact so the link opens the video rather than a zip, then comment the artifact link on the PR
with the workflow's token.

- **Pointer:** [actions/upload-artifact README](https://github.com/actions/upload-artifact#readme),
  the `archive` input (single file, no zip) and the `artifact-url` output.
- **As of:** 2026-10-04.
- **Recheck trigger:** a new major version of `actions/upload-artifact`, or the `archive` input
  changing.

Retention follows the repository's artifact retention setting; say in the comment that the link
expires with it.
