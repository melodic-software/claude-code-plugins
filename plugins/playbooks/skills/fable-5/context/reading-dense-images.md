# Reading dense images

A dense chart, a technical drawing, a small-print screenshot, or a scanned table can be misread with full confidence: the answer comes back fluent whether or not the detail it depends on was legible. This note applies on every model; a model-adaptation chapter may add a per-model delta on top of it.

## A value you could not read is not a reading

- TRIGGER: your answer depends on fine detail in an image, such as a value read off an axis, a label in a crowded legend, a dimension on a drawing, or a cell in a scanned table; or you are building a harness or prompt that feeds such images to a model.
- RULE: a value you could not read reliably is recall-grade under the calibration chapter's "Two grades of knowledge". Say which regions you could not read and grade the value accordingly, rather than reporting a guess as a reading.
- RULE: before acting on the trigger, read your model's section at the pointers below.

> Weak: "The chart shows revenue peaking at 4.2M in Q3."
> Strong: "The Q3 bar looks highest, but its axis labels were too small to read at this resolution, so the value is unverified."

## Pointers

- **Pointer**: for visual inputs per model, see [Tools for complex visual inputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tools-for-complex-visual-inputs) (Sonnet 5.5), [Tools for complex visual inputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#tools-for-complex-visual-inputs) (Opus 5.5), and [Give vision work tools to crop and zoom](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#give-vision-work-tools-to-crop-and-zoom) (Fable 5.1); for image resolution, see [Image quality guidance](https://platform.claude.com/docs/en/build-with-claude/vision#image-quality-guidance); for a working tool definition, see the [crop tool recipe](https://platform.claude.com/cookbook/multimodal-crop-tool).
- **As of**: 2026-10-01
- **Recheck trigger**: any pointed section moving, or a model guide adding or dropping a section on visual inputs.
