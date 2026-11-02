# Gauge in CI

How this plugin wires `gauge eval` into a CI gate.

## The command

```bash
gauge eval ./plugin \
  --trust-plugin \
  --pass-mark 0.8 \
  --agent-model <full agent model ID> \
  --judge-model <full judge model ID> \
  --keep-local \
  --spend-cap-usd 20
```

- Always pass `--trust-plugin`. Leave it out and a job on an untrusted checkout exits 1 when no
  terminal is attached, or hangs on the prompt when the runner provides one.
- Fix **both** model IDs, so that a model rollout does not look like a plugin regression and judge
  verdicts can be compared across runs. Use the full ID, not an alias, as the hub's CI record says.
  Revisit the pinned pair whenever the provider retires or renames a model, and log the change
  next to the trend so a jump in scores has a known cause.
- Use `--pass-mark 0.8` instead of the default (look it up under the Command options pointer,
  **Exit codes**). Requiring a perfect score on every case turns each random near-miss into a
  failed build, and then exit 1 no longer tells you anything.
- `--keep-local` keeps the HTML report on disk. It is one self-contained file that makes no
  network requests, so attach it to the job.
- `--spend-cap-usd` sets a hard spending limit for the job; prefer it to tight limits on each run.
- `gauge eval init` wants a terminal; in CI, start from a blank template with `init --bare <name>`.

## Exit codes

A pass or a fail is never read from the exit code alone.
