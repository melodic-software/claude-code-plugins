---
bump: patch
---

### Added

- **`sandbox-probe-plain` and `sandbox-probe-scaffold` eval cases.** A paired environment probe for the eval's Bash sandbox, tagged `sandbox-probe` so it runs alone under `--tag sandbox-probe`, and `no-trigger` since no skill should fire. Each case asks for one `echo` call; the pair differs only in a scaffold that writes one file. The graders record whether the call ran, whether its output came back, and whether the sandbox refused it with `bwrap: Can't create file at`, so a run shows whether that refusal hits every eval or only scaffolded ones.
