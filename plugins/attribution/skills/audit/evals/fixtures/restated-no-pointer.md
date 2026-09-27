# Widget Runner environment variables

A positive fixture: this restates an external product's reference material with no citation
anywhere in the file or its directory. Widget Runner is fictional; the point of the fixture is
the SHAPE of an unattributed restatement, not the content.

Widget Runner reads the following environment variables at startup. `WIDGET_CACHE_DIR` sets the
cache location and defaults to `.widget/cache` under the workspace root. `WIDGET_MAX_JOBS` caps
concurrent jobs and defaults to the core count. `WIDGET_LOG_LEVEL` accepts `error`, `warn`,
`info`, `debug`, and `trace`, defaulting to `info`. `WIDGET_TIMEOUT_MS` bounds a single job and
defaults to 300000. Setting `WIDGET_TIMEOUT_MS` to 0 disables the bound entirely, which the
runner warns about on startup but permits.

Variables are read once at startup. Changing one mid-run has no effect until the next
invocation.
