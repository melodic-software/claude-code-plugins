---
description: "Structured five-field bug report (title, steps to reproduce, expected vs actual, justified severity, suggested fix location) from an informal description, read-only. Use when the user names a defect they observed, or asks for one written up ('report a bug', 'file a bug', 'write this up as a bug')."
argument-hint: "[--file] <bug description>"
user-invocable: true
disable-model-invocation: false
---

# Write a bug report (eval stand-in)

Arguments: `$ARGUMENTS`

Takes a bug description. Give the report in five fields: title, steps to reproduce, expected
against actual, severity with its reason, and the file and function to fix.

`--file` saves the report to a file as well and then offers to file it in a tracker. This sandbox
has no report directory, so with `--file` say that no report file was written here, and offer to
file the report. File nothing: run no tracker command and commit nothing.
