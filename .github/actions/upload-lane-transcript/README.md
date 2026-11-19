# upload-lane-transcript

Keep one lane leg's transcript for 7 days as an encrypted artifact, so a puller outside CI can copy
it to a private sink. CI holds only the public key: it can seal a transcript but never open one.
This repository is public, so its artifacts are too; only ciphertext is uploaded.

## Inputs

| Input | Meaning |
|---|---|
| `execution-file` | The leg's execution file: run-claude-cli's `execution-file` or claude-code-action's `execution_file` output. Empty, missing, empty-file or a symbolic link uploads nothing |
| `public-key` | `${{ vars.LANE_TRANSCRIPT_PUBLIC_KEY }}`, one line `x25519 <key id> <base64 raw key>`. Empty skips with a notice; anything else that is not a key line fails the step |
| `job-id` | A fixed key for the leg, unique in the run, matching `^[A-Za-z_][A-Za-z0-9_-]{0,99}$` |
| `otel-file` | Optional: run-claude-cli's `otel-file` output, from a leg run with `otel-receiver: "true"`. Empty uploads the transcript alone |

Callers run it with `if: always()` and `continue-on-error: true` after the leg, so a failed leg's
transcript is kept and an upload failure never changes the lane's outcome.

## Artifact

`lane-transcript-<job-id>-<run attempt>`, kept 7 days, holding one file,
`transcript.json.gz.sealed`. The file is one [`seal-lane-output`](../seal-lane-output/README.md#format)
record for the payload name `transcript.json.gz`, bound to `GITHUB_RUN_ID` and `job-id`; its
plaintext is the execution file, gzipped.

With `otel-file`, the artifact also holds `otel.jsonl.gz.sealed`: the leg's OTLP/JSON traces and
logs, scanned on their own after the transcript is sealed, then sealed the same way under the payload
name `otel.jsonl.gz`. Telemetry that fails its scan, cannot be sealed, or would take the artifact past
the puller's 64 MiB limit is left out with an annotation; the transcript still uploads.

The [transcript puller](../../../scripts/lane-transcripts/README.md) opens it: it takes the run id
from the artifact's workflow run and the job id from the artifact name (everything between
`lane-transcript-` and the last `-`), opens the record with `openRecord` from
[`open-lane-output/open.mjs`](../open-lane-output/open.mjs), and keeps the gzip. A record moved to
another run or job name does not open.

## Key setup

The private key lives only in Key Vault, read by the puller through `vault-exec`; CI never holds it.
Use a key pair of its own, never the scan-carrier key: that one's private half is a CI environment
secret. The puller's [key setup](../../../scripts/lane-transcripts/README.md#key-setup) has the
line that generates the pair with [`keygen.mjs`](../open-lane-output/keygen.mjs), sets this
variable and stores the private key.
