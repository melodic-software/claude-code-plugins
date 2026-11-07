#!/usr/bin/env bash
# Two tracked docs in different directories: docs/env/widget-env.md restates a fictional tool's
# environment variables with no citation in the file or its directory; notes/concurrency.md quotes
# the same tool's docs with the attribution beside each quotation.
set -euo pipefail

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
# The eval workspace sits inside the run's temporary home, itself a repository: allow only that one.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  tmp="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P || true)"
  if [[ "${top}" == "${here}" ]]; then
    echo "refusing to scaffold: ${here} is already a repository" >&2
    exit 3
  fi
  run="$(dirname "${tmp:-/}")"
  if [[ -z "${tmp}" || "$(basename "${tmp}")" != tmp || "$(basename "${run}")" != claude-eval-* || "${top}" != "${run}/home" || "${here}/" != "${top}/"* ]]; then
    echo "refusing to scaffold inside ${top}, a repository outside TMPDIR (${TMPDIR:-unset})" >&2
    exit 3
  fi
fi
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES

git init -q -b main .
mkdir -p docs/env notes
cat >docs/env/widget-env.md <<'MD'
# Widget Runner environment variables

Widget Runner reads the following environment variables at startup. `WIDGET_CACHE_DIR` sets the
cache location and defaults to `.widget/cache` under the workspace root. `WIDGET_MAX_JOBS` caps
concurrent jobs and defaults to the core count. `WIDGET_LOG_LEVEL` accepts `error`, `warn`,
`info`, `debug`, and `trace`, defaulting to `info`. `WIDGET_TIMEOUT_MS` bounds a single job and
defaults to 300000. Setting `WIDGET_TIMEOUT_MS` to 0 disables the bound entirely, which the
runner warns about on startup but permits.

Variables are read once at startup. Changing one mid-run has no effect until the next
invocation.
MD
cat >notes/concurrency.md <<'MD'
# Widget Runner concurrency, quoted

The upstream documentation is explicit about the default:

> Widget Runner executes one job per core by default, and refuses to oversubscribe unless
> `--force-parallel` is passed.
>
> Source: Widget Runner docs, `https://example.invalid/widget-runner/docs/concurrency`, read 2026-08-20

We accept that default. Our agents are memory-bound rather than CPU-bound, so oversubscribing
would trade a small wall-clock gain for eviction churn we have measured as worse.

The docs also note, inline, that "`--force-parallel` is unsupported on Windows"
(`https://example.invalid/widget-runner/docs/concurrency`, read 2026-08-20), which is why our
Windows lane never sets it.
MD
printf '.work/\n' >.gitignore
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
