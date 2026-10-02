# model-adaptation chapters: contributor conventions

## Links only, no upstream text

A chapter stores no text from Anthropic's prompting guides, system cards or blog posts, quoted or
paraphrased. It states what this repository does differently on that model, in our own words, and
points at the exact upstream section for the reason, in the record shape the
[upstream-drift convention](../../../../docs/conventions/upstream-drift/README.md#required-parts)
defines: pointer, as-of date, recheck trigger.

Tested phrasing, such as a guide's effort steers or a length-calibration sentence, is not copied
into a chapter even where rewording might weaken it. The chapter names the trigger for using it
and links the section, and a reader who needs the exact words reads them there. The same holds for
a system-card finding: link the section rather than restate it, so no qualifier is dropped.

A blog post appears only as a `correlate with <blog link>` note beside a main-docs pointer. A
conflict between two pages is recorded only as "pages X and Y disagree on topic T", with both
links, the as-of date and a trigger.
