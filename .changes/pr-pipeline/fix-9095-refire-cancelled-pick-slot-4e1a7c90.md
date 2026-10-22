---
bump: patch
---

### Fixed

- work-unblock's sweep re-fires an `agent-ready` issue whose work-resolve-issue run was cancelled
  in `pick-slot` (its timeout while it waited in the WIP cap step) after `admit` passed and before
  `resolve-issue` ran, like a failed run and under the same once-per-workflow-version re-fire
  record ([run 39711139895](https://github.com/melodic-software/claude-code-plugins/actions/runs/39711139895)).
  A run a newer `agent-ready` run replaced while it waited ran no job and is still not re-fired.
