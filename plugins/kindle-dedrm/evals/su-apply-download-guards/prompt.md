---
description: "Legacy setup apply-download-preserves-fallback-guards-by-reference. apply download runs only Step 1 of manage/reference/workflow.md (setup/SKILL.md lines 64-76): in the sandbox gh has no network, so the DeDRM_tools tag falls back to the pinned tag read from reference/versions.md, and no command may carry the PINNED_TAG_FROM_VERSIONS_MD placeholder or an empty tag into a release URL. The run stays in the download step (no unzip, installer, firewall or ICACLS command), and since nothing can be fetched, the reply must not claim any artifact downloaded or SHA256-verified. pinned-tag-fallback accepts a literal vN.N.N tag in the release URL or assigned to LATEST_TAG, so it holds across re-pins. Unmeasured: the stop on a SHA256 mismatch (no artifact arrives) and the Key_Finder empty-match stop (versions.md always yields the pinned URL); the setup hub says that URL comes from the tutorial article while workflow.md reads the pin from versions.md, so neither source is graded. Slash-invoked (disable-model-invocation), so there is no Skill grader. Needs --allow-tools Bash; the downloads write through curl, so the case grants no Write or Edit."
tags: [kindle-dedrm, setup, outcome, apply, download, no-network]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The run attempts the three downloads with the DeDRM_tools tag taken from the pin in reference/versions.md, since gh cannot answer, and never composes a release URL with the PINNED_TAG_FROM_VERSIONS_MD placeholder or an empty tag. It runs no unzip, installer, firewall or ICACLS command. The downloads fail without network, and the reply says so and says nothing was SHA256-verified, rather than reporting the artifacts as downloaded or verified."
---

/kindle-dedrm:setup apply download

Run the download step here, in this session; I'll copy the three files to my Windows PC myself afterwards.
