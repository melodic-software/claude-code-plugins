# Posting the video

The video goes to the pull request through the user's own GitHub access; no new credential is
created for it. Post only after the QC and the independent review pass, including its check for
secrets, personal data and internal hosts in the frames. Record against fixture or test accounts so
the video carries none to begin with.

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
