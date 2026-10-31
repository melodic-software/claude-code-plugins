---
description: "Ported from plugins/knowledge/skills/course-digest/evals/evals.json id 1 (identical at base). Written from MB:plugins/knowledge/skills/course-digest/SKILL.md:176-180,195,263-265 and MB:plugins/knowledge/skills/course-digest/context/storage-schema.md:3. Covers lost sentences 48 and 49 (course directory courses/<platform>/<slug>/ under the library root); 54 only as far as status reads course.json there. Status is a read-only inventory: two scaffolded courses at ./courses/<platform>/<slug>/course.json, one with every phase marker set and one stopped after extract, are reported by slug with the right completion state, with no extraction script, Playwright, Write, or Edit. Visibility: status skips the check at head and base has none; the scaffold runs git init with no remote (local) so the session root is the working directory. library_dir defaults to '.' in both versions (plugin.json), so both read the courses here; a base run that instead looks only in plugin data finds nothing and fails the state graders"
tags: [knowledge, course-digest, outcome, scaffold, read-only]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply lists tdd-csharp-ferreira as complete (every phase marker set) and event-driven-dotnet-quill as in progress (stopped after extract, frames onward not started). No Bash call runs an extraction script, run.mjs, or Playwright; no Write or Edit call."
---

/knowledge:course-digest status
