# open-lane-output

Open the bundle [`seal-lane-output`](../seal-lane-output/README.md) made in an earlier job of the
same workflow run, with the recipient's X25519 private key, into one file per payload under a
directory the caller names.

## Inputs

| Input | Meaning |
|---|---|
| `private-key` | The private key, base64 PKCS#8 DER as `keygen.mjs` writes it. Pass a secret through `with:`; the action reads it in its one step's `env:` and nowhere else |
| `expected-key-ids` | The key ids a record may name, whitespace-separated: normally the second field of the committed public key file |
| `job-id` | The producing job's key, the same fixed string the seal step passed |
| `max-bytes` | One `name=bytes` line per payload name that may open, with its plaintext cap |
| `directory` | An absolute path, missing or empty, outside the workspace (for example under `runner.temp`) |
| `sealed-length`, `sealed-1` … `sealed-6` | The seal step's outputs, as the producing job mapped them |

The key is checked first: an empty or malformed key fails, even with nothing sealed. With no
`sealed-length` and no chunk, nothing opens and the directory is made empty.

In a reusable workflow, declare the key under `on.workflow_call.secrets` and have each caller pass
the environment secret by name (never `secrets: inherit`): GitHub hands an environment secret to a
reusable workflow only when the caller passes it, and gives the environment's value only to the job
that names the environment.

## Outputs

`opened`: the payload names opened, space-separated. The plaintext is only in the files; the action
never prints it, sets it as an output, writes it to `GITHUB_ENV` or masks anything derived from it.

## Refusals

Every refusal is one `::error::` line naming a kind, never a value, and writes no file: every
record is checked and decrypted in memory before the first file is written. The checks run in this
order: the key, the size of the ciphertext as it arrived, then each record's framing and header,
then its GCM tag, which also authenticates the AAD (the header, payload name, run id and job id).

- `no-key`: one fixed message, `the private key is missing or malformed; no payload opened`.
- `too-large`: the sealed text over six chunks of 98304 characters, or one chunk over 98304,
  refused before any decode; or a record whose plaintext is over its name's cap, refused before
  decryption.

- `output-withheld`: a chunk the length says is there arrived empty, which is how the runner drops an
  output it judges may hold a secret. The message ends with `rotate this credential`.
- `sealed-mismatch`: a wrong private key, a failed GCM tag, a truncated bundle or record, an unknown
  key id, a bad version, a record sealed for another run, job or payload name, a name not in
  `max-bytes`, or a chunk of the wrong length. No rotation line.
- `bad-input`: an input other than the key is unusable.

A record re-read at another run attempt of the same run opens, so re-running a failed job works.

## Threat model

- The producing job holds only the public key: it can seal but never open.
- Ciphertext in logs or job outputs reveals nothing without the private key.
- One key pair per repository, its private key in one environment secret; never share it across an
  organization.

## Setup order

Set up the opening job's environment in this order, from the repository root (`gh api` fills in
`{owner}/{repo}` from the current repository; `$ENVIRONMENT` is the environment the opening job
names):

1. Create the environment, with custom deployment branch policies:

   ```bash
   gh api -X PUT "repos/{owner}/{repo}/environments/$ENVIRONMENT" -F 'deployment_branch_policy[protected_branches]=false' -F 'deployment_branch_policy[custom_branch_policies]=true'
   ```

2. Admit the default branch only (here `main`):

   ```bash
   gh api -X POST "repos/{owner}/{repo}/environments/$ENVIRONMENT/deployment-branch-policies" -f name=main -f type=branch
   ```

3. Only then set the private key on it, with the [key generation](#key-generation) line.
4. Rerun the shadow check described under key generation.

The order matters: a secret set before the branch policy reaches a job dispatched from any branch,
and that branch's modified copy of the workflow could print it.

## Key generation

The owner runs `keygen.mjs` offline, never on a runner. It prints the public key file's one line,
`x25519 <key id> <base64 raw key>`, to stdout and writes the private key to the file descriptor
`--private-key-fd` names (3 or above), so it goes straight into the secret store and never to disk.
From the repository root, in bash or zsh:

```bash
{ node .github/actions/open-lane-output/keygen.mjs --private-key-fd 3 >"$PUBLIC_KEY_FILE"; } 3>&1 | gh secret set "$SECRET_NAME" --env "$ENVIRONMENT"
```

Inside the braces stdout goes to the key file; outside them `3>&1` sends descriptor 3 into the pipe.
Keep the braces: zsh's default `MULTIOS` would send a bare `>file | ...` stdout to both the file and
the pipe, appending the public line to the secret. Commit the key file; the secret lives only in the
environment, which the opening job names.

Then check that no repository-level or organization-level secret shares the environment secret's
name: outside the opening job a caller's by-name pass resolves to that one. A repository may ship a
check for it; this one's is `scripts/check-scan-carrier-secret-shadow.sh <owner/repo>` (exit 0
none, 1 one exists, 2 a listing it cannot read). It reads secret names only.

## Rotation

1. Confirm the environment still admits the default branch only (setup steps 1 and 2), then run
   the key generation line above. It replaces the secret and rewrites the public key file. Run
   the shadow check after it.
2. Merge the new public key file at once. A run that sealed under the old key and opens under the
   new secret fails closed (`sealed-mismatch`, unknown key id or wrong key, no rotation line);
   re-run it after the merge.
3. Nothing old remains to drop: the replaced secret is gone, and a sealed bundle lives only as
   long as its run's job outputs.

Rotate on an `output-withheld` refusal, or whenever the private key may have been exposed.
