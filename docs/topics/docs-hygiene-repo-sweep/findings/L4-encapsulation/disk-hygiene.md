# L4 encapsulation. Leaked skills in `plugins/disk-hygiene`

2 violations, both from the plugin README into `disk-hygiene:clean`. One of the two is a heading
anchor, which is private at any depth.

**Owning skill:** `disk-hygiene:clean` (`plugins/disk-hygiene/skills/clean/`).
**Private surface reached:** `reference/safety-model.md`, and one anchor inside it.
**Citing file:** `plugins/disk-hygiene/README.md`. A plugin README is an external consumer under the
contract: it is not carried when the skill directory is ripped and pasted, and READMEs are named
explicitly among the consumers the contract binds.

## V-dh-01. `plugins/disk-hygiene/README.md:190`, heading-anchor cite

**Leak kind:** heading anchor.

Verbatim:

```text
  [safety model](skills/clean/reference/safety-model.md#standalone-git-checkout-evidence) pass.
```

The anchor `#standalone-git-checkout-evidence` binds the README to a heading string inside a private
reference file. Renaming that heading, which the skill author is free to do at any time, breaks the
link with nothing failing.

**Public surface element:** `/disk-hygiene:clean`. The README is describing a safety check the skill
performs before deleting anything, which is behavior.

**Replacement text:**

```text
  `/disk-hygiene:clean`'s standalone-git-checkout evidence pass.
```

## V-dh-02. `plugins/disk-hygiene/README.md:280`

**Leak kind:** private subdir.

Verbatim:

```text
  destructive surface, never widen it (see [the safety model](skills/clean/reference/safety-model.md)
```

**Public surface element:** `/disk-hygiene:clean`.

**Replacement text:**

```text
  destructive surface, never widen it (`/disk-hygiene:clean` carries the safety model)
```

## Judgment note

Both cites are the same shape as most plugin-README leaks in this lane: the README wants to describe
a safety property so a reader trusts the plugin, and reaches for the file that states it. Nothing
about the safety model is cross-plugin shared vocabulary, so **Path A. promote** is the wrong
remedy here. Path B. route is correct: the reader wants to know that `/disk-hygiene:clean` refuses
to widen its destructive surface, not to read the skill's internal reasoning.

## Cross-lane observations

- L8 (write-for-humans): `plugins/disk-hygiene/README.md` is a HUMAN-audience file. Both replacements
  keep the sentence readable without the link; the L8 editor should check that the sentence still
  reads as prose after the citation is removed.
