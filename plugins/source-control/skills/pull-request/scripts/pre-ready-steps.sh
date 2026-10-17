# shellcheck shell=bash
# The pre-flip steps of `/source-control:pull-request ready`, in run order: the
# one definition pre_ready (read-pre-ready.sh) and --skip (parse-ready-skip.sh,
# ready-skip-comment.sh) read. Sourced, never run.
# shellcheck disable=SC2034
PRE_READY_STEPS=(base-merge plan-evidence code-review security-review verify)
