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

Callers run it with `if: always()` and `continue-on-error: true` after the leg, so a failed leg's
transcript is kept and an upload failure never changes the lane's outcome.

## Artifact

`lane-transcript-<job-id>-<run attempt>`, kept 7 days, holding one file,
`transcript.json.gz.sealed`. The file is one [`seal-lane-output`](../seal-lane-output/README.md#format)
record for the payload name `transcript.json.gz`, bound to `GITHUB_RUN_ID` and `job-id`; its
plaintext is the execution file, gzipped.

To open it, the puller takes the run id from the artifact's workflow run, the job id from the
artifact name (everything between `lane-transcript-` and the last `-`), and calls `openRecord` from
[`open-lane-output/open.mjs`](../open-lane-output/open.mjs) with the private key, the key id, the
payload name, the record, the run id and the job id, then gunzips the result. A record moved to
another run or job name does not open.

## Key setup

The private key lives only in Key Vault, read by the puller through `vault-exec`; CI never holds it.
Generate the pair offline with [`keygen.mjs`](../open-lane-output/keygen.mjs), which prints the
public line to stdout and writes the private key to the descriptor `--private-key-fd` names. From
the repository root, in bash or zsh:

```bash
{ node .github/actions/open-lane-output/keygen.mjs --private-key-fd 3 | gh variable set LANE_TRANSCRIPT_PUBLIC_KEY >/dev/null; } 3>&1 | <command that stores stdin as the Key Vault secret>
```

Use a key pair of its own, never the scan-carrier key: that one's private half is a CI environment
secret. To rotate, run the same line; artifacts sealed under the old key open only with the old
private key until they expire.
