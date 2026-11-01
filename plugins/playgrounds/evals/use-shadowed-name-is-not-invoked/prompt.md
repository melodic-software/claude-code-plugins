---
tags: ['use', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Notices the listed playground skill does not describe an interactive-explorer builder and says a local shadow is likely; then, if the install record confirms playground@claude-plugins-official, warns about the shadow and invokes the namespaced playground:playground form, and only without that install record takes the install/guidance path. The shadowing skill itself is never invoked.'
description: 'Narration case: it assumes an install record for playground@claude-plugins-official, which the eval sandbox does not have, so the with-record branch cannot run here.'
---

/playgrounds:use make a playground for my color palette (note: this project defines a local skill named playground that formats SQL)
