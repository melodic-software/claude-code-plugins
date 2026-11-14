---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the recorded sources first and says none hold a rule or paved path. Derives the request-handler building block from the five handlers, reproduces it against the cited files, and presents it as a proposed rule with its instances, its kind and its route (a paved-path entry to /discipline:reuse-or-replace). It asks which proposals to record and, with no yes given, writes no file and invokes no other skill.'
---

/architecture:improve conventions. The repository has no paved-path index and no recorded boundary rules. Under src/Orders/Handlers there are five classes, each implementing IRequestHandler<TRequest> and registered in src/Orders/Startup.cs. Show me what conventions you find; I have not decided which to keep yet.
