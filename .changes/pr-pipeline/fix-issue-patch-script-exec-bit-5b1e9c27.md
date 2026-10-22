---
bump: patch
---

### Fixed

- The issue lane's new or changed scripts land executable. apply-patch now makes each file that
  ends in `.sh` or starts with `#!` mode 100755 after every refusal passes, under the new
  `script-exec-bit` row key that the `issue` row sets. The model still sets no mode:
  `new-executable` refuses any executable bit the patch itself carries. Before this, the patch
  committed such files as 100644 and check-affected's exec-bit check failed
  ([run 39729937593](https://github.com/melodic-software/claude-code-plugins/actions/runs/39729937593)).
  A resumed run keeps the executable scripts an earlier lane commit landed.
- Inside an issue lane's patch run, `check-affected.sh --uncommitted` gives its snapshot the same
  bits: the checks wrapper sets `CHECK_AFFECTED_SCRIPT_EXEC_BIT=1`, so exec-bit passes on a new
  script. A run that commits gets no such flag and still has to chmod its own scripts.
- The `issue` row now refuses `instruction-path`, so the issue lane pushes no plugin hooks,
  monitors or bin, and no agent instruction file. A row that sets `script-exec-bit` must refuse it.
