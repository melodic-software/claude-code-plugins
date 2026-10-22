# seal-lane-output

Seal named payload files to a committed X25519 public key, so a job that must not publish (one that
ran model or untrusted code) can hand them to a later job of the same run as job outputs that are
ciphertext only. The later job opens them with
[`open-lane-output`](../open-lane-output/README.md).

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `public-key-file` | required | The key file, relative to the workspace or absolute: one line, `x25519 <key id> <base64 raw key>`. Anything else, a placeholder included, fails the step |
| `payloads` | required | One `name=path` line per payload. The name is a lower-case file name (`reply.txt`) and becomes the file the opening job gets. A missing path or a symbolic link is an absent payload |
| `job-id` | required | The producing job's key, a fixed string; the opening job passes the same one |
| `max-chunks` | `6` | How many chunk outputs the caller maps, 1 to 6; a bundle needing more fails the step |

## Outputs

`sealed-length` is the bundle's base64 length, and `sealed-1` … `sealed-6` are its base64 text in
chunks of 98304 characters, each small enough for one environment variable. With no payload
present every output is empty. Map them to job outputs, never to `workflow_call` outputs, so no
caller echoes them. GitHub's limit on a job's outputs applies to them all together.

## Format

The bundle is, per payload: name length (1 byte), name, record length (4 bytes, big-endian), record.
A record is version `1` (1 byte), key id (8 bytes), ephemeral public key (32), nonce (12),
ciphertext, GCM tag (16). Each record takes a fresh ephemeral X25519 key and a random 96-bit nonce.
The AES-256-GCM key is HKDF-SHA256 over the shared secret, salt the ephemeral and recipient public
keys, info the binding below plus the header. The AAD is the header plus the binding:
`lane-output/v1`, the payload name, `GITHUB_RUN_ID` and `job-id`, each NUL-separated. The run attempt
is left out, so a re-run of only the opening job still opens. The key id is the first 16 hex digits
of the SHA-256 of the raw public key.

## Threat model

- The producing job holds only the public key: it can seal but never open.
- Ciphertext in logs or job outputs reveals nothing without the private key.
- One key pair per repository, its private key in one environment secret; never share it across an
  organization.

Key generation and rotation: [`open-lane-output`](../open-lane-output/README.md#key-generation).
