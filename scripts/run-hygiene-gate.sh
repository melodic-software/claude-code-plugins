#!/usr/bin/env bash
# Run one hygiene gate step's script and keep a copy of its output, so the
# aggregator at the foot of the job can say WHY a gate failed, not only that it
# did (scripts/aggregate-hygiene-results.sh).
#
#   shell: bash scripts/run-hygiene-gate.sh <check-name> {0}
#
# A `run:` gate step names this as its custom shell. The runner writes the
# step's `run:` body to a temporary file and passes its path at `{0}`. The
# body runs as `bash -e <file>`, the command the runner uses for a step with no
# `shell:` on Linux, so the gate's semantics and exit code are unchanged. Its
# combined stdout and stderr still reach the step log and are also written to
# <dir>/<check-name>.log, where <dir> is HYGIENE_OUTPUT_DIR, else
# $RUNNER_TEMP/hygiene. <check-name> is the gate's name in the job's
# CHECK_RESULTS feed, which is how the aggregator finds the file.
#
# Custom shell syntax, as of 2026-10-11 (recheck when a gate's capture file goes
# missing on a run): https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#custom-shell
#
# Capture is best effort. When the output file cannot be created the body
# still runs, uncaptured, with a warning, and the aggregator reports the gate
# with "no captured output".
set -u

if [[ $# -ne 2 || ! "$1" =~ ^[A-Za-z0-9._-]+$ || -z "$2" ]]; then
  echo "usage: $0 <check-name> <script-file>  (check-name: letters, digits, '.', '_', '-')" >&2
  exit 2
fi

check=$1
script=$2
dir=${HYGIENE_OUTPUT_DIR:-${RUNNER_TEMP:+$RUNNER_TEMP/hygiene}}
log=$dir/$check.log

# No shared-temp fallback: a fixed path under /tmp lets another local user
# pre-plant the log as a symlink.
if [[ -z "$dir" ]] || ! mkdir -p "$dir" 2>/dev/null || ! : >"$log" 2>/dev/null; then
  echo "::warning title=$check output not captured::Could not write $log; the aggregator will report this gate without its output."
  exec bash -e "$script"
fi

bash -e "$script" 2>&1 | tee "$log"
exit "${PIPESTATUS[0]}"
