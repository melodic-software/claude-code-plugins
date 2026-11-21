---
bump: patch
---

### Fixed

- The bedroom sound test passes on a Windows host. Its stand-in for the file check now compares the probed path with the drive letter and backslashes removed, since the engine resolves `/usr/bin/ffplay` to a drive path such as `D:\usr\bin\ffplay` there ([#17823](https://github.com/melodic-software/claude-code-plugins/issues/17823)).
