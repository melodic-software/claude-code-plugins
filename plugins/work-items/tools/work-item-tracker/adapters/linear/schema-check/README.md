# Linear schema check

Validates every GraphQL operation this adapter sends against Linear's **real published schema**.

## Why this exists

Every test in this adapter runs against a mock transport whose responses the tests themselves
author. That catches logic errors and catches nothing about whether the operations are *valid* — a
wrong field name, argument, enum member or variable type passes the entire suite and fails on the
first real call. This adapter has never run against a live server, and
[#2946](https://github.com/melodic-software/claude-code-plugins/issues/2946) closed with its
live-conformance criterion **descoped**, with this check as the substitute evidence. It is
committed so that claim is reproducible rather than a one-off assertion in a closed issue.

It is not a replacement for a live run. It proves the requests are well-formed; it cannot prove
what the resolvers do with them. What remains unverifiable without a credential is recorded on
issue `#2946` — notably whether `assigneeId: null` semantically unassigns, and Linear's default
comment ordering.

## Running it

```bash
cd "$(git rev-parse --show-toplevel)/plugins/work-items/tools/work-item-tracker/adapters/linear/schema-check"
./fetch-schema.sh                 # ~1.2 MB SDL, fetched not vendored
npm install graphql               # or have graphql >= 17 resolvable
node validate.mjs                 # every operation must PASS
node negative.mjs                 # every deliberate fault must FAIL
bash fidelity.sh                  # every operation must match the adapter AND validate.mjs
```

## The three scripts, and why there are three

**`validate.mjs`** builds the SDL and runs `graphql.validate()` plus spec-compliant
`getVariableValues()` coercion over each operation. That checks field names, argument names and
types, nested selections, enum members, variable-position types, input-field names and
required-ness — by the reference implementation, not by reading.

**`negative.mjs`** is the control that makes a green run mean something. It feeds deliberately
broken variants — wrong field name, wrong mutation name, wrong argument, bogus enum member, wrong
variable type, missing required input field, bad `pageInfo` field — and **every one must fail**. A
validator that cannot fail is not evidence. When this was first run it caught 10 of 10.

**`fidelity.sh`** proves the operations `validate.mjs` checked are the adapter's own text rather
than a paraphrase, by matching each one as a fixed string against **both** sides — the adapter
source *and* `validate.mjs`. Both matter: checking only the adapter would prove the literal exists
somewhere while `validate.mjs` quietly validated a different, still-schema-valid query, and the
whole guarantee ("the thing validated IS the thing sent") would be worth nothing. Multi-line
operations are covered too, whitespace-normalized, since those are the ones an eyeball skips —
and so is `WIT_LINEAR_ISSUE_FIELDS`, the shared field-selection block that `fetch_issue`,
`list-items` and `list-sub-items` all interpolate rather than spelling out. That one was
previously extracted, printed, and compared to nothing, which left the three highest-traffic
reads resting on a human noticing a difference between two `echo` blocks. It is
also the drift alarm: **change an operation in the adapter and not here, and `fidelity.sh` fails**
— intended, not a nuisance. It caught exactly that when the label lookup moved to the root
`issueLabels` connection.

**All three exit non-zero on failure.** That is not decoration: a check that prints `FAIL` and
exits 0 is read as success by every caller, which is the same vacuous green this harness exists to
rule out. Verified by breaking each one deliberately — an invalid field in `validate.mjs`, a
neutered fault in `negative.mjs`, and a `validate.mjs` query that no longer matches the adapter —
and confirming each returns 1.

## Provenance

Schema source: `https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql`
— the file this adapter's own comments cite. The original run additionally cross-checked it against
the generated types inside `npm pack @linear/sdk` (90.0.0) and found them byte-identical, doc
strings included.
