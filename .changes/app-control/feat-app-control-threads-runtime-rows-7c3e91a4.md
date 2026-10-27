---
bump: minor
---

### Added

- The control-skill contract's hang (`threads`) row now names an all-thread dump command for JVM (`jcmd` `Thread.print`), .NET (`dotnet-stack report`) and Linux native (`gdb` `thread apply all bt`), each against the launched `<pid>`, and reads n/a for Node.js. Each new tool has a manual pointer with an as-of date and a recheck trigger. Go stays "not yet": its goroutine dump is served on the app's own endpoint, which drive's pid binding cannot hold to the launched process.
