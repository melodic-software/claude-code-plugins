---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Uses row R1: runs claude.exe from WSL by absolute path (/mnt/c/Users/<user>/.local/bin/claude.exe) after cd to a Windows-side scratch directory, with < /dev/null, and asks that turn to list sessions and then SendMessage to the named one. Does not use ssh for a same-machine hop and does not rely on the local ListAgents, which shows only the WSL lane. Notes that starting the turn prompts under auto mode.'
---

I'm in WSL on the desktop. Tell the Claude session running in native Windows on this same machine to pause its build.
