# CI systems for `apply install-ci`

What the setup agent consults to write the comment lint's CI step in the repository's own system.
It holds our decisions only: no vendor template, no vendor link, and no system here is a default.
Read the system's documentation at run time for every name the step uses (variables, keywords,
step syntax); never write one from memory.

## What the step does, in any system

1. Runs on a change: a pull request, merge request or change-triggered build, not on every push to
   the default branch.
2. Has a clone holding the change's head commit, the target branch, and history back to their merge
   base. A shallow clone that stops short of the merge base makes the script exit 2.
3. Has `python3` with pygments importable on `PATH`, provided the way the repository's other jobs
   provide tools (a setup step, an image, a requirements or lock file they install).
4. Gets the script (below) and runs `bash <path>/comment-lint-ci.sh <head> <base>`, where `<head>`
   is the change's head commit and `<base>` the target branch's ref in the clone (such as
   `origin/<branch>`) or its commit id.
5. Fails the job on a non-zero exit. The script exits 0 while `comment_lint` is `off` or `report`,
   so the step blocks nothing until the team file sets `block`.

## Where the script comes from

In this order:

1. **The repository's committed hook copies.** After `apply install-git-hooks scope=shared` the
   script sits beside the hook entry under `.githooks/code-tidying/`, so the step runs it from the
   checkout with nothing to fetch.
2. **A fetch of the marketplace repository**, the `remote.git_url` in the plugin's
   `git-hooks/entries.json`, at a commit pinned the way the repository pins its other external
   dependencies, then `plugins/code-tidying/git-hooks/comment-lint-ci.sh` inside it.
3. **The plugin's own path**, in the marketplace repository itself.

The script and the lint run from the job's checkout, so a change that edits a committed copy runs
its edited copy. A repository that wants the base's copy runs it from a checkout of the base.

## Matching the repository

Write the step as the repository's existing jobs are written: the same pinning style, runners or
images, shell, caching, naming and job layout. Prefer adding a step to a job that already lints
changes and already has `python3`; otherwise add a job shaped like its siblings. When the CI job
runs a task-runner target for its checks (`runners` in the scan), the step can be a target there,
called from that job.

## The system's own documentation

The scan names each system by its id. Before drafting, read that system's current documentation
for two things: how a job step runs a shell command, and which predefined variables name the
change's head commit and its target branch. Find the pages with `/discovery:research` (if enabled),
otherwise search the vendor's own documentation site, and cite the pages you read beside the
proposal. This file links no vendor page: a stored link is one tool's documentation, which the
plugin philosophy's "No ecosystem-specific examples" rule keeps out of a shipped reference.

When the system's documentation cannot be found or read, or the pipeline is configured outside the
repository, print the step and where it goes instead of writing it.
