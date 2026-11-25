# CI systems for `apply install-ci`

What the setup agent consults to write the comment lint's CI step in the repository's own system.
It holds our decisions and pointers to each vendor's live documentation; it holds no vendor
template, and no system here is a default. Read the vendor's pages at run time for every name the
step uses (variables, keywords, step syntax); never write one from memory.

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

## Vendors with a pointer

| System (scan id) | Step syntax | The change's head commit and target branch |
|---|---|---|
| `github-actions` | [Workflow syntax: `jobs.<job_id>.steps[*].run`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsrun) | [Contexts: `github` context](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context) |
| `azure-pipelines` | [YAML schema: steps.script](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-script#stepsscript-definition) | [Predefined variables: build variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables#build-variables-devops-services) |
| `gitlab-ci` | [CI/CD YAML syntax: `script`](https://docs.gitlab.com/ci/yaml/#script) | [Predefined variables for merge request pipelines](https://docs.gitlab.com/ci/variables/predefined_variables/#predefined-variables-for-merge-request-pipelines) |
| `jenkins` | [Pipeline syntax: declarative steps](https://www.jenkins.io/doc/book/pipeline/syntax/#declarative-steps) | [Multibranch: additional environment variables](https://www.jenkins.io/doc/book/pipeline/multibranch/#additional-environment-variables) |
| `circleci` | [Configuration reference: `run`](https://circleci.com/docs/reference/configuration-reference/#run) | [Built-in environment variables](https://circleci.com/docs/reference/variables/#built-in-environment-variables) |
| `bitbucket-pipelines` | [Step options](https://support.atlassian.com/bitbucket-cloud/docs/step-options/) | [Variables and secrets: default variables](https://support.atlassian.com/bitbucket-cloud/docs/variables-and-secrets/#Default-Variables) |

Every other system the scan names, and a pipeline configured outside the repository: find its
step-syntax and predefined-variables pages with `/discovery:research` (if enabled), otherwise ask
the user for them, then print the step and where it goes instead of writing it.
