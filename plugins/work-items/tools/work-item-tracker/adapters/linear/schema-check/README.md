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
bash fidelity.sh                  # every operation string must match the adapter VERBATIM
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

**`fidelity.sh`** proves the operations in `validate.mjs` are the adapter's own text rather than a
paraphrase of it, by extracting each one from the source and matching it as a fixed string. Without
this, the other two scripts could validate a tidied-up copy while the adapter shipped something
else. It is also the drift alarm: **if you change an operation in the adapter and do not change it
here, `fidelity.sh` fails** — which is the intended behaviour, not a nuisance. It caught exactly
that when the label lookup moved to the root `issueLabels` connection.

## Provenance

Schema source: `https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql`
— the file this adapter's own comments cite. The original run additionally cross-checked it against
the generated types inside `npm pack @linear/sdk` (90.0.0) and found them byte-identical, doc
strings included.
