---
description: "Node package a depends on b through file:../b, Go module c replaces example.com/foo with ../a, and a Gemfile sits at the root: dependency-graph.json reads result ok and ecosystem mixed with node and go nodes each carrying their own ecosystem and no Gemfile node, the a -> b edge cites the package.json declaration and the c -> a edge the go.mod replace line, the reply names the Gemfile as not read, and the collector never runs once per package nor is the record written or edited by hand. Needs --scaffold and --allow-tools Bash,Write,Edit."
tags: [architecture, map-dependencies, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/architecture/dependency-graph.json holds result ok, ecosystem mixed, a/package.json and b/package.json as node nodes and c/go.mod as a go node, no node from the Gemfile, an a/package.json -> b/package.json edge citing \"b\": \"file:../b\", and a c/go.mod -> a/go.mod edge citing the replace line. The reply names the Gemfile as not read. No dependency-graph.sh call targets a, b or c alone, and no Write or Edit targets the record."
---

/architecture:map-dependencies
